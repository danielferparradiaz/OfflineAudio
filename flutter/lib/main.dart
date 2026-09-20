import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:offline_audio_app/src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // iOS: la sesión de audio arranca en "ambient/solo" y el reproductor suena
  // en silencio (sobre todo con el interruptor físico de silencio). Se fija
  // categoría playback una sola vez al arrancar.
  if (Platform.isIOS) {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      // Configurar no basta: la sesión tiene que estar ACTIVA para que mpv
      // abra el dispositivo. Sin esto el avance abre pero no suena
      // ("Could not open/initialize audio device").
      await session.setActive(true);
    } catch (_) {
      // Sin audio sesión no se bloquea el arranque: el simulador a veces
      // tarda en exponer CoreAudio; la app sigue y se reintenta abajo.
    }
  }
  runApp(const OfflineAudioApp());
}
