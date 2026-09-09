// ignore_for_file: avoid_print
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Sonda de búsqueda fuera de la app.
///
/// Uso:
///   cd flutter && dart run tool/search_probe.dart "j balvin"
///
/// Replica lo que hace YoutubeSearch.search pero en CLI, para aislar si el
/// fallo está en la red/parsing (aquí también falla) o en la UI (aquí va
/// bien y en la app no).
Future<void> main(List<String> args) async {
  final query = args.join(' ').trim();
  if (query.isEmpty) {
    print('Uso: dart run tool/search_probe.dart "<búsqueda>"');
    return;
  }
  final yt = YoutubeExplode();
  final sw = Stopwatch()..start();
  print('[probe] query="$query" inicio');
  try {
    final videos = await yt.search
        .search(query)
        .timeout(const Duration(seconds: 25));
    sw.stop();
    print('[probe] raw=${videos.length} en ${sw.elapsedMilliseconds}ms');
    for (var i = 0; i < videos.length && i < 10; i++) {
      final v = videos[i];
      print('  [$i] "${v.title}" · ${v.author} '
          '· dur=${v.duration} · id=${v.id}');
      print('       thumb=${v.thumbnails.highResUrl}');
      print('       url=${v.url}');
    }
    if (videos.isEmpty) {
      print('[probe] 0 resultados: YouTube devolvió lista vacía '
          '(mismo caso que "Sin resultados" en la app).');
    }
  } catch (e, st) {
    sw.stop();
    print('[probe] ERROR tras ${sw.elapsedMilliseconds}ms: $e');
    print(st);
  } finally {
    yt.close();
  }
}
