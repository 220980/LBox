import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Builds fl_tty's native library, and on Android arm64 the proot pair.
///
/// One library, `fl_tty`, everywhere: the pty (`src/flutter_pty.c`, which
/// `#include`s the rest of it). On iOS arm64 the ish shim is compiled into the
/// same library and linked against the engine's static libraries, which
/// `scripts/ensure-ish-libs.sh` fetches for the submodule's revision (or
/// builds, without a release for it).
///
/// User-defines, in the app's pubspec under `hooks: user_defines: fl_tty:`:
///
///   ish: false        an iOS build without the engine: `IosRootfs.isAvailable`
///                     answers false and nothing of ish is linked.
///   proot: false      an Android build without proot.
///
/// proot built ahead of time by running `scripts/build-proot-android.sh` (a
/// build that must not reach the network) is in `build/proot-android/out` and
/// is used as it is.
///
/// proot needs the app to set `packaging.jniLibs.useLegacyPackaging = true`:
/// otherwise nothing is extracted from the APK and there is nowhere to
/// `execve` it from.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final root = input.packageRoot;

    final ish = code.targetOS == OS.iOS &&
        code.targetArchitecture == Architecture.arm64 &&
        input.userDefines['ish'] != false;
    final ishSrc = root.resolve('third_party/ish-arm64/');
    Uri? ishLibs;
    if (ish) {
      final sim = code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
      ishLibs = root.resolve('build/ish/build-${sim ? 'iossim' : 'ios'}-arm64/');
      await _run('scripts/ensure-ish-libs.sh', [], root, {
        'SBM_ISH': '1',
        'PLATFORM_NAME': sim ? 'iphonesimulator' : 'iphoneos',
        'ISH_BUILD_DIR': ishLibs.toFilePath(),
      });
      for (final lib in _ishLibs) {
        output.dependencies.add(ishLibs.resolve('lib$lib.a'));
      }
    }

    await CBuilder.library(
      name: 'fl_tty',
      assetName: 'fl_tty',
      sources: ['src/flutter_pty.c', if (code.targetOS == OS.iOS) 'ish/sbm_ish.c'],
      includes: [
        'src',
        'ish',
        // The build directory's headers exist only after a local meson build;
        // a fetched release is the three libraries alone.
        if (ish)
          for (final dir in [ishSrc, ishLibs!, ishSrc.resolve('vdso/arm64/'), ishLibs.resolve('vdso/arm64/')])
            if (Directory.fromUri(dir).existsSync()) dir.toFilePath(),
      ],
      std: ish ? 'gnu11' : null,
      defines: {
        // What dart_api_dl.c needs to link as part of this library.
        'DART_SHARED_LIB': null,
        if (code.targetOS == OS.iOS) 'SBM_ISH_ENABLED': ish ? '1' : '0',
        if (ish) ...{'GUEST_ARM64': '1', 'LOG_HANDLER_DPRINTF': '1'},
      },
      libraries: [if (ish) ..._ishLibs, if (ish) 'sqlite3'],
      libraryDirectories: [if (ish) ishLibs!.toFilePath()],
      flags: [
        // Android 15 ships a 16 KB page size, and a library linked for 4 KB
        // will not load on it.
        if (code.targetOS == OS.android) '-Wl,-z,max-page-size=16384',
      ],
    ).run(input: input, output: output);

    if (code.targetOS == OS.android &&
        code.targetArchitecture == Architecture.arm64 &&
        input.userDefines['proot'] != false) {
      final dir = await _proot(input);
      for (final name in const ['proot', 'proot-loader']) {
        final file = dir.resolve('lib$name.so');
        output.assets.code.add(
          CodeAsset(package: input.packageName, name: name, linkMode: DynamicLoadingBundled(), file: file),
        );
        output.dependencies.add(file);
      }
    }
  });
}

const _ishLibs = ['ish', 'ish_emu', 'fakefs'];

/// Where `libproot.so` and `libproot-loader.so` are: built ahead of time, or
/// built once into the shared output directory with the NDK this build uses.
Future<Uri> _proot(BuildInput input) async {
  bool built(Uri dir) =>
      File.fromUri(dir.resolve('libproot.so')).existsSync() &&
      File.fromUri(dir.resolve('libproot-loader.so')).existsSync();
  final ahead = input.packageRoot.resolve('build/proot-android/out/');
  if (built(ahead)) return ahead;
  final out = input.outputDirectoryShared.resolve('proot/');
  if (built(out)) return out;
  // .../ndk/<version>/toolchains/llvm/prebuilt/<host>/bin/clang
  final cc = input.config.code.cCompiler?.compiler;
  if (cc == null) throw StateError('No NDK compiler to build proot with');
  final ndk = cc.resolve('../../../../../');
  await _run('scripts/build-proot-android.sh', [], input.packageRoot, {
    'ANDROID_NDK_HOME': ndk.toFilePath(),
    'PROOT_OUT_DIR': out.toFilePath(),
    'PROOT_BUILD_DIR': input.outputDirectoryShared.resolve('proot-build/').toFilePath(),
  });
  return out;
}

Future<void> _run(String script, List<String> args, Uri root, Map<String, String> env) async {
  final r = await Process.run(
    'bash',
    [root.resolve(script).toFilePath(), ...args],
    workingDirectory: root.toFilePath(),
    environment: env,
  );
  if (r.exitCode != 0) {
    throw ProcessException(script, args, '${r.stdout}\n${r.stderr}', r.exitCode);
  }
}
