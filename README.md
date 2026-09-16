# OfflineAudio

Reproductor de audio offline multi-plataforma. Descarga audio desde YouTube,
Instagram y otras fuentes vía `yt-dlp`, lo convierte a **Opus** con `ffmpeg`, lo
guarda en una biblioteca local (SQLite) y lo reproduce sin conexión, agrupado en
playlists.

Stack: motor Rust (`rust/`) + UI Flutter (`flutter/`) con `flutter_rust_bridge`.

## Descarga

Los instaladores se compilan automáticamente en GitHub Actions y se publican en
la pestaña **[Releases](https://github.com/danielferparradiaz/OfflineAudio/releases)**
de este repo al crear un tag `v*`.

| Dispositivo | Archivo | Cómo instalar |
| ----------- | ------- | ------------- |
| **macOS** (Apple Silicon / Intel) | `OfflineAudio-macos.dmg` (o `.zip`) | Abrir el DMG y arrastrar `OfflineAudio.app` a Aplicaciones |
| **Windows** (10/11) | `OfflineAudio-windows.zip` | Descomprimir y ejecutar `OfflineAudio.exe` |
| **Linux** (x64) | `OfflineAudio-linux.tar.gz` | Descomprimir la carpeta y ejecutar el binario `offline_audio` |
| **iPhone / iPad** | `OfflineAudio-ios-altstore.ipa` | Instalar con **AltStore** o **Sideloadly** (firma el instalador tu cuenta de Apple). La versión oficial llegará **próximamente a la App Store** |
| **Android** | `OfflineAudio-android-arm64-v8a.apk` (y variantes `armeabi-v7a`, `x86_64`) + `.aab` | Permitir «orígenes desconocidos» e instalar el APK de tu arquitectura (arm64 en la mayoría de móviles) |

> **Binarios del motor (`yt-dlp` + `ffmpeg`):** el usuario no tiene que
> descargar ni instalar nada: la app los trae integrados donde el sistema
> lo permite y, si falta alguno, el motor lo prepara solo en segundo plano.
>
> | Plataforma | yt-dlp | ffmpeg |
> | ---------- | ------ | ------ |
> | Windows (`.zip`) | Integrado | Integrado |
> | macOS (`.dmg`/`.zip`) | Integrado | Integrado (uno por arch) |
> | Linux (`.tar.gz`) | Integrado | Integrado |
> | Android (`.apk`) | Automático (runtime propio, ver nota) | Automático |
> | iOS | No disponible (sandbox) | No disponible (sandbox) |
>
> En Android no existe un binario oficial de `yt-dlp` (glibc/musl frente a
> bionic), así que cada release de este repo publica su propio runtime
> autocontenido (`OfflineAudio-ytdlp-arm64-v8a.zip` / `-x86_64.zip`): un
> launcher mínimo + el CPython oficial de python.org para Android + el `yt-dlp`
> de PyPI. La app lo instala sola en su carpeta privada
> (`.../app_flutter/bin/ytdlp`) al arrancar, sin pasos ni avisos.
> Detalles de construcción en `flutter/tool/android/` (script
> `build_ytdlp_runtime.sh` + job `ytdlp-runtime` del workflow Release).
> Solo hay runtime de 64 bits (python.org no publica CPython de 32 bits para
> Android). En iOS el sandbox prohíbe
> ejecutar binarios externos, así que el soporte pasa por librerías (ver
> Roadmap).

## Búsqueda y vídeo

- La **barra de búsqueda de la biblioteca** busca directamente en YouTube
  (proyecto [`youtube_explode_dart`, fijado a `3.1.0`](flutter/pubspec.yaml)).
  Teclea, pulsa Enter o la lupa y verás resultados con miniatura, título,
  autor, duración y dos botones por resultado: **audio** (+) y **vídeo**
  (cámara). El botón `+` descarga a **Opus**; el de cámara baja el **MP4**
  (`yt-dlp -f bv\*+ba/b --merge-output-format mp4`), revisado con `ffprobe`
  antes de guardarse en la biblioteca.
- Los vídeos se reproducen desde la barra de reproducción (icono de pantalla
  completa) con el reproductor nativo de `media_kit_video`. La búsqueda está
  desacoplada del motor: vive en el front (`lib/src/search/youtube_search.dart`)
  y las descargas entran por la misma tubería que las URLs del botón Añadir.

## Roadmap

- [ ] **Apple Watch (reloj)** — soporte para ver y controlar el reproductor desde
      la muñeca (`voo_watch`), con estado de reproducción y cola.
- [ ] **iOS en App Store** — la app ya se distribuye como IPA sin firmar para
      AltStore/Sideloadly; falta el motor de descargas en el dispositivo (el
      sandbox de iOS prohíbe ejecutar binarios externos como `yt-dlp`/`ffmpeg`,
      así que hay que migrar a librerías: `ffmpeg-kit` + extracción sin
      procesos hijo) y el lanzamiento oficial.
- [ ] Instalador nativo de **Windows** (MSIX/NSIS; hoy se distribuye como `.zip`
      portable).

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

Si no los pones, el workflow sigue generando los artefactos de escritorio, un
APK de Android firmado con la clave de debug y un IPA de iOS sin firmar para
AltStore/Sideloadly.

## Datos

- Biblioteca `.opus` + miniaturas + base de datos SQLite en el directorio de
  configuración del usuario (macOS: `~/Library/Application Support/OfflineAudio`).
- En Android los binarios del motor se guardan en la carpeta privada de la app
  (`.../app_flutter`); la app los prepara sola al arrancar, sin intervención:
  `yt-dlp` llega como runtime propio publicado en cada release.

## Legal

Software de **uso personal** con contenidos que tienes derecho a descargar. No
facilita la descarga de material protegido sin autorización y respeta los
[términos de uso de YouTube](https://www.youtube.com/t/terms) y las webs
soportadas. Descarga solo lo que puedas reproducir y distribuir legalmente.