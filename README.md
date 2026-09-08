# OfflineAudio

Reproductor de audio offline multi-plataforma. Descarga audio desde YouTube,
Instagram y otras fuentes vía `yt-dlp`, lo convierte a **Opus** con `ffmpeg`, lo
guarda en una biblioteca local (SQLite) y lo reproduce sin conexión, agrupado en
playlists.

Stack: motor Rust (`rust/`) + UI Flutter (`flutter/`) con `flutter_rust_bridge`.

## Descarga

Los instaladores se generan automáticamente y se publican en la pestaña
**[Releases](https://github.com/danielferparradiaz/OfflineAudio/releases)** de
este repo al crear un tag `v*`.

| Dispositivo | Archivo | Cómo instalar |
| ----------- | ------- | ------------- |
| **macOS** (Apple Silicon / Intel) | `OfflineAudio-macos-<versión>.zip` | Descomprimir y arrastrar `OfflineAudio.app` a Aplicaciones |
| **Windows** (10/11) | `OfflineAudio-windows-<versión>.zip` | Descomprimir y ejecutar `OfflineAudio.exe` |
| **iPhone / iPad** | `OfflineAudio-ios-<versión>.ipa` | Instalar vía TestFlight o tu distribuidor |
| **Android** | `OfflineAudio-android-<versión>-arm64-v8a.apk` (y variantes) + `.aab` | Permitir «orígenes desconocidos» e instalar el APK de tu arquitectura |

> **Motor en móvil:** en Android el motor descarga los binarios `yt-dlp` y
> `ffmpeg` la primera vez (te lo pregunta al abrir la app). Puedes gestionarlos
> en **Ajustes → Paquetes del motor**. En iOS la descarga automática aún es un
> TODO (ver Roadmap). En el escritorio necesitas los binarios en `PATH`:
> `brew install yt-dlp ffmpeg` (macOS) / `winget install yt-dlp.yt-dlp` y
> `winget install Gyan.FFmpeg` (Windows).

## Roadmap

- [ ] **Apple Watch (reloj)** — soporte para ver y controlar el reproductor desde
      la muñeca (`voo_watch`), con estado de reproducción y cola.
- [ ] **iOS** — fuente fiable de binarios estáticos del motor (descarga automática
      igual que Android; hoy solo se soporta en Android).
- [ ] Instaladores nativos (DMG para macOS, MSIX/NSIS para Windows).

## Desarrollar

```sh
# Regenerar bindings FRB tras tocar rust/src/api/*.rs
cd flutter && flutter_rust_bridge_codegen generate

# Tests del motor
cd rust && cargo test

# Lint de ambos lados (lo que exige el CI)
cd rust && cargo fmt --check && cargo clippy --all-targets -- -D warnings
cd flutter && flutter analyze

# Builds
cd flutter && flutter build macos --release    # macOS
cd flutter && flutter build windows --release  # Windows
cd flutter && flutter build appbundle --release  # Android (.aab)
cd flutter && flutter build apk --release --split-per-abi  # Android (APKs)
cd flutter && flutter build ipa --release      # iOS (requiere firma)
```

## Releases y firma

El workflow de release construye todos los artefactos al crear un tag `v*` y los
adjunta a la release. Para iOS/Android con firma real necesitas configurar estos
**secrets de GitHub** (`Settings → Secrets and variables → Actions`):

| Secret | Uso |
| ------ | --- |
| `CERTIFICATE_P12_BASE64` | Certificado de distribución de Apple en base64 (`base64 -i cert.p12`) |
| `CERTIFICATE_PASSWORD` | Contraseña del `.p12` |
| `PROVISIONING_PROFILES_BASE64` | Perfiles de provisión en base64 (tar o zip) para el bundle `com.offlineaudio.app` |
| `KEYCHAIN_PASSWORD` | Contraseña temporal del keychain del runner |
| `EXPORT_TEAM_ID` | Team ID de Apple (10 caracteres) |
| `KEYSTORE_BASE64` | Android upload keystore en base64 (`base64 -i release.jks`) |
| `KEYSTORE_PASSWORD` / `KEY_ALIAS` / `KEY_PASSWORD` | Credenciales del keystore de Android |

Si no los pones, el workflow sigue generando los artefactos de escritorio y un
Android APK firmado con la clave de debug.

## Datos

- Biblioteca `.opus` + miniaturas + base de datos SQLite en el directorio de
  configuración del usuario (macOS: `~/Library/Application Support/OfflineAudio`).
- En Android los binarios del motor se guardan en la carpeta privada de la app
  (`.../app_flutter`), descargables desde **Ajustes → Paquetes del motor** con
  URLs configurables (`binary.ytdlp_url`, `binary.ffmpeg_url`) por si quieres
  apuntar a tus propios builds estáticos.

## Legal

Software de **uso personal** con contenidos que tienes derecho a descargar. No
facilita la descarga de material protegido sin autorización y respeta los
[términos de uso de YouTube](https://www.youtube.com/t/terms) y las webs
soportadas. Descarga solo lo que puedas reproducir y distribuir legalmente.