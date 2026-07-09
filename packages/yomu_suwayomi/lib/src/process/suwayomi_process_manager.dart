import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:yomu_core/yomu_core.dart';

import '../client/suwayomi_client.dart';
import '../config/suwayomi_paths.dart';
import '../config/vendor_manifest.dart';
import '../java/java_resolver.dart';

typedef StatusListener = void Function(SuwayomiStatus status);

/// Default loopback port dedicated to Yomu-managed Suwayomi.
///
/// Avoids colliding with a standalone Suwayomi on 4567.
const int kYomuSuwayomiPort = 14567;

/// System property confirmed in Suwayomi-Server v2.3.2238 bytecode
/// (`ApplicationRootDirKt` → `suwayomi.tachidesk.config.server.rootDir`).
const String kSuwayomiRootDirProperty =
    'suwayomi.tachidesk.config.server.rootDir';

/// Starts, monitors and stops a loopback-only Suwayomi-Server process.
///
/// Hard isolation rules:
/// - Never read/write/patch `%LOCALAPPDATA%\\Tachidesk`.
/// - JVM `-D` system properties must be **before** `-jar`.
/// - Data root is [SuwayomiPaths.dataDir] only.
/// - Start fails if the real data root is not the managed directory.
class SuwayomiProcessManager {
  SuwayomiProcessManager({
    required this.paths,
    required this.manifest,
    this.javaResolver = const JavaResolver(),
    this.host = '127.0.0.1',
    this.port = kYomuSuwayomiPort,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final SuwayomiPaths paths;
  final VendorManifest manifest;
  final JavaResolver javaResolver;
  final String host;
  final int port;
  final http.Client _http;

  Process? _process;
  IOSink? _logSink;
  final StringBuffer _combinedLog = StringBuffer();
  SuwayomiStatus _status =
      const SuwayomiStatus(state: SuwayomiProcessState.stopped);
  final _controller = StreamController<SuwayomiStatus>.broadcast();

  SuwayomiStatus get status => _status;
  Stream<SuwayomiStatus> get statusStream => _controller.stream;

  String get baseUrl => 'http://$host:$port';

  /// Absolute managed data root (Suwayomi `server.rootDir`).
  String get managedRootDir => paths.dataDir.absolute.path;

  SuwayomiClient createClient() =>
      SuwayomiClient(baseUrl: baseUrl, httpClient: _http);

  void _emit(SuwayomiStatus next) {
    _status = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  /// Ensures JAR is present and SHA-256 matches the pinned manifest.
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

  /// Writes seed config **only** under the managed Yomu data dir.
  ///
  /// Never touches `%LOCALAPPDATA%\Tachidesk`.
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
    final managedConf =
        File(p.join(paths.dataDir.path, 'server.conf'));
    await managedConf.writeAsString(conf);
    // Mirror for Yomu diagnostics only (still outside Tachidesk AppData).
    await paths.serverConf.writeAsString(conf);
  }

  /// JVM args: all `-D` system properties **before** `-jar`.
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
    // Suwayomi/Typesafe accept forward slashes on Windows.
    return path.replaceAll(r'\', '/');
  }

  Future<Result<SuwayomiStatus>> start({
    Duration readyTimeout = const Duration(minutes: 3),
  }) async {
    if (_process != null) {
      return Ok(_status);
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
    _logSink!.writeln(
      '\n--- start ${DateTime.now().toIso8601String()} '
      'java=${java.javaExecutable} ---\n'
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

    void onLog(String data) {
      _combinedLog.write(data);
      _logSink?.write(data);
    }

    _process!.stdout.transform(utf8.decoder).listen(onLog);
    _process!.stderr.transform(utf8.decoder).listen(onLog);
    unawaited(_process!.exitCode.then((code) {
      _logSink?.writeln('--- exit code $code ---');
      if (_status.state != SuwayomiProcessState.stopping &&
          _status.state != SuwayomiProcessState.stopped) {
        _emit(
          SuwayomiStatus(
            state: SuwayomiProcessState.crashed,
            message:
                'Suwayomi encerrou inesperadamente (code $code). Veja logs/suwayomi.log',
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
        pid: _process!.pid,
        version: manifest.suwayomi.displayVersion,
      ),
    );

    final ready = await _waitUntilHealthy(readyTimeout);
    if (!ready) {
      await stop();
      final msg =
          'Timeout aguardando health do Suwayomi em $baseUrl. '
          'Verifique Java, porta $port e ${paths.processLog.path}';
      _emit(SuwayomiStatus(state: SuwayomiProcessState.crashed, message: msg));
      return Err(msg);
    }

    final isolation = await verifyManagedDataRoot();
    if (!isolation.isOk) {
      await stop();
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
      pid: _process?.pid,
      version: manifest.suwayomi.displayVersion,
      lastHealthCheck: DateTime.now(),
    );
    _emit(ok);
    return Ok(ok);
  }

  /// Verifies real data root is the Yomu managed directory.
  ///
  /// Uses log line `Data Root directory is set to:` and on-disk artifacts.
  Future<({bool isOk, String? message, String? observedRoot})>
      verifyManagedDataRoot() async {
    final expected = _normalizedRootPath(managedRootDir).toLowerCase();
    final expectedNative = managedRootDir.toLowerCase();

    // Give the log a moment to flush the data-root line if it arrived late.
    String? fromLog = _parseDataRootFromLog(_combinedLog.toString());
    if (fromLog == null && paths.processLog.existsSync()) {
      fromLog = _parseDataRootFromLog(await paths.processLog.readAsString());
    }

    // On-disk proof: Suwayomi creates server.conf / database under rootDir.
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
      if (!hasManagedArtifacts) {
        // Log ok but empty dir is suspicious; still accept if log matches.
        return (
          isOk: true,
          message: null,
          observedRoot: fromLog,
        );
      }
      return (isOk: true, message: null, observedRoot: fromLog);
    }

    // Fallback without log line: require managed artifacts AND no exclusive
    // reliance on global Tachidesk (we still require managed conf/db).
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

  Future<bool> _waitUntilHealthy(Duration timeout) async {
    final client = createClient();
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_process == null) return false;
      final healthy = await client.isHealthy();
      if (healthy) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<void> stop() async {
    final proc = _process;
    if (proc == null) {
      _emit(const SuwayomiStatus(state: SuwayomiProcessState.stopped));
      return;
    }
    _emit(
      _status.copyWith(
        state: SuwayomiProcessState.stopping,
        message: 'Parando Suwayomi…',
      ),
    );
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
    await _logSink?.close();
    _logSink = null;
    _emit(
      const SuwayomiStatus(
        state: SuwayomiProcessState.stopped,
        message: 'Suwayomi parado',
      ),
    );
  }

  Future<Result<SuwayomiStatus>> restart() async {
    await stop();
    return start();
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
    } else if (healthy && _status.state != SuwayomiProcessState.running) {
      _emit(
        _status.copyWith(
          state: SuwayomiProcessState.running,
          message: 'Suwayomi pronto',
          lastHealthCheck: DateTime.now(),
        ),
      );
    } else if (healthy) {
      _emit(_status.copyWith(lastHealthCheck: DateTime.now()));
    }
    return healthy;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
    _http.close();
  }
}
