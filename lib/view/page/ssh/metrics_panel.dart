import 'dart:async';

import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:server_box/core/extension/context/locale.dart';
import 'package:server_box/core/route.dart';
import 'package:server_box/data/model/app/scripts/cmd_types.dart';
import 'package:server_box/data/model/server/disk.dart';
import 'package:server_box/data/model/server/net_speed.dart';
import 'package:server_box/data/model/server/server.dart';
import 'package:server_box/data/model/server/server_private_info.dart';
import 'package:server_box/data/provider/server/all.dart';
import 'package:server_box/data/provider/server/single.dart';
import 'package:server_box/data/res/store.dart';
import 'package:server_box/view/page/process.dart';
import 'package:server_box/view/page/server/card/metric.dart';
import 'package:server_box/view/page/server/reading_text.dart';
import 'package:server_box/view/page/ssh/panel_style.dart';

/// The panel's background — the one chrome colour at the one chrome
/// transparency, shared with the rail, the top bar and the file browser. See
/// [PanelStyle].
Color _panelBg(BuildContext context) => PanelStyle.withOpacity(context);

/// meatshell's design tokens, transcribed from `ui/theme.slint` so the panel
/// looks like their sidebar rather than like this app's own surfaces. Both
/// palettes are theirs: dark charcoal, and the light one that is Apple's grays
/// with the same blue accent.
final class _Ms {
  final Color bgRoot, bgPanel, bgElevated, bgHover, borderSubtle;
  final Color textPrimary, textSecondary, textMuted;
  final Color accent, success, warning, danger;

  const _Ms({
    required this.bgRoot,
    required this.bgPanel,
    required this.bgElevated,
    required this.bgHover,
    required this.borderSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
  });

  static const dark = _Ms(
    bgRoot: Color(0xFF1b1d23),
    bgPanel: Color(0xFF23262d),
    bgElevated: Color(0xFF30333c),
    bgHover: Color(0xFF373a44),
    borderSubtle: Color(0xFF3a3d46),
    textPrimary: Color(0xFFe6e8ee),
    textSecondary: Color(0xFFb4b9c4),
    textMuted: Color(0xFF9196a3),
    accent: Color(0xFF4a90e2),
    success: Color(0xFF4ec9b0),
    warning: Color(0xFFe2a84a),
    danger: Color(0xFFe25c5c),
  );

  static const light = _Ms(
    bgRoot: Color(0xFFf5f5f7),
    bgPanel: Color(0xFFFFFFFF),
    bgElevated: Color(0xFFe8e8ed),
    bgHover: Color(0xFFe0e0e6),
    borderSubtle: Color(0xFFe2e2e8),
    textPrimary: Color(0xFF1d1d1f),
    textSecondary: Color(0xFF45454a),
    textMuted: Color(0xFF606066),
    accent: Color(0xFF0071e3),
    success: Color(0xFF34c759),
    warning: Color(0xFFFF9F0A),
    danger: Color(0xFFFF3B30),
  );

  /// This palette with the whole-page accent and text colours folded in, so
  /// one setting recolours the readings panel and the network sparklines.
  _Ms recolor({Color? accent, Color? text}) {
    if (accent == null && text == null) return this;
    return _Ms(
      bgRoot: bgRoot,
      bgPanel: bgPanel,
      bgElevated: bgElevated,
      bgHover: bgHover,
      borderSubtle: borderSubtle,
      textPrimary: text ?? textPrimary,
      textSecondary: text == null
          ? textSecondary
          : Color.alphaBlend(text.withValues(alpha: 0.8), bgPanel),
      textMuted: text == null
          ? textMuted
          : Color.alphaBlend(text.withValues(alpha: 0.6), bgPanel),
      accent: accent ?? this.accent,
      success: success,
      warning: warning,
      danger: danger,
    );
  }

  static _Ms of(BuildContext c) {
    final base =
        Theme.of(c).brightness == Brightness.dark ? dark : light;
    return base.recolor(
      accent: PanelStyle.accentOverride(),
      text: PanelStyle.textOverride(),
    );
  }
}

/// A server's readings down the right of its terminal, transcribed from
/// meatshell's `Sidebar` (`ui/sidebar.slint`): a status header with the host to
/// copy, a "Local resources" block of CPU / memory / swap bars, dual network
/// graphs, then the per-filesystem disk list and a version line.
///
/// Fixed and quiet on purpose. Unlike the bottom `TerminalMetricsBar` it does
/// not move with the terminal, so a keystroke cannot make it jump — it is
/// painted once per poll and nothing else touches it. Nothing for a server
/// that is gone, which is a tab restored after its server was deleted.
final class TerminalMetricsPanel extends ConsumerWidget {
  final String serverId;
  final VoidCallback? onCollapse;

  const TerminalMetricsPanel({
    super.key,
    required this.serverId,
    this.onCollapse,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final present = ref.watch(
      serversProvider.select((s) => s.servers.containsKey(serverId)),
    );
    if (!present) return const SizedBox.shrink();
    final srv = ref.watch(serverProvider(serverId));

    // This device's own network: the local server the user added ("this
    // device" in the intro) has a generated id, not LocalDevice.id, so it is
    // found by `Spi.local` rather than by a fixed one. Guarded, so a window
    // without a local server shows a hint instead of watching nothing.
    ServerMetric? localNet;
    NetSpeed? localNs;
    final localId = ref.watch(
      serversProvider.select((s) {
        for (final e in s.servers.values) {
          if (e.local) return e.id;
        }
        return null;
      }),
    );
    if (localId != null && localId != serverId) {
      final local = ref.watch(serverProvider(localId));
      localNs = local.status.netSpeed;
      localNet = serverCardReadings(local)
          .all
          .firstWhereOrNull((m) => m.kind == ServerMetricKind.netSpeed);
    } else if (localId == serverId) {
      // The panel is the local server itself: its own network is the server
      // network above, and a second graph would say the same thing twice.
      localNs = srv.status.netSpeed;
    }

    // Repaint at once when the whole-page accent or text colour changes, not
    // only on the next status poll.
    return ListenableBuilder(
      listenable: Listenable.merge([
        Stores.setting.uiAccentColor.listenable(),
        Stores.setting.uiTextColor.listenable(),
      ]),
      builder: (context, _) => _PanelBody(
        srv: srv,
        onCollapse: onCollapse,
        localNet: localNet,
        localNs: localNs,
      ),
    );
  }
}

/// The thin bar a collapsed panel leaves behind, so it can be opened again from
/// the edge it sits on (`DockExpandButton` in meatshell's `widgets.slint`).
final class TerminalMetricsStrip extends StatelessWidget {
  final VoidCallback onExpand;

  const TerminalMetricsStrip({super.key, required this.onExpand});

  @override
  Widget build(BuildContext context) {
    final p = _Ms.of(context);
    return GestureDetector(
      onTap: onExpand,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          color: _panelBg(context),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            width: 20,
            height: 22,
            decoration: BoxDecoration(
              color: p.bgElevated,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: p.borderSubtle),
            ),
            child: Icon(
              Icons.chevron_left,
              size: 16,
              color: p.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

final class _PanelBody extends StatelessWidget {
  final ServerState srv;
  final VoidCallback? onCollapse;
  final ServerMetric? localNet;
  final NetSpeed? localNs;

  const _PanelBody({
    required this.srv,
    this.onCollapse,
    this.localNet,
    this.localNs,
  });

  @override
  Widget build(BuildContext context) {
    final p = _Ms.of(context);
    final all = serverCardReadings(srv).all;
    ServerMetric? pick(ServerMetricKind k) =>
        all.firstWhereOrNull((m) => m.kind == k);
    final net = pick(ServerMetricKind.netSpeed);

    return Container(
      width: 275,
      color: _panelBg(context),
      padding: const EdgeInsets.all(10),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _panelBg(context),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: p.borderSubtle),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusBlock(srv: srv, p: p, onCollapse: onCollapse),
            _divider(p),
            _StatsBlock(srv: srv, p: p, pick: pick),
            _divider(p),
            _NetBlock(
              net: net,
              ns: srv.status.netSpeed,
              localNet: localNet,
              localNs: localNs,
              p: p,
            ),
            _divider(p),
            _InfoBlock(srv: srv, p: p),
            _divider(p),
            Expanded(child: _DiskBlock(disks: srv.status.disk, p: p)),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'LBox',
                style: TextStyle(fontSize: 11, color: p.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(_Ms p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Container(height: 1, color: p.borderSubtle),
      );
}

// --- Connection / system facts + hardware summary, ported from the detail page
final class _InfoBlock extends StatelessWidget {
  final ServerState srv;
  final _Ms p;

  const _InfoBlock({required this.srv, required this.p});

  @override
  Widget build(BuildContext context) {
    final ss = srv.status;
    final more = ss.more;
    String pick(StatusCmdType t) {
      final v = more[t];
      return (v == null || v.trim().isEmpty) ? '--' : v.trim();
    }

    final rows = <(String, String)>[
      (libL10n.conn, _connectionLabel()),
      (libL10n.system, pick(StatusCmdType.sys)),
      (libL10n.host, pick(StatusCmdType.host)),
      (libL10n.uptime, pick(StatusCmdType.uptime)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    k,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: p.textMuted),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    v,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: p.textPrimary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// How the app reaches this machine, plus the round trip when one was timed.
  String _connectionLabel() {
    final name = switch (srv.spi.transport) {
      ServerTransport.monitorHttp => 'Monitor',
      ServerTransport.ssh => 'SSH',
      ServerTransport.local => 'Local',
    };
    final latency = srv.latencyMs;
    return latency == null ? name : '$name · ${latency}ms';
  }
}

// --- Status header (dot + "Status" + collapse; host click-to-copy) ----------
final class _StatusBlock extends StatefulWidget {
  final ServerState srv;
  final _Ms p;
  final VoidCallback? onCollapse;

  const _StatusBlock({required this.srv, required this.p, this.onCollapse});

  @override
  State<_StatusBlock> createState() => _StatusBlockState();
}

class _StatusBlockState extends State<_StatusBlock> {
  bool _copied = false;

  Color _connColor() {
    switch (widget.srv.conn) {
      case ServerConn.finished:
        return widget.p.success;
      case ServerConn.failed:
        return widget.p.danger;
      case ServerConn.connecting:
      case ServerConn.connected:
      case ServerConn.loading:
        return widget.p.warning;
      case ServerConn.disconnected:
        return widget.p.textMuted;
    }
  }

  Future<void> _copy() async {
    final host = widget.srv.spi.displayAddr;
    await Clipboard.setData(ClipboardData(text: host));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _connColor(),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              l10n.status,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: p.textPrimary,
              ),
            ),
            const Spacer(),
            _HoverIcon(
              icon: Icons.chevron_right,
              size: 14,
              color: p.textSecondary,
              hoverColor: p.bgHover,
              onTap: widget.onCollapse,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            // Masked by default — a screenshot or a shared desktop should not
            // hand out the address. The copy button beside it hands over the
            // real one.
            Text(
              _maskAddr(widget.srv.spi.displayAddr),
              style: TextStyle(fontSize: 12, color: p.textSecondary),
            ),
            const SizedBox(width: 4),
            _HoverIcon(
              icon: Icons.copy,
              size: 12,
              color: p.textSecondary,
              hoverColor: p.bgHover,
              onTap: _copy,
            ),
            if (_copied) ...[
              const SizedBox(width: 6),
              Text(
                l10n.copied,
                style: TextStyle(fontSize: 12, color: p.success),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// `user@host:port` with the host's middle hidden: `root@8.***.**.205:22`.
/// IPv4 keeps its first and last octet; anything else keeps its ends.
String _maskAddr(String addr) {
  final at = addr.indexOf('@');
  final user = at >= 0 ? addr.substring(0, at + 1) : '';
  final rest = at >= 0 ? addr.substring(at + 1) : addr;
  final colon = rest.lastIndexOf(':');
  final host = colon >= 0 ? rest.substring(0, colon) : rest;
  final port = colon >= 0 ? rest.substring(colon) : '';
  return '$user${_maskHost(host)}$port';
}

String _maskHost(String host) {
  final parts = host.split('.');
  if (parts.length == 4) {
    return '${parts[0]}.***.**.${parts[3]}';
  }
  if (host.length <= 4) return '***';
  return '${host.substring(0, 1)}***${host.substring(host.length - 1)}';
}

// --- "Local resources" + CPU / Memory / Swap bars -------------------------
final class _StatsBlock extends StatelessWidget {
  final ServerState srv;
  final _Ms p;
  final ServerMetric? Function(ServerMetricKind) pick;

  const _StatsBlock({required this.srv, required this.p, required this.pick});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cpu = pick(ServerMetricKind.cpu);
    final mem = pick(ServerMetricKind.mem);
    final swap = pick(ServerMetricKind.swap);
    final cores = srv.status.cpu.coresCount;
    final memTotal = srv.status.mem.total;
    final swapTotal = srv.status.swap.total;
    final disk = srv.status.diskUsage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.localResources,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
            ),
            _HoverIcon(
              icon: Icons.info_outline,
              size: 14,
              color: p.textSecondary,
              hoverColor: p.bgHover,
              onTap: () => _showInfo(context),
            ),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: () => _openProcesses(context),
              child: Container(
                height: 20,
                width: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.bgElevated,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  l10n.processes,
                  style: TextStyle(fontSize: 11, color: p.textSecondary),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Each bar carries the total it is a share of, so the hardware figures
        // live here rather than repeated in a block of their own below.
        _StatRow(
          label: 'CPU',
          metric: cpu,
          detail: cores > 0 ? '×$cores' : '',
          barColor: p.accent,
          p: p,
        ),
        const SizedBox(height: 6),
        _StatRow(
          label: libL10n.memory,
          metric: mem,
          detail: memTotal > 0 ? (memTotal * 1024).bytes2Str : '',
          barColor: p.success,
          p: p,
        ),
        const SizedBox(height: 6),
        _StatRow(
          label: l10n.swap,
          metric: swap,
          detail: swapTotal > 0 ? (swapTotal * 1024).bytes2Str : '',
          barColor: p.warning,
          p: p,
        ),
        const SizedBox(height: 6),
        // The disk as one bar, under memory and swap: the per-mount list below
        // is the detail; this is the share in the same shape as the two above.
        _StatRow(
          label: libL10n.disk,
          metric: null,
          percent: (disk?.usedPercent ?? 0) / 100,
          detail: disk != null ? disk.size.kb2Str : '',
          barColor: p.accent,
          p: p,
        ),
      ],
    );
  }

  /// The server's process list, the same page the server card opens.
  void _openProcesses(BuildContext context) {
    unawaited(ProcessPage.route.go(context, SpiRequiredArgs(srv.spi)));
  }

  /// Everything the status poll learned that the bars do not show — the
  /// machine's own addresses and each `more` command's line, under its label.
  Future<void> _showInfo(BuildContext context) async {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);
    final valueStyle = TextStyle(fontSize: 11, color: scheme.onSurface);
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 84, child: Text(k, style: labelStyle)),
          Expanded(child: SelectableText(v, style: valueStyle)),
        ],
      ),
    );
    final rows = <Widget>[];
    if (srv.status.ips.isNotEmpty) {
      rows.add(row(l10n.ipAddress, srv.status.ips.join(', ')));
    }
    for (final e in srv.status.more.entries) {
      if (e.value.trim().isEmpty) continue;
      rows.add(row(e.key.i18n, e.value));
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(srv.spi.displayAddr),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: rows.isEmpty ? [Text(libL10n.empty)] : rows,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(libL10n.close),
          ),
        ],
      ),
    );
  }
}

final class _StatRow extends StatelessWidget {
  final String label;
  final ServerMetric? metric;
  final String detail;
  final Color barColor;
  final _Ms p;

  /// Overrides [metric]'s percent for rows that have a usage share but no
  /// [ServerMetric] of their own — the disk total, summed across mounts.
  final double? percent;

  const _StatRow({
    required this.label,
    required this.metric,
    required this.detail,
    required this.barColor,
    required this.p,
    this.percent,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (percent ?? metric?.percent ?? 0).clamp(0.0, 1.0).toDouble();
    final pctText = '${(pct * 100).round()}%';
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          const SizedBox(width: 4),
          SizedBox(
            width: 36,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: p.textSecondary),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                height: 6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: p.bgRoot),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: pct,
                        child: ColoredBox(color: barColor),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 34,
            child: Text(
              pctText,
              textAlign: TextAlign.right,
              maxLines: 1,
              style: TextStyle(fontSize: 11, color: p.textPrimary),
            ),
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 52),
            child: Text(
              detail,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: p.textMuted),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// --- Network graphs (server + local, each ↑/↓ + NIC selector + sparkline) --
final class _NetBlock extends StatefulWidget {
  final ServerMetric? net;
  final NetSpeed? ns;
  final ServerMetric? localNet;
  final NetSpeed? localNs;
  final _Ms p;

  const _NetBlock({
    required this.net,
    required this.ns,
    required this.p,
    this.localNet,
    this.localNs,
  });

  @override
  State<_NetBlock> createState() => _NetBlockState();
}

class _NetBlockState extends State<_NetBlock> {
  String? _iface;

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final ns = widget.ns;
    final samples = widget.net?.samples ?? const <double?>[];
    final ifaces = ns?.ifaces ?? const <String>[];
    final sel = _iface ?? (ifaces.isEmpty ? '' : ifaces.first);
    final up = ns == null ? '--' : ReadingFmt.rate(ns.speedOutBytesOf(device: _iface));
    final down =
        ns == null ? '--' : ReadingFmt.rate(ns.speedInBytesOf(device: _iface));
    final localNs = widget.localNs;
    final localSamples = widget.localNet?.samples ?? const <double?>[];
    final localUp = localNs == null
        ? '--'
        : ReadingFmt.rate(localNs.speedOutBytesOf());
    final localDown = localNs == null
        ? '--'
        : ReadingFmt.rate(localNs.speedInBytesOf());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NetGraph(
          upText: up,
          downText: down,
          samples: samples,
          p: p,
          showSelector: ifaces.isNotEmpty,
          ifaces: ifaces,
          selected: sel,
          onSelect: (v) => setState(() => _iface = v),
        ),
        const SizedBox(height: 6),
        Text(
          libL10n.local,
          style: TextStyle(fontSize: 11, color: p.textMuted),
        ),
        const SizedBox(height: 3),
        if (widget.localNs == null && widget.localNet == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              context.l10n.localNotAdded,
              style: TextStyle(fontSize: 11, color: p.textMuted),
            ),
          )
        else
          _NetGraph(
            upText: localUp,
            downText: localDown,
            samples: localSamples,
            p: p,
          ),
      ],
    );
  }
}

final class _NetGraph extends StatelessWidget {
  final String upText;
  final String downText;
  final List<double?> samples;
  final _Ms p;
  final bool showSelector;
  final List<String> ifaces;
  final String selected;
  final ValueChanged<String>? onSelect;

  const _NetGraph({
    required this.upText,
    required this.downText,
    required this.samples,
    required this.p,
    this.showSelector = false,
    this.ifaces = const [],
    this.selected = '',
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.arrow_upward, size: 12, color: p.success),
            const SizedBox(width: 3),
            Text(
              upText,
              style: TextStyle(fontSize: 11, color: p.textSecondary),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_downward, size: 12, color: p.accent),
            const SizedBox(width: 3),
            Text(
              downText,
              style: TextStyle(fontSize: 11, color: p.textSecondary),
            ),
            const Spacer(),
            if (showSelector)
              _IfSelector(
                p: p,
                ifaces: ifaces,
                selected: selected,
                onSelect: onSelect,
              ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 48,
            color: p.bgRoot,
            child: CustomPaint(
              painter: _BarsPainter(samples: samples, color: p.accent),
            ),
          ),
        ),
      ],
    );
  }
}

final class _IfSelector extends StatelessWidget {
  final _Ms p;
  final List<String> ifaces;
  final String selected;
  final ValueChanged<String>? onSelect;

  const _IfSelector({
    required this.p,
    required this.ifaces,
    required this.selected,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '',
      padding: EdgeInsets.zero,
      onSelected: onSelect,
      itemBuilder: (context) => [
        for (final i in ifaces)
          PopupMenuItem<String>(
            value: i,
            height: 30,
            child: Text(
              i,
              style: TextStyle(fontSize: 11, color: p.textPrimary),
            ),
          ),
      ],
      child: Container(
        width: 64,
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: p.bgElevated,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: p.textPrimary),
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 12, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}

/// A bar-chart sparkline, as meatshell's `Sparkline` draws it: one bar per
/// sample, scaled to the window's own maximum, a missing sample a gap.
final class _BarsPainter extends CustomPainter {
  final List<double?> samples;
  final Color color;

  const _BarsPainter({required this.samples, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final n = samples.length;
    if (n == 0 || size.width <= 0 || size.height <= 0) return;
    double? hi;
    for (final s in samples) {
      if (s == null) continue;
      hi = hi == null ? s : (s > hi ? s : hi);
    }
    final maxV = (hi == null || hi.abs() < 1e-9) ? 1.0 : hi;
    final bw = size.width / n;
    final paint = Paint()..color = color.withValues(alpha: 0.85);
    for (var i = 0; i < n; i++) {
      final s = samples[i];
      if (s == null) continue;
      final h = size.height * (s / maxV).clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTWH(i * bw, size.height - h, (bw - 1).clamp(0.5, bw), h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.color != color || old.samples != samples;
}

// --- Disk list (Path / Free-Total, fill by usage) -------------------------
final class _DiskBlock extends StatelessWidget {
  final List<Disk> disks;
  final _Ms p;

  const _DiskBlock({required this.disks, required this.p});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  libL10n.path,
                  style: TextStyle(fontSize: 11, color: p.textMuted),
                ),
              ),
              Text(
                context.l10n.freeTotal,
                style: TextStyle(fontSize: 11, color: p.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: disks.length,
            itemBuilder: (context, i) {
              final d = disks[i];
              final pct = (d.usedPercent / 100).clamp(0.0, 1.0).toDouble();
              final fill = pct > 0.9
                  ? p.danger.withValues(alpha: 0.32)
                  : pct > 0.75
                      ? p.warning.withValues(alpha: 0.30)
                      : p.accent.withValues(alpha: 0.22);
              final path = d.mount.isNotEmpty ? d.mount : d.path;
              return Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Tooltip(
                  message: path,
                  waitDuration: const Duration(milliseconds: 400),
                  child: Container(
                    height: 20,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: pct,
                          child: ColoredBox(color: fill),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  path,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: p.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${_fmtBytes(d.avail)}/${_fmtBytes(d.size)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: p.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// --- small shared bits -----------------------------------------------------
final class _HoverIcon extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color color;
  final Color hoverColor;
  final VoidCallback? onTap;

  const _HoverIcon({
    required this.icon,
    required this.size,
    required this.color,
    required this.hoverColor,
    this.onTap,
  });

  @override
  State<_HoverIcon> createState() => _HoverIconState();
}

class _HoverIconState extends State<_HoverIcon> {
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
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? widget.hoverColor : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(widget.icon, size: widget.size, color: widget.color),
        ),
      ),
    );
  }
}

String _fmtBytes(BigInt v) {
  const units = ['B', 'K', 'M', 'G', 'T', 'P'];
  var d = v.toDouble();
  var i = 0;
  while (d >= 1024 && i < units.length - 1) {
    d /= 1024;
    i++;
  }
  if (i == 0) return '${v}B';
  final s = d >= 100 ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
  return '$s${units[i]}';
}
