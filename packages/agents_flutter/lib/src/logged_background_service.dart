import 'package:extensions/extensions.dart';

/// A [BackgroundService] that frames its lifecycle as a readable log
/// transcript: starting/started, stopping/stopped, and completed/cancelled/
/// failed (with timing) around the actual work.
///
/// Subclasses implement [executeLogged] instead of [execute]; the base owns the
/// `execute` seam so every service logs consistently. Because [start] kicks the
/// work off asynchronously (`BackgroundService.start` returns as soon as the
/// operation is in flight), the "started" line means *kicked off* — the
/// completed/cancelled/failed line is emitted from the [execute] wrapper when
/// the work actually finishes.
///
/// Services that handle their own errors internally (catch + log + return) keep
/// doing so; their own `logError` remains the authoritative failure signal and
/// the base records a neutral "completed". The base's "failed" branch only
/// fires for errors that genuinely escape [executeLogged].
abstract base class LoggedBackgroundService extends BackgroundService {
  LoggedBackgroundService({
    required LoggerFactory loggerFactory,
    required String serviceName,
    String Function()? startupDetails,
  }) : _logger = loggerFactory.createLogger(serviceName),
       // ignore: prefer_initializing_formals
       _startupDetails = startupDetails;

  final Logger _logger;
  final String Function()? _startupDetails;

  /// The category logger for this service, available to subclasses for their
  /// own milestone logs so the whole transcript shares one category.
  Logger get logger => _logger;

  /// The background work to run, implemented by subclasses. Replaces the
  /// `execute` override, which the base reserves for lifecycle logging.
  Future<void> executeLogged(CancellationToken stoppingToken);

  @override
  Future<void> start(CancellationToken cancellationToken) async {
    final details = _startupDetails?.call();
    _logger.logInformation(
      details == null ? 'starting' : 'starting ($details)',
    );
    // `super.start` kicks `execute` off without awaiting it, so it returns
    // synchronously with the work in flight. Log "started" before awaiting the
    // returned future so the transcript reads starting -> started -> completed
    // even for instantaneous services (awaiting first would let a fast
    // `execute` log "completed" ahead of "started").
    try {
      final startFuture = super.start(cancellationToken);
      _logger.logInformation('started');
      await startFuture;
    } catch (e, st) {
      _logger.logError('failed to start: $e\n$st', error: e);
      rethrow;
    }
  }

  @override
  Future<void> stop(CancellationToken cancellationToken) async {
    _logger.logInformation('stopping');
    final stopwatch = Stopwatch()..start();
    try {
      await super.stop(cancellationToken);
    } catch (e, st) {
      _logger.logError(
        'failed to stop in ${stopwatch.elapsedMilliseconds}ms: $e\n$st',
        error: e,
      );
      rethrow;
    }
    _logger.logInformation('stopped in ${stopwatch.elapsedMilliseconds}ms');
  }

  @override
  Future<void> execute(CancellationToken stoppingToken) async {
    final stopwatch = Stopwatch()..start();
    try {
      await executeLogged(stoppingToken);
      if (stoppingToken.isCancellationRequested) {
        _logger.logInformation(
          'cancelled in ${stopwatch.elapsedMilliseconds}ms',
        );
      } else {
        _logger.logInformation(
          'completed in ${stopwatch.elapsedMilliseconds}ms',
        );
      }
    } catch (e, st) {
      _logger.logError(
        'failed in ${stopwatch.elapsedMilliseconds}ms: $e\n$st',
        error: e,
      );
      rethrow;
    }
  }
}
