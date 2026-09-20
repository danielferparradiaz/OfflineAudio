//! Cookies de YouTube para yt-dlp (`--cookies-from-browser` / `--cookies`).
//!
//! YouTube responde cada vez más con `Sign in to confirm you're not a bot`.
//! El login con usuario+contraseña (`--username`/`--netrc`) ya no funciona
//! para YouTube: la única salida soportada es reutilizar las cookies de una
//! sesión real del navegador.
//!
//! Modo `auto` (por defecto): se detecta el primer navegador con perfil en
//! disco y se pasa `--cookies-from-browser <navegador>` a todos los comandos
//! de yt-dlp. Si no hay ninguno, se llama sin cookies (vídeos no
//! restringidos siguen funcionando). Un archivo `cookies.txt` explícito
//! (`ytdlp.cookies_file`) tiene prioridad sobre el navegador.

use crate::storage::AppDatabase;

pub const SETTING_COOKIES_BROWSER: &str = "ytdlp.cookies_browser";
pub const SETTING_COOKIES_FILE: &str = "ytdlp.cookies_file";

/// Valor que desactiva las cookies aunque haya navegador.
pub const COOKIES_OFF: &str = "off";
/// Valor por defecto: detectar solo.
pub const COOKIES_AUTO: &str = "auto";

/// Navegadores soportados por yt-dlp para `--cookies-from-browser`, en orden
/// de preferencia para la detección automática (Safari al final: en macOS
/// suele pedir Full Disk Access y falla más).
pub fn supported_browsers() -> &'static [&'static str] {
    &[
        "chrome", "brave", "edge", "chromium", "firefox", "opera", "vivaldi", "safari",
    ]
}

pub fn is_supported_browser(name: &str) -> bool {
    supported_browsers().contains(&name.to_lowercase().as_str())
}

/// ¿Este stderr es el reto anti-bot de YouTube?
pub fn is_bot_challenge(text: &str) -> bool {
    let lower = text.to_lowercase();
    lower.contains("sign in to confirm you’re not a bot")
        || lower.contains("sign in to confirm you're not a bot")
        || lower.contains("confirm you’re not a bot")
        || lower.contains("confirm you're not a bot")
        || (lower.contains("not a bot") && lower.contains("youtube"))
        || (lower.contains("use --cookies") && lower.contains("youtube"))
}

/// ¿Falló la propia extracción de cookies (perfil bloqueado, sin permiso,
/// navegador no encontrado, TCC de macOS)? En ese caso vale reintentar sin
/// cookies: el vídeo quizá no necesitaba login.
pub fn is_cookie_extraction_failure(text: &str) -> bool {
    let lower = text.to_lowercase();
    if !(lower.contains("cookie") || lower.contains("browser")) {
        return false;
    }
    [
        "could not copy",
        "could not open",
        "could not find",
        "could not read",
        "could not get",
        "not found",
        "no such file",
        "database",
        "failed",
        "failure",
        "error extracting",
        "error getting",
        "permission",
        "denied",
        "blocked",
        "tcc",
        "operation not permitted",
        "oserror",
        "errno 1",
        "locked",
        "in use",
        "running",
        "snap",
        "flatpak",
        "keyring",
        "keychain",
        "full disk access",
        "archivos y carpetas",
    ]
    .iter()
    .any(|k| lower.contains(k))
}

/// Mensaje corto cuando ni siquiera se pudieron leer las cookies del
/// navegador (DB inexistente, perfil bloqueado o bloqueo de macOS).
/// Distinto del reto anti-bot: aquí el problema es local, no de YouTube.
pub fn friendly_cookie_extraction_error(browser_used: Option<&str>, tail: &str) -> String {
    let where_hint = match browser_used {
        Some(b) => format!("de {b}"),
        None => "del navegador".to_string(),
    };
    // Recorta el tail crudo a 2 líneas para no inundar la UI.
    let raw: String = tail
        .lines()
        .filter(|l| !l.trim().is_empty())
        .rev()
        .take(2)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect::<Vec<_>>()
        .join("\n");
    format!(
        "No se pudieron leer las cookies {where_hint} ({raw}). En Ajustes → \
         YouTube cambia de navegador o ponlo en «off» para reintentar sin \
         cookies. En macOS, «--cookies-from-browser» puede pedir permiso en \
         Ajustes del Sistema → Privacidad y seguridad → Archivos y carpetas; \
         lo más fiable es exportar un cookies.txt con «Get cookies.txt \
         LOCALLY» y usarlo en Ajustes."
    )
}

/// Mensaje corto en español cuando YouTube pide login aunque ya pasamos
/// cookies (o no había ninguna que pasar).
pub fn friendly_bot_error(browser_used: Option<&str>) -> String {
    match browser_used {
        Some(b) => format!(
            "YouTube pidió iniciar sesión para confirmar que no eres un bot, \
             incluso con cookies de {b}. Abre YouTube en {b} con tu cuenta, \
             reproduce un vídeo y reintenta. Si sigue fallando, en Ajustes → \
             YouTube cambia el navegador o exporta un cookies.txt."
        ),
        None => "YouTube pidió iniciar sesión para confirmar que no eres un \
         bot. Abre YouTube en tu navegador con tu cuenta, reproduce un vídeo \
         y reintenta con las cookies automáticas activadas (Ajustes → \
         YouTube). O exporta un cookies.txt con la extensión «Get \
         cookies.txt LOCALLY»."
            .to_string(),
    }
}

/// ¿Hay DB real de cookies bajo un `User Data` chromium
/// (`<dir>/Default/Cookies`, `<dir>/Default/Network/Cookies` o cualquier
/// `<dir>/<perfil>/Cookies`)? Mirar solo si existe el dir da falsos
/// positivos (Chrome instalado pero sin sesión) y yt-dlp falla con
/// `could not find chrome cookies database`.
fn chromium_cookies_present(user_data: &std::path::Path) -> bool {
    if !user_data.is_dir() {
        return false;
    }
    // Rápido: perfiles habituales.
    for profile in ["Default", "Profile 1", "Profile 2"] {
        if user_data.join(profile).join("Cookies").is_file()
            || user_data
                .join(profile)
                .join("Network")
                .join("Cookies")
                .is_file()
        {
            return true;
        }
    }
    // Barrido de un nivel: cualquier subdir con Cookies.
    std::fs::read_dir(user_data)
        .into_iter()
        .flatten()
        .flatten()
        .any(|e| {
            let p = e.path();
            p.is_dir()
                && (p.join("Cookies").is_file() || p.join("Network").join("Cookies").is_file())
        })
}

/// ¿Hay `cookies.sqlite` en algún perfil de Firefox?
fn firefox_cookies_present(profiles_dir: &std::path::Path) -> bool {
    if !profiles_dir.is_dir() {
        return false;
    }
    std::fs::read_dir(profiles_dir)
        .into_iter()
        .flatten()
        .flatten()
        .any(|e| {
            let p = e.path();
            p.is_dir() && p.join("cookies.sqlite").is_file()
        })
}

/// Evidencia en disco de que `browser` tiene DB real de cookies (no solo el
/// binario instalado o la carpeta del perfil vacía).
fn browser_has_profile(browser: &str) -> bool {
    let home = dirs::home_dir().unwrap_or_default();
    let local_app_data = std::env::var("LOCALAPPDATA").unwrap_or_default();
    let app_data = std::env::var("APPDATA").unwrap_or_default();

    match browser {
        "chrome" => {
            chromium_cookies_present(
                &home.join("Library/Application Support/Google/Chrome"),
            ) || chromium_cookies_present(&home.join(".config/google-chrome"))
                || chromium_cookies_present(&std::path::PathBuf::from(format!(
                    "{local_app_data}/Google/Chrome/User Data"
                )))
        }
        "brave" => {
            chromium_cookies_present(
                &home.join("Library/Application Support/BraveSoftware/Brave-Browser"),
            ) || chromium_cookies_present(&home.join(".config/BraveSoftware/Brave-Browser"))
                || chromium_cookies_present(&std::path::PathBuf::from(format!(
                    "{local_app_data}/BraveSoftware/Brave-Browser/User Data"
                )))
        }
        "edge" => {
            chromium_cookies_present(&home.join("Library/Application Support/Microsoft Edge"))
                || chromium_cookies_present(&home.join(".config/microsoft-edge"))
                || chromium_cookies_present(&std::path::PathBuf::from(format!(
                    "{local_app_data}/Microsoft/Edge/User Data"
                )))
        }
        "chromium" => {
            chromium_cookies_present(&home.join("Library/Application Support/Chromium"))
                || chromium_cookies_present(&home.join(".config/chromium"))
                || chromium_cookies_present(&std::path::PathBuf::from(format!(
                    "{local_app_data}/Chromium/User Data"
                )))
        }
        "firefox" => {
            firefox_cookies_present(&home.join("Library/Application Support/Firefox/Profiles"))
                || firefox_cookies_present(&home.join(".mozilla/firefox"))
                || firefox_cookies_present(&std::path::PathBuf::from(format!(
                    "{app_data}/Mozilla/Firefox/Profiles"
                )))
        }
        "safari" => {
            home.join("Library/Cookies/Cookies.binarycookies").is_file()
                || home
                    .join(
                        "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
                    )
                    .is_file()
        }
        "opera" => {
            chromium_cookies_present(
                &home.join("Library/Application Support/com.operasoftware.Opera"),
            ) || chromium_cookies_present(&home.join(".config/opera"))
                || chromium_cookies_present(&std::path::PathBuf::from(format!(
                    "{app_data}/Opera Software/Opera Stable"
                )))
        }
        "vivaldi" => {
            chromium_cookies_present(&home.join("Library/Application Support/Vivaldi"))
                || chromium_cookies_present(&home.join(".config/vivaldi"))
                || chromium_cookies_present(&std::path::PathBuf::from(format!(
                    "{local_app_data}/Vivaldi/User Data"
                )))
        }
        _ => false,
    }
}

/// Primer navegador con perfil en disco, en orden de preferencia.
/// En móvil no hay navegador de escritorio accesible: siempre `None`.
pub fn detect_browser() -> Option<String> {
    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        return None;
    }
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    {
        supported_browsers()
            .iter()
            .find(|b| browser_has_profile(b))
            .map(|b| b.to_string())
    }
}

/// Config de cookies ya resuelta para invocar yt-dlp: los args extra y el
/// navegador del que vienen (solo para mensajes).
///
/// Es la unidad central de esta config: todo camino yt-dlp (probe, avance,
/// descarga audio/vídeo) resuelve una vez con [`resolve_for_db`] y la pasa
/// tal cual. Política única de reintento: si el fallo se clasifica como
/// [`YtDlpFailure::CookieExtraction`] y había cookies, se reintenta UNA vez
/// sin cookies; el error final se mapea con [`friendly_message`].
#[derive(Debug, Clone, Default)]
pub struct ResolvedCookies {
    /// Args extra (`--cookies-from-browser <b>` o `--cookies <file>`).
    pub args: Vec<String>,
    /// Navegador usado, si aplica (para el mensaje amigable).
    pub browser: Option<String>,
}

impl ResolvedCookies {
    pub fn none() -> Self {
        Self::default()
    }

    pub fn has_cookies(&self) -> bool {
        !self.args.is_empty()
    }

    pub fn browser_used(&self) -> Option<&str> {
        self.browser.as_deref()
    }

    /// `--extractor-args` de YouTube para esta config. El web client exige
    /// PO-token (imposible de falsificar) y dispara el reto anti-bot, así
    /// que se identifica otro player: `android` genera su propio PO-token
    /// dentro de yt-dlp y es el más resistente sin cuenta; `web_safari` de
    /// fallback. Con cookies NO se usa un client móvil (la sesión se puede
    /// invalidar): solo `web_safari`. Verificado contra yt-dlp 2026.08.19
    /// (`tv` está caído a día de hoy: devuelve "The page needs to be
    /// reloaded", así que no va en la lista).
    pub fn extractor_args(&self) -> Vec<String> {
        let spec = if self.has_cookies() {
            "youtube:player_client=web_safari"
        } else {
            "youtube:player_client=android,web_safari"
        };
        vec!["--extractor-args".to_string(), spec.to_string()]
    }

    /// Args completos de una invocación: base + cookies + extractor + URL.
    pub fn full_args(&self, base: &[&str], url: &str) -> Vec<String> {
        let mut out: Vec<String> = base.iter().map(|s| s.to_string()).collect();
        out.extend(self.args.iter().cloned());
        out.extend(self.extractor_args());
        out.push(url.to_string());
        out
    }
}

/// Fallo clasificado de una invocación yt-dlp. Un solo clasificador para
/// todos los caminos, en vez de un `if` distinto en cada sitio.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum YtDlpFailure {
    /// YouTube pide login anti-bot (`Sign in to confirm you're not a bot`).
    BotChallenge,
    /// Ni siquiera se pudieron leer las cookies (DB inexistente, perfil
    /// bloqueado, TCC de macOS). Candidato a reintento sin cookies.
    CookieExtraction,
    /// Cualquier otro error: se muestra el tail crudo.
    Other,
}

/// Clasifica el stderr de yt-dlp. El orden importa: el reto anti-bot menciona
/// `--cookies` y también matchearía como extracción.
pub fn classify(tail: &str) -> YtDlpFailure {
    if is_bot_challenge(tail) {
        YtDlpFailure::BotChallenge
    } else if is_cookie_extraction_failure(tail) {
        YtDlpFailure::CookieExtraction
    } else {
        YtDlpFailure::Other
    }
}

/// Mensaje en español para un fallo FINAL (tras agotar el reintento).
/// `raw_tail` solo se usa en `Other` y en extracción (recortado a 2 líneas).
pub fn friendly_message(failure: YtDlpFailure, browser: Option<&str>, raw_tail: &str) -> String {
    match failure {
        YtDlpFailure::BotChallenge => friendly_bot_error(browser),
        YtDlpFailure::CookieExtraction => friendly_cookie_extraction_error(browser, raw_tail),
        YtDlpFailure::Other => format!("yt-dlp no pudo analizar el enlace:\n{raw_tail}"),
    }
}

/// Construye los args de cookies a partir de valores ya resueltos.
/// `browser_cfg`: `auto`/`off`/nombre. `file_cfg`: ruta a cookies.txt.
pub fn resolve_cookies(browser_cfg: &str, file_cfg: &str) -> ResolvedCookies {
    let (args, browser) = cookies_args_for(browser_cfg, file_cfg);
    ResolvedCookies { args, browser }
}

/// Nivel bajo (testeable sin FS salvo el `cookies.txt`): devuelve
/// `(args, browser_usado)`.
pub fn cookies_args_for(browser_cfg: &str, file_cfg: &str) -> (Vec<String>, Option<String>) {
    let file = file_cfg.trim();
    if !file.is_empty() {
        let path = std::path::Path::new(file);
        if path.is_file() {
            return (vec!["--cookies".to_string(), file.to_string()], None);
        }
        // Archivo configurado pero inexistente: se ignora y se sigue con el
        // navegador (no se aborta la descarga por un path roto).
    }

    let cfg = browser_cfg.trim().to_lowercase();
    if cfg.is_empty() || cfg == COOKIES_AUTO {
        return match detect_browser() {
            Some(b) => (
                vec!["--cookies-from-browser".to_string(), b.clone()],
                Some(b),
            ),
            None => (vec![], None),
        };
    }
    if cfg == COOKIES_OFF {
        return (vec![], None);
    }
    if is_supported_browser(&cfg) {
        return (
            vec!["--cookies-from-browser".to_string(), cfg.clone()],
            Some(cfg),
        );
    }
    // Valor desconocido: como auto, para no romper descargas por un typo.
    match detect_browser() {
        Some(b) => (
            vec!["--cookies-from-browser".to_string(), b.clone()],
            Some(b),
        ),
        None => (vec![], None),
    }
}

/// Lee la config de la DB (con defaults `auto`/vacío) y la resuelve una vez.
/// El resultado se pasa tal cual a todos los comandos yt-dlp de la operación.
pub async fn resolve_for_db(db: &AppDatabase) -> ResolvedCookies {
    let browser = db
        .get_setting(SETTING_COOKIES_BROWSER)
        .await
        .ok()
        .flatten()
        .unwrap_or_else(|| COOKIES_AUTO.to_string());
    let file = db
        .get_setting(SETTING_COOKIES_FILE)
        .await
        .ok()
        .flatten()
        .unwrap_or_default();
    resolve_cookies(&browser, &file)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn off_disables_everything() {
        let (args, used) = cookies_args_for("off", "");
        assert!(args.is_empty());
        assert!(used.is_none());
    }

    #[test]
    fn explicit_browser_wins_without_fs_checks() {
        let (args, used) = cookies_args_for("firefox", "");
        assert_eq!(args, vec!["--cookies-from-browser", "firefox"]);
        assert_eq!(used.as_deref(), Some("firefox"));
    }

    #[test]
    fn unknown_browser_falls_back_to_auto_without_panic() {
        // No debe explotar aunque el valor sea basura.
        let (args, _) = cookies_args_for("netscape", "");
        assert!(args.is_empty() || args[0] == "--cookies-from-browser");
    }

    #[test]
    fn missing_file_falls_back_to_browser_logic() {
        let (args, _) = cookies_args_for("off", "/ruta/que/no/existe/cookies.txt");
        assert!(args.is_empty());
    }

    #[test]
    fn bot_challenge_detection() {
        assert!(is_bot_challenge(
            "ERROR: [youtube] abc123: Sign in to confirm you're not a bot. Use --cookies-from-browser or --cookies for authentication."
        ));
        assert!(is_bot_challenge(
            "ERROR: [youtube] xyz: Sign in to confirm you’re not a bot"
        ));
        assert!(!is_bot_challenge("ERROR: [youtube] Private video"));
    }

    #[test]
    fn cookie_extraction_failure_detection() {
        assert!(is_cookie_extraction_failure(
            "Could not copy Chrome cookie database"
        ));
        assert!(is_cookie_extraction_failure(
            "snaps need full disk access for cookies"
        ));
        // Caso real del reporte: auto eligió chrome sin DB.
        assert!(is_cookie_extraction_failure(
            "ERROR: could not find chrome cookies database in \
             \"/Users/dan/Library/Application Support/Google/Chrome\""
        ));
        assert!(is_cookie_extraction_failure(
            "ERROR: [youtube] Permission denied reading browser cookies"
        ));
        assert!(!is_cookie_extraction_failure("Sign in to confirm"));
    }

    #[test]
    fn friendly_message_mentions_browser_when_used() {
        let m = friendly_bot_error(Some("chrome"));
        assert!(m.contains("chrome"));
        let m2 = friendly_bot_error(None);
        assert!(m2.contains("Ajustes"));
    }

    #[test]
    fn classify_prefers_bot_over_extraction() {
        // El reto anti-bot menciona `--cookies`: debe ganar BotChallenge.
        assert_eq!(
            classify(
                "ERROR: [youtube] abc: Sign in to confirm you're not a bot. \
                 Use --cookies-from-browser or --cookies for authentication."
            ),
            YtDlpFailure::BotChallenge
        );
        assert_eq!(
            classify("ERROR: could not find chrome cookies database in \"/x\""),
            YtDlpFailure::CookieExtraction
        );
        assert_eq!(
            classify("ERROR: [youtube] Private video"),
            YtDlpFailure::Other
        );
    }

    #[test]
    fn full_args_appends_cookies_then_url_last() {
        let c = resolve_cookies("firefox", "");
        let full = c.full_args(&["--dump-json", "--skip-download"], "https://x");
        assert_eq!(
            full,
            vec![
                "--dump-json",
                "--skip-download",
                "--cookies-from-browser",
                "firefox",
                "--extractor-args",
                "youtube:player_client=web_safari",
                "https://x"
            ]
        );
        let bare = ResolvedCookies::none();
        assert!(!bare.has_cookies());
        assert_eq!(bare.browser_used(), None);
        let bare_full = bare.full_args(&["-f", "b"], "https://x");
        assert_eq!(bare_full.last().unwrap(), "https://x");
        // Sin cookies se usa android primero (PO-token propio).
        assert!(bare_full.contains(&"youtube:player_client=android,web_safari".to_string()));
    }

    #[test]
    fn friendly_message_covers_all_failures() {
        assert!(friendly_message(YtDlpFailure::BotChallenge, Some("brave"), "").contains("brave"));
        assert!(
            friendly_message(YtDlpFailure::CookieExtraction, Some("brave"), "raw")
                .contains("Ajustes")
        );
        assert!(friendly_message(YtDlpFailure::Other, None, "tail crudo").contains("tail crudo"));
    }
}
