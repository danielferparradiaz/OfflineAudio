# Política de seguridad

## Versiones soportadas

Solo la última release publicada recibe parches de seguridad.

| Versión | Soportada |
| ------- | --------- |
| última release de [Releases](https://github.com/danielferparradiaz/OfflineAudio/releases) | ✅ |
| versiones anteriores | ❌ (actualiza) |

## Cómo reportar una vulnerabilidad

1. Usa **Report a vulnerability** de GitHub en la pestaña *Security* del repo
   (advisory privado) o escribe a `danielferparradiaz@gmail.com`.
2. Incluye: descripción del problema, plataforma y versión, pasos de
   reproducción e impacto estimado.

No abras issues públicas con detalles de la vulnerabilidad. Prometemos:

- Acusar recibo en un plazo de 48 h.
- Dar seguimiento con una corrección y una release en cuanto sea viable.

## Alcance

Interesan especialmente:

- Fuga o manejo inseguro de datos personales/cookies del usuario
  (el motor usa cookies del navegador configuradas por el usuario).
- Ejecución de comandos con rutas o URLs controladas por terceros.
- El runtime de Android (`flutter/tool/android/`) y los binarios que se
  inyectan en los bundles de escritorio.
- Dependencias nativas (`yt-dlp`, `ffmpeg`, `youtubedl-android`,
  `ffmpeg-kit`): la app empaqueta/binaria versiones conocidas; un CVE nuevo en
  ellas es reportable aquí.

## Notas de diseño

La app no recoge telemetría ni envía datos a terceros fuera de los servidores
públicos de las fuentes que el usuario elige (YouTube, etc.). Las credenciales
de sincronización (OfflineAudio Cloud, próximo release) se manejarán bajo esta
misma política.
