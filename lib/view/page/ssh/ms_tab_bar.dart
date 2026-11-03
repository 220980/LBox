import 'package:material_ui/material_ui.dart';

/// A row of terminal tabs across the top of the terminal page, built like
/// meatshell's `TabBar` (`ui/tabs.slint`): 36px tall on `bg-panel-alt`, each tab
/// a 30px chip with an 8px status dot, its name and a close cross, the active
/// one ringed in the accent colour.
///
/// It is a view of this app's existing session tabs — the list the rail and
/// `SessionTabBar` already drive — restyled to meatshell's strip rather than a
/// second source of truth. `names[0]` is the leading "select" entry and the
/// real sessions start at 1, matching `SessionTabsController`.
final class MsTabBar extends StatelessWidget {
  const MsTabBar({
    super.key,
    required this.names,
    required this.index,
    required this.onTap,
    required this.onClose,
    this.dotOf,
    this.trailing = const [],
    this.height = barHeight,
    this.bgColor,
    this.opacity = 1.0,
  });

  /// Tall enough for a tab chip (30px) and the 32px icon buttons that share the
  /// row with it.
  static const barHeight = 36.0;

  final double height;

  /// Overrides the strip's own colour — the user's status-bar colour, when one
  /// is set. Null keeps meatshell's `bg-panel-alt`.
  final Color? bgColor;

  /// How solid the strip's background is; below 1 the terminal shows through.
  final double opacity;

  final List<String> names;

  /// Index into [names] of the active entry; 0 is the leading/picker entry.
  final int index;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onClose;

  /// The 8px status dot drawn before a tab's name, given its index in [names].
  final Widget Function(int index)? dotOf;

  /// Right-aligned buttons for whichever terminal is showing.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final palette = _BarPalette.of(context);
    final sessions = [
      for (var i = 1; i < names.length; i++) i,
    ];
    return Container(
      height: height,
      // An explicit [bgColor] is used as given (the page paints the bar's one
      // shared colour and transparency behind it, and passes transparent here);
      // only the palette default takes [opacity].
      color: bgColor ?? palette.bgPanelAlt.withValues(alpha: opacity),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final i in sessions) ...[
                    _MsTab(
                      title: names[i],
                      active: i == index,
                      leading: dotOf?.call(i),
                      onTap: () => onTap(i),
                      onClose: () => onClose(i),
                    ),
                    const SizedBox(width: 2),
                  ],
                ],
              ),
            ),
          ),
          for (final w in trailing) ...[
            const SizedBox(width: 2),
            w,
          ],
        ],
      ),
    );
  }
}

final class _MsTab extends StatefulWidget {
  const _MsTab({
    required this.title,
    required this.active,
    required this.onTap,
    required this.onClose,
    this.leading,
  });

  final String title;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final Widget? leading;

  @override
  State<_MsTab> createState() => _MsTabState();
}

class _MsTabState extends State<_MsTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = _BarPalette.of(context);
    final bg = widget.active
        ? p.bgElevated
        : (_hover ? p.bgHover : Colors.transparent);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.only(left: 10, right: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: widget.active
                ? Border.all(color: p.accent, width: 2)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: 8),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.active ? p.textPrimary : p.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _CloseButton(p: p, onTap: widget.onClose),
            ],
          ),
        ),
      ),
    );
  }
}

final class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.p, required this.onTap});

  final _BarPalette p;
  final VoidCallback onTap;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? widget.p.bgHover : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(Icons.close, size: 13, color: widget.p.textSecondary),
        ),
      ),
    );
  }
}

/// meatshell's palette for the strip, transcribed from `ui/theme.slint`.
final class _BarPalette {
  final Color bgPanelAlt, bgElevated, bgHover, textPrimary, textSecondary, accent;

  const _BarPalette({
    required this.bgPanelAlt,
    required this.bgElevated,
    required this.bgHover,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
  });

  static const dark = _BarPalette(
    bgPanelAlt: Color(0xFF2a2d35),
    bgElevated: Color(0xFF30333c),
    bgHover: Color(0xFF373a44),
    textPrimary: Color(0xFFe6e8ee),
    textSecondary: Color(0xFFb4b9c4),
    accent: Color(0xFF4a90e2),
  );

  static const light = _BarPalette(
    bgPanelAlt: Color(0xFFf2f2f7),
    bgElevated: Color(0xFFe8e8ed),
    bgHover: Color(0xFFe0e0e6),
    textPrimary: Color(0xFF1d1d1f),
    textSecondary: Color(0xFF45454a),
    accent: Color(0xFF0071e3),
  );

  static _BarPalette of(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? dark : light;
}
