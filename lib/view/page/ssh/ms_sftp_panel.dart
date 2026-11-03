import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart' show SSHClient;
import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:server_box/core/extension/context/locale.dart';
import 'package:server_box/core/utils/ssh_file_backend.dart';
import 'package:server_box/data/model/file/file_backend.dart';
import 'package:server_box/data/model/server/server_private_info.dart';
import 'package:server_box/data/model/server/ssh_credential.dart';
import 'package:server_box/data/provider/server/single.dart';
import 'package:server_box/data/res/store.dart';
import 'package:server_box/src/rust/api/files.dart' as files;
import 'package:server_box/view/page/ssh/panel_style.dart';

/// meatshell's palette, transcribed from `ui/theme.slint` (`ThemePalette`), so
/// the file panel matches their SFTP pane rather than this app's surfaces.
final class _P {
  final Color bgRoot, bgPanelAlt, bgHover, borderSubtle;
  final Color textPrimary, textSecondary, textMuted, accent, danger;

  const _P({
    required this.bgRoot,
    required this.bgPanelAlt,
    required this.bgHover,
    required this.borderSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.danger,
  });

  static const dark = _P(
    bgRoot: Color(0xFF1b1d23),
    bgPanelAlt: Color(0xFF2a2d35),
    bgHover: Color(0xFF373a44),
    borderSubtle: Color(0xFF3a3d46),
    textPrimary: Color(0xFFe6e8ee),
    textSecondary: Color(0xFFb4b9c4),
    textMuted: Color(0xFF9196a3),
    accent: Color(0xFF4a90e2),
    danger: Color(0xFFe25c5c),
  );

  static const light = _P(
    bgRoot: Color(0xFFf5f5f7),
    bgPanelAlt: Color(0xFFf2f2f7),
    bgHover: Color(0xFFe0e0e6),
    borderSubtle: Color(0xFFe2e2e8),
    textPrimary: Color(0xFF1d1d1f),
    textSecondary: Color(0xFF45454a),
    textMuted: Color(0xFF606066),
    accent: Color(0xFF0071e3),
    danger: Color(0xFFFF3B30),
  );

  static _P of(BuildContext c) {
    final base = Theme.of(c).brightness == Brightness.dark ? dark : light;
    final tint = _PanelTint.maybeOf(c);
    final p = tint == null ? base : base.tinted(tint);
    final accent = PanelStyle.accentOverride();
    final text = PanelStyle.textOverride();
    if (accent == null && text == null) return p;
    return p.recolor(accent: accent, text: text);
  }

  /// This palette with the whole-page accent and text colours folded in — the
  /// same two settings the readings panel takes, so the file browser's text
  /// and accent follow one choice.
  _P recolor({Color? accent, Color? text}) {
    return _P(
      bgRoot: bgRoot,
      bgPanelAlt: bgPanelAlt,
      bgHover: bgHover,
      borderSubtle: borderSubtle,
      textPrimary: text ?? textPrimary,
      textSecondary: text == null
          ? textSecondary
          : Color.alphaBlend(text.withValues(alpha: 0.8), bgPanelAlt),
      textMuted: text == null
          ? textMuted
          : Color.alphaBlend(text.withValues(alpha: 0.6), bgPanelAlt),
      accent: accent ?? this.accent,
      danger: danger,
    );
  }

  /// This palette with its surfaces taken from [c] — the one colour the terminal
  /// page's chrome shares — so the file panel matches the rail, the top bar and
  /// the readings panel.
  _P tinted(Color c) => _P(
    bgRoot: c,
    bgPanelAlt: c,
    bgHover: bgHover,
    borderSubtle: borderSubtle,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    textMuted: textMuted,
    accent: accent,
    danger: danger,
  );
}

/// Carries [MsSftpPanel.tint] down to every [_P.of] call in its subtree, so the
/// panel's toolbar, header, listing, tree and status line all take the one
/// shared colour without threading it through each builder.
class _PanelTint extends InheritedWidget {
  final Color? color;

  const _PanelTint({required this.color, required super.child});

  static Color? maybeOf(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<_PanelTint>()?.color;

  @override
  bool updateShouldNotify(_PanelTint old) => old.color != color;
}

/// A server's files, laid out like meatshell's `SftpPanel` (`ui/sftp_panel.slint`)
/// in its single-pane Files view: a 34px toolbar over a 20px column header, a
/// 24px-row listing and an 18px status line.
///
/// Real work goes through this app's [FileBackend] — the same SFTP/SCP backend
/// the file tab uses — so listing, navigating, new folder, rename and delete
/// actually act on the server. Upload/download and the tree/dual/tunnels panes
/// of the original are not wired here yet.
final class MsSftpPanel extends ConsumerStatefulWidget {
  final Spi spi;

  /// Folds the whole panel to its edge strip (the toolbar's minimise chevron).
  final VoidCallback? onMinimize;

  /// The one colour the terminal page's chrome shares — see `PanelStyle`. Null
  /// keeps meatshell's own palette.
  final Color? tint;

  const MsSftpPanel({super.key, required this.spi, this.onMinimize, this.tint});

  @override
  ConsumerState<MsSftpPanel> createState() => _MsSftpPanelState();
}

class _MsSftpPanelState extends ConsumerState<MsSftpPanel> {
  FileBackend? _backend;
  String _path = '/';
  List<FileEntry> _entries = const [];
  bool _loading = true;
  String? _error;
  final _selected = <String>{};
  String _sortKey = 'name';
  int _sortDir = 1;

  /// Uploads this panel has started, newest first, with what has reached the
  /// far side so far. Kept after they finish so the list is a short record.
  final _uploads = <_UploadTask>[];
  bool _showUploads = false;
  double _uploadsWidth = 220;
  DateTime _lastPump = DateTime.fromMillisecondsSinceEpoch(0);

  /// Which tree folders are open, and their subfolders once read.
  final _expanded = <String>{'/'};
  final _treeChildren = <String, List<FileEntry>>{};

  final _pathCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    _backend?.close();
    super.dispose();
  }

  /// A bound for the dock's SFTP operations. The 5s the setting defaults to is
  /// fine for a command but tight for listing a directory over a WAN, and an
  /// operation that exceeds it closes the channel — after which every later
  /// call fails until the session is reopened. Flooring it higher here keeps a
  /// slow listing from tearing down a working session.
  Duration get _opTimeout {
    final s = Stores.setting.timeout.fetch();
    return Duration(seconds: s > 20 ? s : 20);
  }

  Future<void> _init({String? path}) async {
    // Drop whatever the last session was: a timed-out SFTP operation closes its
    // channel, so the backend that failed is dead and must not be reused.
    final previous = _backend;
    _backend = null;
    if (previous != null) {
      unawaited(previous.close().catchError((_) {}));
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final spi = ref.read(serverProvider(widget.spi.id)).spi;
      final client =
          await ref.read(serverProvider(spi.id).notifier).ensureShellClient();
      final backend = await openSshFileBackend(
        client,
        transport: spi.ssh?.fileTransport ?? SshFileTransport.sftp,
        timeout: _opTimeout,
      );
      final home = path ?? await _home(client, spi);
      _backend = backend;
      await _list(home, reset: true);
      unawaited(_loadTreeChildren('/'));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// Reopens the session at the directory on screen — what the error view's
  /// button and a refresh after a dead channel both do.
  Future<void> _reconnect() => _init(path: _path.isEmpty ? null : _path);

  Future<String> _home(SSHClient client, Spi spi) async {
    final user = spi.ssh?.user ?? '';
    String? passwd;
    try {
      final bytes = await client.run(files.filesHomeCommand(user: user));
      passwd = utf8.decode(bytes);
    } catch (_) {}
    final home = files.filesHomeFrom(output: passwd, user: user);
    return home.isEmpty ? '/' : home;
  }

  Future<void> _list(String path, {bool reset = false}) async {
    final backend = _backend;
    if (backend == null) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _selected.clear();
    });
    try {
      final entries = await backend.list(path);
      if (!mounted) return;
      setState(() {
        _path = path;
        _pathCtrl.text = path;
        _entries = _sorted(entries);
        _loading = false;
      });
    } catch (e) {
      // An operation that timed out closed the channel underneath us, so this
      // backend is dead — forget it, and the next refresh reopens a session
      // instead of failing against a closed channel forever.
      final dead = _backend;
      _backend = null;
      if (dead != null) unawaited(dead.close().catchError((_) {}));
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  List<FileEntry> _sorted(List<FileEntry> entries) {
    final out = [...entries];
    out.sort((a, b) {
      // Directories first, always, then the chosen key.
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      int c;
      switch (_sortKey) {
        case 'size':
          c = (a.size ?? 0).compareTo(b.size ?? 0);
        case 'modified':
          c = (a.modified?.millisecondsSinceEpoch ?? 0)
              .compareTo(b.modified?.millisecondsSinceEpoch ?? 0);
        default:
          c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return c * _sortDir;
    });
    return out;
  }

  Future<void> _refresh() async {
    if (_backend == null) return _reconnect();
    return _list(_path);
  }

  void _up() {
    if (_path == '/' || _path.isEmpty) return;
    final idx = _path.lastIndexOf('/');
    final parent = idx <= 0 ? '/' : _path.substring(0, idx);
    _list(parent, reset: true);
  }

  void _open(FileEntry e) {
    if (e.isDir) {
      final base = _path.endsWith('/') ? _path : '$_path/';
      unawaited(_list('$base${e.name}', reset: true));
    }
  }

  String _full(FileEntry e) {
    final base = _path.endsWith('/') ? _path : '$_path/';
    return '$base${e.name}';
  }

  Future<void> _mkdir() async {
    final name = await _prompt(context.l10n.sftpNewFolder, '');
    if (name == null || name.trim().isEmpty) return;
    final backend = _backend;
    if (backend == null) return;
    final base = _path.endsWith('/') ? _path : '$_path/';
    try {
      await backend.mkdir('$base${name.trim()}');
      await _refresh();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _rename(FileEntry e) async {
    final name = await _prompt(libL10n.rename, e.name);
    if (name == null || name.trim().isEmpty) return;
    final backend = _backend;
    if (backend == null) return;
    final base = _path.endsWith('/') ? _path : '$_path/';
    try {
      await backend.rename('$base${e.name}', '$base${name.trim()}');
      await _refresh();
    } catch (ex) {
      _toast('$ex');
    }
  }

  Future<void> _delete(FileEntry e) async {
    final backend = _backend;
    if (backend == null) return;
    final ok = await _confirm(context.l10n.sftpDeleteConfirm(e.name));
    if (ok != true) return;
    try {
      await backend.remove(_full(e), recursive: e.isDir);
      await _refresh();
    } catch (ex) {
      _toast('$ex');
    }
  }

  /// Picks a local file and writes it into the folder on screen.
  ///
  /// Opens its own [FileBackend] rather than using the one the listing is on: a
  /// large write occupies a channel, and sharing it made every navigation and
  /// refresh stutter for the length of the transfer. The bytes are counted on
  /// their way to [FileBackend.write] so [_UploadTask] can show how far it got;
  /// the write itself is still the same staged replace the Files page uses.
  Future<void> _upload() async {
    final local = await Pfs.pickFilePath();
    if (local == null || !mounted) return;
    final name = local.split(Platform.pathSeparator).lastOrNull;
    if (name == null || name.isEmpty) return;
    final base = _path.endsWith('/') ? _path : '$_path/';
    final file = File(local);
    final spi = ref.read(serverProvider(widget.spi.id)).spi;
    final size = await file.length().catchError((_) => 0);
    final task = _UploadTask(name: name, total: size);
    setState(() {
      _uploads.insert(0, task);
      _showUploads = true;
    });
    FileBackend? up;
    try {
      final client =
          await ref.read(serverProvider(spi.id).notifier).ensureShellClient();
      up = await openSshFileBackend(
        client,
        transport: spi.ssh?.fileTransport ?? SshFileTransport.sftp,
        timeout: _opTimeout,
      );
      final sftp = (spi.ssh?.fileTransport ?? SshFileTransport.sftp) ==
          SshFileTransport.sftp;
      Stream<List<int>> payload = file.openRead();
      if (!sftp) {
        // SCP reports no acknowledgement, so count what this side reads.
        payload = payload.transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleData: (chunk, sink) {
              task.sent += chunk.length;
              _pumpUpload(task);
              sink.add(chunk);
            },
          ),
        );
      }
      await up.write(
        '$base$name',
        payload,
        size: size,
        // SFTP acknowledges each packet; counting those is what makes the bar
        // show what arrived, rather than what was only queued.
        onProgress: sftp
            ? (acked) {
                task.sent = acked;
                _pumpUpload(task);
              }
            : null,
      );
      task.sent = task.total;
      task.status = _UploadStatus.done;
      task.finishedAt = DateTime.now();
      if (mounted) setState(() {});
      unawaited(_refresh());
      _toast(libL10n.success);
    } catch (e) {
      task.status = _UploadStatus.failed;
      task.error = '$e';
      task.finishedAt = DateTime.now();
      if (mounted) setState(() {});
      _toast('$e');
    } finally {
      if (up != null) unawaited(up.close().catchError((_) {}));
    }
  }

  /// Repaints for progress at most every ~80ms: chunks arrive far more often
  /// than a frame, and one setState per chunk is what made the panel feel stuck.
  void _pumpUpload(_UploadTask t) {
    final now = DateTime.now();
    if (t.sent < t.total &&
        now.difference(_lastPump).inMilliseconds < 80) {
      return;
    }
    _lastPump = now;
    if (mounted) setState(() {});
  }

  Widget _uploadsView(_P p) {
    final Widget body;
    if (_uploads.isEmpty) {
      body = Center(
        child: Text(
          context.l10n.sftpNoUploads,
          style: TextStyle(fontSize: 12, color: p.textMuted),
        ),
      );
    } else {
      body = ListView.builder(
        itemCount: _uploads.length,
        itemBuilder: (context, i) {
          final t = _uploads[i];
          final uploading = t.status == _UploadStatus.uploading;
          final failed = t.status == _UploadStatus.failed;
          final timeText = uploading
              ? '${t.total <= 0 ? 0 : (t.sent * 100 ~/ t.total)}%'
              : failed
                  ? context.l10n.sftpUploadFailed
                  : _fmtRecordTime(t.finishedAt);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeText,
                      style: TextStyle(
                        fontSize: 10,
                        color: failed ? p.danger : p.textMuted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _fmtBytes(t.total),
                      style: TextStyle(fontSize: 10, color: p.textMuted),
                    ),
                  ],
                ),
                if (uploading) ...[
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: t.fraction,
                      minHeight: 4,
                      backgroundColor: p.borderSubtle,
                      color: p.accent,
                    ),
                  ),
                ],
                if (failed && (t.error?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 2),
                  Text(
                    t.error!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9, color: p.danger),
                  ),
                ],
              ],
            ),
          );
        },
      );
    }
    return Container(
      color: p.bgPanelAlt,
      child: Column(
        children: [
          Container(
            height: 26,
            padding: const EdgeInsets.only(left: 10, right: 4),
            color: p.bgPanelAlt,
            child: Row(
              children: [
                Icon(Icons.cloud_upload_outlined, size: 13, color: p.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.l10n.sftpUploads,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: p.textSecondary,
                    ),
                  ),
                ),
                _iconBtn(p, Icons.close, onTap: () {
                  setState(() => _showUploads = false);
                }),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  void _sortBy(String key) {
    setState(() {
      if (_sortKey == key) {
        _sortDir = -_sortDir;
      } else {
        _sortKey = key;
        _sortDir = 1;
      }
      _entries = _sorted(_entries);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds when the whole-page accent or text colour changes, so a pick in
    // Settings recolours the file browser at once rather than on the next tap.
    return ListenableBuilder(
      listenable: Listenable.merge([
        Stores.setting.uiAccentColor.listenable(),
        Stores.setting.uiTextColor.listenable(),
      ]),
      builder: (context, _) {
        final base = _P.of(context);
        final p = widget.tint == null ? base : base.tinted(widget.tint!);
        return _PanelTint(
          color: widget.tint,
          child: Container(
            color: p.bgRoot,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toolbar(p),
                _header(p),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _tree(p),
                      SizedBox(
                          width: 5, child: ColoredBox(color: p.borderSubtle)),
                      Expanded(child: _body(p)),
                    ],
                  ),
                ),
                _statusBar(p),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Toolbar (34px, bg-panel-alt) ---------------------------------------
  Widget _toolbar(_P p) {
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 10, right: 6, top: 6, bottom: 6),
      color: p.bgPanelAlt,
      child: Row(
        children: [
          Icon(Icons.drag_indicator, size: 16, color: p.textMuted),
          const SizedBox(width: 6),
          _tab(p, context.l10n.sftpFiles, active: true),
          const SizedBox(width: 4),
          _tab(p, context.l10n.sftpTunnels, active: false),
          const SizedBox(width: 4),
          _iconBtn(p, Icons.vertical_split_outlined, onTap: null),
          const SizedBox(width: 4),
          Expanded(
            child: SizedBox(
              height: 22,
              child: TextField(
                controller: _pathCtrl,
                style: TextStyle(fontSize: 12, color: p.textPrimary),
                cursorHeight: 13,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  filled: true,
                  fillColor: p.bgRoot,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: p.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: p.accent),
                  ),
                ),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) _list(v.trim(), reset: true);
                },
              ),
            ),
          ),
          const SizedBox(width: 4),
          _iconBtn(p, Icons.star_border, onTap: null),
          _iconBtn(p, Icons.bookmarks_outlined, onTap: null),
          _iconBtn(p, Icons.content_copy, onTap: () {
            Clipboard.setData(ClipboardData(text: _path));
          }),
          _iconBtn(p, Icons.arrow_upward, onTap: _up),
          _iconBtn(p, Icons.create_new_folder_outlined, onTap: _mkdir),
          const SizedBox(width: 4),
          _uploadPill(p),
          const SizedBox(width: 4),
          _iconBtn(p, Icons.list_alt, onTap: () {
            setState(() => _showUploads = !_showUploads);
          }),
          _iconBtn(p, Icons.refresh, onTap: _refresh),
          _iconBtn(p, Icons.keyboard_arrow_down, onTap: widget.onMinimize),
        ],
      ),
    );
  }

  Widget _tab(_P p, String label, {required bool active}) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? p.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: active ? Colors.white : p.textSecondary,
        ),
      ),
    );
  }

  Widget _uploadPill(_P p) {
    return GestureDetector(
      onTap: _upload,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.accent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            libL10n.upload,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(_P p, IconData icon, {VoidCallback? onTap}) {
    return _HoverSquare(
      p: p,
      onTap: onTap,
      child: Icon(icon, size: 15, color: p.textSecondary),
    );
  }

  // --- Column header (20px, bg-root) --------------------------------------
  Widget _header(_P p) {
    return Container(
      height: 20,
      color: p.bgRoot,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const SizedBox(width: 16),
          const SizedBox(width: 8),
          Expanded(
            child: _headCell(p, libL10n.name, 'name', align: TextAlign.left),
          ),
          _col(p, _headCell(p, libL10n.size, 'size'), 72),
          _col(p, _headCell(p, context.l10n.sftpModified, 'modified'), 116),
          _col(p, _headText(p, context.l10n.sftpPermissions), 104),
        ],
      ),
    );
  }

  Widget _col(_P p, Widget child, double w) => SizedBox(
        width: w,
        child: Align(alignment: Alignment.centerRight, child: child),
      );

  Widget _headText(_P p, String t) => Text(
        t,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: p.textMuted),
      );

  Widget _headCell(_P p, String t, String key,
      {TextAlign align = TextAlign.right}) {
    final active = _sortKey == key;
    final arrow = active ? (_sortDir > 0 ? ' ↑' : ' ↓') : '';
    return GestureDetector(
      onTap: () => _sortBy(key),
      behavior: HitTestBehavior.opaque,
      child: Text(
        '$t$arrow',
        textAlign: align,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: active ? p.accent : p.textMuted,
        ),
      ),
    );
  }

  // --- Rows ---------------------------------------------------------------
  Widget _body(_P p) {
    final files = _filesBody(p);
    // The upload record sits beside the files rather than over them: a transfer
    // in progress should not hide the folder it is landing in. The bar between
    // them drags, so the split is whatever the user wants; toggled from the
    // toolbar's progress button.
    if (!_showUploads) return files;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = (constraints.maxWidth - 160).clamp(140.0, constraints.maxWidth);
        final w = _uploadsWidth.clamp(140.0, maxW);
        return Row(
          children: [
            Expanded(child: files),
            MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) {
                  setState(() {
                    _uploadsWidth =
                        (_uploadsWidth - d.delta.dx).clamp(140.0, 620.0);
                  });
                },
                child: SizedBox(
                  width: 6,
                  child: Center(
                    child: Container(width: 1, color: p.borderSubtle),
                  ),
                ),
              ),
            ),
            SizedBox(width: w, child: _uploadsView(p)),
          ],
        );
      },
    );
  }

  Widget _filesBody(_P p) {
    if (_loading) {
      return Center(
        child: Text(context.l10n.sftpLoading,
            style: TextStyle(fontSize: 12, color: p.textMuted)),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: p.danger),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _reconnect,
                child: Text(
                  context.l10n.reconnect,
                  style: TextStyle(fontSize: 12, color: p.accent),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return Center(
        child: Text(context.l10n.sftpEmptyDir,
            style: TextStyle(fontSize: 12, color: p.textMuted)),
      );
    }
    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (context, i) {
        final e = _entries[i];
        final selected = _selected.contains(e.name);
        final bg = selected
            ? p.accent.withValues(alpha: 0.21)
            : (i.isOdd ? Colors.white.withValues(alpha: 0.03) : Colors.transparent);
        return _Row(
          p: p,
          entry: e,
          bg: bg,
          selected: selected,
          onTap: () => setState(() {
            if (!_selected.remove(e.name)) _selected.add(e.name);
          }),
          onDoubleTap: () => _open(e),
          onSecondary: (pos) => _contextMenu(pos, e),
        );
      },
    );
  }

  Future<void> _contextMenu(Offset pos, FileEntry e) async {
    final p = _P.of(context);
    final chosen = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        _menuItem(p, 'open', Icons.open_in_new, libL10n.open),
        _menuItem(p, 'rename', Icons.drive_file_rename_outline, libL10n.rename),
        _menuItem(p, 'delete', Icons.delete_outline, libL10n.delete),
        _menuItem(p, 'copy', Icons.content_copy, context.l10n.copyPath),
      ],
    );
    if (!mounted || chosen == null) return;
    switch (chosen) {
      case 'open':
        _open(e);
      case 'rename':
        await _rename(e);
      case 'delete':
        await _delete(e);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: _full(e)));
    }
  }

  PopupMenuItem<String> _menuItem(
      _P p, String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      height: 32,
      child: Row(
        children: [
          Icon(icon, size: 16, color: p.textSecondary),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(fontSize: 13, color: p.textPrimary)),
        ],
      ),
    );
  }

  // --- Directory tree (160px) ---------------------------------------------
  String _join(String base, String name) =>
      base.endsWith('/') ? '$base$name' : '$base/$name';

  Future<void> _loadTreeChildren(String path) async {
    final backend = _backend;
    if (backend == null) return;
    try {
      final entries = await backend.list(path);
      final dirs = entries.where((e) => e.isDir).toList()
        ..sort((a, b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() => _treeChildren[path] = dirs);
    } catch (_) {
      if (mounted) setState(() => _treeChildren[path] = const []);
    }
  }

  Future<void> _toggleTree(_TNode n) async {
    if (_expanded.contains(n.path)) {
      final prefix = n.path == '/' ? '/' : '${n.path}/';
      _expanded.removeWhere((p) => p == n.path || p.startsWith(prefix));
      setState(() {});
    } else {
      _expanded.add(n.path);
      setState(() {});
      if (!_treeChildren.containsKey(n.path)) await _loadTreeChildren(n.path);
    }
    unawaited(_list(n.path, reset: true));
  }

  List<_TNode> _buildTreeNodes() {
    final out = <_TNode>[];
    void walk(String path, String name, int depth) {
      final expanded = _expanded.contains(path);
      final kids = _treeChildren[path];
      final hasChildren =
          path == '/' ? true : (kids == null ? true : kids.isNotEmpty);
      out.add(_TNode(
        path: path,
        name: name,
        depth: depth,
        expanded: expanded,
        hasChildren: hasChildren,
      ));
      if (expanded && kids != null) {
        for (final k in kids) {
          walk(_join(path, k.name), k.name, depth + 1);
        }
      }
    }

    walk('/', '/', 0);
    return out;
  }

  Widget _tree(_P p) {
    final nodes = _buildTreeNodes();
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 20,
            color: p.bgRoot,
            padding: const EdgeInsets.only(left: 8),
            alignment: Alignment.centerLeft,
            child: Text(
              context.l10n.sftpDirectoryTree,
              style: TextStyle(fontSize: 11, color: p.textMuted),
            ),
          ),
          Container(height: 1, color: p.borderSubtle),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: nodes.length,
              itemBuilder: (context, i) {
                final n = nodes[i];
                return _TreeRow(
                  p: p,
                  node: n,
                  current: _path,
                  index: i,
                  onTap: () => _toggleTree(n),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- Status bar (18px) ---------------------------------------------------
  Widget _statusBar(_P p) {
    final sel = _selected.isEmpty
        ? ''
        : '   ${context.l10n.selected(_selected.length)}';
    final text = _error != null
        ? _error!
        : '$_path   ·   ${context.l10n.sftpItems(_entries.length)}$sel';
    return Container(
      height: 18,
      color: p.bgPanelAlt,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: p.textMuted),
      ),
    );
  }

  // --- helpers -----------------------------------------------------------
  Future<String?> _prompt(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(isDense: true),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(libL10n.cancel)),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(libL10n.ok),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<bool?> _confirm(String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(libL10n.cancel)),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(libL10n.delete)),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
  }
}

// --- One 24px row ----------------------------------------------------------
final class _Row extends StatelessWidget {
  final _P p;
  final FileEntry entry;
  final Color bg;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final void Function(Offset) onSecondary;

  const _Row({
    required this.p,
    required this.entry,
    required this.bg,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onSecondaryTapDown: (d) => onSecondary(d.globalPosition),
        child: Container(
          height: 24,
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: Center(
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: selected ? p.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: selected ? p.accent : p.borderSubtle,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check,
                            size: 10, color: Colors.white)
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Icon(_iconFor(e),
                        size: 14,
                        color: e.isDir ? p.accent : p.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: e.isDir ? p.accent : p.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  e.isDir ? '' : _fmtBytes(e.size),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: p.textSecondary),
                ),
              ),
              SizedBox(
                width: 116,
                child: Text(
                  _fmtDate(e.modified),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: p.textMuted),
                ),
              ),
              SizedBox(
                width: 104,
                child: Text(
                  e.modeStr ?? '--',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: p.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(FileEntry e) {
    if (e.isDir) return Icons.folder;
    if (e.linkTarget != null) return Icons.link;
    return Icons.insert_drive_file_outlined;
  }
}

// --- A flattened directory-tree node and its 22px row ---------------------
final class _TNode {
  final String path;
  final String name;
  final int depth;
  final bool expanded;
  final bool hasChildren;

  const _TNode({
    required this.path,
    required this.name,
    required this.depth,
    required this.expanded,
    required this.hasChildren,
  });
}

final class _TreeRow extends StatefulWidget {
  final _P p;
  final _TNode node;
  final String current;
  final int index;
  final VoidCallback onTap;

  const _TreeRow({
    required this.p,
    required this.node,
    required this.current,
    required this.index,
    required this.onTap,
  });

  @override
  State<_TreeRow> createState() => _TreeRowState();
}

class _TreeRowState extends State<_TreeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final n = widget.node;
    final isCurrent = n.path == widget.current;
    final bg = _hover
        ? p.bgHover
        : isCurrent
            ? p.accent.withValues(alpha: 0.19)
            : (widget.index.isOdd
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.transparent);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 22,
          color: bg,
          child: Row(
            children: [
              SizedBox(width: n.depth * 12.0),
              SizedBox(
                width: 14,
                child: Center(
                  child: Text(
                    n.hasChildren ? (n.expanded ? '▼' : '▶') : '',
                    style: TextStyle(fontSize: 9, color: p.textMuted),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  n.depth == 0 ? '/' : n.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isCurrent ? p.accent : p.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Hover square button ---------------------------------------------------
final class _HoverSquare extends StatefulWidget {
  final _P p;
  final Widget child;
  final VoidCallback? onTap;

  const _HoverSquare({required this.p, required this.child, this.onTap});

  @override
  State<_HoverSquare> createState() => _HoverSquareState();
}

class _HoverSquareState extends State<_HoverSquare> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 24,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? widget.p.bgHover : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// --- formatters ------------------------------------------------------------
String _fmtBytes(int? bytes) {
  if (bytes == null) return '--';
  const units = ['B', 'K', 'M', 'G', 'T', 'P'];
  var d = bytes.toDouble();
  var i = 0;
  while (d >= 1024 && i < units.length - 1) {
    d /= 1024;
    i++;
  }
  if (i == 0) return '${bytes}B';
  final s = d >= 100 ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
  return '$s${units[i]}';
}

String _fmtDate(DateTime? t) {
  if (t == null) return '--';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

enum _UploadStatus { uploading, done, failed }

/// One entry in the panel's upload record: how much of a picked file has
/// reached the far side, and how it ended.
class _UploadTask {
  _UploadTask({required this.name, required this.total});

  final String name;
  final int total;
  int sent = 0;
  _UploadStatus status = _UploadStatus.uploading;
  String? error;
  DateTime? finishedAt;

  /// Null while the size is unknown, which [LinearProgressIndicator] draws as
  /// indeterminate rather than as an empty bar.
  double? get fraction =>
      total <= 0 ? null : (sent / total).clamp(0.0, 1.0);
}

/// The upload record's stamp: `2026/2/5-22:53:35` — month and day unpadded, as
/// the row has little width to spare, and the time zero-padded.
String _fmtRecordTime(DateTime? t) {
  if (t == null) return '--';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}/${t.month}/${t.day}-${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
