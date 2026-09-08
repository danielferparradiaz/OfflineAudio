# OfflineAudio

Reproductor de audio offline multi-plataforma (macOS prioritario, luego Windows y Linux).

Descarga audio desde YouTube, Instagram y otras fuentes vía `yt-dlp`, lo convierte a
**Opus** con `ffmpeg`, lo guarda en una biblioteca local (SQLite) y permite reproducirlo
sin conexión, agrupado en playlists.

## Arquitectura

| Capa      | Stack                                                        |
| --------- | ------------------------------------------------------------ |
| Motor     | Rust (`rust/`) — descarga, conversión, eventos, SQLite       |
| UI        | Flutter (`flutter/`) — `offline_audio_app`                   |
| Puente    | `flutter_rust_bridge` v2 (cargokit)                          |
| Reproducción | `media_kit` (lado Flutter)                                |

```
URL → yt-dlp ──(stream)──▶ ffmpeg ──▶ cache/tracks/<hash>.opus ──▶ SQLite ──▶ UI
       └────────(fallback a disco)────────▶ ffmpeg ──▶ caching ─┘
```

- Estrategia A: `yt-dlp -o -` (stdout) → `pipe:0` de ffmpeg.
- Estrategia B (fallback): descarga temporal completa antes de convertir.
- Deduplicación por `source_id` (`{extractor}:{video_id}`): no se descarga dos veces.
- Los `.opus` se guardan con nombre hash (`sha256(source_id)[..16]`).
- Duración/velocidad/ETA se muestran vía eventos en tiempo real.

## Requisitos

- Rust (edición 2021), Flutter stable, `yt-dlp`, `ffmpeg`.
- macOS: `brew install yt-dlp ffmpeg` (los binarios deben estar en `PATH`).
- `flutter_rust_bridge_codegen` (solo para regenerar bindings tras cambios en `rust/src/api`).

## Desarrollo

```sh
# regenerar bindings FRB (tras editar rust/src/api/*.rs)
cd flutter && flutter_rust_bridge_codegen generate

# tests del motor
cd rust && cargo test

# build macos (debug)
cd flutter && flutter build macos --debug
```

El esquema SQLite vive en `rust/migrations/0001_init.sql` (migraciones automáticas con sqlx).

## Cómo probar en cada OS

### macOS (plataforma principal)

```sh
# 1. Dependencias del sistema
brew install yt-dlp ffmpeg            # runtime de descarga/conversión
brew install --cask flutter           # o https://flutter.dev/docs/get-started/install
rustup install stable                 # si no tienes Rust: https://rustup.rs

# 2. Tests y build
cd rust && cargo test                 # motor
cd ../flutter && flutter pub get
flutter analyze && flutter test       # linter + tests de widgets

# 3. Probar la app
flutter run -d macos                  # o: flutter build macos --debug
# abrir manualmente: open build/macos/Build/Products/Debug/OfflineAudio.app
```

### Windows

```powershell
# 1. Dependencias del sistema
winget install yt-dlp.yt-dlp
winget install Gyan.FFmpeg            # asegúrate de que ambos quedan en PATH
winget install Rustlang.Rustup && rustup install stable
# Flutter: https://docs.flutter.dev/get-started/install/windows
# Requiere Visual Studio con "Desktop development with C++".

# 2. Tests y build
cd rust; cargo test
cd ..\flutter; flutter pub get; flutter analyze; flutter test

# 3. Probar la app
flutter run -d windows
```

### Linux

```sh
# 1. Dependencias del sistema (Debian/Ubuntu)
sudo apt install yt-dlp ffmpeg \
  clang cmake ninja-build pkg-config libgtk-3-dev
rustup install stable
# Flutter: https://docs.flutter.dev/get-started/install/linux

# 2. Tests y build
cd rust && cargo test
cd ../flutter && flutter pub get && flutter analyze && flutter test

# 3. Probar la app
flutter run -d linux
```

### Prueba de humo (cualquier OS)

1. Arranca la app y abre **Biblioteca → «+»** y pega una URL de YouTube/Instagram.
2. Pulsa **Analizar** → comprueba que aparece título/artista/duración → **Descargar**.
3. Observa el progreso en la pestaña **Descargas** (porcentaje, velocidad, ETA).
4. Vuelve a **Biblioteca** y reproduce el track: pausa/continúa y arrastra el slider.
5. Crea una **playlist**, añade el track (menú ⋮ → «Añadir a playlist»),
   reordénala arrastrando y reprodúcela completa.
6. En **Ajustes** comprueba el estado de `yt-dlp` y las rutas de datos.

Si cambias algo en `rust/src/api/`, recuerda regenerar los bindings:
`cd flutter && flutter_rust_bridge_codegen generate`.

## Datos

- Linux/macOS/Windows: directorio de configuración del usuario
  (`~/Library/Application Support/OfflineAudio` en macOS; `%APPDATA%\OfflineAudio` en Windows).
  En macOS, una app firmada sin notarizar corre en sandbox → los datos van al container
  de la app (`~/Library/Containers/com.offlineaudio.offlineAudio/...`).

## Legal

Este software está pensado **exclusivamente para uso personal** con contenidos que tienes
derecho a descargar. No facilita la descarga de material protegido sin autorización y
cumple con los [términos de uso de YouTube](https://www.youtube.com/t/terms) y las webs
soportadas. Respeta los derechos de autor: descarga solo lo que puedas reproducir y
distribuir legalmente.

## Sin notas de copyright / licencia

Por definir. El proyecto es privado hasta su liberación.