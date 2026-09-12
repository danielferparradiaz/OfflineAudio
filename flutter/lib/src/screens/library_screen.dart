import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:offline_audio_app/src/adaptive.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/screens/screens.dart';
import 'package:offline_audio_app/src/widgets/widgets.dart';

/// Biblioteca local: lista de tracks descargados. El buscador mantiene el
/// mismo aspecto que el de Descargas pero solo filtra la biblioteca local
/// (no hace búsquedas de YouTube ni descargas).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final SortOrder _order = SortOrder.dateDesc;
  final _searchController = TextEditingController();

  /// Búsqueda local en curso / consulta activa en la biblioteca.
  bool _searching = false;
  String? _activeQuery;

  String? _selectedTrackId;
  final FocusNode _listFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _listFocusNode.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Vuelve a mostrar la biblioteca completa (sin filtro de búsqueda).
  Future<void> _serveLibrary() async {
    _searchController.clear();
    setState(() {
      _searching = false;
      _activeQuery = null;
    });
    await AppModelProvider.of(context)
        .reloadLibrary(search: null, order: _order);
  }

  /// Busca dentro de la biblioteca local. El backend filtra las pistas por
  /// título/artista/álbum; sin llamadas de red.
  Future<void> _searchNow([String? queryOverride]) async {
    final q = (queryOverride ?? _searchController.text).trim();
    if (q.isEmpty) {
      await _serveLibrary();
      return;
    }
    FocusScope.of(context).unfocus();
    final model = AppModelProvider.of(context);
    setState(() {
      _searching = true;
      _activeQuery = q;
    });
    try {
      await model.reloadLibrary(search: q, order: _order);
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  /// Reproduce un track; si es vídeo, abre directamente el reproductor de
  /// vídeo (que además garantiza su propia reproducción).
  static Future<void> openTrack(
    BuildContext context,
    AppModel model,
    Track track,
  ) async {
    if (track.contentKind == 'video') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => VideoPlayerScreen(track: track)),
      );
    } else {
      await model.playTrack(track);
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = AppModelProvider.of(context);
    return SafeArea(
      child: Focus(
        autofocus: true,
        focusNode: _listFocusNode,
        onKeyEvent: (node, event) {
          // Espacio alterna play/pause SOLO cuando el foco es la propia
          // lista. Mientras se escribe en el buscador (foco en el campo), el
          // evento nunca se reclama y el espacio se inserta con normalidad.
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.space &&
              FocusManager.instance.primaryFocus == _listFocusNode) {
            AppModelProvider.of(context).togglePause();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          children: [
            _buildFrostedTop(context),
            Expanded(child: _buildContent(context, model)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, AppModel model) {
    final subtle = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.6);
    if (_searching) {
      return SearchFeedback(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: isApplePlatform
                  ? const CupertinoActivityIndicator()
                  : const CircularProgressIndicator(),
            ),
            const SizedBox(height: 12),
            Text('Buscando…', style: TextStyle(color: subtle, fontSize: 12)),
          ],
        ),
      );
    }
    if (_activeQuery != null) {
      return _buildResults(context, model);
    }
    return _buildList(context, model, model.library);
  }

  Widget _buildResults(BuildContext context, AppModel model) {
    final tracks = model.library;
    final query = _activeQuery ?? '';
    final subtle = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.55);
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: GestureDetector(
            onTap: _serveLibrary,
            child: Text(
              'Resultados para «$query»',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            '${tracks.length} '
            '${tracks.length == 1 ? 'canción' : 'canciones'}',
            style: TextStyle(fontSize: 11, color: subtle),
          ),
        ),
        const SizedBox(height: 4),
        if (tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedSearch02,
                  size: 48,
                  color: subtle.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'Sin resultados en la biblioteca para «$query»',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subtle),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _serveLibrary,
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh),
                  label: const Text('Volver a la biblioteca'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ...tracks.map(
            (t) => TrackTile(
              track: t,
              selected: _selectedTrackId == t.id,
              onPlay: () => openTrack(context, model, t),
              onSelect: () => setState(() => _selectedTrackId = t.id),
            ),
          ),
      ],
    );
  }

  /// Panel superior (buscador) con superficie translúcida, mismo aspecto que
  /// el de la pestaña Descargas.
  Widget _buildFrostedTop(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.72),
            border: Border(
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // En Apple no hay avatar sobre el buscador (los ajustes están
              // en el sidebar). En Material se conserva el avatar que abre el
              // cajón de ajustes.
              if (!isApplePlatform) _buildHeader(context),
              _buildSearchField(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Align(
        alignment: Alignment.centerRight,
        child: Builder(
          builder: (context) => InkWell(
            onTap: () => Scaffold.of(context).openEndDrawer(),
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: CircleAvatar(
                radius: 16,
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedUser,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, isApplePlatform ? 12 : 4, 16, 10),
      child: AppSearchField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onSearch: _searchNow,
        onChanged: (value) {
          // La X del buscador está vaciando el campo: si estábamos viendo
          // resultados, volvemos a la biblioteca completa.
          if (value.isEmpty && _activeQuery != null) _serveLibrary();
        },
      ),
    );
  }

  Widget _buildList(BuildContext context, AppModel model, List<Track> tracks) {
    if (tracks.isEmpty) {
      return const EmptyLibrary();
    }
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      children: [
        SectionHeader(
          'Biblioteca',
          trailing: _ShuffleCoinButton(
            onPressed: model.shuffleLibrary,
          ),
        ),
        ...tracks.map(
          (t) => TrackTile(
            track: t,
            selected: _selectedTrackId == t.id,
            onPlay: () => openTrack(context, model, t),
            onSelect: () => setState(() => _selectedTrackId = t.id),
          ),
        ),
      ],
    );
  }
}

/// Botón "Aleatorio" de la biblioteca: solo el icono poker_chip, sin texto.
/// Al pulsar hace un efecto de tirar la moneda (giro 3D + salto) y dispara
/// la reproducción aleatoria.
class _ShuffleCoinButton extends StatefulWidget {
  const _ShuffleCoinButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_ShuffleCoinButton> createState() => _ShuffleCoinButtonState();
}

class _ShuffleCoinButtonState extends State<_ShuffleCoinButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final Animation<double> _toss = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (_controller.isAnimating) return;
    _controller.forward(from: 0);
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: 'Aleatorio',
      child: OutlinedButton(
        onPressed: _handleTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary.withValues(alpha: 0.5), width: 1),
          padding: const EdgeInsets.all(10),
          minimumSize: const Size(44, 44),
          shape: const CircleBorder(),
          backgroundColor: Colors.transparent,
        ),
        child: AnimatedBuilder(
          animation: _toss,
          builder: (context, child) {
            final v = _toss.value;
            final angle = v * math.pi * 4;
            final dy = -math.sin(v * math.pi) * 18;
            final scale = 1 + math.sin(v * math.pi) * 0.15;
            return Transform.translate(
              offset: Offset(0, dy),
              child: Transform(
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateY(angle),
                alignment: Alignment.center,
                child: Transform.scale(scale: scale, child: child),
              ),
            );
          },
          child: PokerChipIcon(size: 24, color: primary),
        ),
      ),
    );
  }
}

/// Icono poker_chip de Material Symbols, dibujado desde su path SVG
/// (viewBox "0 -960 960 960") para no añadir dependencias nuevas.
class PokerChipIcon extends StatelessWidget {
  const PokerChipIcon({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  // Path original aportado por el usuario (fill #1f1f1f).
  static const _data =
      'M480-80q-83 0-156-31.5T197-197q-54-54-85.5-127T80-480q0-83 31.5-156T197-763q54-54 127-85.5T480-880q83 0 156 31.5T763-763q54 54 85.5 127T880-480q0 83-31.5 156T763-197q-54 54-127 85.5T480-80Zm-40-83v-40q-35-5-67.5-19T312-256l-28 29q33 26 72.5 42.5T440-163Zm80 0q44-5 83.5-21.5T676-227l-28-29q-28 20-60.5 34T520-203v40Zm-40-117q83 0 141.5-58.5T680-480q0-83-58.5-141.5T480-680q-83 0-141.5 58.5T280-480q0 83 58.5 141.5T480-280Zm253-4q26-33 42.5-72.5T797-440h-40q-5 35-19 67.5T704-312l29 28Zm-506 0 29-29q-20-28-34-60t-19-67h-40q5 44 21.5 83.5T227-284Zm253-36L360-480l120-160 120 160-120 160ZM163-520h40q5-35 19-67t34-60l-29-29q-26 33-42.5 72.5T163-520Zm594 0h40q-5-44-22-83.5T732-676l-28 28q20 28 34 60.5t19 67.5ZM313-704q28-20 60-34t67-19v-40q-44 5-83.5 21.5T284-733l29 29Zm335 0 28-28q-33-26-72.5-43T520-797v40q35 5 67.5 19t60.5 34Z';

  static Path? _cache;

  static Path _basePath() {
    final cached = _cache;
    if (cached != null) return cached;
    final path = _parseSvgPath(_data);
    _cache = path;
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return CustomPaint(
      size: Size.square(size),
      painter: _PokerChipPainter(_basePath(), c),
    );
  }
}

class _PokerChipPainter extends CustomPainter {
  _PokerChipPainter(this.base, this.color);

  final Path base;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // El path está en coords 0..960 x, -960..0 y. Lo desplazamos a 0..960
    // y lo escalamos al tamaño pedido.
    final shifted = base.shift(const Offset(0, 960));
    final scale = size.width / 960;
    final matrix = Matrix4.diagonal3Values(scale, scale, 1).storage;
    final scaled = shifted.transform(matrix);
    scaled.fillType = PathFillType.evenOdd;
    canvas.drawPath(scaled, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PokerChipPainter old) =>
      old.color != color || old.base != base;
}

/// Mini parser SVG (M/m/L/l/H/h/V/v/Q/q/T/t/Z) suficiente para el path del
/// poker_chip. Los números pegados tipo "480-80" se separan correctamente.
Path _parseSvgPath(String d) {
  final tokenRe = RegExp(r'[MmLlHhVvQqTtZz]|_?-?\d*\.?\d+');
  final tokens = tokenRe
      .allMatches(d.replaceAll(',', ' '))
      .map((m) => m.group(0)!)
      .where((t) => t.isNotEmpty && t != '_')
      .toList();
  final path = Path();
  var i = 0;
  String? cmd;
  double cx = 0, cy = 0, sx = 0, sy = 0;
  double prevCx = 0, prevCy = 0;
  String prevCmd = '';

  double nextNum() => double.parse(tokens[i++]);

  bool isNumToken() =>
      i < tokens.length && !RegExp(r'^[MmLlHhVvQqTtZz]$').hasMatch(tokens[i]);

  void lineToAbs(double x, double y) {
    path.lineTo(x, y);
    cx = x;
    cy = y;
  }

  void lineToRel(double dx, double dy) => lineToAbs(cx + dx, cy + dy);

  void moveToAbs(double x, double y) {
    path.moveTo(x, y);
    cx = x;
    cy = y;
    sx = x;
    sy = y;
  }

  void moveToRel(double dx, double dy) => moveToAbs(cx + dx, cy + dy);

  void quadToAbs(double x1, double y1, double x, double y) {
    path.quadraticBezierTo(x1, y1, x, y);
    prevCx = x1;
    prevCy = y1;
    cx = x;
    cy = y;
  }

  void quadToRel(double dx1, double dy1, double dx, double dy) =>
      quadToAbs(cx + dx1, cy + dy1, cx + dx, cy + dy);

  void smoothQuadToAbs(double x, double y) {
    double x1, y1;
    if (prevCmd == 'Q' || prevCmd == 'q' || prevCmd == 'T' || prevCmd == 't') {
      x1 = 2 * cx - prevCx;
      y1 = 2 * cy - prevCy;
    } else {
      x1 = cx;
      y1 = cy;
    }
    quadToAbs(x1, y1, x, y);
  }

  void smoothQuadToRel(double dx, double dy) =>
      smoothQuadToAbs(cx + dx, cy + dy);

  while (i < tokens.length) {
    final t = tokens[i];
    if (RegExp(r'^[MmLlHhVvQqTtZz]$').hasMatch(t)) {
      cmd = t;
      i++;
    } else if (cmd == null) {
      i++;
      continue;
    }
    switch (cmd) {
      case 'M':
        moveToAbs(nextNum(), nextNum());
        prevCmd = 'M';
        // Pares extra tras M son LineTo implícitos.
        while (isNumToken()) {
          lineToAbs(nextNum(), nextNum());
          prevCmd = 'L';
        }
        break;
      case 'm':
        moveToRel(nextNum(), nextNum());
        prevCmd = 'm';
        while (isNumToken()) {
          lineToRel(nextNum(), nextNum());
          prevCmd = 'l';
        }
        break;
      case 'L':
        while (isNumToken()) {
          lineToAbs(nextNum(), nextNum());
        }
        prevCmd = 'L';
        break;
      case 'l':
        while (isNumToken()) {
          lineToRel(nextNum(), nextNum());
        }
        prevCmd = 'l';
        break;
      case 'H':
        while (isNumToken()) {
          lineToAbs(nextNum(), cy);
        }
        prevCmd = 'H';
        break;
      case 'h':
        while (isNumToken()) {
          lineToRel(nextNum(), 0);
        }
        prevCmd = 'h';
        break;
      case 'V':
        while (isNumToken()) {
          lineToAbs(cx, nextNum());
        }
        prevCmd = 'V';
        break;
      case 'v':
        while (isNumToken()) {
          lineToRel(0, nextNum());
        }
        prevCmd = 'v';
        break;
      case 'Q':
        while (isNumToken()) {
          quadToAbs(nextNum(), nextNum(), nextNum(), nextNum());
        }
        prevCmd = 'Q';
        break;
      case 'q':
        while (isNumToken()) {
          quadToRel(nextNum(), nextNum(), nextNum(), nextNum());
        }
        prevCmd = 'q';
        break;
      case 'T':
        while (isNumToken()) {
          smoothQuadToAbs(nextNum(), nextNum());
        }
        prevCmd = 'T';
        break;
      case 't':
        while (isNumToken()) {
          smoothQuadToRel(nextNum(), nextNum());
        }
        prevCmd = 't';
        break;
      case 'Z':
      case 'z':
        path.close();
        cx = sx;
        cy = sy;
        prevCmd = 'Z';
        break;
    }
  }
  return path;
}
