//! yt-dlp interaction: metadata probe and command builders for both download
//! strategies (direct streaming to stdout, and disk-based fallback).

use anyhow::{bail, Context, Result};
use serde_json::Value;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::time::timeout;

use crate::engine::cookies::ResolvedCookies;
use crate::engine::models::ProbeInfo;
use crate::engine::process::{
    child_log, ensure_yt_dlp, null, pace_ytdlp_calls, pipe, sanitize_url,
};

const PROBE_TIMEOUT_SECS: u64 = 180;
const STREAM_URL_TIMEOUT_SECS: u64 = 30;

/// Selector de formato para resolver la URL directa de un avance.
/// Audio: mejor stream solo-audio (mpv lo reproduce sin problema); vídeo:
/// mejor archivo único (progresivo) capado a 480p para que el reproductor
/// arranque antes (menos buffer inicial).
pub fn preview_format(video: bool) -> &'static str {
    if video {
        "b[height<=480]/b"
    } else {
        "ba/b"
    }
}

/// Único ejecutor con fallback para los comandos puntuales de yt-dlp
/// (probe y avance): corre `base + cookies + url` y, solo si el fallo se
/// clasifica como extracción de cookies y había cookies, reintenta UNA vez
/// pelado. El error final ya viene clasificado y en español vía
/// [`cookies::friendly_message`].
async fn output_with_cookie_fallback(
    bin: &std::path::Path,
    base_args: &[&str],
    url: &str,
    cookies: &ResolvedCookies,
    timeout_dur: std::time::Duration,
    on_timeout: anyhow::Error,
) -> Result<std::process::Output> {
    let attempts: Vec<ResolvedCookies> = if cookies.has_cookies() {
        vec![cookies.clone(), ResolvedCookies::none()]
    } else {
        vec![ResolvedCookies::none()]
    };
    let mut last_tail = String::new();
    // Ritmo global anti-bloqueo antes del primer intento (el reintento
    // hereda el hueco del intento fallido).
    pace_ytdlp_calls().await;
    for (i, attempt) in attempts.iter().enumerate() {
        let owned = attempt.full_args(base_args, url);
        let refs: Vec<&str> = owned.iter().map(|s| s.as_str()).collect();
        let mut cmd = child_log(bin, &refs, null(), pipe(), pipe());
        let out = timeout(timeout_dur, cmd.output())
            .await
            .map_err(|_| anyhow::anyhow!("{on_timeout}"))?
            .map_err(|e| anyhow::anyhow!("error ejecutando yt-dlp ({}): {e}", bin.display()))?;
        if out.status.success() {
            return Ok(out);
        }
        let tail = String::from_utf8_lossy(&out.stderr)
            .lines()
            .rev()
            .take(6)
            .collect::<Vec<_>>()
            .join("\n");
        let failure = crate::engine::cookies::classify(&tail);
        if i == 0
            && attempt.has_cookies()
            && failure == crate::engine::cookies::YtDlpFailure::CookieExtraction
        {
            last_tail = tail;
            continue;
        }
        bail!(
            "{}",
            crate::engine::cookies::friendly_message(failure, attempt.browser_used(), &tail)
        );
    }
    bail!(
        "{}",
        crate::engine::cookies::friendly_message(
            crate::engine::cookies::YtDlpFailure::CookieExtraction,
            cookies.browser_used(),
            &last_tail,
        )
    );
}

/// Resuelve con yt-dlp la URL directa de stream para previsualizar un
/// resultado sin descargarlo (vía principal del avance).
/// Devuelve la primera URL; caducan en horas, vale para reproducir al momento.
pub async fn stream_url(url: &str, video: bool, cookies: &ResolvedCookies) -> Result<String> {
    let url = sanitize_url(url)?;
    let bin = ensure_yt_dlp().await?;
    let format = preview_format(video);
    let base = [
        "--get-url",
        "--no-playlist",
        "--no-warnings",
        "--socket-timeout",
        "15",
        "-f",
        format,
    ];
    let out = output_with_cookie_fallback(
        &bin,
        &base,
        &url,
        cookies,
        std::time::Duration::from_secs(STREAM_URL_TIMEOUT_SECS),
        anyhow::anyhow!("yt-dlp tardó demasiado resolviendo el avance (>30s)"),
    )
    .await?;
    let stdout = String::from_utf8_lossy(&out.stdout).to_string();
    let first = stdout
        .lines()
        .map(str::trim)
        .find(|l| l.starts_with("http"))
        .context("yt-dlp no devolvió URL de stream")?;
    Ok(first.to_string())
}

fn json_str(v: &Value) -> Option<String> {
    match v {
        Value::String(s) => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        _ => None,
    }
}

/// Extract the `artist`/`creator`/`uploader` else `None`.
fn extract_artist(v: &Value) -> Option<String> {
    for key in ["artist", "creator", "uploader", "channel"] {
        if let Some(s) = json_str(v.get(key)?) {
            return Some(s);
        }
    }
    None
}

fn extract_genre(v: &Value) -> Option<String> {
    match v.get("genre")? {
        Value::String(s) => Some(s.clone()),
        Value::Array(items) => {
            let joined: Vec<&str> = items.iter().filter_map(|x| x.as_str()).collect();
            if joined.is_empty() {
                None
            } else {
                Some(joined.join(", "))
            }
        }
        _ => None,
    }
}

/// Heuristic: is this content more likely speech/podcast than music?
/// Long videos or podcast-ish channel/title keywords push towards speech.
pub fn likely_speech(
    duration_seconds: Option<i64>,
    uploader: Option<&str>,
    title: Option<&str>,
) -> bool {
    if let Some(d) = duration_seconds {
        if d >= 40 * 60 {
            return true;
        }
    }
    let keywords = [
        "podcast",
        "audiobook",
        "audiolibro",
        "charla",
        "talk",
        "entrevista",
        "interview",
        "lectura",
        "lecture",
        "conferencia",
    ];
    let hay = format!(
        "{} {}",
        uploader.unwrap_or("").to_lowercase(),
        title.unwrap_or("").to_lowercase()
    );
    keywords.iter().any(|k| hay.contains(k))
}

/// Query yt-dlp for metadata of a URL without downloading it.
/// Usa el ejecutor central con fallback: si la extracción de cookies falla
/// se reintenta una vez sin cookies (el vídeo público sale sin login).
pub async fn probe(url: &str, cookies: &ResolvedCookies) -> Result<ProbeInfo> {
    let url = sanitize_url(url)?;
    let bin = ensure_yt_dlp().await.context(
        "Motor de descargas no disponible todavía. \
         Se está preparando solo; inténtalo de nuevo en un momento.",
    )?;
    let base: Vec<&str> = vec![
        "--dump-json",
        "--no-playlist",
        "--no-warnings",
        "--skip-download",
        "--force-ipv4",
        "--socket-timeout",
        "45",
    ];
    let out = output_with_cookie_fallback(
        &bin,
        &base,
        &url,
        cookies,
        std::time::Duration::from_secs(PROBE_TIMEOUT_SECS),
        anyhow::anyhow!(
            "El análisis del enlace tardó demasiado (>{PROBE_TIMEOUT_SECS}s). \
             Comprueba tu conexión e inténtalo de nuevo."
        ),
    )
    .await?;

    let stdout = String::from_utf8_lossy(&out.stdout);
    parse_probe_json(&stdout)
}

/// Parsea el JSON de `--dump-json` a [`ProbeInfo`].
fn parse_probe_json(stdout: &str) -> Result<ProbeInfo> {
    let mut v: Value = serde_json::from_str(stdout.trim())
        .map_err(|e| anyhow::anyhow!("respuesta de yt-dlp no válida: {e}"))?;

    // Some extractors emit a small playlists array; unwrap the first entry.
    if v.get("_type").and_then(|t| t.as_str()) == Some("playlist") {
        let entries = v
            .get_mut("entries")
            .and_then(|e| e.as_array_mut())
            .ok_or_else(|| anyhow::anyhow!("no se encontró ninguna entrada en el enlace"))?;
        let first = entries.first().cloned().context("playlist vacía")?;
        v = first;
    }

    let id = json_str(&v["id"]).unwrap_or_default();
    let extractor = json_str(&v["extractor_key"])
        .or_else(|| json_str(&v["extractor"]))
        .unwrap_or_else(|| "desconocido".to_string());
    let duration = v["duration"].as_f64().map(|f| f.round() as i64);
    let title = json_str(&v["title"]).unwrap_or_else(|| "<sin título>".to_string());
    let uploader = json_str(&v["uploader"]).or_else(|| json_str(&v["creator"]));

    let probe = ProbeInfo {
        source_id: format!("{}:{}", extractor.to_lowercase(), id),
        id,
        title,
        artist: extract_artist(&v),
        album: json_str(&v["album"]),
        genre: extract_genre(&v),
        duration_seconds: duration,
        thumbnail_url: json_str(&v["thumbnail"]),
        platform: Some(extractor.to_lowercase()),
        uploader: uploader.clone(),
        webpage_url: json_str(&v["webpage_url"]),
        estimated_size_bytes: v["filesize_approx"].as_u64(),
        likely_speech: likely_speech(duration, uploader.as_deref(), Some(&v["title"].to_string())),
    };
    Ok(probe)
}

/// Args for strategy A: yt-dlp streams the media to stdout.
pub fn ytdlp_stream_args(url: &str, cookies: &ResolvedCookies) -> Vec<String> {
    let mut args = vec![
        "-f".to_string(),
        "bestaudio/best".to_string(),
        "-o".to_string(),
        "-".to_string(),
        "--no-part".to_string(),
        "--newline".to_string(),
        "--no-colors".to_string(),
        "--no-playlist".to_string(),
        "--force-ipv4".to_string(),
        "--socket-timeout".to_string(),
        "30".to_string(),
    ];
    args.extend(cookies.args.iter().cloned());
    args.extend(cookies.extractor_args());
    args.push(url.to_string());
    args
}

/// Args for strategy B: yt-dlp downloads to a local temp file.
pub fn ytdlp_disk_args(url: &str, dest_pattern: &str, cookies: &ResolvedCookies) -> Vec<String> {
    let mut args = vec![
        "-f".to_string(),
        "bestaudio/best".to_string(),
        "-o".to_string(),
        dest_pattern.to_string(),
        "--newline".to_string(),
        "--no-colors".to_string(),
        "--no-playlist".to_string(),
        "--force-ipv4".to_string(),
        "--socket-timeout".to_string(),
        "30".to_string(),
    ];
    args.extend(cookies.args.iter().cloned());
    args.extend(cookies.extractor_args());
    args.push(url.to_string());
    args
}

/// Args for downloading a full video: best video + best audio muxed into an
/// `.mp4` container via ffmpeg (`--merge-output-format mp4`).
pub fn ytdlp_video_args(url: &str, dest_pattern: &str, cookies: &ResolvedCookies) -> Vec<String> {
    let mut args = vec![
        "-f".to_string(),
        "bv*+ba/b".to_string(),
        "--merge-output-format".to_string(),
        "mp4".to_string(),
        "-o".to_string(),
        dest_pattern.to_string(),
        "--newline".to_string(),
        "--no-colors".to_string(),
        "--no-playlist".to_string(),
        "--force-ipv4".to_string(),
        "--socket-timeout".to_string(),
        "30".to_string(),
    ];
    args.extend(cookies.args.iter().cloned());
    args.extend(cookies.extractor_args());
    args.push(url.to_string());
    args
}

/// Streaming read of a (possibly large) stdout JSON line-by-line is not
/// needed here; probe output is small. This helper is used by tests.
pub async fn read_first_line<R: tokio::io::AsyncBufRead + Unpin>(reader: R) -> Result<String> {
    let mut reader = BufReader::new(reader);
    let mut first = String::new();
    let n = reader.read_line(&mut first).await?;
    if n == 0 {
        bail!("sin salida");
    }
    Ok(first)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn heuristic_longs_are_speech() {
        assert!(likely_speech(Some(50 * 60), None, None));
        assert!(likely_speech(Some(120), Some("My Podcast Show"), None));
        assert!(likely_speech(
            Some(120),
            None,
            Some("Episode: Talk with guests")
        ));
        assert!(!likely_speech(Some(180), Some("Official Music"), None));
        assert!(!likely_speech(Some(120), None, Some("Song Title")));
    }

    #[test]
    fn sanitize_rejects_bad_input() {
        assert!(sanitize_url("https://youtube.com/watch?v=x").is_ok());
        assert!(sanitize_url("  https://ok.com  ").is_ok());
        assert!(sanitize_url("javascript:alert(1)").is_err());
        assert!(sanitize_url("file:///etc/passwd").is_err());
        assert!(sanitize_url("https://x.com/a b").is_err());
        assert!(sanitize_url("https://x.com/a\n--exec").is_err());
        assert!(sanitize_url("").is_err());
    }

    #[test]
    fn stream_args_use_argv_not_shell() {
        let args = ytdlp_stream_args("https://youtube.com/watch?v=abc", &ResolvedCookies::none());
        assert!(args.contains(&"-o".to_string()));
        assert!(args.contains(&"-".to_string()));
        assert!(args.iter().any(|a| a.contains("https://")));
        // El player client anti-bot viaja siempre, incluso sin cookies.
        assert!(args.contains(&"--extractor-args".to_string()));
    }

    #[test]
    fn stream_args_include_cookies() {
        let cookies = ResolvedCookies {
            args: vec!["--cookies-from-browser".to_string(), "chrome".to_string()],
            browser: Some("chrome".to_string()),
        };
        let args = ytdlp_stream_args("https://youtube.com/watch?v=abc", &cookies);
        assert!(args.contains(&"--cookies-from-browser".to_string()));
        assert!(args.contains(&"chrome".to_string()));
        // Con cookies no se usa tv (invalidaría la sesión): web_safari.
        assert!(args.contains(&"youtube:player_client=web_safari".to_string()));
        // La URL siempre va al final, tras las cookies.
        assert_eq!(args.last().unwrap(), "https://youtube.com/watch?v=abc");
    }

    #[test]
    fn video_args_mux_to_mp4() {
        let args = ytdlp_video_args(
            "https://youtube.com/watch?v=abc",
            "tmp/%(ext)s",
            &ResolvedCookies::none(),
        );
        assert!(args.contains(&"bv*+ba/b".to_string()));
        assert!(args.contains(&"mp4".to_string()));
        assert!(args.contains(&"tmp/%(ext)s".to_string()));
    }

    #[test]
    fn preview_format_single_file_selections() {
        // Audio: solo-audio; vídeo: mejor archivo único (progresivo),
        // capado a 480p para arrancar antes, porque el reproductor solo
        // acepta una URL.
        assert_eq!(preview_format(false), "ba/b");
        assert_eq!(preview_format(true), "b[height<=480]/b");
    }
}
