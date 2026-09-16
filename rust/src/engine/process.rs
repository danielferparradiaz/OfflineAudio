//! Helpers for spawning and supervising child processes (yt-dlp, ffmpeg).

use std::path::PathBuf;

use anyhow::{bail, Context, Result};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;

use crate::engine::paths;

fn find_in(dir: Option<PathBuf>, names: &[String]) -> Option<PathBuf> {
    let dir = dir?;
    names.iter().map(|n| dir.join(n)).find(|p| p.is_file())
}

/// Carpeta del ejecutable en curso. Permite integrar yt-dlp/ffmpeg junto a
/// la app (p. ej. el .zip portable de Windows o el .app de macOS) sin tocar
/// el PATH.
fn exe_dir() -> Option<PathBuf> {
    std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|p| p.to_path_buf()))
}

fn ytdlp_candidate_names() -> Vec<String> {
    vec!["yt-dlp".to_string(), "yt-dlp.exe".to_string()]
}

fn ffmpeg_candidate_names() -> Vec<String> {
    let arch_first: Option<String> = {
        #[cfg(target_os = "macos")]
        {
            Some(format!("ffmpeg-{}", std::env::consts::ARCH))
        }
        #[cfg(not(target_os = "macos"))]
        {
            None
        }
    };
    arch_first
        .into_iter()
        .chain(["ffmpeg".to_string(), "ffmpeg.exe".to_string()])
        .collect()
}

/// Android yt-dlp runtime root: `<bin_dir>/ytdlp`. Holds the `ytdlp` launcher
/// plus the CPython prefix (`prefix/lib/...`). There is no official yt-dlp
/// binary for Android (bionic), so the runtime is a self-contained bundle:
/// python.org CPython-for-Android + the `yt-dlp` PyPI wheel, driven by a tiny
/// C launcher that embeds libpython (see `flutter/tool/android/`).
///
/// Versiones pineadas en `flutter/tool/android/runtime_versions.env`:
/// mantener estos consts sincronizados (el script de build falla si el zip
/// no trae exactamente `YTDLP_RUNTIME_YTDLP_VERSION`).
pub const YTDLP_RUNTIME_YTDLP_VERSION: &str = "2026.08.19";
pub const YTDLP_RUNTIME_PYTHON_MM: &str = "3.14";
pub fn ytdlp_runtime_dir() -> PathBuf {
    paths::bin_dir().join("ytdlp")
}

/// The launcher executable inside the Android yt-dlp runtime.
pub fn ytdlp_runtime_launcher() -> PathBuf {
    ytdlp_runtime_dir().join("ytdlp")
}

/// `prefix/lib` inside the Android yt-dlp runtime: home of `libpython`,
/// `libssl_python.so`, `libcrypto_python.so`, ... — needed in
/// `LD_LIBRARY_PATH` so yt-dlp extension modules resolve their deps.
pub fn ytdlp_runtime_prefix_lib() -> PathBuf {
    ytdlp_runtime_dir().join("prefix").join("lib")
}

/// Locate `yt-dlp`: Android runtime launcher → app bin dir (runtime
/// download) → next to the executable (bundled) → PATH.
pub fn ytdlp_bin() -> Option<PathBuf> {
    let runtime = ytdlp_runtime_launcher();
    if runtime.is_file() {
        return Some(runtime);
    }
    let names = ytdlp_candidate_names();
    find_in(Some(paths::bin_dir()), &names)
        .or_else(|| find_in(exe_dir(), &names))
        .or_else(|| which::which("yt-dlp").ok())
}

/// Locate `ffmpeg`: app bin dir (runtime download) → next to the executable
/// (bundled) → PATH.
pub fn ffmpeg_bin() -> Option<PathBuf> {
    let names = ffmpeg_candidate_names();
    find_in(Some(paths::bin_dir()), &names)
        .or_else(|| find_in(exe_dir(), &names))
        .or_else(|| which::which("ffmpeg").ok())
}

/// Carpeta de librerías nativas de la app (Android): se localiza vía
/// `/proc/self/maps` buscando nuestro propio `liboffline_audio.so`, sin JNI.
/// Sirve `libc++_shared.so` (integrado en el APK vía `jniLibs`) a los hijos.
#[cfg(target_os = "android")]
pub fn native_lib_dir() -> Option<PathBuf> {
    let maps = std::fs::read_to_string("/proc/self/maps").ok()?;
    for line in maps.lines() {
        let path = match line.split_whitespace().last() {
            Some(p) => p,
            None => continue,
        };
        if path.ends_with("liboffline_audio.so") {
            return std::path::Path::new(path).parent().map(|p| p.to_path_buf());
        }
    }
    None
}

/// Añade al hijo las rutas donde viven las dependencias nativas (Android:
/// `libc++_shared.so` para el ffmpeg integrado y `prefix/lib` del runtime de
/// yt-dlp para libpython y sus módulos SSL/SQLite). Sin efecto en el resto.
pub fn apply_lib_path(cmd: &mut Command) {
    #[cfg(target_os = "android")]
    {
        let mut dirs = vec![];
        // El runtime de yt-dlp primero: sus `libssl_python.so` y compañía
        // solo existen ahí.
        if ytdlp_runtime_prefix_lib().is_dir() {
            dirs.push(ytdlp_runtime_prefix_lib().to_string_lossy().to_string());
        }
        dirs.push(paths::bin_dir().to_string_lossy().to_string());
        if let Some(lib) = native_lib_dir() {
            dirs.push(lib.to_string_lossy().to_string());
        }
        if let Ok(cur) = std::env::var("LD_LIBRARY_PATH") {
            dirs.push(cur);
        }
        cmd.env("LD_LIBRARY_PATH", dirs.join(":"));
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = cmd;
    }
}

/// Download an engine binary (yt-dlp/ffmpeg) into the app binary dir.
/// Used on Android, where binaries are fetched at runtime; the destination is
/// picked up automatically by `ytdlp_bin`/`ffmpeg_bin`.
pub async fn download_binary(name: &str, url: &str) -> Result<PathBuf> {
    let dir = paths::bin_dir();
    std::fs::create_dir_all(&dir)
        .with_context(|| format!("creando dir de binarios {}", dir.display()))?;

    let dest = dir.join(name);
    let resp = reqwest::get(url).await?.error_for_status()?;
    let bytes = resp.bytes().await?;
    if bytes.is_empty() {
        bail!("descarga de {name} vacía desde {url}");
    }

    use std::io::Write;
    let mut file = std::fs::File::create(&dest)?;
    file.write_all(&bytes)?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&dest, std::fs::Permissions::from_mode(0o755))?;
    }
    Ok(dest)
}

/// Download a zipped engine binary (p. ej. ffmpeg de Tyrrrz/FFmpegBin, que se
/// distribuye como un único `ffmpeg` dentro del zip) y extrae el fichero
/// `name` en el bin dir de la app.
pub async fn download_zip_binary(name: &str, url: &str) -> Result<PathBuf> {
    let dir = paths::bin_dir();
    std::fs::create_dir_all(&dir)
        .with_context(|| format!("creando dir de binarios {}", dir.display()))?;

    let bytes = reqwest::get(url).await?.error_for_status()?.bytes().await?;
    if bytes.is_empty() {
        bail!("descarga de {name} vacía desde {url}");
    }
    let dest = dir.join(name);
    extract_zip_member(&bytes, name, &dest)?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&dest, std::fs::Permissions::from_mode(0o755))?;
    }
    Ok(dest)
}

/// Download a zipped engine binary donde el ejecutable viene anidado
/// (p. ej. `ffmpeg-release-essentials.zip` de Gyan trae
/// `ffmpeg-*-essentials_build/bin/ffmpeg.exe`). Busca la primera entrada
/// cuyo nombre termine en `suffix` (p. ej. `bin/ffmpeg.exe` o `ffmpeg`),
/// la extrae a `dest_name` en el bin dir y le da permiso de ejecución.
/// Rechaza zip-slip igual que `extract_zip_all`.
pub async fn download_zip_binary_suffix(
    dest_name: &str,
    url: &str,
    suffix: &str,
) -> Result<PathBuf> {
    let dir = paths::bin_dir();
    std::fs::create_dir_all(&dir)
        .with_context(|| format!("creando dir de binarios {}", dir.display()))?;

    let bytes = reqwest::get(url).await?.error_for_status()?.bytes().await?;
    if bytes.is_empty() {
        bail!("descarga de {dest_name} vacía desde {url}");
    }
    let dest = dir.join(dest_name);
    extract_zip_suffix(&bytes, suffix, &dest)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&dest, std::fs::Permissions::from_mode(0o755))?;
    }
    Ok(dest)
}

/// Extrae del zip en memoria la primera entrada que termine en `suffix`
/// hacia `dest` (sin red; testeable offline). Usado para zips donde el
/// binario viene anidado (Gyan/BtbN/johnvansickle).
fn extract_zip_suffix(bytes: &[u8], suffix: &str, dest: &std::path::Path) -> Result<()> {
    let mut zip = zip::ZipArchive::new(std::io::Cursor::new(bytes)).context("zip inválido")?;
    let norm = suffix.replace('\\', "/");
    let idx = (0..zip.len())
        .find(|&i| {
            zip.by_index(i)
                .map(|e| {
                    let n = e.name().replace('\\', "/");
                    !e.is_dir()
                        && (n == norm || n.ends_with(&format!("/{norm}")) || n.ends_with(&norm))
                })
                .unwrap_or(false)
        })
        .with_context(|| format!("el zip no contiene *{suffix}"))?;
    let mut entry = zip.by_index(idx)?;
    {
        let mut file = std::fs::File::create(dest)?;
        std::io::copy(&mut entry, &mut file)?;
    }
    Ok(())
}

/// Smoke genérico: `<bin> --version` (yt-dlp) o `-version` (ffmpeg) debe
/// salir con código 0 en menos de 30s. Lo usa el botón Descargar para no dar
/// por bueno un binario corrupto o de otra arquitectura.
pub async fn smoke_binary(bin: &std::path::Path, args: &[&str]) -> Result<String> {
    let mut cmd = child_log(bin, args, null(), pipe(), null());
    let out = tokio::time::timeout(std::time::Duration::from_secs(30), cmd.output())
        .await
        .context("timeout en smoke --version")??;
    if !out.status.success() {
        bail!("{} no arranca ({:?} falló)", bin.display(), args);
    }
    Ok(String::from_utf8_lossy(&out.stdout)
        .lines()
        .next()
        .unwrap_or("")
        .trim()
        .to_string())
}
/// Download the Android yt-dlp runtime zip (launcher + CPython prefix +
/// yt-dlp wheel) and extract it into `<bin_dir>/ytdlp`. Instalación atómica:
/// se extrae a `<bin_dir>/ytdlp.new-<pid>` + verificación y solo entonces se
/// renombra, así un zip corrupto o una descarga a medias nunca deja el
/// runtime anterior roto. Devuelve la ruta del launcher, que `ytdlp_bin`
/// detecta automáticamente.
pub async fn download_ytdlp_runtime(url: &str) -> Result<PathBuf> {
    let dir = ytdlp_runtime_dir();
    let staging = paths::bin_dir().join(format!("ytdlp.new-{}", std::process::id()));
    if staging.exists() {
        let _ = std::fs::remove_dir_all(&staging);
    }
    std::fs::create_dir_all(&staging)
        .with_context(|| format!("creando staging del runtime {}", staging.display()))?;

    let install = async {
        let bytes = reqwest::get(url).await?.error_for_status()?.bytes().await?;
        if bytes.is_empty() {
            bail!("descarga del runtime de yt-dlp vacía desde {url}");
        }
        extract_zip_all(&bytes, &staging)?;
        verify_ytdlp_runtime(&staging)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(
                staging.join("ytdlp"),
                std::fs::Permissions::from_mode(0o755),
            )?;
        }
        // Smoke real: el launcher debe responder `--version` (con el
        // LD_LIBRARY_PATH del runtime). Si falla, no se toca lo instalado.
        smoke_ytdlp_launcher(&staging.join("ytdlp")).await?;
        anyhow::Result::<()>::Ok(())
    }
    .await;
    if let Err(e) = install {
        let _ = std::fs::remove_dir_all(&staging);
        return Err(e).with_context(|| format!("instalando runtime desde {url}"));
    }
    // Swap atómico: el dir anterior se mueve a .old y se borra tras renombrar.
    let backup = paths::bin_dir().join("ytdlp.old");
    let _ = std::fs::remove_dir_all(&backup);
    if dir.exists() {
        std::fs::rename(&dir, &backup)?;
    }
    if let Err(e) = std::fs::rename(&staging, &dir) {
        // Rollback: intenta devolver el anterior a su sitio.
        if backup.exists() {
            let _ = std::fs::rename(&backup, &dir);
        }
        return Err(e).with_context(|| "activando runtime de yt-dlp")?;
    }
    let _ = std::fs::remove_dir_all(&backup);
    Ok(ytdlp_runtime_launcher())
}

/// Comprueba que un dir (instalado o en staging) sea un runtime completo:
/// launcher + libpython del minor esperado + `yt_dlp/__main__.py` + certifi.
/// Barato (solo FS) y evita dar por buena una extracción parcial.
pub fn verify_ytdlp_runtime(dir: &std::path::Path) -> Result<()> {
    let launcher = dir.join("ytdlp");
    if !launcher.is_file() {
        bail!("el zip no contiene el launcher `ytdlp` en su raíz");
    }
    let lib_glob = format!("libpython{YTDLP_RUNTIME_PYTHON_MM}");
    let prefix_lib = dir.join("prefix").join("lib");
    let has_libpython = std::fs::read_dir(&prefix_lib)
        .with_context(|| format!("sin prefix/lib en {}", dir.display()))?
        .filter_map(|e| e.ok())
        .any(|e| e.file_name().to_string_lossy().starts_with(&lib_glob));
    if !has_libpython {
        bail!("falta {lib_glob}.so en prefix/lib (CPython {YTDLP_RUNTIME_PYTHON_MM} esperado)");
    }
    let main = prefix_lib.join(format!(
        "python{}/site-packages/yt_dlp/__main__.py",
        YTDLP_RUNTIME_PYTHON_MM
    ));
    if !main.is_file() {
        bail!("falta yt_dlp/__main__.py en {}", main.display());
    }
    // certifi trae su propio dir de paquete.
    let certifi = prefix_lib.join(format!(
        "python{}/site-packages/certifi",
        YTDLP_RUNTIME_PYTHON_MM
    ));
    if !certifi.is_dir() {
        bail!("falta certifi en el runtime");
    }
    Ok(())
}

/// Ejecuta `<launcher> --version` con el entorno que usará en producción
/// (LD_LIBRARY_PATH a prefix/lib en Android / al lado del binario en el
/// resto) y comprueba que la versión sea la pineada. Timeout corto para no
/// colgar Ajustes si el runtime está roto.
async fn smoke_ytdlp_launcher(launcher: &std::path::Path) -> Result<String> {
    use tokio::process::Command as TokioCommand;
    let prefix_lib = launcher
        .parent()
        .map(|p| p.join("prefix").join("lib"))
        .unwrap_or_default();
    let mut cmd = TokioCommand::new(launcher);
    cmd.args(["--version", "--no-cache-dir"])
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .kill_on_drop(false);
    #[cfg(target_os = "android")]
    {
        let mut dirs = vec![];
        if prefix_lib.is_dir() {
            dirs.push(prefix_lib.to_string_lossy().to_string());
        }
        dirs.push(paths::bin_dir().to_string_lossy().to_string());
        if let Some(lib) = native_lib_dir() {
            dirs.push(lib.to_string_lossy().to_string());
        }
        if let Ok(cur) = std::env::var("LD_LIBRARY_PATH") {
            if !cur.is_empty() {
                dirs.push(cur);
            }
        }
        cmd.env("LD_LIBRARY_PATH", dirs.join(":"));
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = &prefix_lib;
    }
    hide_console_tokio(&mut cmd);
    let out = tokio::time::timeout(std::time::Duration::from_secs(30), cmd.output())
        .await
        .context("timeout en --version del runtime")??;
    if !out.status.success() {
        bail!("el launcher no arranca (--version falló)");
    }
    let v = String::from_utf8_lossy(&out.stdout).trim().to_string();
    // yt-dlp escribe la versión cero-padded (2026.08.19) pero el pin puede
    // ir sin ceros: se comparan los números, no el string.
    if normalize_version(&v) != normalize_version(YTDLP_RUNTIME_YTDLP_VERSION) {
        bail!("runtime trae yt-dlp {v}, esperado {YTDLP_RUNTIME_YTDLP_VERSION}");
    }
    Ok(v)
}

/// Normaliza una versión `yyyy.mm.dd` a números sin cero-padding para
/// comparar (`2026.08.19` == `2026.8.19`). Lo no parseable se deja tal cual
/// para que el mismatch siga cantando en vez de colar.
fn normalize_version(s: &str) -> String {
    let parts: Vec<String> = s
        .trim()
        .split(['.', '-'])
        .take(3)
        .map(|p| {
            p.parse::<u32>()
                .map(|n| n.to_string())
                .unwrap_or_else(|_| p.to_string())
        })
        .collect();
    parts.join(".")
}

#[cfg(windows)]
fn hide_console_tokio(cmd: &mut tokio::process::Command) {
    use std::os::windows::process::CommandExt;
    cmd.creation_flags(0x0800_0000);
}
#[cfg(not(windows))]
fn hide_console_tokio(_cmd: &mut tokio::process::Command) {}

/// Extrae el miembro `name` de un zip en memoria hacia `dest` (sin red).
fn extract_zip_member(bytes: &[u8], name: &str, dest: &std::path::Path) -> Result<()> {
    let mut zip = zip::ZipArchive::new(std::io::Cursor::new(bytes)).context("zip inválido")?;
    let mut entry = zip
        .by_name(name)
        .with_context(|| format!("el zip no contiene {name}"))?;
    {
        let mut file = std::fs::File::create(dest)?;
        std::io::copy(&mut entry, &mut file)?;
    }
    Ok(())
}

/// Extrae TODO el contenido de un zip en memoria hacia `dest`, preservando
/// la estructura de carpetas. Rechaza rutas absolutas o con `..` (zip-slip)
/// para que un zip malicioso no escriba fuera del destino.
fn extract_zip_all(bytes: &[u8], dest: &std::path::Path) -> Result<()> {
    let mut zip = zip::ZipArchive::new(std::io::Cursor::new(bytes)).context("zip inválido")?;
    for i in 0..zip.len() {
        let mut entry = zip.by_index(i)?;
        let rel = std::path::Path::new(entry.name());
        if rel.is_absolute()
            || rel.components().any(|c| {
                matches!(
                    c,
                    std::path::Component::ParentDir | std::path::Component::Prefix(_)
                )
            })
        {
            bail!("entrada insegura en el zip: {}", entry.name());
        }
        let out_path = dest.join(rel);
        if entry.is_dir() {
            std::fs::create_dir_all(&out_path)?;
            continue;
        }
        if let Some(parent) = out_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let mut file = std::fs::File::create(&out_path)?;
        std::io::copy(&mut entry, &mut file)?;
    }
    Ok(())
}

#[cfg(all(unix, not(target_os = "android")))]
async fn download_yt_dlp() -> Result<PathBuf> {
    let target_dir = dirs::home_dir().context("no home dir")?.join(".local/bin");
    std::fs::create_dir_all(&target_dir).ok();

    let latest = reqwest::get("https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")
        .await?
        .json::<serde_json::Value>()
        .await?;

    let assets = latest
        .get("assets")
        .and_then(|a| a.as_array())
        .cloned()
        .unwrap_or_default();

    let asset = assets
        .iter()
        .find(|x| {
            x.get("name")
                .and_then(|v| v.as_str())
                .map(|s| s.contains("yt-dlp"))
                .unwrap_or(false)
        })
        .ok_or_else(|| anyhow::anyhow!("no yt-dlp asset found"))?;

    let url = asset
        .get("browser_download_url")
        .and_then(|v| v.as_str())
        .context("no url")?;
    let name = asset
        .get("name")
        .and_then(|v| v.as_str())
        .context("no name")?;

    let dest = target_dir.join(name);
    let resp = reqwest::get(url).await?;
    let mut file = std::fs::File::create(&dest)?;
    let bytes = resp.bytes().await?.to_vec();
    use std::io::Write;
    file.write_all(&bytes)?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let perms = std::fs::Permissions::from_mode(0o755);
        // Try to set permissions; if it fails (e.g., SIP on macOS), continue anyway
        let _ = std::fs::set_permissions(&dest, perms);
        // Remove quarantine attribute on macOS to allow execution
        let _ = std::process::Command::new("xattr")
            .args(["-d", "-c", "com.apple.quarantine", dest.to_str().unwrap()])
            .output();
    }

    Ok(dest)
}

pub async fn ensure_yt_dlp() -> Result<PathBuf> {
    if let Some(bin) = ytdlp_bin() {
        return Ok(bin);
    }

    #[cfg(target_os = "macos")]
    {
        let common_paths = ["/usr/local/bin/yt-dlp", "/opt/homebrew/bin/yt-dlp"];
        for path in &common_paths {
            if std::path::Path::new(path).exists() {
                return Ok(PathBuf::from(path));
            }
        }
    }

    #[cfg(all(unix, not(target_os = "android")))]
    {
        let bin = download_yt_dlp().await?;
        Ok(bin)
    }

    // En Android no hay builds oficiales de yt-dlp (glibc/musl vs bionic):
    // el motor descarga solo su runtime integrado (launcher + CPython +
    // wheel) la primera vez que hace falta.
    #[cfg(target_os = "android")]
    {
        bail!(
            "Motor de descargas no disponible todavía. \
             Se está preparando solo; inténtalo de nuevo en un momento."
        );
    }

    #[cfg(windows)]
    {
        bail!(
            "Motor de descargas no disponible todavía. \
             Se está preparando solo; inténtalo de nuevo en un momento."
        );
    }
}

/// Locate or install `ffmpeg`. Missing binaries are provisioned silently by
/// the engine (bundled in the release or auto-downloaded); this only locates.
pub async fn ensure_ffmpeg() -> Result<PathBuf> {
    if let Some(bin) = ffmpeg_bin() {
        return Ok(bin);
    }

    #[cfg(target_os = "macos")]
    {
        let common_paths = ["/usr/local/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg"];
        for path in &common_paths {
            if std::path::Path::new(path).exists() {
                return Ok(PathBuf::from(path));
            }
        }
    }

    bail!(
        "Motor de conversión no disponible todavía. \
         Se está preparando solo; inténtalo de nuevo en un momento."
    );
}

/// Validate a URL the user pasted before it ever reaches a child process.
/// Returns the normalized URL. Rejects anything that is not http(s) so a
/// malformed string can never be interpreted as a command-line option.
pub fn sanitize_url(url: &str) -> Result<String> {
    let trimmed = url.trim();
    if !trimmed.starts_with("https://") && !trimmed.starts_with("http://") {
        bail!("URL inválida: debe empezar por http:// o https://");
    }
    if trimmed.contains(char::is_whitespace) || trimmed.contains('\n') || trimmed.contains('\r') {
        bail!("URL inválida: contiene espacios o saltos de línea");
    }
    Ok(trimmed.to_string())
}

/// Buffered reader of a child's stderr that keeps the last `max_lines` lines
/// for diagnostics without unbounded buffering.
pub struct StderrTail {
    lines: Vec<String>,
    max_lines: usize,
}

impl StderrTail {
    pub fn new(max_lines: usize) -> Self {
        StderrTail {
            lines: Vec::new(),
            max_lines,
        }
    }

    pub fn push(&mut self, line: String) {
        if self.lines.len() >= self.max_lines {
            self.lines.remove(0);
        }
        self.lines.push(line);
    }

    pub fn as_text(&self) -> String {
        self.lines.join("\n")
    }
}

/// Read a child's stderr to EOF, keeping a rolling tail, and call `on_line`
/// for every line (e.g. yt-dlp progress lines) while it is `Some`.
pub async fn read_stderr<F>(
    stderr: Box<dyn tokio::io::AsyncRead + Send + Unpin>,
    max_lines: usize,
    mut on_line: Option<F>,
) -> String
where
    F: FnMut(&str) + Send + 'static,
{
    let mut reader = BufReader::new(stderr).lines();
    let mut tail = StderrTail::new(max_lines);
    loop {
        let line = match reader.next_line().await {
            Ok(Some(line)) => line,
            Ok(None) => break,
            Err(_) => break,
        };
        tail.push(line.clone());
        if let Some(cb) = on_line.as_mut() {
            cb(&line);
        }
    }
    tail.as_text()
}

/// Oculta la ventana de consola de los hijos en Windows: sin
/// `CREATE_NO_WINDOW` cada invocación a yt-dlp/ffmpeg abre (y cierra) una
/// terminal. Los pipes de stdin/stdout/stderr siguen funcionando igual.
pub fn hide_console(cmd: &mut Command) {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    }
    #[cfg(not(windows))]
    {
        let _ = cmd;
    }
}

/// Size a `Command` with default safety (no shell), default env inheritance.
pub fn child_log(
    program: &std::path::Path,
    args: &[&str],
    stdin: std::process::Stdio,
    stdout: std::process::Stdio,
    stderr: std::process::Stdio,
) -> Command {
    let mut cmd = Command::new(program);
    cmd.args(args)
        .stdin(stdin)
        .stdout(stdout)
        .stderr(stderr)
        .kill_on_drop(false);
    apply_lib_path(&mut cmd);
    hide_console(&mut cmd);
    cmd
}

pub fn pipe() -> std::process::Stdio {
    std::process::Stdio::piped()
}

pub fn null() -> std::process::Stdio {
    std::process::Stdio::null()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zip_member_extracts_by_name() {
        let mut buf = std::io::Cursor::new(Vec::new());
        {
            let mut w = zip::ZipWriter::new(&mut buf);
            w.start_file("ffmpeg", zip::write::SimpleFileOptions::default())
                .unwrap();
            use std::io::Write;
            w.write_all(b"fake-binary").unwrap();
            w.finish().unwrap();
        }
        let dir = tempfile::tempdir().unwrap();
        let dest = dir.path().join("ffmpeg");
        extract_zip_member(buf.get_ref(), "ffmpeg", &dest).unwrap();
        assert_eq!(std::fs::read(&dest).unwrap(), b"fake-binary");
        assert!(extract_zip_member(buf.get_ref(), "otro", &dest).is_err());
    }

    #[test]
    fn zip_all_extracts_tree_and_rejects_traversal() {
        use std::io::Write;
        let mut buf = std::io::Cursor::new(Vec::new());
        {
            let mut w = zip::ZipWriter::new(&mut buf);
            w.start_file("ytdlp", zip::write::SimpleFileOptions::default())
                .unwrap();
            w.write_all(b"launcher").unwrap();
            w.start_file(
                "prefix/lib/python3.14/site-packages/yt_dlp/__init__.py",
                zip::write::SimpleFileOptions::default(),
            )
            .unwrap();
            w.write_all(b"# pkg").unwrap();
            w.finish().unwrap();
        }
        let dir = tempfile::tempdir().unwrap();
        extract_zip_all(buf.get_ref(), dir.path()).unwrap();
        assert_eq!(
            std::fs::read(dir.path().join("ytdlp")).unwrap(),
            b"launcher"
        );
        assert!(dir
            .path()
            .join("prefix/lib/python3.14/site-packages/yt_dlp/__init__.py")
            .is_file());

        // Zip-slip: `..` debe rechazarse sin escribir nada fuera.
        let mut evil = std::io::Cursor::new(Vec::new());
        {
            let mut w = zip::ZipWriter::new(&mut evil);
            w.start_file("../evil.sh", zip::write::SimpleFileOptions::default())
                .unwrap();
            w.write_all(b"nope").unwrap();
            w.finish().unwrap();
        }
        let dir2 = tempfile::tempdir().unwrap();
        assert!(extract_zip_all(evil.get_ref(), dir2.path()).is_err());
        assert!(!dir2.path().join("evil.sh").exists());
    }

    #[test]
    fn normalize_version_ignores_zero_padding() {
        assert_eq!(normalize_version("2026.08.19"), "2026.8.19");
        assert_eq!(normalize_version("2026.8.19"), "2026.8.19");
        assert_eq!(normalize_version("  2026.08.19\n"), "2026.8.19");
        // Lo no parseable no cuela como igual.
        assert_ne!(normalize_version("nightly"), normalize_version("2026.8.19"));
    }

    #[test]
    fn ytdlp_runtime_layout_paths() {
        // Rutas puras: no tocan el FS.
        assert!(ytdlp_runtime_launcher().starts_with(ytdlp_runtime_dir()));
        assert_eq!(ytdlp_runtime_launcher().file_name().unwrap(), "ytdlp");
        assert!(ytdlp_runtime_prefix_lib().ends_with(std::path::Path::new("prefix/lib")));
    }

    #[test]
    fn runtime_verify_rejects_incomplete_tree() {
        let dir = tempfile::tempdir().unwrap();
        // Vacío: falla por launcher.
        assert!(verify_ytdlp_runtime(dir.path()).is_err());
        std::fs::write(dir.path().join("ytdlp"), b"x").unwrap();
        // Con launcher pero sin prefix/lib: falla.
        assert!(verify_ytdlp_runtime(dir.path()).is_err());
        // Árbol completo mínimo: pasa.
        let mm = YTDLP_RUNTIME_PYTHON_MM;
        let sp = dir
            .path()
            .join("prefix")
            .join("lib")
            .join(format!("python{mm}/site-packages"));
        std::fs::create_dir_all(sp.join("yt_dlp")).unwrap();
        std::fs::create_dir_all(sp.join("certifi")).unwrap();
        std::fs::write(
            dir.path()
                .join("prefix/lib")
                .join(format!("libpython{mm}.so")),
            b"so",
        )
        .unwrap();
        std::fs::write(sp.join("yt_dlp/__main__.py"), b"#").unwrap();
        assert!(verify_ytdlp_runtime(dir.path()).is_ok());
    }

    #[test]
    fn zip_suffix_extracts_nested_binary() {
        use std::io::Write;
        let mut buf = std::io::Cursor::new(Vec::new());
        {
            let mut w = zip::ZipWriter::new(&mut buf);
            // Layout tipo Gyan essentials.
            w.start_file(
                "ffmpeg-7-essentials_build/bin/ffmpeg.exe",
                zip::write::SimpleFileOptions::default(),
            )
            .unwrap();
            w.write_all(b"fake-ffmpeg").unwrap();
            w.start_file("README.txt", zip::write::SimpleFileOptions::default())
                .unwrap();
            w.write_all(b"hi").unwrap();
            w.finish().unwrap();
        }
        let dir = tempfile::tempdir().unwrap();
        let dest = dir.path().join("ffmpeg.exe");
        extract_zip_suffix(buf.get_ref(), "bin/ffmpeg.exe", &dest).unwrap();
        assert_eq!(std::fs::read(&dest).unwrap(), b"fake-ffmpeg");
        assert!(extract_zip_suffix(buf.get_ref(), "bin/ffprobe.exe", &dest).is_err());
    }
    #[test]
    fn ffmpeg_prefers_bundled_arch_on_macos() {
        // Solo comprueba la construcción de candidatos (sin FS).
        let names = ffmpeg_candidate_names();
        assert!(names.contains(&"ffmpeg".to_string()));
        #[cfg(target_os = "macos")]
        assert!(names.first().unwrap().starts_with("ffmpeg-"));
    }
}
