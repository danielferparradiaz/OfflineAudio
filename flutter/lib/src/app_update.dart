import 'dart:convert';
import 'dart:io' show HttpClient;

/// Comprueba el último release publicado en GitHub y devuelve el mensaje a
/// mostrar junto a la versión instalada: hay update, está al día o no se
/// pudo comprobar. La app no se auto-actualiza: en móvil lo gestionan las
/// stores y en escritorio se enlaza la descarga.
Future<String?> checkAppUpdate(String current) async {
  const releasesApi =
      'https://api.github.com/repos/danielferparradiaz/OfflineAudio/'
      'releases/latest';
  try {
    final req = await HttpClient().getUrl(Uri.parse(releasesApi));
    req.headers.set('Accept', 'application/vnd.github+json');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode == 404) {
      return 'Sin releases publicadas; llevas la última build';
    }
    if (res.statusCode != 200) {
      return 'GitHub respondió ${res.statusCode}; inténtalo más tarde';
    }
    final tag = (jsonDecode(body) as Map<String, dynamic>)['tag_name']
        ?.toString()
        .replaceFirst(RegExp(r'^[vV]'), '');
    if (tag == null || tag.isEmpty) return null;
    if (isNewerVersion(tag, current)) {
      return 'Nueva versión disponible: v$tag';
    }
    return 'OfflineAudio está actualizado';
  } catch (_) {
    return 'Sin conexión; no se pudo comprobar';
  }
}

/// Compara semver "x.y.z": true si [remote] es más nueva que [local].
bool isNewerVersion(String remote, String local) {
  List<int> parts(String v) => v
      .split('.')
      .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9].*$'), '')) ?? 0)
      .toList();
  final r = parts(remote);
  final l = parts(local);
  for (var i = 0; i < 3; i++) {
    final rv = i < r.length ? r[i] : 0;
    final lv = i < l.length ? l[i] : 0;
    if (rv != lv) return rv > lv;
  }
  return false;
}
