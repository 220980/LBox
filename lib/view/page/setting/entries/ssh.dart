part of '../entry.dart';

extension _SSH on _AppSettingsPageState {
  void _refreshApp({bool closeDialog = false}) {
    if (closeDialog && mounted) {
      context.popDialog();
    }
    RNodes.app.notify();
  }

  List<SettingsGroup> _buildSSH() {
    return [
      SettingsGroup(libL10n.general, [
        if (isDesktop) _buildSSHConfigImport(),
        _buildLetterCache(),
        _buildSSHWakeLock(),
        _buildSSHVirtualKeyAutoOff(),
        _buildProgramStatusAlerts(),
        _buildTermMetricsBar(),
        _buildTermSideMetrics(),
        _buildTermFilePanel(),
        _buildHostCertAuthorities(),
        _buildRememberKeyPassphrase(),
      ]),
      SettingsGroup(libL10n.theme, [
        _buildTermTheme(),
        _buildFont(),
        _buildTermFontSize(),
        _buildTermLineHeight(),
        _buildTermBgColor(),
        _buildTermFgColor(),
        _buildBarColor(),
        _buildFilePanelOpacity(),
        _buildUiAccentColor(),
        _buildUiTextColor(),
      ]),
      // Three rows about one picture, which is what the tile they were folded
      // into was for.
      SettingsGroup(libL10n.background, [
        _buildSshBgImage(),
        _buildSshBgOpacity(),
        _buildSshBlurRadius(),
      ]),
      SettingsGroup(l10n.tmuxAutoAttach, [
        _buildTmuxAutoToggle(),
        _buildTmuxShowSelector(),
        _buildTmuxSessionName(),
      ]),
    ];
  }

  SettingsRow _buildSSHConfigImport() {
    final label = l10n.sshConfigImport;
    return SettingsRow(
      label,
      () => ListTile(
        leading: const Icon(MingCute.file_import_line),
        title: Text(label),
        trailing: const Icon(Icons.keyboard_arrow_right),
        onTap: _onTapSSHConfigImport,
      ),
    );
  }

  // Scanning a shared code used to be a row here, mobile-only and under SSH
  // *preferences*, while importing the same server from a file was under
  // Backup. Both are ways of acquiring a server, and which one a person needs
  // depends on what the sender picked — so they now sit together behind the
  // server list's add button. See `_onTapAddServer`.

  Future<void> _onTapSSHConfigImport() async {
    try {
      final servers = await SSHConfig.parseConfig();
      if (!mounted) return;
      if (servers.isEmpty) {
        Toast.show(l10n.sshConfigNoServers);
        return;
      }

      await _processSSHServers(servers);
    } catch (e, s) {
      if (!mounted) return;
      await _handleImportSSHCfgPermissionIssue(e, s);
    }
  }

  Future<void> _processSSHServers(List<Spi> servers) async {
    final existing = Stores.server.fetch();
    final deduplicated = ServerDeduplication.deduplicateServers(
      servers,
      existingServers: existing,
    );
    final resolved = ServerDeduplication.resolveNameConflicts(
      deduplicated,
      existingServers: existing,
    );
    final summary = ServerDeduplication.getImportSummary(servers, resolved);

    if (!summary.hasItemsToImport) {
      if (!mounted) return;
      Toast.show(l10n.sshConfigAllExist(summary.duplicates));
      return;
    }

    final shouldImport = await context.showRoundDialog<bool>(
      title: l10n.sshConfigImport,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.sshConfigFoundServers(summary.total)),
            if (summary.hasDuplicates)
              Text(
                l10n.sshConfigDuplicatesSkipped(summary.duplicates),
                style: UIs.textGrey,
              ),
            Text(l10n.sshConfigServersToImport(summary.toImport)),
            const SizedBox(height: 16),
            ...resolved.map((s) => Text('• ${s.name} (${s.displayAddr})')),
          ],
        ),
      ),
      actions: Btnx.cancelOk,
    );

    if (!mounted) return;

    if (shouldImport == true) {
      await ServerDeduplication.importServersWithNotification(
        ref: ref,
        context: context,
        resolvedServers: resolved,
        originalCount: summary.total,
        allExistMessage: l10n.sshConfigAllExist,
        importedMessage: l10n.sshConfigImported,
      );
    }
  }

  Future<void> _handleImportSSHCfgPermissionIssue(
    Object e,
    StackTrace s,
  ) async {
    dprint('Error importing SSH config: $e');
    if (e is PathAccessException ||
        e.toString().contains('Operation not permitted')) {
      final useFilePicker = await context.showRoundDialog<bool>(
        title: l10n.sshConfigImport,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.sshConfigPermissionDenied),
            const SizedBox(height: 8),
            Text(l10n.sshConfigManualSelect),
          ],
        ),
        actions: Btnx.cancelOk,
      );

      if (!mounted) return;

      if (useFilePicker == true) {
        await _onTapSSHImportWithFilePicker();
      }
    } else {
      if (!mounted) return;
      context.showErrDialog(e, s);
    }
  }

  Future<void> _onTapSSHImportWithFilePicker() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.any,
        dialogTitle: l10n.sshConfigImport,
      );

      if (!mounted) return;

      if (picked?.path case final path?) {
        final servers = await SSHConfig.parseConfig(path);
        if (!mounted) return;
        if (servers.isEmpty) {
          Toast.show(l10n.sshConfigNoServers);
          return;
        }

        await _processSSHServers(servers);
      }
    } catch (e, s) {
      if (!mounted) return;
      context.showErrDialog(e, s);
    }
  }

  SettingsRow _buildSSHVirtualKeyAutoOff() {
    final label = l10n.sshVirtualKeyAutoOff;
    return SettingsRow(
      label,
      () => ListTile(
        leading: const Icon(MingCute.hotkey_fill),
        title: Text(label),
        subtitle: const Text('Ctrl & Alt', style: UIs.textGrey),
        trailing: StoreSwitch(prop: _setting.sshVirtualKeyAutoOff),
      ),
      keywords: 'Ctrl Alt',
    );
  }

  SettingsRow _buildFont() {
    final label = libL10n.font;
    return SettingsRow(
      label,
      () => ListTile(
        leading: const Icon(MingCute.font_fill),
        title: TipText(label, l10n.termFontTip),
        // Which font is in use: the system's when none is chosen, and a chosen
        // one that did not load says so instead of looking as if it applied.
        trailing: ListenableBuilder(
          listenable: Listenable.merge([
            _setting.fontPath.listenable(),
            TerminalFont.failed,
          ]),
          builder: (_, _) {
            final fontName = _setting.fontPath.fetch().getFileName(
              withoutExtension: true,
            );
            if (fontName == null) {
              return Text(libL10n.system, style: UIs.text15);
            }
            if (TerminalFont.failed.value) {
              return Text(
                '$fontName · ${libL10n.fail}',
                style: UIs.text15.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              );
            }
            return Text(fontName, style: UIs.text15);
          },
        ),
        onTap: () {
          context.showRoundDialog(
            title: label,
            actions: [
              TextButton(
                onPressed: () async => await _pickFontFile(),
                child: Text(libL10n.file),
              ),
              TextButton(
                onPressed: () async {
                  await _clearCachedFont();
                  _setting.fontPath.delete();
                  await TerminalFont.load('');
                  _refreshApp(closeDialog: true);
                },
                child: Text(libL10n.clear),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _clearCachedFont() async {
    final oldFontPath = _setting.fontPath.fetch();
    if (oldFontPath.isEmpty || !oldFontPath.startsWith(Paths.font)) return;
    final oldFile = File(oldFontPath);
    if (await oldFile.exists()) {
      await oldFile.delete();
    }
  }

  Future<void> _pickFontFile() async {
    final path = await Pfs.pickFilePath();
    if (path == null) return;

    // The iOS file picker grants access to the selected file in place, so keep
    // its original path instead of copying it into the app directory.
    if (isIOS) {
      _setting.fontPath.put(path);
      await TerminalFont.load(path);
    } else {
      final fontName = path.getFileName();
      final fontPath = Paths.font.joinPath(fontName ?? 'font.ttf');
      // Copied beside the target and renamed over it only once whole: a file
      // that cannot be read now leaves the font that was working — even one
      // of the same name — and says why.
      final part = File('$fontPath.part');
      try {
        await File(path).copy(part.path);
        await part.rename(fontPath);
      } catch (e, s) {
        if (await part.exists()) await part.delete();
        if (mounted) context.showErrDialog(e, s, libL10n.font);
        return;
      }
      if (_setting.fontPath.fetch() != fontPath) await _clearCachedFont();
      _setting.fontPath.put(fontPath);
      await TerminalFont.load(fontPath);
    }

    _refreshApp(closeDialog: true);
  }

  SettingsRow _buildTermFontSize() {
    final label = libL10n.fontSize;
    return SettingsRow(
      label,
      () => ListTile(
        leading: const Icon(MingCute.font_size_line),
        title: TipText(label, l10n.termFontSizeTip),
        trailing: ValBuilder(
          listenable: _setting.termFontSize.listenable(),
          builder: (val) => Text(val.toString(), style: UIs.text15),
        ),
        onTap: () => _showFontSizeDialog(_setting.termFontSize),
      ),
      keywords: l10n.termFontSizeTip,
    );
  }

  SettingsRow _buildTermLineHeight() {
    final label = l10n.termLineHeight;
    final ctrl = TextEditingController(
      text: _setting.termLineHeight.fetch().toString(),
    );
    void onSave() {
      final val = double.tryParse(ctrl.text);
      if (val == null) {
        Toast.error('${libL10n.invalid}: ${ctrl.text}');
        return;
      }
      _setting.termLineHeight.put(
        val.clamp(TerminalLook.minLineHeight, TerminalLook.maxLineHeight),
      );
      context.popDialog();
    }

    return SettingsRow(
      label,
      () => ListTile(
        leading: const Icon(Icons.format_line_spacing),
        title: TipText(label, l10n.termLineHeightTip),
        trailing: ValBuilder(
          listenable: _setting.termLineHeight.listenable(),
          builder: (val) => Text(val.toString(), style: UIs.text15),
        ),
        onTap: () {
          ctrl.text = _setting.termLineHeight.fetch().toString();
          context.showRoundDialog(
            title: label,
            child: Input(
              controller: ctrl,
              autoFocus: true,
              type: const TextInputType.numberWithOptions(decimal: true),
              hint: '1.2',
              icon: Icons.format_line_spacing,
              suggestion: false,
              onSubmitted: (_) => onSave(),
            ),
            actions: Btn.ok(onTap: onSave).toList,
          );
        },
      ),
      keywords: l10n.termLineHeightTip,
    );
  }

  Future<void> _pickBgImage() async {
    final path = await Pfs.pickFilePath();
    if (path == null) return;

    final file = File(path);
    final extIndex = path.lastIndexOf('.');
    final ext = extIndex != -1 ? path.substring(extIndex) : '';
    // A new name for each picture: one path for every picture leaves the
    // terminal page and Flutter's image cache drawing the one before.
    final newPath = Paths.img.joinPath('ssh_bg_${DateTime.now().millisecondsSinceEpoch}$ext');
    await file.copy(newPath);
    final old = _setting.sshBgImage.fetch();
    _setting.sshBgImage.put(newPath);
    await _deleteBgImage(old);

    _refreshApp(closeDialog: true);
  }

  /// The copy [_pickBgImage] made at [path]; never a file of the user's own.
  Future<void> _deleteBgImage(String path) async {
    if (path.isEmpty || !path.startsWith(Paths.img)) return;
    try {
      await File(path).delete();
    } catch (_) {}
  }

  SettingsRow _buildTermTheme() {
    String index2Str(int index) {
      switch (index) {
        case 0:
          return libL10n.auto;
        case 1:
          return libL10n.bright;
        case 2:
          return libL10n.dark;
        default:
          return libL10n.error;
      }
    }

    return SettingsRow(
      libL10n.theme,
      () => ListTile(
        leading: const Icon(MingCute.moon_stars_fill),
        title: Text(libL10n.theme),
        trailing: ValBuilder(
          listenable: _setting.termTheme.listenable(),
          builder: (val) => Text(index2Str(val), style: UIs.text15),
        ),
        onTap: () async {
          final selected = await context.showPickSingleDialog(
            title: libL10n.theme,
            items: List.generate(3, (index) => index),
            display: (p0) => index2Str(p0),
            initial: _setting.termTheme.fetch(),
          );
          if (selected != null) {
            _setting.termTheme.put(selected);
          }
        },
      ),
    );
  }

  SettingsRow _buildSSHWakeLock() {
    final label = l10n.wakeLock;
    return SettingsRow(
      label,
      () => ListTile(
        leading: const Icon(MingCute.lock_fill),
        title: Text(label),
        trailing: StoreSwitch(prop: _setting.sshWakeLock),
      ),
    );
  }

  SettingsRow _buildRememberKeyPassphrase() {
    final label = l10n.rememberKeyPassphrase;
    return SettingsRow(
      label,
      () => ListTile(
        leading: const Icon(Icons.key),
        title: TipText(label, l10n.rememberKeyPassphraseTip),
        trailing: StoreSwitch(
          prop: _setting.rememberKeyPassphrase,
          // Off means none kept, not merely none added from now on. Off
          // before clearing, so no write queued behind the clear keeps one.
          callback: (on) async {
            if (on) return;
            _setting.rememberKeyPassphrase.put(false);
            await KeyPassphrases.clear();
          },
        ),
      ),
    );
  }

  SettingsRow _buildProgramStatusAlerts() {
    final label = l10n.programStatusAlerts;
    return SettingsRow(
      label,
      () => ListTile(
        leading: const Icon(MingCute.notification_line),
        title: TipText(label, l10n.programStatusAlertsTip),
        trailing: StoreSwitch(prop: _setting.programStatusAlerts),
      ),
      keywords: l10n.programStatusAlertsTip,
    );
  }

  SettingsRow _buildTermMetricsBar() {
    final label = l10n.termMetricsBar;
    return SettingsRow(
      label,
      () => ListTile(
        leading: const Icon(Icons.speed_outlined),
        title: TipText(label, l10n.termMetricsBarTip),
        trailing: StoreSwitch(prop: _setting.termMetricsBar),
      ),
      keywords: l10n.termMetricsBarTip,
    );
  }

  SettingsRow _buildTermSideMetrics() {
    final label = l10n.termSideMetrics;
    return SettingsRow(
      label,
      () => ListTile(
        leading: const Icon(Icons.view_sidebar_outlined),
        title: TipText(label, l10n.termSideMetricsTip),
        trailing: StoreSwitch(prop: _setting.termSideMetrics),
      ),
      keywords: l10n.termSideMetricsTip,
    );
  }

  SettingsRow _buildTermFilePanel() {
    final label = l10n.termFilePanel;
    return SettingsRow(
      label,
      () => ListTile(
        leading: const Icon(Icons.folder_copy_outlined),
        title: TipText(label, l10n.termFilePanelTip),
        trailing: StoreSwitch(prop: _setting.termFilePanel),
      ),
      keywords: l10n.termFilePanelTip,
    );
  }

  SettingsRow _buildLetterCache() {
    final label = l10n.letterCache;
    return SettingsRow(
      label,
      () => ListTile(
        leading: const Icon(Bootstrap.alphabet),
        title: TipText(label, '${l10n.letterCacheTip}\n${l10n.needRestart}'),
        trailing: StoreSwitch(prop: _setting.letterCache),
      ),
      keywords: l10n.letterCacheTip,
    );
  }

  SettingsRow _buildSshBgImage() {
    final label = libL10n.image;
    return SettingsRow(
      label,
      () => ListTile(
        leading: const Icon(Icons.image),
        title: Text(label),
        trailing: _setting.sshBgImage.listenable().listenVal((val) {
          final name = val.getFileName();
          return Text(name ?? libL10n.empty, style: UIs.text15);
        }),
        onTap: () {
          context.showRoundDialog(
            title: label,
            actions: [
              TextButton(
                onPressed: () async => await _pickBgImage(),
                child: Text(libL10n.file),
              ),
              TextButton(
                onPressed: () async {
                  final old = _setting.sshBgImage.fetch();
                  _setting.sshBgImage.delete();
                  await _deleteBgImage(old);
                  _refreshApp(closeDialog: true);
                },
                child: Text(libL10n.clear),
              ),
            ],
          );
        },
      ),
      keywords: libL10n.background,
    );
  }

  SettingsRow _buildSshBgOpacity() {
    void onSave(String s) {
      final val = double.tryParse(s);
      if (val == null) {
        Toast.error(libL10n.fail);
        return;
      }
      _setting.sshBgOpacity.put(val.clamp(0.0, 1.0));
      context.popDialog();
    }

    return SettingsRow(
      libL10n.opacity,
      () => ListTile(
        leading: const Icon(Icons.opacity),
        title: Text(libL10n.opacity),
        trailing: ValBuilder(
          listenable: _setting.sshBgOpacity.listenable(),
          builder: (val) => Text(val.toString(), style: UIs.text15),
        ),
        onTap: () => context.showRoundDialog(
          title: libL10n.opacity,
          child: Input(
            controller: _sshOpacityCtrl,
            autoFocus: true,
            type: TextInputType.number,
            hint: '0.3',
            icon: Icons.opacity,
            suggestion: false,
            onSubmitted: onSave,
          ),
          actions: Btn.ok(onTap: () => onSave(_sshOpacityCtrl.text)).toList,
        ),
      ),
      keywords: libL10n.background,
    );
  }

  SettingsRow _buildSshBlurRadius() {
    void onSave(String s) {
      final val = double.tryParse(s);
      if (val == null) {
        Toast.error(libL10n.fail);
        return;
      }
      const minRadius = 0.0;
      const maxBlur = 50.0;
      final clampedVal = val.clamp(minRadius, maxBlur);
      _setting.sshBlurRadius.put(clampedVal);
      context.popDialog();
    }

    return SettingsRow(
      libL10n.blurRadius,
      () => ListTile(
        leading: const Icon(Icons.blur_on),
        title: Text(libL10n.blurRadius),
        trailing: ValBuilder(
          listenable: _setting.sshBlurRadius.listenable(),
          builder: (val) => Text(val.toString(), style: UIs.text15),
        ),
        onTap: () => context.showRoundDialog(
          title: libL10n.blurRadius,
          child: Input(
            controller: _sshBlurCtrl,
            autoFocus: true,
            type: TextInputType.number,
            hint: '0',
            icon: Icons.blur_on,
            suggestion: false,
            onSubmitted: onSave,
          ),
          actions: Btn.ok(onTap: () => onSave(_sshBlurCtrl.text)).toList,
        ),
      ),
      keywords: libL10n.background,
    );
  }

  SettingsRow _buildTmuxAutoToggle() {
    final label = l10n.tmuxAuto;
    return SettingsRow(
      label,
      () => ListTile(
        leading: const Icon(Icons.terminal),
        title: Text(label),
        subtitle: Text(l10n.tmuxAutoTip, style: UIs.textGrey),
        trailing: StoreSwitch(prop: _setting.tmuxAuto),
      ),
      keywords: 'tmux ${l10n.tmuxAutoTip}',
    );
  }

  SettingsRow _buildTmuxShowSelector() {
    final label = l10n.tmuxSessionSelector;
    return SettingsRow(
      label,
      () => _setting.tmuxAuto.listenable().listenVal((autoEnabled) {
        return IgnorePointer(
          ignoring: !autoEnabled,
          child: Opacity(
            opacity: autoEnabled ? 1.0 : 0.5,
            child: ListTile(
              leading: const Icon(Icons.list_alt),
              title: Text(label),
              subtitle: Text(l10n.tmuxSessionSelectorTip, style: UIs.textGrey),
              trailing: StoreSwitch(prop: _setting.tmuxShowSelector),
            ),
          ),
        );
      }),
      keywords: 'tmux ${l10n.tmuxSessionSelectorTip}',
    );
  }

  SettingsRow _buildTmuxSessionName() {
    final label = l10n.tmuxDefaultSessionName;
    return SettingsRow(
      label,
      () => _setting.tmuxAuto.listenable().listenVal((autoEnabled) {
        return _setting.tmuxSessionName.listenable().listenVal((name) {
          final displayName = name.isEmpty ? 'server_box' : name;
          return IgnorePointer(
            ignoring: !autoEnabled,
            child: Opacity(
              opacity: autoEnabled ? 1.0 : 0.5,
              child: ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(label),
                trailing: Text(displayName, style: UIs.text15),
                onTap: () => _showTmuxSessionNameDialog(name),
              ),
            ),
          );
        });
      }),
      keywords: 'tmux',
    );
  }

  Future<void> _showTmuxSessionNameDialog(String current) async {
    withTextFieldController((ctrl) async {
      ctrl.text = current;
      void onSave() {
        _setting.tmuxSessionName.put(ctrl.text.trim());
        // `popDialog`: `context` here is the settings page's, and the dialog
        // is on the root navigator.
        context.popDialog();
      }

      await context.showRoundDialog<bool>(
        title: l10n.tmuxSessionName,
        child: Input(
          controller: ctrl,
          autoFocus: true,
          hint: 'server_box',
          suggestion: false,
          onSubmitted: (_) => onSave(),
        ),
        actions: Btn.ok(onTap: onSave).toList,
      );
    });
  }

  SettingsRow _buildHostCertAuthorities() {
    final label = l10n.hostCertAuthorities;
    return SettingsRow(
      label,
      () => ListTile(
        leading: const Icon(Icons.verified_user_outlined),
        title: TipText(label, l10n.hostCertAuthoritiesTip),
        trailing: _setting.sshHostCertAuthorities.listenable().listenVal(
          (list) => Text('${list.length}', style: UIs.text15),
        ),
        onTap: _showHostCertAuthorities,
      ),
      keywords: 'ssh certificate ca cert-authority known_hosts',
    );
  }

  Future<void> _showHostCertAuthorities() async {
    final prop = _setting.sshHostCertAuthorities;
    await context.showRoundDialog(
      title: l10n.hostCertAuthorities,
      child: SizedBox(
        width: 480,
        child: prop.listenable().listenVal((list) {
          if (list.isEmpty) {
            return Text(libL10n.empty, style: UIs.textGrey);
          }
          return ListView(
            shrinkWrap: true,
            children: [
              for (final (index, ca) in list.indexed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_hostCertAuthorityLabel(ca)),
                  subtitle: Text(ca.hosts, style: UIs.textGrey),
                  trailing: IconButton(
                    tooltip: libL10n.delete,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _removeHostCertAuthority(index, ca),
                  ),
                ),
            ],
          );
        }),
      ),
      actions: [
        Btn.text(text: libL10n.add, onTap: _addHostCertAuthority),
        Btn.ok(),
      ],
    );
  }

  /// The key's type and comment, which is how a person tells two apart.
  String _hostCertAuthorityLabel(HostCertAuthority ca) =>
      [ca.type, if (ca.comment.isNotEmpty) ca.comment].join(' ');

  /// Asked first, as forgetting a host key is: every host it vouches for
  /// goes back to the first-use prompt.
  Future<void> _removeHostCertAuthority(int index, HostCertAuthority ca) async {
    final ok = await context.showRoundDialog<bool>(
      title: libL10n.attention,
      child: Text(
        libL10n.askContinue('${libL10n.delete} ${_hostCertAuthorityLabel(ca)}'),
      ),
      actions: Btnx.cancelRedOk,
    );
    if (ok != true) return;
    final prop = _setting.sshHostCertAuthorities;
    final list = [...prop.get()];
    // By position: the list may have changed while this was asked.
    if (index < list.length && list[index] == ca) {
      list.removeAt(index);
      prop.put(list);
    }
  }

  void _addHostCertAuthority() {
    withTextFieldController((keyCtrl) async {
      // Not a second `withTextFieldController`: it returns nothing to await,
      // so this callback would end at once and [keyCtrl] be disposed under an
      // open dialog.
      final hostsCtrl = TextEditingController(text: '*');
      try {
        // The dialog's own state, so nothing outlives it: a notifier disposed
        // when this returns would still be listened to through its exit
        // animation.
        String? keyError;
        String? hostsError;
        late StateSetter setErrors;
        void onSave() {
          final ca = HostCertAuthority.parse(
            keyCtrl.text,
            hosts: hostsCtrl.text,
          );
          final prop = _setting.sshHostCertAuthorities;
          final list = prop.get();
          setErrors(() {
            keyError = ca.key == null
                ? l10n.hostCertAuthorityInvalid
                : list.any(ca.sameAs)
                ? l10n.hostCertAuthorityExists
                : null;
            hostsError = ca.hasHosts ? null : l10n.hostCertAuthorityNoHosts;
          });
          if (keyError != null || hostsError != null) return;
          prop.put([...list, ca]);
          context.popDialog();
        }

        await context.showRoundDialog(
          title: libL10n.add,
          child: StatefulBuilder(
            builder: (context, setState) {
              setErrors = setState;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Input(
                    controller: keyCtrl,
                    autoFocus: true,
                    label: libL10n.key,
                    hint: 'ssh-ed25519 AAAA... ca@example.com',
                    maxLines: 3,
                    suggestion: false,
                    errorText: keyError,
                  ),
                  Input(
                    controller: hostsCtrl,
                    label: libL10n.host,
                    hint: '*.example.com,!bastion.example.com',
                    suggestion: false,
                    errorText: hostsError,
                    onSubmitted: (_) => onSave(),
                  ),
                ],
              );
            },
          ),
          actions: Btn.ok(onTap: onSave).toList,
        );
      } finally {
        _disposeAfterExit(hostsCtrl);
      }
    });
  }

  // —— Terminal page colours ——————————————————————————————————————————

  SettingsRow _buildTermBgColor() => _buildColorRow(
    l10n.termBgColor,
    Stores.setting.termBgColor.fetch,
    (v) => Stores.setting.termBgColor.put(v),
  );

  SettingsRow _buildTermFgColor() => _buildColorRow(
    l10n.termFgColor,
    Stores.setting.termFgColor.fetch,
    (v) => Stores.setting.termFgColor.put(v),
  );

  SettingsRow _buildBarColor() => _buildColorRow(
    l10n.barColor,
    Stores.setting.barColor.fetch,
    (v) => Stores.setting.barColor.put(v),
  );

  /// The accent every chrome palette takes: the network sparklines, the
  /// progress bars, the file browser's buttons and sort marks.
  SettingsRow _buildUiAccentColor() => _buildColorRow(
    l10n.uiAccentColor,
    Stores.setting.uiAccentColor.fetch,
    (v) => Stores.setting.uiAccentColor.put(v),
  );

  /// The text colour the readings panel and the file browser draw their
  /// labels and figures in.
  SettingsRow _buildUiTextColor() => _buildColorRow(
    l10n.uiTextColor,
    Stores.setting.uiTextColor.fetch,
    (v) => Stores.setting.uiTextColor.put(v),
  );

  /// One colour setting: a swatch in the row showing the choice, a picker on
  /// tap. `0` is the "leave it to the theme" value, drawn as an empty swatch.
  SettingsRow _buildColorRow(
    String label,
    int Function() read,
    void Function(int) write,
  ) {
    final raw = read();
    final color = raw == 0 ? null : Color(raw);
    final outline = Theme.of(context).colorScheme.outline;
    return SettingsRow(
      label,
      () => ListTile(
        leading: const Icon(Icons.palette_outlined),
        title: Text(label),
        trailing: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: outline),
          ),
          child: color == null
              ? Icon(Icons.block, size: 16, color: outline)
              : null,
        ),
        onTap: () async {
          await _pickColor(label, raw, write);
        },
      ),
    );
  }

  /// One colour setting: a swatch in the row showing the choice, and the app's
  /// own RGB-slider picker on tap. `0` is "leave it to the theme", shown as an
  /// empty swatch and reachable from the dialog's reset.
  ///
  /// The colour is written and the app repainted on every change the picker
  /// reports, so the page behind the dialog is the preview — cancel puts the
  /// old value back.
  Future<void> _pickColor(
    String title,
    int current,
    void Function(int) write,
  ) async {
    var picked = current == 0
        ? Theme.of(context).colorScheme.primary
        : Color(current);
    void preview(Color c) {
      picked = c;
      write(c.toARGB32());
      unawaited(RNodes.app.notify());
    }

    final result = await showGeneralDialog<int>(
      context: context,
      barrierDismissible: false,
      barrierLabel: title,
      barrierColor: Colors.transparent,
      pageBuilder: (ctx, _, _) => _ColorPreviewScaffold(
        title: title,
        initial: picked,
        onChanged: preview,
        onReset: () => Navigator.of(ctx).pop(0),
        onCancel: () => Navigator.of(ctx).pop(),
        onOk: () => Navigator.of(ctx).pop(picked.toARGB32()),
      ),
    );

    // Cancelled: put back whatever the setting was, undoing the previews.
    // Anything else (ok / reset) is already written by [preview] or is the
    // reset's `0`, which is written here.
    if (result == null) {
      write(current);
      unawaited(RNodes.app.notify());
      return;
    }
    write(result);
    unawaited(RNodes.app.notify());
  }

  SettingsRow _buildFilePanelOpacity() => _buildOpacityRow(
    l10n.filePanelOpacity,
    Stores.setting.filePanelOpacity.fetch,
    (v) => Stores.setting.filePanelOpacity.put(v),
  );

  SettingsRow _buildOpacityRow(
    String label,
    double Function() read,
    void Function(double) write,
  ) {
    final value = read();
    return SettingsRow(
      label,
      () => ListTile(
        leading: const Icon(Icons.opacity),
        title: Text(label),
        trailing: Text('${(value * 100).round()}%', style: UIs.textGrey),
        onTap: () async {
          final picked = await _pickOpacity(label, value);
          if (picked == null) return;
          write(picked);
          unawaited(RNodes.app.notify());
        },
      ),
    );
  }

  Future<double?> _pickOpacity(String title, double current) async {
    var v = current;
    return showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 320,
            child: Row(
              children: [
                Expanded(
                  child: Slider(
                    value: v,
                    min: 0.2,
                    max: 1.0,
                    divisions: 16,
                    label: '${(v * 100).round()}%',
                    onChanged: (x) => setLocal(() => v = x),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text('${(v * 100).round()}%'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(libL10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(v),
              child: Text(libL10n.ok),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen live preview for a colour picker: the settings page is replaced
/// by a terminal drawn with the colours being picked, so moving a slider shows
/// the end result there instead of making the user leave Settings to check.
/// The picker card floats on top; the terminal beneath listens to the stores
/// the picker writes on every step.
class _ColorPreviewScaffold extends StatelessWidget {
  final String title;
  final Color initial;
  final ValueChanged<Color> onChanged;
  final VoidCallback onReset;
  final VoidCallback onCancel;
  final VoidCallback onOk;

  const _ColorPreviewScaffold({
    required this.title,
    required this.initial,
    required this.onChanged,
    required this.onReset,
    required this.onCancel,
    required this.onOk,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          const Positioned.fill(child: _TerminalPreview()),
          Center(
            child: Card(
              elevation: 8,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 300,
                        child: ColorPicker(
                          color: initial,
                          onColorChanged: onChanged,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: onReset,
                            child: Text(libL10n.reset),
                          ),
                          TextButton(
                            onPressed: onCancel,
                            child: Text(libL10n.cancel),
                          ),
                          FilledButton(
                            onPressed: onOk,
                            child: Text(libL10n.ok),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A stand-in for the terminal page, painted from the live settings: the top
/// bar, some terminal lines, the readings panel and the file strip — enough
/// that a colour change shows where it lands.
class _TerminalPreview extends StatelessWidget {
  const _TerminalPreview();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        Stores.setting.termBgColor.listenable(),
        Stores.setting.termFgColor.listenable(),
        Stores.setting.barColor.listenable(),
        Stores.setting.filePanelOpacity.listenable(),
        Stores.setting.uiAccentColor.listenable(),
        Stores.setting.uiTextColor.listenable(),
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final dark = theme.brightness == Brightness.dark;
        final bgV = Stores.setting.termBgColor.fetch();
        final fgV = Stores.setting.termFgColor.fetch();
        final bg = bgV == 0 ? theme.scaffoldBackgroundColor : Color(bgV);
        final fg = fgV == 0 ? theme.colorScheme.onSurface : Color(fgV);
        final bar =
            PanelStyle.color(context).withValues(alpha: PanelStyle.opacity());
        final accent = PanelStyle.accentOverride() ?? const Color(0xFF4A90E2);
        final uiText = PanelStyle.textOverride() ??
            (dark ? const Color(0xFFE6E8EE) : const Color(0xFF1C1C1E));
        return Container(
          color: bg,
          child: Column(
            children: [
              _PreviewTopBar(bar: bar, accent: accent, uiText: uiText),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _PreviewTerminal(bg: bg, fg: fg, accent: accent),
                    ),
                    Container(
                      width: 275,
                      color: bar,
                      child: _PreviewReadings(uiText: uiText, accent: accent),
                    ),
                  ],
                ),
              ),
              _PreviewFileStrip(bar: bar, uiText: uiText, accent: accent),
            ],
          ),
        );
      },
    );
  }
}

class _PreviewTopBar extends StatelessWidget {
  final Color bar;
  final Color accent;
  final Color uiText;

  const _PreviewTopBar({
    required this.bar,
    required this.accent,
    required this.uiText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      color: bar,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            'LBox',
            style: TextStyle(
              color: uiText,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 16),
          Text('本地 · 终端', style: TextStyle(color: uiText, fontSize: 13)),
          const Spacer(),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text('已连接', style: TextStyle(color: uiText, fontSize: 12)),
        ],
      ),
    );
  }
}

class _PreviewTerminal extends StatelessWidget {
  final Color bg;
  final Color fg;
  final Color accent;

  const _PreviewTerminal({
    required this.bg,
    required this.fg,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.6);
    final lines = <(String, Color)>[
      ('user@host:~\$ ls -la', fg),
      ('total 24', fg),
      ('drwxr-xr-x  5 user user 4096  .', fg),
      ('-rw-r--r--  1 user user  220  .bashrc', fg),
      ('user@host:~\$ echo "LBox"', fg),
      ('LBox', accent),
      ('user@host:~\$ ▊', fg),
    ];
    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (text, color) in lines)
            Text(text, style: mono.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _PreviewReadings extends StatelessWidget {
  final Color uiText;
  final Color accent;

  const _PreviewReadings({required this.uiText, required this.accent});

  @override
  Widget build(BuildContext context) {
    final secondary = uiText.withValues(alpha: 0.62);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LBox',
            style: TextStyle(
              color: uiText,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          _PreviewBar(label: 'CPU', value: 0.42, color: accent, text: uiText),
          _PreviewBar(label: '内存', value: 0.63, color: accent, text: uiText),
          _PreviewBar(label: 'Swap', value: 0.08, color: accent, text: uiText),
          const SizedBox(height: 10),
          Text('连接   SSH', style: TextStyle(color: secondary, fontSize: 12)),
          Text('系统   Linux', style: TextStyle(color: secondary, fontSize: 12)),
          Text('主机   localhost', style: TextStyle(color: secondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _PreviewBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final Color text;

  const _PreviewBar({
    required this.label,
    required this.value,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(label, style: TextStyle(color: text, fontSize: 12)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Stack(
                  children: [
                    Container(color: color.withValues(alpha: 0.18)),
                    FractionallySizedBox(
                      widthFactor: value,
                      child: Container(color: color),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 34,
            child: Text(
              '${(value * 100).round()}%',
              textAlign: TextAlign.right,
              style: TextStyle(color: text, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewFileStrip extends StatelessWidget {
  final Color bar;
  final Color uiText;
  final Color accent;

  const _PreviewFileStrip({
    required this.bar,
    required this.uiText,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      color: bar,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 16, color: uiText),
          const SizedBox(width: 6),
          Text('文件', style: TextStyle(color: uiText, fontSize: 12)),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('上传', style: TextStyle(color: accent, fontSize: 12)),
          ),
          const Spacer(),
          Text('name  ·  size', style: TextStyle(color: uiText, fontSize: 12)),
        ],
      ),
    );
  }
}
