import 'dart:async';


/// What a command left behind.
class ExecResult {
  const ExecResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.outputIncomplete = false,
    this.streamError,
    this.streamErrorStackTrace,
    this.mayStillRun = false,
  });

  /// Null where the source cannot report one — a shell that was closed rather
  /// than exited.
  final int? exitCode;
  final String stdout;
  final String stderr;

  /// The command finished but its output did not, and waiting was given up on.
  ///
  /// A process that leaves a child holding the channel — `nohup ... &`,
  /// `setsid` — exits without closing stdout, and a reader that waits for the
  /// end of that stream waits for a process nobody is tracking. What arrived
  /// is here; this says there may have been more.
  final bool outputIncomplete;

  /// An error while reading stdout or stderr, after preserving everything that
  /// arrived before it.
  final Object? streamError;
  final StackTrace? streamErrorStackTrace;

  /// Cancelled, and what the command started could not be confirmed stopped:
  /// it may still be running on the server. A process that left the command's
  /// session (`setsid`, a daemon doing the work) is out of every source's
  /// reach, and some sources cannot stop a command at all.
  final bool mayStillRun;

  /// Both streams in the order a terminal would have shown them. Most callers
  /// want this: they are parsing what a command printed, not auditing which
  /// file descriptor it used.
  String get combined => stderr.isEmpty ? stdout : '$stdout$stderr';

  bool get succeeded =>
      streamError == null &&
      (exitCode == 0 || (exitCode == null && stderr.isEmpty));
}

typedef OnExecOutput = void Function(String chunk);

/// Running one command on a machine and collecting what it printed.
///
/// "Run this and tell me what it said": no terminal, no protocol. A process on
/// this device, a command in a guest, an SSH channel or an agent's `/exec`
/// all keep this promise, so a caller written against it does not care which
/// one it was handed. Anything that needs more — a byte stream, a forwarded
/// port — asks for that instead.
abstract interface class CommandExec {
  /// Runs [script] and collects its output.
  ///
  /// [script] is handed to the server's own shell as the command to run, so it
  /// may be a pipeline or several lines. [stdin] is written to it — a real
  /// input stream, which is how a sudo password gets in without a terminal to
  /// type it into, and the reason a password never has to be written into the
  /// command where a log or a process list would see it.
  ///
  /// [entry] is for the other shape: something that reads a script on *its*
  /// stdin rather than running one, which is what installing the status script
  /// is (`mkdir -p; cat > path; chmod`). Then [entry] is the command and
  /// [stdin] followed by [script] is what it reads.
  ///
  /// "The server's own shell" is the account's login shell, and nothing says
  /// that is a POSIX one: fish rejects `VAR=value cmd`, `if ...; then` and a
  /// heredoc, and a syntax error there is not an exception but a diagnostic
  /// on stderr and none of the output the caller is looking for. So a
  /// [script] written in POSIX syntax goes through `entry: 'sh'`; only a
  /// single command with quoted arguments is safe to run as the command.
  ///
  /// [cancel] completing means the caller has stopped waiting: the result is
  /// whatever had arrived by then, and the command is stopped where that is
  /// possible. Only some sources can actually stop one — see the note on each
  /// implementation — so a cancelled command is not a command guaranteed not
  /// to have finished.
  Future<ExecResult> run(
    String script, {
    String? entry,
    Map<String, String>? env,
    String? stdin,
    OnExecOutput? onStdout,
    OnExecOutput? onStderr,
    Future<void>? cancel,
  });
}

/// A [CommandExec] whose command can be fed bytes while it runs, rather than a
/// string written before it starts.
///
/// What an upload through a command needs (`virsh vol-upload --file
/// /dev/stdin`): the file is the command's stdin, sent as it is read, with
/// the command's own output watched meanwhile. An SSH session and a local
/// process carry that; a monitor agent's `/exec` takes its stdin whole, in
/// the request, so it is not one of these.
abstract interface class CommandByteExec implements CommandExec {
  /// Starts [command], handed to the server's own shell as the command to run
  /// — one line with single-quoted arguments only, for the reason
  /// [CommandExec.run] gives.
  Future<ExecSession> start(String command);
}

/// A command started by [CommandByteExec.start].
abstract interface class ExecSession {
  /// What it prints, decoded; both end when it has.
  Stream<String> get stdout;
  Stream<String> get stderr;

  /// Writes [data] to its stdin, returning once the transport has taken it:
  /// a caller writing a large file in a loop is held back to the pace the
  /// command reads at, rather than buffering the file in memory.
  Future<void> write(List<int> data);

  /// Ends its stdin, which is how it learns the input is complete.
  Future<void> closeStdin();

  /// Its exit status once it has ended; null where the source cannot say
  /// (killed).
  Future<int?> get done;

  /// Stops it, and releases the channel.
  void kill();
}
