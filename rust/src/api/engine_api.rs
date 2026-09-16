//! FRB surface: everything the Flutter UI can call.

use std::sync::OnceLock;

use anyhow::Result;
use serde::{Deserialize, Serialize};

use crate::frb_generated::StreamSink;

use crate::engine::events::Event;
use crate::engine::models::{
    ContentKind, Playlist, ProbeInfo, SearchHistoryEntry, SortOrder, Track,
};
use crate::engine::{pipeline, AppEngine};

/// The single shared engine instance.
static ENGINE: OnceLock<AppEngine> = OnceLock::new();

fn engine_ref() -> &'static AppEngine {
    ENGINE
        .get()
        .expect("engine not initialized: call RustLib.init() first")
}

/// Initialize the engine (directories, SQLite, settings) and start background
/// workers. Called explicitly from Dart after `RustLib.init()` (and after
/// `set_app_dir()` on mobile) — NOT auto-run, so the app dir override lands
/// before the engine touches the filesystem.
#[flutter_rust_bridge::frb]
pub async fn init_app() -> Result<()> {
    flutter_rust_bridge::setup_default_user_utils();
    if ENGINE.get().is_some() {
        return Ok(());
    }
    let engine = AppEngine::init().await?;
    let _ = ENGINE.set(engine);

    // El usuario nunca descarga nada a mano: el motor se auto-abastece en
    // segundo plano (binarios integrados en el release o descarga silenciosa
    // la primera vez) y el check de versión llega después, ya con motor.
    tokio::spawn(async move {
        let _ = ensure_engine_binaries().await;
        let engine = engine_ref().clone();
        let _ = crate::engine::ytdlp::check_and_update(&engine).await;
    });
    Ok(())
}

// ---- downloads ----------------------------------------------------------

/// Query metadata for a URL without downloading anything.
#[flutter_rust_bridge::frb]
pub async fn probe_url(url: String) -> Result<ProbeInfo> {
    crate::engine::downloader::probe(&url).await
}

/// Start a download+convert task. Returns a task id; progress and result are
/// delivered on the event stream.
#[flutter_rust_bridge::frb]
pub async fn start_download(url: String, kind: ContentKind) -> Result<String> {
    pipeline::start_download(engine_ref(), url, kind)
}

/// Cancel a running download task.
#[flutter_rust_bridge::frb]
pub async fn cancel_download(task_id: String) -> Result<()> {
    engine_ref().cancel_download(&task_id).await
}

/// Number of currently active downloads.
#[flutter_rust_bridge::frb]
pub async fn active_download_count() -> Result<i64> {
    Ok(engine_ref().active_downloads().await as i64)
}

// ---- library ------------------------------------------------------------

#[flutter_rust_bridge::frb]
pub async fn get_library(search: Option<String>, order: SortOrder) -> Result<Vec<Track>> {
    engine_ref().db.list_tracks(search.as_deref(), order).await
}

#[flutter_rust_bridge::frb]
pub async fn get_track(id: String) -> Result<Option<Track>> {
    engine_ref().db.get_track(&id).await
}

/// Delete a track from the library and remove its cached files.
#[flutter_rust_bridge::frb]
pub async fn delete_track(id: String) -> Result<Option<Track>> {
    let engine = engine_ref();
    let track = engine.db.delete_track(&id).await?;
    if let Some(t) = &track {
        let _ = std::fs::remove_file(&t.file_path);
        if let Some(thumb) = &t.thumbnail_path {
            let _ = std::fs::remove_file(thumb);
        }
        engine.emit(Event::LibraryChanged);
    }
    Ok(track)
}

/// Record a playback: bumps play_count and stamps last_played.
#[flutter_rust_bridge::frb]
pub async fn record_play(id: String) -> Result<()> {
    engine_ref()
        .db
        .record_play(&id, &chrono::Utc::now().to_rfc3339())
        .await
}

/// Record a completed listen (playhead reached the end of the track):
/// bumps completed_count, accumulates listened seconds and refreshes
/// last_played. Feeds the expert shuffle.
#[flutter_rust_bridge::frb]
pub async fn record_play_completed(id: String, listened_seconds: i64) -> Result<()> {
    engine_ref()
        .db
        .record_play_completed(&id, listened_seconds, &chrono::Utc::now().to_rfc3339())
        .await
}

// ---- playlists ----------------------------------------------------------

#[flutter_rust_bridge::frb]
pub async fn create_playlist(name: String) -> Result<Playlist> {
    engine_ref().db.create_playlist(&name).await
}

#[flutter_rust_bridge::frb]
pub async fn rename_playlist(id: String, name: String) -> Result<()> {
    engine_ref().db.rename_playlist(&id, &name).await
}

#[flutter_rust_bridge::frb]
pub async fn delete_playlist(id: String) -> Result<()> {
    let engine = engine_ref();
    engine.db.delete_playlist(&id).await?;
    engine.emit(Event::LibraryChanged);
    Ok(())
}

#[flutter_rust_bridge::frb]
pub async fn list_playlists() -> Result<Vec<Playlist>> {
    engine_ref().db.list_playlists().await
}

#[flutter_rust_bridge::frb]
pub async fn add_to_playlist(playlist_id: String, track_id: String) -> Result<()> {
    engine_ref()
        .db
        .add_to_playlist(&playlist_id, &track_id)
        .await
}

#[flutter_rust_bridge::frb]
pub async fn remove_from_playlist(playlist_id: String, track_id: String) -> Result<()> {
    engine_ref()
        .db
        .remove_from_playlist(&playlist_id, &track_id)
        .await
}

#[flutter_rust_bridge::frb]
pub async fn reorder_playlist(playlist_id: String, ordered_track_ids: Vec<String>) -> Result<()> {
    engine_ref()
        .db
        .reorder_playlist(&playlist_id, &ordered_track_ids)
        .await
}

#[flutter_rust_bridge::frb]
pub async fn playlist_tracks(playlist_id: String) -> Result<Vec<Track>> {
    engine_ref().db.playlist_tracks(&playlist_id).await
}

// ---- search history ------------------------------------------------------

#[flutter_rust_bridge::frb]
pub async fn record_search(query: String, source: String) -> Result<()> {
    engine_ref().db.record_search(&query, &source).await
}

#[flutter_rust_bridge::frb]
pub async fn recent_searches(source: String, limit: i64) -> Result<Vec<SearchHistoryEntry>> {
    engine_ref().db.recent_searches(&source, limit).await
}

#[flutter_rust_bridge::frb]
pub async fn delete_search(id: i64) -> Result<()> {
    engine_ref().db.delete_search(id).await
}

// ---- settings -----------------------------------------------------------

#[flutter_rust_bridge::frb]
pub async fn get_setting(key: String) -> Result<Option<String>> {
    engine_ref().db.get_setting(&key).await
}

#[flutter_rust_bridge::frb]
pub async fn set_setting(key: String, value: String) -> Result<()> {
    engine_ref().db.set_setting(&key, &value).await
}

#[derive(Serialize, Deserialize)]
pub struct AppDirs {
    pub home: String,
    pub cache: String,
    pub thumbs: String,
    pub tmp: String,
}

#[flutter_rust_bridge::frb]
pub async fn app_dirs() -> Result<AppDirs> {
    let engine = engine_ref();
    Ok(AppDirs {
        home: crate::engine::paths::app_home()
            .to_string_lossy()
            .to_string(),
        cache: engine.cache_dir.to_string_lossy().to_string(),
        thumbs: engine.thumbs_dir.to_string_lossy().to_string(),
        tmp: engine.tmp_dir.to_string_lossy().to_string(),
    })
}

// ---- yt-dlp -------------------------------------------------------------

#[derive(Serialize, Deserialize)]
pub struct YtdlpInfo {
    pub present: bool,
    pub version: Option<String>,
    pub outdated: bool,
    pub last_checked: Option<String>,
}

/// Snapshot of the last yt-dlp check (from persisted settings).
#[flutter_rust_bridge::frb]
pub async fn get_ytdlp_status() -> Result<YtdlpInfo> {
    let db = &engine_ref().db;
    let version = db.get_setting(crate::engine::SETTING_YTDLP_VERSION).await?;
    let last_checked = db
        .get_setting(crate::engine::SETTING_YTDLP_CHECKED_AT)
        .await?;
    let present = crate::engine::process::ytdlp_bin().is_some();
    // Sin binario no hay nada que comparar: `outdated` solo aplica cuando
    // hay versión instalada (si no, la UI diría "desactualizado" en vacío).
    let outdated = present
        && version
            .as_deref()
            .map(crate::engine::ytdlp::is_outdated)
            .unwrap_or(false);
    Ok(YtdlpInfo {
        present,
        version,
        outdated,
        last_checked,
    })
}

/// Run the yt-dlp check/update in the background. Results arrive as a
/// `YtdlpStatus` event.
#[flutter_rust_bridge::frb]
pub async fn check_ytdlp() -> Result<()> {
    let engine = engine_ref().clone();
    tokio::spawn(async move {
        let _ = crate::engine::ytdlp::check_and_update(&engine).await;
    });
    Ok(())
}

// ---- app data dir -------------------------------------------------------

/// Fija el directorio base de datos del motor (db, caché, tmp, binarios).
/// En Android/iOS Dart pasa el directorio privado de la app antes de
/// cualquier otra llamada; en escritorio no se usa (vale `dirs::config_dir`).
#[flutter_rust_bridge::frb]
pub async fn set_app_dir(path: String) -> Result<()> {
    let home = std::path::PathBuf::from(&path);
    crate::engine::paths::set_app_home(home);
    Ok(())
}

// ---- engine binaries (mobile) -------------------------------------------
#[derive(Serialize, Deserialize)]
pub struct BinariesStatus {
    pub yt_dlp_present: bool,
    pub ffmpeg_present: bool,
    pub bin_dir: String,
}

/// Presence of the runtime binaries used by the engine. Found in the app
/// `bin_dir` (runtime download), next to the executable (bundled, e.g. the
/// Windows .zip) or in PATH.
#[flutter_rust_bridge::frb]
pub async fn binaries_status() -> Result<BinariesStatus> {
    Ok(BinariesStatus {
        yt_dlp_present: crate::engine::process::ytdlp_bin().is_some(),
        ffmpeg_present: crate::engine::process::ffmpeg_bin().is_some(),
        bin_dir: crate::engine::paths::bin_dir()
            .to_string_lossy()
            .to_string(),
    })
}

/// Default download sources for the runtime binaries. Overridable via
/// the `binary.ytdlp_url` / `binary.ffmpeg_url` settings (only set
/// programmatically; there is no UI for them — the engine self-provisions).
/// Host your own static builds (e.g. a `OfflineAudio-Binaries` release) and
/// point these URLs there.
///
/// Versiones del runtime Android pineadas en
/// `flutter/tool/android/runtime_versions.env`; mantener sincronizado
/// `YTDLP_RUNTIME_*` con ese fichero (el build falla si el zip no coincide).
#[cfg(target_os = "android")]
pub const YTDLP_RUNTIME_YTDLP_VERSION: &str = "2026.08.19";
#[cfg(target_os = "android")]
pub const YTDLP_RUNTIME_PYTHON_MM: &str = "3.14";
#[cfg(all(target_os = "android", target_arch = "aarch64"))]
const DEFAULT_FFMPEG_URL: &str =
    "https://github.com/Tyrrrz/FFmpegBin/releases/latest/download/ffmpeg-android-arm64.zip";
#[cfg(all(target_os = "android", target_arch = "arm"))]
const DEFAULT_FFMPEG_URL: &str =
    "https://github.com/Tyrrrz/FFmpegBin/releases/latest/download/ffmpeg-android-arm.zip";
#[cfg(all(target_os = "android", target_arch = "x86_64"))]
const DEFAULT_FFMPEG_URL: &str =
    "https://github.com/Tyrrrz/FFmpegBin/releases/latest/download/ffmpeg-android-x64.zip";
#[cfg(all(target_os = "android", target_arch = "x86"))]
const DEFAULT_FFMPEG_URL: &str =
    "https://github.com/Tyrrrz/FFmpegBin/releases/latest/download/ffmpeg-android-x86.zip";
/// On desktop yt-dlp ships a standalone executable per OS in its official
/// releases; it is downloaded into the app bin dir (found first by
/// `ytdlp_bin`, ahead of any copy bundled next to the app executable).
#[cfg(target_os = "windows")]
const DEFAULT_YTDLP_URL: &str =
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe";
#[cfg(target_os = "windows")]
const DEFAULT_YTDLP_NAME: &str = "yt-dlp.exe";
#[cfg(target_os = "macos")]
const DEFAULT_YTDLP_URL: &str =
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos";
#[cfg(target_os = "linux")]
const DEFAULT_YTDLP_URL: &str = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp";
#[cfg(any(target_os = "macos", target_os = "linux"))]
const DEFAULT_YTDLP_NAME: &str = "yt-dlp";

/// ffmpeg por defecto en escritorio (misma fuente que empaquetan los
/// releases del CI, para que "Descargar" repare lo mismo que trae el .zip):
/// Windows = Gyan essentials (zip anidado), macOS = Tyrrrz por arch,
/// Linux = BtbN gpl zip. En Android siguen siendo los builds por ABI.
#[cfg(target_os = "windows")]
const DEFAULT_FFMPEG_URL: &str = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip";
#[cfg(target_os = "macos")]
const DEFAULT_FFMPEG_URL_ARM: &str =
    "https://github.com/Tyrrrz/FFmpegBin/releases/latest/download/ffmpeg-osx-arm64.zip";
#[cfg(target_os = "macos")]
const DEFAULT_FFMPEG_URL_X64: &str =
    "https://github.com/Tyrrrz/FFmpegBin/releases/latest/download/ffmpeg-osx-x64.zip";
#[cfg(target_os = "linux")]
const DEFAULT_FFMPEG_URL: &str =
    "https://github.com/BtbN/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-linux64-gpl.zip";

/// Base de los assets del runtime de yt-dlp para Android (launcher + CPython
/// + wheel), publicados por el workflow `ytdlp-runtime` en cada release.
/// No existe build oficial de yt-dlp para Android (bionic), así que el propio
/// repo distribuye el bundle autocontenido por ABI. Solo hay builds de 64
/// bits: python.org no publica CPython embeddable de 32 bits para Android.
#[cfg(target_os = "android")]
const YTDLP_RUNTIME_RELEASE_BASE: &str =
    "https://github.com/danielferparradiaz/OfflineAudio/releases/latest/download";

/// Default del runtime de yt-dlp según la ABI del dispositivo. Se resuelve en
/// tiempo de ejecución (no con `cfg(target_arch)`) porque lo que importa es
/// la ABI del APK que corre, no la del host de compilación.
#[cfg(target_os = "android")]
fn default_ytdlp_runtime_url() -> anyhow::Result<String> {
    let asset = match std::env::consts::ARCH {
        "aarch64" => "OfflineAudio-ytdlp-arm64-v8a.zip",
        "x86_64" => "OfflineAudio-ytdlp-x86_64.zip",
        other => anyhow::bail!(
            "yt-dlp no disponible en esta ABI ({other}): el runtime solo existe para arm64-v8a y x86_64."
        ),
    };
    Ok(format!("{YTDLP_RUNTIME_RELEASE_BASE}/{asset}"))
}
/// Garantiza yt-dlp + ffmpeg sin pedirle nada al usuario. Si ya están
/// (integrados en el release, en PATH o descargados antes) es un chequeo
/// barato; si falta alguno se descarga en silencio con las mismas fuentes
/// pineadas del release. Las descargas concurrentes se serializan con un
/// candado global para no bajar dos veces lo mismo. En caso de fallo
/// (p. ej. sin conexión) devuelve un error neutro: el arranque y los
/// reintentos lo volverán a intentar solos.
pub async fn ensure_engine_binaries() -> Result<()> {
    use crate::engine::process::{ffmpeg_bin, ytdlp_bin};
    if ytdlp_bin().is_some() && ffmpeg_bin().is_some() {
        return Ok(());
    }
    static LOCK: std::sync::OnceLock<tokio::sync::Mutex<()>> = std::sync::OnceLock::new();
    let _guard = LOCK
        .get_or_init(|| tokio::sync::Mutex::new(()))
        .lock()
        .await;
    // Re-chequear tras el candado: otra tarea pudo completar la descarga.
    if ytdlp_bin().is_some() && ffmpeg_bin().is_some() {
        return Ok(());
    }
    provision_engine_binaries().await
}

/// Descarga yt-dlp + ffmpeg en el bin dir de la app. Funciona en todas las
/// plataformas: en Android ffmpeg viene de builds por ABI (Tyrrrz/FFmpegBin)
/// y yt-dlp como runtime autocontenido publicado por este repo (no existe
/// build oficial: glibc/musl frente a bionic); en escritorio yt-dlp viene de
/// su release oficial y ffmpeg de la misma fuente que empaquetan los
/// releases del CI (Gyan/Tyrrrz/BtbN). iOS no puede ejecutar binarios
/// externos (sandbox).
async fn provision_engine_binaries() -> Result<()> {
    #[cfg(target_os = "ios")]
    {
        anyhow::bail!(
            "Motor de descargas no disponible en este dispositivo. \
             Se reintentará automáticamente."
        );
    }

    #[cfg(not(target_os = "ios"))]
    {
        let db = &engine_ref().db;
        #[cfg(target_os = "android")]
        {
            // Fail-fast en ABIs sin runtime (32 bits): antes de bajar nada,
            // para no dejar medio instalado ffmpeg y luego fallar yt-dlp.
            let yt_url = match db.get_setting("binary.ytdlp_url").await? {
                Some(u) if !u.trim().is_empty() => u,
                _ => default_ytdlp_runtime_url()?,
            };
            let ff_url = db
                .get_setting("binary.ffmpeg_url")
                .await?
                .filter(|u| !u.trim().is_empty())
                .unwrap_or_else(|| DEFAULT_FFMPEG_URL.to_string());
            let ff_bin = crate::engine::process::download_zip_binary("ffmpeg", &ff_url).await?;
            crate::engine::process::smoke_binary(&ff_bin, &["-version"]).await?;
            // yt-dlp llega como runtime autocontenido (zip con launcher +
            // CPython + wheel). La instalación es atómica + smoke
            // `--version` dentro de `download_ytdlp_runtime`.
            let launcher = crate::engine::process::download_ytdlp_runtime(&yt_url).await?;
            let _ = launcher;
            Ok(())
        }
        #[cfg(not(target_os = "android"))]
        {
            let yt_url = db
                .get_setting("binary.ytdlp_url")
                .await?
                .filter(|u| !u.trim().is_empty())
                .unwrap_or_else(|| DEFAULT_YTDLP_URL.to_string());
            // Si el release ya trae el binario integrado no se toca.
            if crate::engine::process::ytdlp_bin().is_none() {
                let yt_bin =
                    crate::engine::process::download_binary(DEFAULT_YTDLP_NAME, &yt_url).await?;
                crate::engine::process::smoke_binary(&yt_bin, &["--version"]).await?;
            }
            // ffmpeg: si ya está (integrado junto al ejecutable o en PATH)
            // no se toca; si falta se baja de la misma fuente del CI.
            if crate::engine::process::ffmpeg_bin().is_none() {
                download_desktop_ffmpeg(db).await?;
            }
            if crate::engine::process::ffmpeg_bin().is_none()
                || crate::engine::process::ytdlp_bin().is_none()
            {
                anyhow::bail!(
                    "No se pudo preparar el motor de descargas. \
                     Comprueba tu conexión; se reintentará automáticamente."
                );
            }
            Ok(())
        }
    }
}

/// Compatibilidad: antes lo llamaba un botón de Ajustes (ya eliminado; el
/// motor se auto-abastece). Se mantiene expuesto por si hace falta
/// re-provisionar desde diagnósticos.
#[flutter_rust_bridge::frb]
pub async fn download_mobile_binaries() -> Result<()> {
    ensure_engine_binaries().await
}
/// Baja ffmpeg en escritorio desde la fuente del CI (o `binary.ffmpeg_url`
/// si el usuario la configuró) y verifica que arranque. El zip anidado de
/// cada proveedor se resuelve por sufijo.
#[cfg(not(target_os = "android"))]
async fn download_desktop_ffmpeg(db: &crate::storage::AppDatabase) -> anyhow::Result<()> {
    use crate::engine::process as proc;
    if let Some(custom) = db
        .get_setting("binary.ffmpeg_url")
        .await?
        .filter(|u| !u.trim().is_empty())
    {
        // URL personalizada: se asume el layout Tyrrrz (un `ffmpeg` en la
        // raíz del zip); si tu zip lo trae anidado, usa el nombre con el que
        // lo publiques o apunta al binario directo.
        if custom.ends_with(".zip") {
            let bin = proc::download_zip_binary("ffmpeg", &custom).await?;
            proc::smoke_binary(&bin, &["-version"]).await?;
        } else {
            let bin = proc::download_binary("ffmpeg", &custom).await?;
            proc::smoke_binary(&bin, &["-version"]).await?;
        }
        return Ok(());
    }
    #[cfg(target_os = "windows")]
    {
        let bin =
            proc::download_zip_binary_suffix("ffmpeg.exe", DEFAULT_FFMPEG_URL, "bin/ffmpeg.exe")
                .await?;
        proc::smoke_binary(&bin, &["-version"]).await?;
        Ok(())
    }
    #[cfg(target_os = "macos")]
    {
        let url = match std::env::consts::ARCH {
            "aarch64" => DEFAULT_FFMPEG_URL_ARM,
            _ => DEFAULT_FFMPEG_URL_X64,
        };
        // Se guarda como `ffmpeg-<arch>` igual que el bundle del CI para que
        // `ffmpeg_bin()` lo prefiera en su arquitectura.
        let dest = format!("ffmpeg-{}", std::env::consts::ARCH);
        let bin = proc::download_zip_binary(&dest, url).await?;
        proc::smoke_binary(&bin, &["-version"]).await?;
        Ok(())
    }
    #[cfg(target_os = "linux")]
    {
        let bin =
            proc::download_zip_binary_suffix("ffmpeg", DEFAULT_FFMPEG_URL, "bin/ffmpeg").await?;
        proc::smoke_binary(&bin, &["-version"]).await?;
        Ok(())
    }
    #[cfg(target_os = "ios")]
    {
        let _ = db;
        anyhow::bail!("ffmpeg no disponible en iOS (sandbox)");
    }
}

// ---- events -------------------------------------------------------------

/// Subscribe to engine events. The returned stream must be listened to as a
/// native Dart stream (`RustStreamSink`).
#[flutter_rust_bridge::frb]
pub async fn event_stream(sink: StreamSink<Event>) -> Result<()> {
    use std::collections::HashMap;
    use std::time::Duration;

    let mut rx = engine_ref().subscribe_events();
    tokio::spawn(async move {
        // Coalescing forwarder. A long download emits many progress events far
        // faster than the UI consumes them, and a full broadcast buffer used to
        // kill the whole stream (`Lagged`), silently dropping the terminal
        // events the UI depends on (finished/cancelled/failed). Here progress
        // snapshots are collapsed to the newest one per task and flushed a few
        // times a second, so the live bar still moves, while every non-progress
        // event is always forwarded and Lagged is treated as "skip stale data".
        const FLUSH_INTERVAL: Duration = Duration::from_millis(300);
        let mut pending: HashMap<String, Event> = HashMap::new();

        loop {
            let (ev, tick) = tokio::select! {
                r = rx.recv() => match r {
                    Ok(ev) => (Some(ev), false),
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => (None, false),
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => return,
                },
                _ = tokio::time::sleep(FLUSH_INTERVAL) => (None, true),
            };

            if let Some(ev) = ev {
                match &ev {
                    Event::DownloadProgress { task_id, .. } => {
                        pending.insert(task_id.clone(), ev);
                    }
                    _ => {
                        // Send the freshest progress before any terminal event
                        // so the UI lands on the final percentage.
                        for e in pending.drain().map(|(_, e)| e) {
                            if sink.add(e).is_err() {
                                return;
                            }
                        }
                        if sink.add(ev).is_err() {
                            return;
                        }
                        continue;
                    }
                }
            }

            if tick {
                for e in pending.drain().map(|(_, e)| e) {
                    if sink.add(e).is_err() {
                        return;
                    }
                }
            }
        }
    });
    Ok(())
}
