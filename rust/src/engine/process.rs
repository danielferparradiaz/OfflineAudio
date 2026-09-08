//! Helpers for spawning and supervising child processes (yt-dlp, ffmpeg).

use std::path::PathBuf;

use anyhow::{bail, Context, Result};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;

use crate::engine::paths;

fn in_binary_dir(names: &[&str]) -> Option<PathBuf> {
    for name in names {
        let p = paths::bin_dir().join(name);
        if p.is_file() {
            return Some(p);
        }
    }
    None
}

/// Locate `yt-dlp`: first in the app binary dir (mobile download), then PATH.
pub fn ytdlp_bin() -> Option<PathBuf> {
    in_binary_dir(&["yt-dlp", "yt-dlp.exe"]).or_else(|| which::which("yt-dlp").ok())
}

/// Locate `ffmpeg`: first in the app binary dir (mobile download), then PATH.
pub fn ffmpeg_bin() -> Option<PathBuf> {
    in_binary_dir(&["ffmpeg", "ffmpeg.exe"]).or_else(|| which::which("ffmpeg").ok())
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

    #[cfg(unix)]
    {
        let bin = download_yt_dlp().await?;
        Ok(bin)
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
    cmd
}

pub fn pipe() -> std::process::Stdio {
    std::process::Stdio::piped()
}

pub fn null() -> std::process::Stdio {
    std::process::Stdio::null()
}
