import 'dart:async';
import 'dart:typed_data';


/// A live shell: bytes in, bytes out, and a size.
///
/// A terminal is written against this rather than against any one source: a
/// pty on this device, a session in a guest and an SSH channel are the same
/// shape — a byte stream that can be resized and that ends.
abstract interface class ShellSession {
  Stream<Uint8List>? get stdout;

  /// Null for sources that don't separate it — a PTY merges the two streams
  /// the same way a real terminal does.
  Stream<Uint8List>? get stderr;

  void write(List<int> data);

  /// Tells the far end the terminal's new size. Advisory, and must not throw
  /// once the session has ended: it is called from the terminal's layout, and
  /// a session that is gone says so through [done].
  void resizeTerminal(int width, int height);

  /// Completes when the shell is gone for good. A source that can recover
  /// from a dropped link must not complete this for a mere disconnection.
  Future<void> get done;

  void close();
}

/// Where a [ShellSession] comes from, and what else that source can do.
abstract interface class ShellBackend {
  /// Whether the source itself is dead. A session ending does not imply this:
  /// an SSH client outlives the shells it opens.
  bool get isClosed;

  /// Whether one-off commands can run alongside the interactive shell.
  ///
  /// SSH multiplexes channels, so it can. A single PTY cannot — there is one
  /// stream and a command written into it would land in the user's shell.
  /// Everything built on [execute] (tmux, snippets that need a second
  /// channel, the AI helper's probe) has to check this rather than assume it.
  bool get supportsExec;

  /// Whether tmux can be driven here: [execute] runs its command with a POSIX
  /// `sh` on a pseudo-terminal, which both the discovery shell and `tmux -CC`
  /// need. Implies [supportsExec].
  bool get supportsTmux;

  Future<ShellSession> openShell({
    required int width,
    required int height,
    Map<String, String>? environment,
  });

  /// Runs [command] on its own channel. Throws [UnsupportedError] when
  /// [supportsExec] is false.
  Future<ShellSession> execute(
    String command, {
    required int width,
    required int height,
    Map<String, String>? environment,
  });

  /// Throws when the link is gone. Drives the terminal page's keep-alive.
  Future<void> ping();

  void close();
}
