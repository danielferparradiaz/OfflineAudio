import 'package:flutter/foundation.dart';

/// True en iOS y macOS: ahí preferimos widgets y estilos Cupertino nativos.
bool get isApplePlatform =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

bool get isIOSPlatform => defaultTargetPlatform == TargetPlatform.iOS;

bool get isMacOSPlatform => defaultTargetPlatform == TargetPlatform.macOS;
