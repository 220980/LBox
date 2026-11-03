import 'package:material_ui/material_ui.dart';
import 'package:server_box/data/res/store.dart';

/// The one colour and one transparency every piece of the terminal page's
/// chrome shares — the left session rail, the top tab/status bar, the readings
/// panel down the right, and the file browser docked under the terminal. One
/// setting for the colour ([SettingStore.barColor]) and one for how solid they
/// are ([SettingStore.filePanelOpacity]), applied to all four so they read as
/// one surface rather than four.
abstract final class PanelStyle {
  /// meatshell's panel charcoal, and its light counterpart.
  static const _dark = Color(0xFF23262D);
  static const _light = Color(0xFFF2F2F7);

  /// The chosen colour, or meatshell's own when the setting is `0`.
  static Color color(BuildContext context) {
    final v = Stores.setting.barColor.fetch();
    if (v != 0) return Color(v);
    return Theme.of(context).brightness == Brightness.dark ? _dark : _light;
  }

  /// The chosen transparency, 1 being solid.
  static double opacity() =>
      Stores.setting.filePanelOpacity.fetch().clamp(0.0, 1.0);

  /// What the chrome is seen against: the terminal's own background, so that a
  /// lower transparency fades the chrome towards the terminal colour instead of
  /// towards whatever opaque surface happens to sit behind it — the top bar and
  /// the app rail stand over plain window chrome, where a merely translucent
  /// colour would have nothing to show through and would look unchanged.
  static Color backdrop(BuildContext context) {
    final v = Stores.setting.termBgColor.fetch();
    if (v != 0) return Color(v);
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1B1D23)
        : const Color(0xFFF5F5F7);
  }

  /// [color] at [opacity], carried as a translucent colour so the surface it
  /// paints shows whatever is behind it — the window wallpaper, so all the
  /// chrome fades together as one.
  static Color withOpacity(BuildContext context) =>
      color(context).withValues(alpha: opacity());

  /// The accent every chrome palette takes, or null when the setting leaves it
  /// to the palette's own blue.
  static Color? accentOverride() {
    final v = Stores.setting.uiAccentColor.fetch();
    return v == 0 ? null : Color(v);
  }

  /// The text colour the chrome palettes take, or null for their own.
  static Color? textOverride() {
    final v = Stores.setting.uiTextColor.fetch();
    return v == 0 ? null : Color(v);
  }
}
