# Cómo contribuir

¡Gracias por tu interés en OfflineAudio! Es un proyecto personal, pero las
contribuciones son bienvenidas: correcciones de bugs, soporte de plataformas y
mejoras de UX concretas.

## Requisitos previos

- Flutter (canal stable) y Rust (`rustup`).
- Para regenerar bindings: `cargo install flutter_rust_bridge_codegen` (v2.13).
- Un emulador/simulador o dispositivo para probar (iOS: Xcode; Android: SDK 36).

## Estructura

```
rust/     Motor del proyecto (biblioteca SQLite, pipeline de descargas,
          eventos) con bindings generados por flutter_rust_bridge.
flutter/  App Flutter. El plugin nativo de Android vive en
          android/app/src/main/kotlin/.../MainActivity.kt.
```

## Flujo

1. Crea un branch desde `main` con nombre descriptivo (`fix/…`, `feat/…`).
2. Haz tus cambios siguiendo el estilo del código alrededor.
3. Antes de abrir el PR, asegúrate de que esto pase:

```sh
cd rust && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test
cd flutter && flutter analyze && flutter test
```

4. Abre el PR describiendo el qué y el por qué (los screenshots ayudan para
   cambios de UI).

## Convenciones

- Commits en español o inglés, primera línea concisa estilo imperativo
  (`Fix …`, `Add …`).
- Comentarios en el código: español, y solo cuando explican el *por qué*.
- No committear secretos, certificados ni binarios de build.
- Los cambios en `rust/src/api/*.rs` requieren regenerar bindings:
  `cd flutter && flutter_rust_bridge_codegen generate`.
- Todo cambio de comportamiento relevante va con test cuando sea viable
  (engine: `rust/src/engine/*_test.rs`; UI: `flutter/test/`).

## Reportes de bugs y sugerencias

Usa las plantillas de issues (bug / feature). Para fallos de reproducción,
incluye: plataforma, versión de la app (Ajustes → versión), logs del
terminal con `flutter run` y los pasos para reproducir.
