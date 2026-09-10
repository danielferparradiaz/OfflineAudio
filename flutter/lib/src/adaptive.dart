import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'platform.dart';

export 'platform.dart' show isApplePlatform, isIOSPlatform, isMacOSPlatform;

/// Acción de un diálogo adaptativo: se renderiza como toque Cupertino en
/// Apple y como TextButton/FilledButton Material en el resto.
class AppDialogAction<T> {
  const AppDialogAction({
    required this.label,
    this.getValue,
    this.isDefault = false,
    this.isDestructive = false,
  });

  final String label;

  /// Valor a devolver al pulsar la acción. Se evalúa en el momento del toque.
  final T? Function()? getValue;

  final bool isDefault;
  final bool isDestructive;
}

/// Diálogo adaptativo (CupertinoAlertDialog en Apple, AlertDialog Material
/// en Windows/Android). Devuelve el valor de la acción pulsada o `null` al
/// cancelar.
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required Widget title,
  Widget? content,
  List<AppDialogAction<T>> actions = const [],
}) {
  void popAction(BuildContext dialogContext, AppDialogAction<T> a) {
    Navigator.of(dialogContext).pop(a.getValue?.call());
  }

  if (isApplePlatform) {
    return showCupertinoDialog<T>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: title,
        content: content,
        actions: [
          for (final a in actions)
            CupertinoDialogAction(
              isDefaultAction: a.isDefault,
              isDestructiveAction: a.isDestructive,
              onPressed: () => popAction(dialogContext, a),
              child: Text(a.label),
            ),
        ],
      ),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: title,
      content: content,
      actions: [
        for (final a in actions)
          a.isDefault
              ? FilledButton(
                  onPressed: () => popAction(dialogContext, a),
                  child: Text(a.label),
                )
              : TextButton(
                  style: a.isDestructive
                      ? TextButton.styleFrom(
                          foregroundColor: Theme.of(dialogContext)
                              .colorScheme
                              .error,
                        )
                      : null,
                  onPressed: () => popAction(dialogContext, a),
                  child: Text(a.label),
                ),
      ],
    ),
  );
}

/// Item de una hoja adaptativa (selection/action). [value] se devuelve al
/// tocar la fila, como en el comportamiento de showModalBottomSheet.
class AppSheetItem<T> {
  const AppSheetItem({
    required this.value,
    required this.label,
    this.icon,
    this.subtitle,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData? icon;
  final String? subtitle;
  final bool destructive;
}

/// Hoja inferior adaptativa: CupertinoActionSheet en Apple y
/// showModalBottomSheet con ListTiles en el resto.
Future<T?> showAppBottomSheet<T>(
  BuildContext context, {
  Widget? title,
  List<AppSheetItem<T>> items = const [],
  bool withCancel = true,
}) {
  if (isApplePlatform) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: title,
        actions: [
          for (final item in items)
            CupertinoActionSheetAction(
              isDestructiveAction: item.destructive,
              onPressed: () => Navigator.of(sheetContext).pop(item.value),
              child: item.subtitle == null
                  ? Text(item.label)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.label),
                        Text(
                          item.subtitle!,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
            ),
        ],
        cancelButton: withCancel
            ? CupertinoActionSheetAction(
                isDefaultAction: true,
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Cancelar'),
              )
            : null,
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: title,
            ),
            const Divider(height: 1),
          ],
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final item in items)
                  ListTile(
                    leading: item.icon != null ? Icon(item.icon) : null,
                    title: Text(item.label),
                    subtitle: item.subtitle != null
                        ? Text(item.subtitle!)
                        : null,
                    onTap: () => Navigator.of(sheetContext).pop(item.value),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Aviso transitorio. Usa el SnackBar estándar de Material (bien visible en
/// cualquier tema) presentándolo en el Scaffold más cercano; si en una
/// pantalla puramente Cupertino no hubiera ningún Scaffold, cae a un toast
/// propio vía Overlay para no romper la ejecución.
void showAppSnackBar(
  BuildContext context, {
  required String message,
  Duration duration = const Duration(milliseconds: 2800),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger != null) {
    try {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message), duration: duration));
      return;
    } catch (_) {
      // Sin Scaffold descendiente: fallamos al toast propio.
    }
  }
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _OverlaySnackbar(
      message: message,
      duration: duration,
      onDismissed: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _OverlaySnackbar extends StatefulWidget {
  const _OverlaySnackbar({
    required this.message,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_OverlaySnackbar> createState() => _OverlaySnackbarState();
}

class _OverlaySnackbarState extends State<_OverlaySnackbar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _anim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    Future<void>.delayed(widget.duration, _dismiss);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    // Superficie oscura neutra en ambos modos (estilo Cupertino): evita que
    // en modo oscuro el fondo claro se vea amarillento.
    const background = Color(0xF0222222);
    const foreground = Colors.white;

    return Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.of(context).padding.bottom + 20,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.3),
              end: Offset.zero,
            ).animate(_anim),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                widget.message,
                style: TextStyle(color: foreground, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Campo de texto adaptativo para el contenido de los diálogos: Cupertino
/// en Apple, Material en el resto.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.autofocus = false,
    this.onSubmitted,
    this.label,
  });

  final TextEditingController? controller;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (isApplePlatform) {
      return CupertinoTextField(
        controller: controller,
        autofocus: autofocus,
        onSubmitted: onSubmitted,
        placeholder: label,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      );
    }
    return TextField(
      controller: controller,
      autofocus: autofocus,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(labelText: label),
    );
  }
}

/// Buscador adaptativo: CupertinoSearchTextField en Apple, TextField de
/// Material redondeado en el resto.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.onSearch,
    this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onSearch;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (isApplePlatform) {
      return CupertinoSearchTextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: (_) => onSearch(),
        itemColor: CupertinoTheme.of(context).primaryColor,
      );
    }
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        prefixIcon: IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Buscar en YouTube',
          onPressed: onSearch,
        ),
        hintText: 'Buscar',
        filled: true,
        fillColor: Theme.of(context).colorScheme.onSurface
            .withValues(alpha: 0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide.none,
        ),
      ),
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSearch(),
    );
  }
}

/// Página completa adaptativa: CupertinoPageScaffold + CupertinoNavigationBar
/// en Apple, Scaffold + AppBar Material en el resto.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    this.title,
    this.actions = const [],
    required this.body,
  });

  final String? title;
  final List<Widget> actions;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    if (isApplePlatform) {
      final tint = CupertinoTheme.of(context).primaryColor;
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: title == null ? null : Text(title!),
          trailing: actions.isEmpty
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final action in actions)
                      DefaultTextStyle(
                        style: TextStyle(color: tint),
                        child: IconTheme.merge(
                          data: IconThemeData(color: tint, size: 20),
                          child: action,
                        ),
                      ),
                  ],
                ),
        ),
        child: SafeArea(
          bottom: true,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: body,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: title == null ? null : Text(title!),
        actions: actions,
      ),
      body: body,
    );
  }
}
