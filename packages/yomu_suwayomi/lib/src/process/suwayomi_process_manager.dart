import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:yomu_core/yomu_core.dart';

import '../client/suwayomi_client.dart';
import '../config/suwayomi_paths.dart';
import '../config/vendor_manifest.dart';
import '../java/java_resolver.dart';
import 'managed_instance_identity.dart';
import 'process_ownership.dart';
import 'suwayomi_process_failure.dart';
import 'suwayomi_status.dart';

/// Default loopback port dedicated to Yomu-managed Suwayomi.
const int kYomuSuwayomiPort = 14567;

/// System property confirmed in Suwayomi-Server v2.3.2238 bytecode.
const String kSuwayomiRootDirProperty =
    'suwayomi.tachidesk.config.server.rootDir';

/// Optional injectors for lifecycle unit tests (identity.save / Process.start).
typedef YomuProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
      bool runInShell,
    });

typedef YomuIdentitySaver =
    Future<void> Function(ManagedInstanceIdentity identity, File file);

typedef YomuKillConfirm =
    Future<bool> Function(Process? proc, {required int pid});

/// Starts, monitors and stops a loopback-only Suwayomi-Server process.
///
/// Phase 2D ownership rules:
/// - Never adopt a foreign process on the port.
/// - Only kill PIDs proven to match Yomu identity (jar + rootDir).
/// - Persist identity (PID, runId, java, jar, rootDir, port).
/// - Serialize start/stop/restart/shutdown.
class SuwayomiProcessManager {
  SuwayomiProcessManager({
    required this.paths,
    required this.manifest,
    this.javaResolver = const JavaResolver(),
    this.allowArtifactDownload = true,
    this.packagedArtifactsOnly = false,
    this.packagedEngineDirectoryForTest,
    this.host = '127.0.0.1',
    this.port = kYomuSuwayomiPort,
    ProcessOwnershipProbe? ownershipProbe,
    http.Client? httpClient,
    this.processStartForTest,
    this.identitySaveForTest,
    this.killAndConfirmExitForTest,
  }) : _http = httpClient ?? http.Client(),
       _ownership = ProcessOwnership(
         ownershipProbe ?? const PlatformProcessOwnershipProbe(),
       );

  final SuwayomiPaths paths;
  final VendorManifest manifest;
  final JavaResolver javaResolver;
  final bool allowArtifactDownload;
  final bool packagedArtifactsOnly;
  final Directory? packagedEngineDirectoryForTest;
  final String host;
  final int port;
  final http.Client _http;
  final ProcessOwnership _ownership;

  /// Test-only: intercept [Process.start] (count / fake JVM).
  final YomuProcessStarter? processStartForTest;

  /// Test-only: intercept identity persistence (force save failure).
  final YomuIdentitySaver? identitySaveForTest;

  /// Test-only: intercept kill+exit confirmation (force kill=false/timeout).
  final YomuKillConfirm? killAndConfirmExitForTest;

  Process? _process;
  ManagedInstanceIdentity? _identity;
  IOSink? _logSink;
  final StringBuffer _combinedLog = StringBuffer();
  SuwayomiStatus _status = const SuwayomiStatus(
    state: SuwayomiProcessState.stopped,
  );
  final _controller = StreamController<SuwayomiStatus>.broadcast();

  /// Serializes lifecycle ops.
  Future<void> _chain = Future<void>.value();
  bool _shuttingDown = false;

  SuwayomiStatus get status => _status;
  Stream<SuwayomiStatus> get statusStream => _controller.stream;
  ManagedInstanceIdentity? get identity => _identity;

  String get baseUrl => 'http://$host:$port';

  String get managedRootDir => paths.dataDir.absolute.path;

  File get identityFile =>
      File(p.join(paths.root.path, 'runtime', 'suwayomi-instance.json'));

  SuwayomiClient createClient() =>
      SuwayomiClient(baseUrl: baseUrl, httpClient: _http);

  /// Synchronously seals lifecycle admission before coordinated shutdown.
  void beginShutdown() {
    _shuttingDown = true;
  }

  Future<OwnershipCheck> verifyCurrentOwnership() async {
    final stored =
        _identity ?? await ManagedInstanceIdentity.load(identityFile);
    final listener = await _ownership.probe.findListenerPid(port);
    if (stored == null) {
      return OwnershipCheck(
        verdict: listener == null
            ? OwnershipVerdict.dead
            : OwnershipVerdict.foreignOrUnverifiable,
        message: listener == null
            ? 'Nenhuma instância gerenciada está ativa.'
            : 'Há um listener sem identidade Yomu comprovada.',
      );
    }
    if (!_sameAbsolutePath(stored.rootDir, managedRootDir) ||
        stored.port != port ||
        !_sameAbsolutePath(
          stored.jarPath,
          paths.jarFile(manifest.suwayomi.jarFile).absolute.path,
        )) {
      return const OwnershipCheck(
        verdict: OwnershipVerdict.foreignOrUnverifiable,
        message:
            'A identidade ativa diverge do root, porta ou artefato pinado.',
      );
    }
    final check = await _ownership.verifyIdentity(stored);
    if (check.verdict != OwnershipVerdict.yomuOwned) return check;
    if (listener != stored.pid) {
      return OwnershipCheck(
        verdict: OwnershipVerdict.foreignOrUnverifiable,
        snapshot: check.snapshot,
        message: listener == null
            ? 'O processo owned não é o listener da porta gerenciada.'
            : 'A porta gerenciada pertence a outro PID.',
      );
    }
    _identity = stored;
    return check;
  }

  void _emit(SuwayomiStatus next) {
    _status = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  Err<T> _failure<T>(
    SuwayomiProcessFailureKind kind,
    String code,
    String message, [
    Object? cause,
  ]) => Err<T>(
    message,
    SuwayomiProcessFailure(
      kind: kind,
      code: code,
      message: message,
      cause: cause,
    ),
  );

  Future<T> _serialized<T>(Future<T> Function() op) {
    final c = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        c.complete(await op());
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  Future<Result<File>> ensureJar({bool? downloadIfMissing}) async {
    await paths.ensureLayout();
    final jar = paths.jarFile(manifest.suwayomi.jarFile);
    final expected = manifest.suwayomi.sha256;
    final allowDownload = downloadIfMissing ?? allowArtifactDownload;

    File? packagedSeed;
    if (packagedArtifactsOnly) {
      packagedSeed = _findPackagedSeedJar();
      if (packagedSeed == null) {
        return _failure(
          SuwayomiProcessFailureKind.artifactMissing,
          'engine_artifact_missing',
          'Motor empacotado ausente. Repare ou reinstale o Yomu.',
        );
      }
      if (!await _verifySha256(packagedSeed, expected)) {
        return _failure(
          SuwayomiProcessFailureKind.artifactInvalid,
          'engine_artifact_invalid',
          'Motor empacotado inválido. Repare ou reinstale o Yomu.',
        );
      }
    }

    if (jar.existsSync()) {
      final ok = await _verifySha256(jar, expected);
      if (ok) {
        await _writeManifestCopyAtomically();
        return Ok(jar);
      }
      await jar.delete();
    }

    final seed = packagedSeed ?? await _findDevelopmentSeedJar();
    if (seed != null) {
      return _installVerifiedJar(seed: seed, destination: jar);
    }

    if (!allowDownload) {
      return _failure(
        SuwayomiProcessFailureKind.artifactMissing,
        'engine_artifact_missing',
        'Suwayomi JAR ausente ou hash inválido: ${jar.path}',
      );
    }

    _emit(
      _status.copyWith(
        state: SuwayomiProcessState.starting,
        message: 'Baixando Suwayomi ${manifest.suwayomi.displayVersion}…',
      ),
    );

    File? downloadTemp;
    try {
      final response = await _http.get(
        Uri.parse(manifest.suwayomi.downloadUrl),
      );
      if (response.statusCode != 200) {
        return _failure(
          SuwayomiProcessFailureKind.artifactMissing,
          'engine_artifact_unavailable',
          'Falha ao baixar Suwayomi (HTTP ${response.statusCode}).',
        );
      }
      downloadTemp = _temporarySibling(jar);
      await downloadTemp.writeAsBytes(response.bodyBytes, flush: true);
      final ok = await _verifySha256(downloadTemp, expected);
      if (!ok) {
        await downloadTemp.delete();
        downloadTemp = null;
        return _failure(
          SuwayomiProcessFailureKind.artifactInvalid,
          'engine_artifact_invalid',
          'Checksum SHA-256 do JAR Suwayomi não confere com o manifest pinado.',
        );
      }
      final result = await _promoteVerifiedJar(
        temp: downloadTemp,
        destination: jar,
      );
      downloadTemp = null;
      return result;
    } catch (e) {
      if (downloadTemp?.existsSync() ?? false) await downloadTemp!.delete();
      return _failure(
        SuwayomiProcessFailureKind.artifactMissing,
        'engine_artifact_unavailable',
        'Erro ao obter Suwayomi JAR: $e',
        e,
      );
    }
  }

  File? _findPackagedSeedJar() {
    final engineDir =
        packagedEngineDirectoryForTest ??
        Directory(
          p.join(File(Platform.resolvedExecutable).parent.path, 'engine'),
        );
    final candidate = File(p.join(engineDir.path, manifest.suwayomi.jarFile));
    return candidate.existsSync() ? candidate : null;
  }

  Future<File?> _findDevelopmentSeedJar() async {
    final packaged = _findPackagedSeedJar();
    if (packaged != null) return packaged;
    if (packagedArtifactsOnly) return null;

    final envPath = Platform.environment['YOMU_SUWAYOMI_JAR'];
    if (envPath != null && envPath.isNotEmpty) {
      final f = File(envPath);
      if (f.existsSync()) return f;
    }

    var dir = Directory.current;
    for (var i = 0; i < 6; i++) {
      final candidate = File(
        p.join(
          dir.path,
          'packages',
          'yomu_suwayomi',
          'vendor',
          manifest.suwayomi.jarFile,
        ),
      );
      if (candidate.existsSync()) return candidate;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  Future<Result<File>> _installVerifiedJar({
    required File seed,
    required File destination,
  }) async {
    if (!await _verifySha256(seed, manifest.suwayomi.sha256)) {
      return _failure(
        SuwayomiProcessFailureKind.artifactInvalid,
        'engine_artifact_invalid',
        'JAR seed encontrado mas SHA-256 inválido: ${seed.path}',
      );
    }

    final temp = _temporarySibling(destination);
    try {
      await seed.copy(temp.path);
      if (!await _verifySha256(temp, manifest.suwayomi.sha256)) {
        await temp.delete();
        return _failure(
          SuwayomiProcessFailureKind.artifactInvalid,
          'engine_artifact_invalid',
          'Falha de integridade ao preparar o motor interno.',
        );
      }
      return _promoteVerifiedJar(temp: temp, destination: destination);
    } catch (e) {
      if (temp.existsSync()) await temp.delete();
      return _failure(
        SuwayomiProcessFailureKind.artifactInvalid,
        'engine_artifact_install_failed',
        'Erro ao instalar o motor interno empacotado: $e',
        e,
      );
    }
  }

  Future<Result<File>> _promoteVerifiedJar({
    required File temp,
    required File destination,
  }) async {
    try {
      if (destination.existsSync()) await destination.delete();
      final installed = await temp.rename(destination.path);
      await _writeManifestCopyAtomically();
      return Ok(installed);
    } catch (e) {
      if (temp.existsSync()) await temp.delete();
      return _failure(
        SuwayomiProcessFailureKind.artifactInvalid,
        'engine_artifact_install_failed',
        'Erro ao ativar o motor interno verificado: $e',
        e,
      );
    }
  }

  Future<void> _writeManifestCopyAtomically() async {
    final destination = paths.vendorManifestCopy;
    final temp = _temporarySibling(destination);
    try {
      await temp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
        flush: true,
      );
      if (destination.existsSync()) await destination.delete();
      await temp.rename(destination.path);
    } finally {
      if (temp.existsSync()) await temp.delete();
    }
  }

  File _temporarySibling(File destination) {
    final suffix =
        '${DateTime.now().microsecondsSinceEpoch}-'
        '${Random.secure().nextInt(1 << 32)}';
    return File('${destination.path}.tmp-$suffix');
  }

  Future<bool> _verifySha256(File file, String expectedHex) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == expectedHex.toLowerCase();
  }

  Future<void> writeManagedConfig() async {
    await paths.ensureLayout();
    final conf =
        '''
# Generated by Yomu — managed Suwayomi instance only.
# Do not use the global Tachidesk/Suwayomi AppData directory.
server.ip = "$host"
server.port = $port
server.systemTrayEnabled = false
server.initialOpenInBrowserEnabled = false
server.webUIInterface = BROWSER
server.debugLogsEnabled = false
server.authMode = NONE
''';
    final managedConf = File(p.join(paths.dataDir.path, 'server.conf'));
    await managedConf.writeAsString(conf);
    await paths.serverConf.writeAsString(conf);
  }

  /// JVM args: ownership markers + server props **before** `-jar`.
  List<String> buildJavaArgs(
    File jar, {
    required String runId,
    required DateTime startedAt,
  }) {
    final root = _normalizedRootPath(managedRootDir);
    final jarAbs = jar.absolute.path;
    final started = startedAt.toUtc().toIso8601String();
    return [
      '-D$kYomuRunIdProperty=$runId',
      '-D$kYomuStartedAtProperty=$started',
      '-D$kSuwayomiRootDirProperty=$root',
      '-Dsuwayomi.tachidesk.config.server.ip=$host',
      '-Dsuwayomi.tachidesk.config.server.port=$port',
      '-Dsuwayomi.tachidesk.config.server.systemTrayEnabled=false',
      '-Dsuwayomi.tachidesk.config.server.initialOpenInBrowserEnabled=false',
      '-jar',
      jarAbs,
    ];
  }

  String _normalizedRootPath(String path) {
    return path.replaceAll(r'\', '/');
  }

  Future<Result<SuwayomiStatus>> start({
    Duration readyTimeout = const Duration(minutes: 3),
  }) {
    return _serialized(() => _startBody(readyTimeout: readyTimeout));
  }

  Future<Result<SuwayomiStatus>> _startBody({
    required Duration readyTimeout,
  }) async {
    if (_shuttingDown) {
      const msg = 'Shutdown em andamento — start recusado.';
      _emit(
        const SuwayomiStatus(state: SuwayomiProcessState.crashed, message: msg),
      );
      return _failure(
        SuwayomiProcessFailureKind.stopUnconfirmed,
        'engine_shutdown_in_progress',
        msg,
      );
    }

    if (_process != null && _status.state == SuwayomiProcessState.running) {
      return Ok(_status);
    }

    // Phase 2D.2: memory identity / Process handle first — never a 2nd JVM.
    final existing = await _handleExistingOwnedIdentity(
      readyTimeout: readyTimeout,
    );
    if (existing != null) return existing;
    if (_shuttingDown) return _shutdownInProgressFailure();

    // After handle: still holding process or in-memory identity without a clean
    // stop → refuse (even if identity file is missing).
    if (_process != null || _identity != null) {
      final msg =
          'Processo/identidade em memória ainda ativa '
          '(state=${_status.state.name}, pid=${_process?.pid ?? _identity?.pid}). '
          'Start recusado — não iniciaremos outra JVM.';
      _emit(
        SuwayomiStatus(
          state: SuwayomiProcessState.unhealthy,
          message: msg,
          baseUrl: baseUrl,
          pid: _process?.pid ?? _identity?.pid,
        ),
      );
      return _failure(
        SuwayomiProcessFailureKind.ownershipUnverifiable,
        'engine_ownership_unverifiable',
        msg,
      );
    }

    // Phase 2D: never blind-adopt health-only foreign processes.
    final portIssue = await _resolvePortOccupantBeforeStart();
    if (_shuttingDown) return _shutdownInProgressFailure();
    if (portIssue != null) {
      _emit(
        SuwayomiStatus(
          state: SuwayomiProcessState.crashed,
          message: portIssue,
          baseUrl: baseUrl,
        ),
      );
      return _failure(
        SuwayomiProcessFailureKind.foreignPort,
        'engine_foreign_port',
        portIssue,
      );
    }

    _combinedLog.clear();
    _emit(
      const SuwayomiStatus(
        state: SuwayomiProcessState.starting,
        message: 'Preparando motor Suwayomi…',
      ),
    );

    final java = await javaResolver.resolve(
      paths: paths,
      minMajor: manifest.suwayomi.minJre,
    );
    if (_shuttingDown) return _shutdownInProgressFailure();
    if (java == null) {
      final msg =
          'Java ${manifest.suwayomi.minJre}+ não encontrado. '
          'Use o JRE empacotado (jre/ ao lado do .exe) ou o monorepo '
          r'vendor\jre21. Opcional: YOMU_JAVA_HOME como override explícito.';
      _emit(SuwayomiStatus(state: SuwayomiProcessState.crashed, message: msg));
      return _failure(
        SuwayomiProcessFailureKind.runtimeMissing,
        'engine_runtime_missing',
        msg,
      );
    }
    if (java.versionMajor < manifest.suwayomi.minJre) {
      final msg =
          'Java ${java.versionMajor} encontrado (${java.source}), '
          'mas Suwayomi exige ${manifest.suwayomi.minJre}+. '
          'O Yomu deve usar o JRE empacotado/runtime; não altere JAVA_HOME. '
          'Reinstale o app ou rode tool/bundle_jre_windows.ps1.';
      _emit(SuwayomiStatus(state: SuwayomiProcessState.crashed, message: msg));
      return _failure(
        SuwayomiProcessFailureKind.runtimeIncompatible,
        'engine_runtime_incompatible',
        msg,
      );
    }

    final jarResult = await ensureJar();
    if (_shuttingDown) return _shutdownInProgressFailure();
    Object? jarFailure;
    final jar = jarResult.when(
      ok: (f) => f,
      err: (m, cause) {
        jarFailure = cause;
        _emit(SuwayomiStatus(state: SuwayomiProcessState.crashed, message: m));
        return null;
      },
    );
    if (jar == null) {
      return Err(
        _status.message ?? 'JAR indisponível',
        jarFailure ??
            const SuwayomiProcessFailure(
              kind: SuwayomiProcessFailureKind.artifactMissing,
              code: 'engine_artifact_missing',
              message: 'Motor interno indisponível.',
            ),
      );
    }

    await writeManagedConfig();
    if (_shuttingDown) return _shutdownInProgressFailure();

    _logSink = paths.processLog.openWrite(mode: FileMode.append);
    final runId = _newRunId();
    final startedAt = DateTime.now().toUtc();
    final args = buildJavaArgs(jar, runId: runId, startedAt: startedAt);
    _logSink!.writeln(
      '\n--- start ${startedAt.toIso8601String()} '
      'runId=$runId java=${java.javaExecutable} ---\n'
      'rootDir=$managedRootDir\n'
      'args=${args.join(' ')}',
    );

    try {
      final starter =
          processStartForTest ??
          (
            String executable,
            List<String> arguments, {
            String? workingDirectory,
            Map<String, String>? environment,
            bool runInShell = false,
          }) => Process.start(
            executable,
            arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            runInShell: runInShell,
          );
      _process = await starter(
        java.javaExecutable,
        args,
        workingDirectory: paths.dataDir.path,
        environment: Map<String, String>.from(Platform.environment),
        runInShell: false,
      );
    } catch (e) {
      final msg = 'Falha ao iniciar processo Suwayomi: $e';
      _emit(SuwayomiStatus(state: SuwayomiProcessState.crashed, message: msg));
      return _failure(
        SuwayomiProcessFailureKind.launchFailed,
        'engine_launch_failed',
        msg,
        e,
      );
    }

    if (_shuttingDown) {
      await _stopBody(expectPortFree: true);
      return _shutdownInProgressFailure();
    }

    final pid = _process!.pid;
    final identity = ManagedInstanceIdentity(
      runId: runId,
      pid: pid,
      startedAt: startedAt,
      javaExecutable: File(java.javaExecutable).absolute.path,
      jarPath: jar.absolute.path,
      rootDir: Directory(managedRootDir).absolute.path,
      port: port,
    );
    try {
      final saver =
          identitySaveForTest ??
          (ManagedInstanceIdentity id, File file) => id.save(file);
      await saver(identity, identityFile);
      _identity = identity;
    } catch (e) {
      // Only forget Process after exitCode or a readable dead OS snapshot.
      _identity = identity;
      final orphaned = await _killAndConfirmExit(
        _process,
        pid: pid,
        expectedIdentity: identity,
      );
      if (orphaned) {
        // Keep Process handle + identity-like state — kill=false / timeout.
        final msg =
            'JVM pid $pid: falha ao salvar identidade e encerramento não confirmado '
            '(kill=false ou timeout). Handle preservado — possível órfão. Erro: $e';
        _emit(
          SuwayomiStatus(
            state: SuwayomiProcessState.unhealthy,
            message: msg,
            baseUrl: baseUrl,
            pid: pid,
          ),
        );
        return _failure(
          SuwayomiProcessFailureKind.ownershipUnverifiable,
          'engine_ownership_unverifiable',
          msg,
          e,
        );
      }
      _process = null;
      _identity = null;
      final msg =
          'JVM iniciada (pid $pid) mas falhou ao salvar identidade: $e. '
          'Encerramento do processo confirmado.';
      _emit(
        SuwayomiStatus(
          state: SuwayomiProcessState.crashed,
          message: msg,
          baseUrl: baseUrl,
        ),
      );
      return _failure(
        SuwayomiProcessFailureKind.ownershipUnverifiable,
        'engine_identity_persistence_failed',
        msg,
        e,
      );
    }

    if (_shuttingDown) {
      await _stopBody(expectPortFree: true);
      return _shutdownInProgressFailure();
    }

    final startedProcess = _process!;
    void onLog(String data) {
      _combinedLog.write(data);
      _logSink?.write(data);
    }

    startedProcess.stdout.transform(utf8.decoder).listen(onLog);
    startedProcess.stderr.transform(utf8.decoder).listen(onLog);
    unawaited(
      startedProcess.exitCode.then((code) async {
        _logSink?.writeln('--- exit code $code ---');
        if (_status.state != SuwayomiProcessState.stopping &&
            _status.state != SuwayomiProcessState.stopped &&
            !_shuttingDown) {
          final hint = _crashHintFromLog(_combinedLog.toString(), code);
          _emit(
            SuwayomiStatus(
              state: SuwayomiProcessState.crashed,
              message: hint,
              baseUrl: baseUrl,
            ),
          );
        }
        if (identical(_process, startedProcess)) _process = null;
      }),
    );

    _emit(
      SuwayomiStatus(
        state: SuwayomiProcessState.starting,
        message: 'Aguardando API Suwayomi em $baseUrl…',
        baseUrl: baseUrl,
        pid: pid,
        version: manifest.suwayomi.displayVersion,
      ),
    );

    final ready = await _waitUntilHealthy(readyTimeout);
    if (!ready) {
      await _stopBody(expectPortFree: true);
      if (_shuttingDown) return _shutdownInProgressFailure();
      final msg =
          'Timeout aguardando health do Suwayomi em $baseUrl. '
          'Verifique Java, porta $port e ${paths.processLog.path}';
      _emit(SuwayomiStatus(state: SuwayomiProcessState.crashed, message: msg));
      return _failure(
        SuwayomiProcessFailureKind.readinessTimeout,
        'engine_start_timeout',
        msg,
      );
    }

    final isolation = await verifyManagedDataRoot();
    if (!isolation.isOk) {
      await _stopBody(expectPortFree: true);
      final msg =
          isolation.message ??
          'Isolamento falhou: data root não é o diretório gerenciado pelo Yomu.';
      _emit(SuwayomiStatus(state: SuwayomiProcessState.crashed, message: msg));
      return _failure(
        SuwayomiProcessFailureKind.rootMismatch,
        'engine_root_mismatch',
        msg,
      );
    }
    if (_shuttingDown) {
      await _stopBody(expectPortFree: true);
      return _shutdownInProgressFailure();
    }

    final ok = SuwayomiStatus(
      state: SuwayomiProcessState.running,
      message:
          'Suwayomi pronto (isolado em ${paths.dataDir.path}, loopback $host:$port)',
      baseUrl: baseUrl,
      pid: pid,
      version: manifest.suwayomi.displayVersion,
      lastHealthCheck: DateTime.now(),
    );
    _emit(ok);
    return Ok(ok);
  }

  /// If in-memory or on-disk identity points at a live Yomu-owned process,
  /// wait/reattach or stop with ownership — never start a second JVM.
  ///
  /// **In-memory [identity] is preferred** over the identity file.
  ///
  /// Returns a [Result] when handled; null when caller may proceed to start.
  Future<Result<SuwayomiStatus>?> _handleExistingOwnedIdentity({
    required Duration readyTimeout,
  }) async {
    // Memory first — covers save-fail orphan without a durable file.
    final stored =
        _identity ?? await ManagedInstanceIdentity.load(identityFile);
    if (stored == null) {
      if (_process != null) {
        return _failure(
          SuwayomiProcessFailureKind.ownershipUnverifiable,
          'engine_ownership_unverifiable',
          'Handle de Process em memória (pid ${_process!.pid}) sem identidade '
              'gravada — start recusado.',
        );
      }
      return null;
    }

    final expectedRoot = Directory(managedRootDir).absolute.path;
    if (!_sameAbsolutePath(stored.rootDir, expectedRoot) ||
        stored.port != port) {
      return _failure(
        SuwayomiProcessFailureKind.rootMismatch,
        'engine_root_mismatch',
        'A identidade existente pertence a outro root ou porta. Start recusado.',
      );
    }
    final expectedJar = paths.jarFile(manifest.suwayomi.jarFile).absolute.path;
    if (!_sameAbsolutePath(stored.jarPath, expectedJar)) {
      return _failure(
        SuwayomiProcessFailureKind.ownershipUnverifiable,
        'engine_artifact_identity_mismatch',
        'A identidade existente não corresponde ao artefato pinado.',
      );
    }

    final check = await _ownership.verifyIdentity(stored);
    if (check.verdict == OwnershipVerdict.dead) {
      final healthy = await createClient().isHealthy();
      final listener = await _ownership.probe.findListenerPid(port);
      if (!healthy && listener == null) {
        await ManagedInstanceIdentity.clear(identityFile);
        _identity = null;
        _process = null;
        return null;
      }
      // Dead PID but port/health still busy — do not spawn another JVM.
      return _failure(
        SuwayomiProcessFailureKind.ownershipUnverifiable,
        'engine_ownership_unverifiable',
        check.message ??
            'Identidade aponta para PID morto, mas porta/health ainda ativos. '
                'Start recusado.',
      );
    }

    if (check.verdict != OwnershipVerdict.yomuOwned) {
      // Memory Process/identity without revalidated ownership — never spawn.
      if (_process != null || _identity != null) {
        return _failure(
          SuwayomiProcessFailureKind.ownershipUnverifiable,
          'engine_ownership_unverifiable',
          'Processo/identidade em memória (pid ${stored.pid}) não revalidável '
              '(${check.message ?? 'foreignOrUnverifiable'}). Start recusado — '
              'não iniciaremos outra JVM.',
        );
      }
      return _failure(
        SuwayomiProcessFailureKind.ownershipUnverifiable,
        'engine_ownership_unverifiable',
        check.message ??
            'Identidade em disco não confere com o processo vivo. '
                'Não iniciaremos outra JVM nem sobrescreveremos a identidade.',
      );
    }

    // Owned and alive: wait for health (pending startup) without spawning.
    _identity = stored;
    _emit(
      SuwayomiStatus(
        state: SuwayomiProcessState.starting,
        message:
            'Instância Yomu (pid ${stored.pid}) ainda viva — aguardando API…',
        baseUrl: baseUrl,
        pid: stored.pid,
        version: manifest.suwayomi.displayVersion,
      ),
    );

    final ready = await _waitUntilHealthy(readyTimeout);
    if (ready) {
      final currentOwnership = await verifyCurrentOwnership();
      if (currentOwnership.verdict != OwnershipVerdict.yomuOwned) {
        return _failure(
          SuwayomiProcessFailureKind.ownershipUnverifiable,
          'engine_ownership_unverifiable',
          currentOwnership.message ??
              'O processo owned deixou de controlar a porta gerenciada.',
        );
      }
      final isolation = await verifyManagedDataRoot();
      if (!isolation.isOk) {
        return _failure(
          SuwayomiProcessFailureKind.rootMismatch,
          'engine_root_mismatch',
          isolation.message ?? 'O root ativo não corresponde ao root do Yomu.',
        );
      }
      if (_shuttingDown) return _shutdownInProgressFailure();
      final ok = SuwayomiStatus(
        state: SuwayomiProcessState.running,
        message:
            'Suwayomi reaproveitado (pid ${stored.pid}, ownership Yomu verificado).',
        baseUrl: baseUrl,
        pid: stored.pid,
        version: manifest.suwayomi.displayVersion,
        lastHealthCheck: DateTime.now(),
      );
      _emit(ok);
      return Ok(ok);
    }

    if (_shuttingDown) return _shutdownInProgressFailure();

    // Recovery ownership and backoff belong to ReadingEngineSupervisor.
    const msg =
        'Instância Yomu-owned ainda não respondeu dentro do prazo. '
        'Identidade preservada para recovery supervisionado.';
    _emit(
      SuwayomiStatus(
        state: SuwayomiProcessState.unhealthy,
        message: msg,
        baseUrl: baseUrl,
        pid: stored.pid,
      ),
    );
    return _failure(
      SuwayomiProcessFailureKind.readinessTimeout,
      'engine_owned_not_ready',
      msg,
    );
  }

  bool _sameAbsolutePath(String left, String right) =>
      p.normalize(File(left).absolute.path).toLowerCase() ==
      p.normalize(File(right).absolute.path).toLowerCase();

  Err<SuwayomiStatus> _shutdownInProgressFailure() => _failure(
    SuwayomiProcessFailureKind.stopUnconfirmed,
    'engine_shutdown_in_progress',
    'Shutdown em andamento — start recusado.',
  );

  /// Returns error message if port cannot be used; null if free.
  Future<String?> _resolvePortOccupantBeforeStart() async {
    final healthy = await createClient().isHealthy();
    final listenerPid = await _ownership.probe.findListenerPid(port);
    if (!healthy && listenerPid == null) {
      return null;
    }

    // Port/health busy without a handled owned identity → refuse.
    final who = listenerPid != null
        ? 'PID $listenerPid'
        : 'processo desconhecido';
    return 'Porta $port já em uso ($who) e não foi possível provar ownership Yomu. '
        'Não será adotado nem encerrado. Feche a outra instância de Suwayomi '
        'ou libere a porta, depois tente de novo.';
  }

  Future<({bool isOk, String? message, String? observedRoot})>
  verifyManagedDataRoot() async {
    final expected = _normalizedRootPath(managedRootDir).toLowerCase();
    final expectedNative = managedRootDir.toLowerCase();

    String? fromLog = _parseDataRootFromLog(_combinedLog.toString());
    if (fromLog == null && paths.processLog.existsSync()) {
      fromLog = _parseDataRootFromLog(await paths.processLog.readAsString());
    }

    final managedConf = File(p.join(paths.dataDir.path, 'server.conf'));
    final hasManagedArtifacts =
        managedConf.existsSync() ||
        Directory(
          paths.dataDir.path,
        ).listSync().any((e) => p.basename(e.path).startsWith('database'));

    if (fromLog != null) {
      final observed = _normalizedRootPath(fromLog).toLowerCase();
      final matches =
          observed == expected ||
          observed.replaceAll('/', r'\').toLowerCase() ==
              expectedNative.replaceAll('/', r'\').toLowerCase() ||
          _pathsEqual(fromLog, managedRootDir);
      if (!matches) {
        return (
          isOk: false,
          message:
              'Data root real ($fromLog) ≠ managed Yomu ($managedRootDir). '
              'Isolamento falhou — start abortado.',
          observedRoot: fromLog,
        );
      }
      return (isOk: true, message: null, observedRoot: fromLog);
    }

    if (!hasManagedArtifacts) {
      return (
        isOk: false,
        message:
            'Não foi possível confirmar data root (log sem '
            '"Data Root directory is set to") e o dir managed não tem '
            'server.conf/database. Isolamento falhou.',
        observedRoot: null,
      );
    }

    return (isOk: true, message: null, observedRoot: managedRootDir);
  }

  bool _pathsEqual(String a, String b) {
    final na = p.normalize(a).replaceAll(r'\', '/').toLowerCase();
    final nb = p.normalize(b).replaceAll(r'\', '/').toLowerCase();
    return na == nb;
  }

  String? _parseDataRootFromLog(String log) {
    final re = RegExp(
      r'Data Root directory is set to:\s*(.+)$',
      multiLine: true,
      caseSensitive: false,
    );
    final match = re.firstMatch(log);
    if (match == null) return null;
    return match.group(1)!.trim();
  }

  String _crashHintFromLog(String log, int code) {
    if (log.contains('MutexCheckFailedTachideskRunning') ||
        log.contains('Another instance of Suwayomi-Server is running')) {
      return 'Porta $port já em uso por outro Suwayomi. '
          'Ownership não verificado — encerre a instância estrangeira manualmente. '
          '(code $code)';
    }
    return 'Suwayomi encerrou inesperadamente (code $code). '
        'Veja ${paths.processLog.path}';
  }

  /// Returns true if process may still be alive (orphan risk).
  ///
  /// Never pretends the process is gone without [Process.exitCode] or a
  /// readable OS snapshot that explicitly reports the expected PID as dead.
  Future<bool> _killAndConfirmExit(
    Process? proc, {
    required int pid,
    required ManagedInstanceIdentity? expectedIdentity,
  }) async {
    final override = killAndConfirmExitForTest;
    if (override != null) return override(proc, pid: pid);

    if (proc != null) {
      var sent = false;
      try {
        sent = proc.kill(ProcessSignal.sigterm);
      } catch (_) {
        sent = false;
      }
      if (sent) {
        try {
          await proc.exitCode.timeout(const Duration(seconds: 5));
          return false;
        } on TimeoutException {
          var forced = false;
          try {
            forced = proc.kill(ProcessSignal.sigkill);
          } catch (_) {
            forced = false;
          }
          if (forced) {
            try {
              await proc.exitCode.timeout(const Duration(seconds: 5));
              return false;
            } on TimeoutException {
              return true;
            } catch (_) {
              return true;
            }
          }
          // kill=false on force — still try OS below, but prefer not lying.
        } catch (_) {
          // fall through to OS kill
        }
      }
    }

    // A failed Process.kill must never degrade directly to taskkill/killPid by
    // numeric PID. The PID may have been reused, or OS inspection may be
    // unavailable. Re-prove the exact persisted identity immediately before
    // the fallback and fail closed when that proof is absent.
    final identity = expectedIdentity;
    if (identity == null || identity.pid != pid) return true;
    final beforeFallback = await _ownership.verifyIdentity(identity);
    if (beforeFallback.verdict == OwnershipVerdict.dead) return false;
    if (beforeFallback.verdict != OwnershipVerdict.yomuOwned) return true;

    await _ownership.probe.killOwnedPid(pid, force: true);
    final confirmed = await _confirmExpectedProcessExited(identity);
    return !confirmed;
  }

  Future<bool> _confirmExpectedProcessExited(
    ManagedInstanceIdentity identity,
  ) async {
    for (var i = 0; i < 10; i++) {
      final check = await _ownership.verifyIdentity(identity);
      if (check.verdict == OwnershipVerdict.dead) return true;
      if (check.verdict != OwnershipVerdict.yomuOwned) return false;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  Future<bool> _waitUntilHealthy(Duration timeout) async {
    final client = createClient();
    final deadline = DateTime.now().add(timeout);
    while (!_shuttingDown && DateTime.now().isBefore(deadline)) {
      if (_process == null && _identity == null) return false;
      final healthy = await client.isHealthy();
      if (healthy) return true;
      // Short sleep; isHealthy already has its own timeouts.
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) break;
      await Future<void>.delayed(
        remaining < const Duration(milliseconds: 200)
            ? remaining
            : const Duration(milliseconds: 200),
      );
    }
    return false;
  }

  Future<bool> _waitPortAndHealthDown(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final listener = await _ownership.probe.findListenerPid(port);
      if (listener == null) {
        final healthy = await createClient().isHealthy();
        if (!healthy) return true;
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) break;
      await Future<void>.delayed(
        remaining < const Duration(milliseconds: 200)
            ? remaining
            : const Duration(milliseconds: 200),
      );
    }
    final healthy = await createClient().isHealthy();
    final listener = await _ownership.probe.findListenerPid(port);
    return !healthy && listener == null;
  }

  Future<void> stop() => _serialized(() => _stopBody(expectPortFree: true));

  Future<void> _stopBody({required bool expectPortFree}) async {
    _emit(
      _status.copyWith(
        state: SuwayomiProcessState.stopping,
        message: 'Parando Suwayomi…',
      ),
    );

    final proc = _process;
    if (proc != null) {
      final expectedIdentity =
          _identity ?? await ManagedInstanceIdentity.load(identityFile);
      _identity ??= expectedIdentity;
      final orphaned = await _killAndConfirmExit(
        proc,
        pid: proc.pid,
        expectedIdentity: expectedIdentity,
      );
      if (orphaned) {
        await _logSink?.close();
        _logSink = null;
        _emit(
          SuwayomiStatus(
            state: SuwayomiProcessState.unhealthy,
            message:
                'Stop incompleto: não foi possível confirmar o encerramento '
                'do processo ${proc.pid}. Identidade e handle preservados para retry.',
            baseUrl: baseUrl,
            pid: proc.pid,
          ),
        );
        return;
      }
      _process = null;
    } else {
      // No Process handle — only kill if identity is Yomu-owned.
      final id = _identity ?? await ManagedInstanceIdentity.load(identityFile);
      if (id != null) {
        _identity ??= id;
        final orphaned = await _killAndConfirmExit(
          null,
          pid: id.pid,
          expectedIdentity: id,
        );
        if (orphaned) {
          final msg =
              'Stop recusado: ownership ou encerramento do PID ${id.pid} '
              'não pôde ser confirmado. Identidade preservada para retry.';
          _emit(
            SuwayomiStatus(
              state: SuwayomiProcessState.unhealthy,
              message: msg,
              baseUrl: baseUrl,
              pid: id.pid,
            ),
          );
          return;
        }
      }
    }

    final down = await _waitPortAndHealthDown(const Duration(seconds: 15));
    await _logSink?.close();
    _logSink = null;

    if (!down && expectPortFree) {
      // Preserve identity file for retry/diagnosis — do NOT clear.
      _emit(
        SuwayomiStatus(
          state: SuwayomiProcessState.unhealthy,
          message:
              'Stop incompleto: a porta $port ou o health ainda respondem. '
              'Identidade preservada para retry. Estado não marcado como stopped.',
          baseUrl: baseUrl,
          pid: _identity?.pid,
        ),
      );
      return;
    }

    await ManagedInstanceIdentity.clear(identityFile);
    _identity = null;

    _emit(
      const SuwayomiStatus(
        state: SuwayomiProcessState.stopped,
        message: 'Suwayomi parado',
      ),
    );
  }

  Future<Result<SuwayomiStatus>> restart() {
    return _serialized(() async {
      await _stopBody(expectPortFree: true);
      if (_status.state != SuwayomiProcessState.stopped) {
        final message = _status.message ?? 'Restart abortado: stop incompleto';
        return _failure(
          SuwayomiProcessFailureKind.stopUnconfirmed,
          'engine_stop_unconfirmed',
          message,
        );
      }
      return _startBody(readyTimeout: const Duration(minutes: 3));
    });
  }

  Future<bool> checkHealth() async {
    final healthy = await createClient().isHealthy();
    if (_status.state == SuwayomiProcessState.running && !healthy) {
      _emit(
        _status.copyWith(
          state: SuwayomiProcessState.unhealthy,
          message: 'API Suwayomi não responde',
          lastHealthCheck: DateTime.now(),
        ),
      );
    } else if (healthy && _status.state == SuwayomiProcessState.running) {
      _emit(_status.copyWith(lastHealthCheck: DateTime.now()));
    }
    // Do not flip foreign health into "running" without our process.
    return healthy;
  }

  /// Coordinated shutdown for app close — await this instead of dispose alone.
  Future<void> shutdown() {
    beginShutdown();
    return _serialized(() async {
      await _stopBody(expectPortFree: true);
    });
  }

  Future<void> closeAfterShutdown() async {
    if (_status.state != SuwayomiProcessState.stopped) {
      throw const SuwayomiProcessFailure(
        kind: SuwayomiProcessFailureKind.stopUnconfirmed,
        code: 'engine_stop_unconfirmed',
        message: 'O encerramento do processo owned não foi confirmado.',
      );
    }
    if (!_controller.isClosed) await _controller.close();
    _http.close();
  }

  /// Fallback only — prefer [shutdown] from UI.
  Future<void> dispose() async {
    try {
      await shutdown();
    } catch (_) {}
    if (_status.state == SuwayomiProcessState.stopped) {
      await closeAfterShutdown();
    }
  }

  String _newRunId() {
    final r = Random.secure();
    final n = List.generate(8, (_) => r.nextInt(256));
    return n.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
