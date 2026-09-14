//! Filesystem layout for OfflineAudio data.
//!
//! Uses the platform configuration dir so the paths match the spec:
//!   - macOS:   ~/Library/Application Support/OfflineAudio/
//!   - Windows: %APPDATA%\OfflineAudio\
//!   - Linux:   ~/.config/OfflineAudio/

use std::path::{Path, PathBuf};

use anyhow::{Context, Result};

pub const APP_NAME: &str = "OfflineAudio";

/// Override fijado desde Dart al arrancar (móvil). `dirs::config_dir()` no
/// existe en Android/iOS (devuelve `None` y caíamos a `./OfflineAudio`, de
/// solo lectura) así que la app pasa su directorio privado y el motor lo usa
/// como base de todo: db, caché, tmp y binarios.
static APP_HOME_OVERRIDE: std::sync::OnceLock<PathBuf> = std::sync::OnceLock::new();

/// Fija el directorio base de datos. Llamar una vez antes de `AppEngine::init`.
pub fn set_app_home(path: PathBuf) {
    let _ = APP_HOME_OVERRIDE.set(path);
}

pub fn app_home() -> PathBuf {
    if let Some(home) = APP_HOME_OVERRIDE.get() {
        return home.clone();
    }
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(APP_NAME)
}

pub fn db_path() -> PathBuf {
    app_home().join("app.db")
}

pub fn cache_dir() -> PathBuf {
    app_home().join("cache").join("tracks")
}

pub fn thumbs_dir() -> PathBuf {
    app_home().join("cache").join("thumbs")
}

pub fn tmp_dir() -> PathBuf {
    app_home().join("tmp")
}

/// Directory where runtime-downloaded engine binaries live (mobile).
pub fn bin_dir() -> PathBuf {
    app_home().join("bin")
}

/// Create every directory the app needs, if missing.
pub fn ensure_dirs() -> Result<()> {
    for dir in [cache_dir(), thumbs_dir(), tmp_dir(), bin_dir()] {
        std::fs::create_dir_all(&dir)
            .with_context(|| format!("creating directory {}", dir.display()))?;
    }
    Ok(())
}

/// Available free disk space for the given path, in bytes.
#[cfg(unix)]
pub fn free_disk_bytes(path: &Path) -> Result<u64> {
    use std::ffi::CString;
    use std::mem::MaybeUninit;

    let c_path = CString::new(path.as_os_str().as_encoded_bytes())
        .map_err(|_| anyhow::anyhow!("invalid path: {}", path.display()))?;
    let mut st: libc::statvfs = unsafe { MaybeUninit::zeroed().assume_init() };
    let rc = unsafe { libc::statvfs(c_path.as_ptr(), &mut st) };
    if rc != 0 {
        return Err(anyhow::anyhow!(
            "statvfs failed for {} (errno {})",
            path.display(),
            rc
        ));
    }
    #[allow(clippy::unnecessary_cast)]
    Ok((st.f_bavail as u64).saturating_mul(st.f_frsize as u64))
}

/// Available free disk space for the given path, in bytes.
#[cfg(windows)]
pub fn free_disk_bytes(path: &Path) -> Result<u64> {
    use std::os::windows::ffi::OsStrExt;
    use winapi::shared::minwindef::BOOL;
    use winapi::um::fileapi::GetDiskFreeSpaceExW;
    use winapi::um::winnt::ULARGE_INTEGER;

    let wide: Vec<u16> = path
        .as_os_str()
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();

    let mut free_available: ULARGE_INTEGER = unsafe { std::mem::zeroed() };
    let mut total: ULARGE_INTEGER = unsafe { std::mem::zeroed() };
    let mut free: ULARGE_INTEGER = unsafe { std::mem::zeroed() };

    let ok: BOOL =
        unsafe { GetDiskFreeSpaceExW(wide.as_ptr(), &mut free_available, &mut total, &mut free) };
    if ok == 0 {
        return Err(anyhow::anyhow!(
            "GetDiskFreeSpaceEx failed for {}",
            path.display()
        ));
    }
    // En x64 el union es un solo QuadPart; en x86 hay una HighPart.
    let bytes = unsafe { *free_available.QuadPart() };
    Ok(bytes)
}
