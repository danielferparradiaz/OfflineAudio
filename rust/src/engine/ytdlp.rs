//! yt-dlp management: presence check, version pinning and self-update.

use anyhow::Result;

use crate::engine::events::Event;
use crate::engine::process::{child_log, ensure_yt_dlp, null, pipe};
use crate::engine::AppEngine;
use crate::engine::{SETTING_YTDLP_CHECKED_AT, SETTING_YTDLP_VERSION};

/// Minimum acceptable yt-dlp version (yyyy.mm.dd). yt-dlp breaks often; pin a
/// floor and surface updates rather than guessing.
pub const MIN_YTDLP_VERSION: &str = "2025.10.01";

type Version = (u32, u32, u32);

fn parse_version(s: &str) -> Option<Version> {
    let digits: Vec<u32> = s
        .trim()
        .split(['.', '-'])
        .take(3)
        .map(|p| p.parse().ok())
        .collect::<Option<Vec<u32>>>()?;
    Some((digits[0], digits[1], digits[2]))
}

pub fn is_outdated(installed: &str) -> bool {
    match (parse_version(installed), parse_version(MIN_YTDLP_VERSION)) {
        (Some(inst), Some(min)) => inst < min,
        _ => false,
    }
}

async fn installed_version(bin: &std::path::Path) -> Option<String> {
    let out = tokio::time::timeout(
        std::time::Duration::from_secs(20),
        child_log(bin, &["--version"], null(), pipe(), null()).output(),
    )
    .await
    .ok()?;
    let out = out.ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// Run the version check + optional self-update in the background, emitting a
/// `YtdlpStatus` event and persisting the outcome.
pub async fn check_and_update(engine: &AppEngine) -> Result<()> {
    let now = chrono::Utc::now().to_rfc3339();
    let bin = ensure_yt_dlp().await?;

    let mut version = installed_version(&bin).await;
    let mut outdated = version.as_deref().map(is_outdated).unwrap_or(false);
    let mut message = None;

    if outdated {
        // Try a self-update; failure is non-fatal (offline, sandboxed, etc).
        let up = tokio::time::timeout(
            std::time::Duration::from_secs(120),
            child_log(
                &bin,
                &["-U", "-q", "--no-cache-dir"],
                null(),
                null(),
                pipe(),
            )
            .output(),
        )
        .await;
        if let Ok(Ok(out)) = up {
            if out.status.success() {
                version = installed_version(&bin).await;
                outdated = version.as_deref().map(is_outdated).unwrap_or(false);
                if !outdated {
                    message = Some("yt-dlp actualizado correctamente".to_string());
                }
            } else {
                message = Some(
                    String::from_utf8_lossy(&out.stderr)
                        .lines()
                        .rev()
                        .take(3)
                        .collect::<Vec<_>>()
                        .join("\n"),
                );
            }
        }
    }

    let ev = Event::YtdlpStatus {
        present: true,
        version: version.clone(),
        outdated,
        last_checked: Some(now.clone()),
        message,
    };
    engine.emit(ev);
    if let Some(v) = version {
        engine.db.set_setting(SETTING_YTDLP_VERSION, &v).await?;
    }
    engine
        .db
        .set_setting(SETTING_YTDLP_CHECKED_AT, &now)
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_parse_and_compare() {
        assert_eq!(parse_version("2026.08.19"), Some((2026, 8, 19)));
        assert_eq!(parse_version("2025.12.31"), Some((2025, 12, 31)));
        assert!(parse_version("garbage").is_none());
        assert!(!is_outdated("2026.08.19"));
        assert!(!is_outdated("2025.10.01"));
        assert!(is_outdated("2025.09.30"));
        assert!(is_outdated("2024.01.01"));
    }
}
