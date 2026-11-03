# fl_tty

A shell on the device the app runs on, shared by [ServerBox](https://github.com/lollipopkit/flutter_server_box) and [LLMBox](https://github.com/lollipopkit/llmbox).

| Platform | What runs a command |
|---|---|
| macOS / Linux / Windows | the host: `ProcessExec` (pipes), `LocalShellBackend` (pty) |
| Android | an Alpine (or other) userland under proot, shipped in the APK's native library directory |
| iOS | the same userland under [ish-arm64](https://github.com/lollipopkit/ShellBox), an AArch64 interpreter linked into the app |

## Use

```dart
FlTty.settings = MyTtySettings(); // backed by the app's own store
FlTty.brand = 'myapp';            // fixed once shipped: names /etc/<brand> in a guest
FlTty.appName = 'MyApp';
await Rootfs.prepare();
final exec = LocalExec.forThisDevice();
```

## Native code

Built by `hook/build.dart` (native assets), no plugin:

- the pty everywhere (`src/`, from flutter_pty);
- iOS arm64: the ish shim (`ish/`) linked with the engine's static libraries, fetched for the `third_party/ish-arm64` revision by `scripts/ensure-ish-libs.sh` (or built with `scripts/build-ish-ios.sh`: `brew install meson ninja llvm lld libarchive`);
- Android arm64: `libproot.so` and `libproot-loader.so`, built by `scripts/build-proot-android.sh` with the build's NDK.

Clone with `--recursive`. The app must set, for Android, `packaging.jniLibs.useLegacyPackaging = true`; and may set in its pubspec:

```yaml
hooks:
  user_defines:
    fl_tty:
      ish: false          # an iOS build without the engine
      proot: false        # an Android build without proot
```

For a build that must not reach the network (F-Droid), run `scripts/build-proot-android.sh` first (with `PROOT_NDK_VERSION` set to pin the NDK): the hook takes what it left in `build/proot-android/out`.

A sandboxed macOS build (Mac App Store) cannot `forkpty`: `LocalShellBackend.isSupported` is false there.

## License

AGPL-3.0, as the ServerBox code it came from. `src/` (flutter_pty) is MIT, see `LICENSE.flutter_pty`; `third_party/ish-arm64` is GPL-3.0 with `LICENSE.IOS`.
