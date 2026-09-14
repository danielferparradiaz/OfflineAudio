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

/// Locate `yt-dlp`: app bin dir (runtime download) → next to the executable
/// (bundled) → PATH.
pub fn ytdlp_bin() -> Option<PathBuf> {
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
/// `libc++_shared.so` para el ffmpeg integrado). Sin efecto en el resto.
pub fn apply_lib_path(cmd: &mut Command) {
    #[cfg(target_os = "android")]
    {
        let mut dirs = vec![paths::bin_dir().to_string_lossy().to_string()];
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
    // solo vale lo descargado desde Ajustes > Paquetes (URL propia).
    #[cfg(target_os = "android")]
    {
        bail!("yt-dlp no está instalado. Descárgalo desde Ajustes > Paquetes del motor.");
    }

    #[cfg(windows)]
    {
        bail!("yt-dlp no está instalado y no se pudo descargar automáticamente. Instálalo con: pipx install yt-dlp o descárgalo desde https://github.com/yt-dlp/yt-dlp/releases");
    }
}

/// Locate or install `ffmpeg`. On desktop it must come from the system; on
/// mobile a runtime-downloaded binary is picked up from the app bin dir.
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

    bail!("ffmpeg no está instalado. En el escritorio instálalo con `brew install ffmpeg` (o tu gestor de paquetes); en móvil descárgalo desde Ajustes > Paquetes.");
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
    fn ffmpeg_prefers_bundled_arch_on_macos() {
        // Solo comprueba la construcción de candidatos (sin FS).
        let names = ffmpeg_candidate_names();
        assert!(names.contains(&"ffmpeg".to_string()));
        #[cfg(target_os = "macos")]
        assert!(names.first().unwrap().starts_with("ffmpeg-"));
    }
}
