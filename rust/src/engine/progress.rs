//! Parser for yt-dlp progress output.
//!
//! yt-dlp writes lines of the form (with `--newline --no-colors`):
//! ```text
//! [download]  43.7% of 13.40MiB at 1.23MiB/s ETA 00:07
//! [download] 100% of 13.40MiB
//! ```

use once_cell::sync::Lazy;
use regex::Regex;

#[derive(Debug, Clone, PartialEq)]
pub struct ProgressStatus {
    pub percent: f32,
    pub total_bytes: Option<u64>,
    pub downloaded_bytes: u64,
    pub speed_bytes_sec: Option<u64>,
    pub eta_secs: Option<u64>,
    pub is_fraction: bool,
}

static PROGRESS_RE: Lazy<Regex> = Lazy::new(|| {
    Regex::new(
        r"^\[download\]\s*(?P<fraction>[0-9.]+)%\s+of\s+(?:~)?(?P<total>[0-9.]+\s*(?:[KMGT]i?B|B)?)(?:\s+at\s+(?P<speed>[0-9.]+\s*(?:[KMGT]i?B|B)/s))?(?:\s+ETA\s+(?P<eta>[0-9:]+))?",
    )
    .unwrap()
});

static SIZE_RE: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"^(?P<val>[0-9.]+)\s*(?P<unit>[KMGT]i?B|B)?$").unwrap());

/// `1.23MiB` -> bytes. Also accepts `MB`, `KiB`, `GB`, plain `B`/suffixed.
pub fn parse_size(s: &str) -> Option<u64> {
    let caps = SIZE_RE.captures(s.trim())?;
    let val: f64 = caps.name("val")?.as_str().parse().ok()?;
    let mult: f64 = match caps.name("unit").map(|m| m.as_str()) {
        Some("KiB") | Some("Ki") | Some("kB") => 1024.0,
        Some("MiB") | Some("Mi") | Some("MB") => 1024.0f64.powi(2),
        Some("GiB") | Some("Gi") | Some("GB") => 1024.0f64.powi(3),
        Some("TiB") | Some("Ti") | Some("TB") => 1024.0f64.powi(4),
        Some("B") | None => 1.0,
        _ => 1.0,
    };
    Some((val * mult).round() as u64)
}

/// `1.23MiB/s` -> bytes per second.
pub fn parse_speed(s: &str) -> Option<u64> {
    let inner = s.trim().strip_suffix("/s")?;
    parse_size(inner)
}

/// `00:07` or `1:02:03` -> seconds.
pub fn parse_eta(s: &str) -> Option<u64> {
    let parts: Vec<&str> = s.trim().split(':').collect();
    if parts.is_empty() || parts.len() > 3 {
        return None;
    }
    let mut secs: u64 = 0;
    for part in &parts {
        let v: u64 = part.parse().ok()?;
        secs = secs.saturating_mul(60).saturating_add(v);
    }
    Some(secs)
}

/// Parse one yt-dlp `[download]` line. Returns `None` for anything that is not
/// a progress percentage (e.g. `[download] Destination: foo`).
pub fn parse_progress_line(line: &str) -> Option<ProgressStatus> {
    let caps = PROGRESS_RE.captures(line)?;
    let percent_raw: f32 = caps.name("fraction")?.as_str().parse().ok()?;
    let percent = percent_raw.clamp(0.0, 100.0);
    let total_bytes = caps.name("total").and_then(|m| parse_size(m.as_str()));
    let speed_bytes_sec = caps.name("speed").and_then(|m| parse_speed(m.as_str()));
    let eta_secs = caps.name("eta").and_then(|m| parse_eta(m.as_str()));
    let downloaded_bytes = total_bytes
        .map(|total| ((total as f64) * (percent as f64 / 100.0)).round() as u64)
        .unwrap_or(0);
    Some(ProgressStatus {
        percent,
        total_bytes,
        downloaded_bytes,
        speed_bytes_sec,
        eta_secs,
        is_fraction: percent < 100.0,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_size_values() {
        assert_eq!(parse_size("100B"), Some(100));
        assert_eq!(parse_size("1.00MiB"), Some(1_048_576));
        assert_eq!(parse_size("2.50MiB"), Some(2_621_440));
        assert_eq!(parse_size("500.00KiB"), Some(512_000));
        assert_eq!(parse_size("1.00GiB"), Some(1_073_741_824));
        assert_eq!(parse_size("12MB"), Some(12_582_912));
        assert_eq!(parse_size("7B"), Some(7));
    }

    #[test]
    fn parse_eta_values() {
        assert_eq!(parse_eta("00:07"), Some(7));
        assert_eq!(parse_eta("1:02:03"), Some(3723));
        assert_eq!(parse_eta("7"), Some(7));
        assert_eq!(parse_eta("xx"), None);
    }

    #[test]
    fn parse_speed_values() {
        assert_eq!(parse_speed("1.23MiB/s"), Some(1_289_748));
    }

    #[test]
    fn progress_in_progress() {
        let p =
            parse_progress_line("[download]  43.7% of 13.40MiB at 1.23MiB/s ETA 00:07").unwrap();
        assert!((p.percent - 43.7).abs() < 0.01);
        assert_eq!(p.total_bytes, parse_size("13.40MiB"));
        assert_eq!(p.speed_bytes_sec, parse_speed("1.23MiB/s"));
        assert_eq!(p.eta_secs, Some(7));
        assert!(p.is_fraction);
        assert!(p.downloaded_bytes > 0);
    }

    #[test]
    fn progress_finished() {
        let p = parse_progress_line("[download] 100% of 13.40MiB").unwrap();
        assert_eq!(p.percent, 100.0);
        assert!(!p.is_fraction);
    }

    #[test]
    fn not_progress_lines_ignored() {
        assert!(parse_progress_line("[download] Destination: /tmp/x.webm").is_none());
        assert!(parse_progress_line("[youtube] Extracting URL: https://...").is_none());
        assert!(parse_progress_line("[info] Downloading format 140").is_none());
        assert!(parse_progress_line("").is_none());
    }

    #[test]
    fn fraction_of_tilde_total() {
        let p = parse_progress_line("[download]  12.5% of ~8.00MiB").unwrap();
        assert_eq!(p.total_bytes, parse_size("8.00MiB"));
        assert!((p.percent - 12.5).abs() < 0.01);
    }
}
