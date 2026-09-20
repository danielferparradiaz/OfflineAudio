import 'dart:async';

/// Traduce los errores técnicos del avance (preview) a mensajes cortos en
/// español y accionables. El texto crudo de `youtube_explode_dart` (p. ej.
/// `VideoUnavailableException... Please report this issue on GitHub`) no debe
/// llegar nunca al usuario: no puede hacer nada con él.
///
/// Cuando el avance falla, la salida es la descarga directa desde el menú de
/// opciones de cada resultado (icono ⋮ → Descargar audio/vídeo), que usa
/// yt-dlp y sí maneja esos vídeos; por eso todos los mensajes apuntan ahí.
String friendlyPreviewError(Object e) {
  final raw = e.toString();

  if (e is TimeoutException || raw.contains('TimeoutException')) {
    return 'El avance tardó demasiado. Revisa tu conexión o descárgalo '
        'directamente desde el menú ⋮ → Descargar audio.';
  }
  if (raw.contains('VideoUnavailableException') ||
      raw.contains('Sin streams')) {
    return 'Este video no permite avances (privado, restringido o retirado). '
        'Descárgalo directamente desde el menú ⋮ → Descargar audio.';
  }
  if (raw.contains('VideoRequiresPurchaseException') ||
      raw.contains('requires payment') ||
      raw.contains('purchase')) {
    return 'Este video es de pago y no permite avances. '
        'Descárgalo directamente desde el menú ⋮ si tienes acceso.';
  }
  if (raw.contains('LoginRequiredException') ||
      (raw.contains('login') && raw.contains('required'))) {
    return 'Este video exige iniciar sesión y no permite avances. '
        'Prueba a descargarlo directamente desde el menú ⋮.';
  }
  if (raw.contains('yt-dlp no pudo resolver') ||
      raw.contains('no devolvió URL de stream')) {
    return 'No se pudo abrir el avance ni con el motor. '
        'Descárgalo directamente desde el menú ⋮ → Descargar audio.';
  }
  if (raw.contains('SocketException') ||
      raw.contains('Failed host lookup') ||
      raw.contains('Network is unreachable')) {
    return 'Sin conexión para el avance. Comprueba tu red o descárgalo '
        'directamente cuando vuelva.';
  }
  return 'No se pudo reproducir el avance. Prueba a descargarlo '
      'directamente desde el menú ⋮ → Descargar audio.';
}
