# OfflineAudio (Flutter UI)

UI de OfflineAudio: biblioteca, descargas, playlists y reproductor.

Stack: Flutter + `flutter_rust_bridge` v2 (`lib/src/rust/`) + `media_kit` para
reproducción. El motor vive en `../rust/`.

## Requisitos

- Flutter stable (3.47+, Dart 3.13+), Rust stable.
- `yt-dlp` + `ffmpeg` en `PATH` (`brew install yt-dlp ffmpeg` en macOS).
- `flutter_rust_bridge_codegen` 2.13.0 solo para regenerar bindings.

## Desarrollo

```sh
flutter pub get

# regenerar bindings tras editar rust/src/api/*.rs
flutter_rust_bridge_codegen generate

flutter analyze
flutter test

# build macOS debug
flutter build macos --debug
```

Motor: `cd ../rust && cargo test`.

## Estructura

- `lib/main.dart`, `lib/src/app.dart`: `HomeShell` (Biblioteca/Descargas/Playlists + Ajustes).
- `lib/src/app_model.dart`: `ChangeNotifier` central. Suscrito a `eventStream()`,
  expone `library/downloads/playlists`, `position/duration/isPlaying`, `seek`, `skipNext/Previous`.
- `lib/src/screens/`: `library_screen` (búsqueda backend con debounce 350ms + orden),
  `add_screen` (probe → download), `downloads_screen` (progreso %/MB/velocidad/ETA + errores),
  `playlists_screen` (crear/renombrar/borrar con confirmación),
  `playlist_detail_screen` (`ReorderableListView` → `reorderPlaylist`),
  `settings_screen` (estado yt-dlp + rutas).
- `lib/src/widgets/player_bar.dart`: título/artista + slider seek + prev/play/next.
- `lib/src/rust/`: código generado, no editar a mano.

## Notas

- Búsqueda: backend SQLite `WHERE (title OR artist) + ORDER BY`. Sin filtro cliente.
- Descargas: `DownloadState.percent` es 0..100, `fraction` 0..1 para `LinearProgressIndicator`.
- Player: suscrito a `playing/position/duration/playlist` de media_kit; `recordPlay` por pista
  (incluye avance automático en playlist vía `stream.playlist.index`).
