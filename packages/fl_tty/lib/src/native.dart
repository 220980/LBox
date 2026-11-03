import 'dart:ffi';
import 'dart:io';

/// Android's native library directory: where the APK's libraries were
/// extracted at install, and the one place an app may `execve` from.
///
/// Read off where fl_tty's own library is mapped from, so no platform channel
/// is needed. Null when the libraries were not extracted — mapped straight out
/// of the APK (`base.apk!/lib/...`), which is what an app without
/// `packaging.jniLibs.useLegacyPackaging = true` gets, and where nothing can be
/// executed at all.
String? nativeLibDir() {
  if (!Platform.isAndroid) return null;
  const name = '/libfl_tty.so';
  try {
    DynamicLibrary.open(name.substring(1));
    for (final line in File('/proc/self/maps').readAsLinesSync()) {
      final i = line.indexOf('/');
      if (i < 0 || !line.endsWith(name)) continue;
      final path = line.substring(i);
      if (path.contains('!')) return null;
      return path.substring(0, path.length - name.length);
    }
  } catch (_) {}
  return null;
}
