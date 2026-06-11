import 'dart:io';

/// Waits for [process] to exit, killing it when [timeout] elapses first.
///
/// With [gracefulSigint], the process first receives `SIGINT` and is given a
/// short grace period to shut down before being force-killed. The returned
/// record reports whether the timeout fired; the exit code is the process's
/// actual exit code (the code after a kill when it timed out).
Future<({int exitCode, bool timedOut})> waitForProcessExit(
  Process process, {
  Duration? timeout,
  bool gracefulSigint = false,
}) async {
  if (timeout == null) {
    return (exitCode: await process.exitCode, timedOut: false);
  }
  var timedOut = false;
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () async {
      timedOut = true;
      if (gracefulSigint) {
        try {
          process.kill(ProcessSignal.sigint);
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      try {
        process.kill();
      } catch (_) {}
      return process.exitCode;
    },
  );
  return (exitCode: exitCode, timedOut: timedOut);
}
