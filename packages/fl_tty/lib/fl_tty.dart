/// A shell on the device the app runs on. Set [FlTty] first.
library;

export 'src/config.dart';
export 'src/exec/exec.dart';
export 'src/exec/file_tail.dart';
export 'src/exec/local_exec.dart';
export 'src/exec/local_shell.dart';
export 'src/exec/process_tree.dart';
export 'src/exec/shell_backend.dart';
export 'src/ish/ios_rootfs.dart';
export 'src/ish/ish_exec.dart';
export 'src/ish/ish_shell.dart';
export 'src/pty/pty.dart';
export 'src/rootfs/android_rootfs.dart';
export 'src/rootfs/guest_path.dart';
export 'src/rootfs/linux_distro.dart';
export 'src/rootfs/linux_distros.dart';
export 'src/rootfs/linux_seed.dart';
export 'src/rootfs/oci_image.dart';
export 'src/rootfs/rootfs_lifecycle.dart';
export 'src/rootfs/rootfs_manifest_source.dart';
export 'src/rootfs/rootfs_manifest_trust.dart';
export 'src/rootfs/rootfs_manifest.dart';
export 'src/rootfs/rootfs_tar_utils.dart';
export 'src/rootfs/rootfs_unpack.dart';
export 'src/rootfs/rootfs.dart';
