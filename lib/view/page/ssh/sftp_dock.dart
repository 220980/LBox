import 'package:material_ui/material_ui.dart';
import 'package:server_box/core/extension/context/locale.dart';
import 'package:server_box/data/model/server/server_private_info.dart';
import 'package:server_box/view/page/ssh/ms_sftp_panel.dart';

/// A server's files under its terminal, in meatshell's shape: the panel is
/// docked to the bottom edge behind a 5px splitter that can be dragged to
/// resize it, and folded to a 36px strip at the same edge when minimised. The
/// panel itself is [MsSftpPanel], which carries its own 34px toolbar — so there
/// is one bar here, as there is in meatshell, not a strip above a bar.
final class TerminalSftpDock extends StatefulWidget {
  final Spi spi;

  /// The one chrome colour, passed through to [MsSftpPanel] and the folded
  /// strip so the file browser matches the rest of the page.
  final Color? tint;

  const TerminalSftpDock({super.key, required this.spi, this.tint});

  @override
  State<TerminalSftpDock> createState() => _TerminalSftpDockState();
}

class _TerminalSftpDockState extends State<TerminalSftpDock> {
  static const _kMinHeight = 140.0;
  static const _kMaxHeight = 640.0;
  static const _kStrip = 36.0;

  Color get _bgPanelAlt => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF2a2d35)
      : const Color(0xFFf2f2f7);
  Color get _borderSubtle => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF3a3d46)
      : const Color(0xFFe2e2e8);
  Color get _textSecondary => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFb4b9c4)
      : const Color(0xFF45454a);

  double _height = 220;
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    if (_collapsed) return _strip();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.resizeRow,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (d) {
              setState(() {
                _height = (_height - d.delta.dy).clamp(_kMinHeight, _kMaxHeight);
              });
            },
            child: SizedBox(
              height: 5,
              child: Center(
                child: Container(width: 40, height: 2, color: _borderSubtle),
              ),
            ),
          ),
        ),
        SizedBox(
          height: _height,
          width: double.infinity,
          child: ClipRect(
            child: MsSftpPanel(
              spi: widget.spi,
              tint: widget.tint,
              onMinimize: () => setState(() => _collapsed = true),
            ),
          ),
        ),
      ],
    );
  }

  Widget _strip() {
    return GestureDetector(
      onTap: () => setState(() => _collapsed = false),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: _kStrip,
          decoration: BoxDecoration(
            color: widget.tint ?? _bgPanelAlt,
            border: Border(top: BorderSide(color: _borderSubtle)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(Icons.drag_indicator, size: 16, color: _textSecondary),
              const SizedBox(width: 8),
              Text(
                context.l10n.sftpFiles,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _textSecondary,
                ),
              ),
              const Spacer(),
              Icon(Icons.keyboard_arrow_up, size: 18, color: _textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
