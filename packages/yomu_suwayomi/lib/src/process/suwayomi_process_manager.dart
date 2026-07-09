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

/// Default loopback port dedicated to Yomu-managed Suwayomi.
const int kYomuSuwayomiPort = 14567;

/// System property confirmed in Suwayomi-Server v2.3.2238 bytecode.
const String kSuwayomiRootDirProperty =
    'suwayomi.tachidesk.config.server.rootDir';

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
    this.host = '127.0.0.1',
    this.port = kYomuSuwayomiPort,
    ProcessOwnershipProbe? ownershipProbe,
    http.Client? httpClient,
  })  : _http = httpClient ?? http.Client(),
        _ownership = ProcessOwnership(
          ownershipProbe ?? const PlatformProcessOwnershipProbe(),
        );

  final SuwayomiPaths paths;
  final VendorManifest manifest;
  final JavaResolver javaResolver;
  final String host;
  final int port;
  final http.Client _http;
  final ProcessOwnership _ownership;

  Process? _process;
  ManagedInstanceIdentity? _identity;
  IOSink? _logSink;
  final StringBuffer _combinedLog = StringBuffer();
  SuwayomiStatus _status =
      const SuwayomiStatus(state: SuwayomiProcessState.stopped);
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

  void _emit(SuwayomiStatus next) {
    _status = next;
    if (!_controller.isClosed) _controller.add(next);
  }

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

  Future<Result<File>> ensureJar({bool downloadIfMissing = true}) async {
    await paths.ensureLayout();
    final jar = paths.jarFile(manifest.suwayomi.jarFile);
    final expected = manifest.suwayomi.sha256;

    if (jar.existsSync()) {
      final ok = await _verifySha256(jar, expected);
      if (ok) return Ok(jar);
      await jar.delete();
    }

    final seed = await _findSeedJar();
    if (seed != null) {
      final ok = await _verifySha256(seed, expected);
      if (!ok) {
        return Err(
          'JAR seed encontrado mas SHA-256 inválido: ${seed.path}',
        );
      }
      await seed.copy(jar.path);
      await paths.vendorManifestCopy.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      );
      return Ok(jar);
    }

    if (!downloadIfMissing) {
      return Err(
        'Suwayomi JAR ausente ou hash inválido: ${jar.path}',
      );
    }

    _emit(
      _status.copyWith(
        state: SuwayomiProcessState.starting,
        message: 'Baixando Suwayomi ${manifest.suwayomi.displayVersion}…',
      ),
    );

    try {
      final response =
          await _http.get(Uri.parse(manifest.suwayomi.downloadUrl));
      if (response.statusCode != 200) {
        return Err(
          'Falha ao baixar Suwayomi (HTTP ${response.statusCode}).',
        );
      }
      await jar.writeAsBytes(response.bodyBytes, flush: true);
      final ok = await _verifySha256(jar, expected);
      if (!ok) {
        await jar.delete();
        return const Err(
          'Checksum SHA-256 do JAR Suwayomi não confere com o manifest pinado.',
        );
      }
      await paths.vendorManifestCopy.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      );
      return Ok(jar);
    } catch (e) {
      return Err('Erro ao obter Suwayomi JAR: $e', e);
    }
  }

  Future<File?> _findSeedJar() async {
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

  Future<bool> _verifySha256(File file, String expectedHex) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == expectedHex.toLowerCase();
  }

  Future<void> writeManagedConfig() async {
    await paths.ensureLayout();
    final conf = '''
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

  List<String> buildJavaArgs(File jar) {
    final root = _normalizedRootPath(managedRootDir);
    return [
      '-D$kSuwayomiRootDirProperty=$root',
      '-Dsuwayomi.tachidesk.config.server.ip=$host',
      '-Dsuwayomi.tachidesk.config.server.port=$port',
      '-Dsuwayomi.tachidesk.config.server.systemTrayEnabled=false',
      '-Dsuwayomi.tachidesk.config.server.initialOpenInBrowserEnabled=false',
      '-jar',
      jar.path,
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
      _emit(const SuwayomiStatus(
        state: SuwayomiProcessState.crashed,
        message: msg,
      ));
      return const Err(msg);
    }

    if (_process != null && _status.state == SuwayomiProcessState.running) {
      return Ok(_status);
    }

    // Phase 2D: never blind-adopt health-only.
    final portIssue = await _resolvePortOccupantBeforeStart();
    if (portIssue != null) {
      _emit(SuwayomiStatus(
        state: SuwayomiProcessState.crashed,
        message: portIssue,
        baseUrl: baseUrl,
      ));
      return Err(portIssue);
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
    if (java == null) {
      final msg =
          'Java ${manifest.suwayomi.minJre}+ não encontrado. '
          'Instale um JRE ${manifest.suwayomi.minJre}+ ou use o runtime embutido do Yomu.';
      _emit(SuwayomiStatus(state: SuwayomiProcessState.crashed, message: msg));
      return Err(msg);
    }
    if (java.versionMajor < manifest.suwayomi.minJre) {
      final msg =
          'Java ${java.versionMajor} encontrado (${java.source}), '
          'mas Suwayomi exige ${manifest.suwayomi.minJre}+.';
      _emit(SuwayomiStatus(state: SuwayomiProcessState.crashed, message: msg));
      return Err(msg);
    }

    final jarResult = await ensureJar();
    final jar = jarResult.when(
      ok: (f) => f,
      err: (m, _) {
        _emit(SuwayomiStatus(state: SuwayomiProcessState.crashed, message: m));
        return null;
      },
    );
    if (jar == null) {
      return Err(_status.message ?? 'JAR indisponível');
    }

    await writeManagedConfig();

    _logSink = paths.processLog.openWrite(mode: FileMode.append);
    final args = buildJavaArgs(jar);
    final runId = _newRunId();
    _logSink!.writeln(
      '\n--- start ${DateTime.now().toIso8601String()} '
      'runId=$runId java=${java.javaExecutable} ---\n'
      'rootDir=$managedRootDir\n'
      'args=${args.join(' ')}',
    );

    try {
      _process = await Process.start(
        java.javaExecutable,
        args,
        workingDirectory: paths.dataDir.path,
        environment: Map<String, String>.from(Platform.environment),
        runInShell: false,
      );
    } catch (e) {
      final msg = 'Falha ao iniciar processo Suwayomi: $e';
      _emit(SuwayomiStatus(state: SuwayomiProcessState.crashed, message: msg));
      return Err(msg, e);
    }

    final pid = _process!.pid;
    _identity = ManagedInstanceIdentity(
      runId: runId,
      pid: pid,
      startedAt: DateTime.now(),
      javaExecutable: java.javaExecutable,
      jarPath: jar.absolute.path,
      rootDir: managedRootDir,
      port: port,
    );
    await _identity!.save(identityFile);

    void onLog(String data) {
      _combinedLog.write(data);
      _logSink?.write(data);
    }

    _process!.stdout.transform(utf8.decoder).listen(onLog);
    _process!.stderr.transform(utf8.decoder).listen(onLog);
    unawaited(_process!.exitCode.then((code) async {
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
      _process = null;
    }));

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
      final msg =
          'Timeout aguardando health do Suwayomi em $baseUrl. '
          'Verifique Java, porta $port e ${paths.processLog.path}';
      _emit(SuwayomiStatus(state: SuwayomiProcessState.crashed, message: msg));
      return Err(msg);
    }

    final isolation = await verifyManagedDataRoot();
    if (!isolation.isOk) {
      await _stopBody(expectPortFree: true);
      final msg = isolation.message ??
          'Isolamento falhou: data root não é o diretório gerenciado pelo Yomu.';
      _emit(SuwayomiStatus(state: SuwayomiProcessState.crashed, message: msg));
      return Err(msg);
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

  /// Returns error message if port cannot be used; null if free (or Yomu orphan cleared).
  Future<String?> _resolvePortOccupantBeforeStart() async {
    final healthy = await createClient().isHealthy();
    final listenerPid = await _ownership.probe.findListenerPid(port);
    if (!healthy && listenerPid == null) {
      // Clear stale identity if dead.
      final stored = await ManagedInstanceIdentity.load(identityFile);
      if (stored != null) {
        final check = await _ownership.verifyIdentity(stored);
        if (check.verdict == OwnershipVerdict.dead) {
          await ManagedInstanceIdentity.clear(identityFile);
          _identity = null;
        }
      }
      return null;
    }

    // Something is up — only act if we can prove Yomu ownership.
    final stored = await ManagedInstanceIdentity.load(identityFile);
    if (stored != null) {
      final check = await _ownership.verifyIdentity(stored);
      if (check.verdict == OwnershipVerdict.yomuOwned) {
        _logSink?.writeln(
          'Yomu orphan PID ${stored.pid} validated — stopping before restart',
        );
        final killed =
            await _ownership.probe.killOwnedPid(stored.pid, force: true);
        if (!killed) {
          return 'Órfão Yomu PID ${stored.pid} validado, mas falhou ao encerrar. '
              'Encerre manualmente e tente de novo.';
        }
        final freed = await _waitPortAndHealthDown(
          const Duration(seconds: 20),
        );
        await ManagedInstanceIdentity.clear(identityFile);
        _identity = null;
        if (!freed) {
          return 'Órfão Yomu encerrado, mas a porta $port ainda responde. '
              'Aguarde e tente de novo.';
        }
        return null;
      }
      if (check.verdict == OwnershipVerdict.dead && listenerPid == null && !healthy) {
        await ManagedInstanceIdentity.clear(identityFile);
        return null;
      }
    }

    // Foreign / unverifiable: do NOT kill, do NOT adopt.
    final who = listenerPid != null ? 'PID $listenerPid' : 'processo desconhecido';
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
    final hasManagedArtifacts = managedConf.existsSync() ||
        Directory(paths.dataDir.path)
            .listSync()
            .any((e) => p.basename(e.path).startsWith('database'));

    if (fromLog != null) {
      final observed = _normalizedRootPath(fromLog).toLowerCase();
      final matches = observed == expected ||
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

    return (
      isOk: true,
      message: null,
      observedRoot: managedRootDir,
    );
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

  Future<bool> _waitUntilHealthy(Duration timeout) async {
    final client = createClient();
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_process == null && _identity == null) return false;
      final healthy = await client.isHealthy();
      if (healthy) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<bool> _waitPortAndHealthDown(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final healthy = await createClient().isHealthy();
      final listener = await _ownership.probe.findListenerPid(port);
      if (!healthy && listener == null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 300));
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
      proc.kill(ProcessSignal.sigterm);
      try {
        await proc.exitCode.timeout(const Duration(seconds: 8));
      } on TimeoutException {
        proc.kill(ProcessSignal.sigkill);
        try {
          await proc.exitCode.timeout(const Duration(seconds: 3));
        } catch (_) {}
      }
      _process = null;
    } else {
      // No Process handle — only kill if identity is Yomu-owned.
      final id = _identity ?? await ManagedInstanceIdentity.load(identityFile);
      if (id != null) {
        final check = await _ownership.verifyIdentity(id);
        if (check.verdict == OwnershipVerdict.yomuOwned) {
          await _ownership.probe.killOwnedPid(id.pid, force: true);
        } else if (check.verdict == OwnershipVerdict.foreignOrUnverifiable) {
          final msg = check.message ??
              'Stop recusado: processo na porta não é ownership Yomu verificável.';
          _emit(SuwayomiStatus(
            state: SuwayomiProcessState.unhealthy,
            message: msg,
            baseUrl: baseUrl,
          ));
          return;
        }
      }
    }

    final down = await _waitPortAndHealthDown(const Duration(seconds: 15));
    await _logSink?.close();
    _logSink = null;
    await ManagedInstanceIdentity.clear(identityFile);
    _identity = null;

    if (!down && expectPortFree) {
      _emit(
        SuwayomiStatus(
          state: SuwayomiProcessState.unhealthy,
          message:
              'Stop incompleto: a porta $port ou o health ainda respondem. '
              'Estado não marcado como stopped.',
          baseUrl: baseUrl,
        ),
      );
      return;
    }

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
        return Err(_status.message ?? 'Restart abortado: stop incompleto');
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
    return _serialized(() async {
      _shuttingDown = true;
      await _stopBody(expectPortFree: true);
    });
  }

  /// Fallback only — prefer [shutdown] from UI.
  Future<void> dispose() async {
    try {
      await shutdown();
    } catch (_) {}
    if (!_controller.isClosed) await _controller.close();
    _http.close();
  }

  String _newRunId() {
    final r = Random.secure();
    final n = List.generate(8, (_) => r.nextInt(256));
    return n.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
