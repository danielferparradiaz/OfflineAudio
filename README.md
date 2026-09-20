# OfflineAudio

Reproductor de audio offline multi-plataforma. Descarga audio desde YouTube,
Instagram y otras fuentes, lo guarda en una biblioteca local (SQLite) y lo
reproduce sin conexión, agrupado en playlists.

- **Escritorio**: motor Rust (`yt-dlp` + `ffmpeg`) — audio a **Opus**, vídeo a **MP4**.
- **Android**: motor nativo con [`youtubedl-android` + `ffmpeg-kit`](flutter/android/app/src/main/kotlin/com/offlineaudio/app/MainActivity.kt) (compatibilidad con targetSdk 36: nada de `execve()` en el directorio privado).
- **iOS**: descargas y reproducción 100% nativas vía AVPlayer/Dart — el sandbox de Apple no permite binarios externos.

Stack: motor Rust (`rust/`) + UI Flutter (`flutter/`) con `flutter_rust_bridge`.

## Descarga

Los instaladores se compilan automáticamente en GitHub Actions y se publican en
la pestaña **[Releases](https://github.com/danielferparradiaz/OfflineAudio/releases)**.

| Dispositivo | Archivo | Cómo instalar |
| ----------- | ------- | ------------- |
| **macOS** (Apple Silicon / Intel) | `OfflineAudio-macos.dmg` (o `.zip`) | Abrir el DMG y arrastrar `OfflineAudio.app` a Aplicaciones. Primer arranque: clic derecho → **Abrir** (la app aún no está notariada) |
| **Windows** (10/11) | `OfflineAudio-windows.zip` | Descomprimir y ejecutar `OfflineAudio.exe` |
| **Linux** (x64) | `OfflineAudio-linux.tar.gz` | Descomprimir la carpeta y ejecutar el binario `offline_audio` |
| **iPhone / iPad** | `OfflineAudio-ios-altstore.ipa` | Instalar con **AltStore** o **Sideloadly** (firma el instalador tu cuenta de Apple). La versión oficial llegará **próximamente a la App Store** |
| **Android** | `OfflineAudio-android-arm64-v8a.apk` (y variantes `armeabi-v7a`, `x86_64`) + `.aab` | Permitir «orígenes desconocidos» e instalar el APK de tu arquitectura (arm64 en la mayoría de móviles) |

> **macOS y Gatekeeper:** si al abrir sale «está dañado» o «no se puede
> verificar», abre una Terminal y ejecuta
> `xattr -cr /Applications/OfflineAudio.app`, y vuelve a abrir. Pasa porque
> la app se distribuye sin notariar (sin cuenta de pago de Apple); el
> sello del bundle sí es válido desde la v1.1.1.

> **Binarios del motor (`yt-dlp` + `ffmpeg`):** en escritorio el usuario no
> tiene que descargar ni instalar nada: la app los trae integrados y, si falta
> alguno, el motor lo prepara solo en segundo plano.
>
> | Plataforma | Descargas | Reproducción |
> | ---------- | --------- | ------------ |
> | Windows / macOS / Linux | `yt-dlp` + `ffmpeg` integrados | `media_kit` (mpv) |
> | Android | Nativo: `youtubedl-android` + `ffmpeg-kit` (integrados en el APK) | `media_kit` |
> | iOS | Nativo (Dart): stream directo, sin binarios | AVPlayer (`just_audio`) |
>
> En Android cada release sigue publicando el runtime CLI autocontenido
> (`OfflineAudio-ytdlp-*.zip`): era el motor de descargas hasta v1.1.1 y hoy es
> material de referencia; desde v1.2.0 las descargas usan el motor nativo
> porque Android 10+ prohíbe `execve()` en el home dir de apps con
> targetSdk ≥ 29. En iOS el sandbox prohíbe ejecutar binarios externos: las
> descargas resuelven el stream con `youtube_explode` y lo bajan por HTTPS
> (el stream muxed lleva `ratebypass=yes` firmado y baja completo; los
> streams audio-only, con PO-token obligatorio, están capados a ~1 MiB).

## Búsqueda y vídeo

- La **barra de búsqueda de la biblioteca** busca directamente en YouTube
  (proyecto [`youtube_explode_dart`, fijado a `3.1.0`](flutter/pubspec.yaml)).
  Teclea, pulsa Enter o la lupa y verás resultados con miniatura, título,
  autor, duración y hoja de acciones por resultado: **avance de audio/vídeo**
  y **descarga de audio/vídeo**.
- **Avances (previews)**: suenan al toque con una cadena de resolución
  tolerante a fallos (cliente `androidSdkless` sin PO-token → manifest
  completo → HLS), y en iOS suenan por AVPlayer. El reintentar ante URLs
  caducadas está integrado.
- **Descargas** en todas las plataformas desde el menú ⋮: Opus/MP4 en
  escritorio, motor nativo en Android, stream directo en iOS. El progreso,
  la cancelación y los errores se ven en la pestaña Descargas con el título
  de cada canción.
- **iOS**: la biblioteca suena por AVPlayer (mpv no abre el audio ahí), con
  avance automático de cola, y la Tracklist usa el mismo panel flotante
  translúcido de macOS.
- Los vídeos se reproducen desde la barra de reproducción con el reproductor
  de `media_kit_video`. La búsqueda está desacoplada del motor: vive en el
  front (`lib/src/search/youtube_search.dart`) y las descargas entran por la
  misma tubería que las URLs del botón Añadir.

## Streaming en la nube (próximo release)

En **Ajustes → Almacenamiento** (o en el chip **Sync**) se activa
**Streaming**: la preferencia ya se guarda en el motor
(`sync.streaming_enabled`). Al activarse, la biblioteca (canciones, vídeos,
listas de reproducción y estadísticas) se trasladará a los servidores de
OfflineAudio Cloud para liberar el espacio del dispositivo, y la reproducción
pasará a streaming. El traslado llega en la próxima actualización.

## Roadmap

- [ ] **Streaming en OfflineAudio Cloud** — trasladar biblioteca y listas a
      los servidores y reproducir en streaming (la preferencia ya existe;
      el traslado llega en el próximo release).
- [ ] **Apple Watch (reloj)** — soporte para ver y controlar el reproductor desde
      la muñeca (`voo_watch`), con estado de reproducción y cola.
- [ ] **iOS en App Store** — la app se distribuye como IPA sin firmar para
      AltStore/Sideloadly y ya descarga y reproduce en el dispositivo; falta
      firmar con cuenta de desarrollador y el lanzamiento oficial.
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

- Biblioteca `.opus`/`.mp4` + miniaturas + base de datos SQLite en el
  directorio de configuración del usuario (macOS:
  `~/Library/Application Support/OfflineAudio`; móvil: el contenedor privado
  de la app). En iOS las rutas se reescriben sola si el sistema cambia el
  contenedor al reinstalar.

## Legal

Software de **uso personal** con contenidos que tienes derecho a descargar. No
facilita la descarga de material protegido sin autorización y respeta los
[términos de uso de YouTube](https://www.youtube.com/t/terms) y las webs
soportadas. Descarga solo lo que puedas reproducir y distribuir legalmente.
