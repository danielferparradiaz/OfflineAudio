import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_audio_app/src/search/preview_errors.dart';

void main() {
  test('VideoUnavailableException apunta a descarga directa', () {
    final msg = friendlyPreviewError(
      Exception(
        "VideoUnavailableException: Video 'ApXoWvfEYVU' is unavailable "
        "In most cases, this error indicates that the video doesn't exist. "
        "Please report this issue on GitHub in that case.",
      ),
    );
    expect(msg, contains('Descárgalo directamente'));
    expect(msg, isNot(contains('GitHub')));
    expect(msg, isNot(contains('VideoUnavailableException')));
  });

  test('Sin streams (StateError propio) también es definitivo', () {
    expect(
      friendlyPreviewError(StateError('Sin streams reproducibles para x')),
      contains('Descárgalo directamente'),
    );
  });

  test('Timeout habla de conexión', () {
    expect(
      friendlyPreviewError(TimeoutException('manifest', Duration(seconds: 25))),
      contains('conexión'),
    );
  });

  test('Fallo del fallback del motor sugiere descarga', () {
    expect(
      friendlyPreviewError(Exception('yt-dlp no pudo resolver el avance: ...')),
      contains('Descárgalo directamente'),
    );
  });

  test('Error genérico corto sin volcado técnico', () {
    final msg = friendlyPreviewError(Exception('kaput 12345'));
    expect(msg, contains('avance'));
    expect(msg, isNot(contains('kaput')));
  });
}
