/// The ish shim's functions (`ish/sbm_ish.h`), in fl_tty's library on iOS.
///
/// Resolved when first called, so declaring them costs nothing on a platform
/// whose library has none of them; [IosRootfs] calls them only on iOS.
// ignore_for_file: non_constant_identifier_names
@DefaultAsset('package:fl_tty/fl_tty')
library;

import 'dart:ffi';

@Native<Bool Function()>()
external bool sbm_ish_available();

@Native<Int Function(Pointer<Char>, Pointer<Char>, Pointer<Char>)>()
external int sbm_ish_boot(Pointer<Char> rootfs, Pointer<Char> profile, Pointer<Char> hostname);

@Native<Int Function(Pointer<Char>)>()
external int sbm_ish_attach(Pointer<Char> profile);

@Native<Int Function(Pointer<Char>)>()
external int sbm_ish_detach(Pointer<Char> profile);

@Native<Int Function(Pointer<Char>)>()
external int sbm_ish_sessions(Pointer<Char> profile);

@Native<Int Function(Pointer<Char>, Pointer<Char>, Pointer<Char>, Pointer<Char>, Int, Int)>()
external int sbm_ish_open(
  Pointer<Char> profile,
  Pointer<Char> shell,
  Pointer<Char> command,
  Pointer<Char> env,
  int cols,
  int rows,
);

@Native<Int Function(Int, Pointer<Char>, Int, Int)>()
external int sbm_ish_read(int session, Pointer<Char> buffer, int length, int timeoutMs);

@Native<Int Function(Int, Pointer<Char>, Int)>()
external int sbm_ish_write(int session, Pointer<Char> data, int length);

@Native<Int Function(Int, Pointer<Char>, Int)>()
external int sbm_ish_try_write(int session, Pointer<Char> data, int length);

@Native<Void Function(Int, Int, Int)>()
external void sbm_ish_resize(int session, int cols, int rows);

@Native<Int Function(Int)>()
external int sbm_ish_exit_code(int session);

@Native<Void Function(Int)>()
external void sbm_ish_close(int session);
