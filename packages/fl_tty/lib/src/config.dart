/// What fl_tty reads of the app it is in, set once before anything else here
/// runs: where its settings live, what it is called inside a guest, and where
/// rootfs releases are announced.
library;

/// The settings fl_tty keeps, in whatever store the app has.
///
/// fl_tty owns what they mean and the app owns where they are: each app has
/// its own store, and these travel (or not) with the rest of its settings.
abstract interface class FlTtySettings {
  /// The profile terminals open in, by `LinuxProfile.id`; empty for the first
  /// one there is.
  String get profile;
  set profile(String value);

  /// The distribution a new profile would be of, by `LinuxDistro.id`.
  String get distro;

  /// Each distribution's mirror, by `LinuxDistro.id`; absent for the default.
  Map<String, String> get mirrors;
  set mirrors(Map<String, String> value);

  /// The resolvers a guest is given, as typed; empty for [FlTty.defaultDns].
  String get dns;

  /// The last manifest accepted: its serial, its bytes and its signature,
  /// base64. Empty or 0 when none has been.
  int get manifestSerial;
  set manifestSerial(int value);
  String get manifestCache;
  set manifestCache(String value);
  String get manifestCacheSig;
  set manifestCacheSig(String value);
}

/// [FlTtySettings] in memory: for tests, and for an app that has not set its
/// own yet.
final class MemoryTtySettings implements FlTtySettings {
  MemoryTtySettings({this.distro = 'alpine'});

  @override
  String profile = '';
  @override
  String distro;
  @override
  Map<String, String> mirrors = const {};
  @override
  String dns = '';
  @override
  int manifestSerial = 0;
  @override
  String manifestCache = '';
  @override
  String manifestCacheSig = '';
}

/// Where rootfs releases are announced, and the key that signs the
/// announcement.
final class RootfsManifestConfig {
  const RootfsManifestConfig({required this.url, required this.publicKey});

  /// shellbox-rootfs: the releases ServerBox and LLMBox install.
  ///
  /// `releases/latest` rather than a pinned tag: a device gets a newer pin
  /// without a new build, and the signature and the serial are what make that
  /// safe. The key's private half is in that repository's Actions secret and
  /// in the maintainer's login keychain under `shellbox-rootfs-signing`;
  /// rotating it means shipping a build, which is the point.
  static const shellbox = RootfsManifestConfig(
    url: 'https://github.com/lollipopkit/shellbox-rootfs/releases/latest/download/manifest.json',
    publicKey: 'wsNkktBO13RsNJm9P38/QPXExoFYluty9zKlZpWSYkk=',
  );

  /// The manifest; its signature is at the same URL with `.sig` appended.
  final String url;

  /// The raw Ed25519 public key the signature is checked with, base64.
  final String publicKey;

  String get sigUrl => '$url.sig';
}

abstract final class FlTty {
  static FlTtySettings settings = MemoryTtySettings();

  static RootfsManifestConfig manifest = RootfsManifestConfig.shellbox;

  /// The app's name as a guest reads it: lowercase, no spaces. It names the
  /// directory fl_tty keeps its own files in (`/etc/<brand>`), the marker on
  /// the `chsh` it installs, and the guest's hostname.
  ///
  /// Fixed for an app once it has shipped: a system installed under one brand
  /// does not find its files under another.
  static String brand = 'fltty';

  /// The app's name as a person reads it, for what the guest prints.
  static String appName = 'fl_tty';

  /// The set of installed systems changed. Android: for the app's
  /// DocumentsProvider, which lists them in the system file picker.
  static void Function()? onSystemsChanged;

  /// The shell a guest's terminal opens when nothing else is chosen.
  static const defaultShell = '/bin/sh';

  /// The resolvers a guest gets when none are chosen.
  static const defaultDns = '8.8.8.8, 1.1.1.1';
}
