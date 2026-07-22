/// Suwayomi-Server process management and HTTP client.
library;

export 'src/adapter/suwayomi_core_adapter.dart';
export 'src/adapter/suwayomi_downloads_adapter.dart';
export 'src/adapter/suwayomi_extensions_adapter.dart';
export 'src/adapter/suwayomi_library_adapter.dart';
export 'src/client/suwayomi_api.dart';
export 'src/client/suwayomi_client.dart';
export 'src/client/suwayomi_models.dart';
export 'src/compatibility/suwayomi_compatibility_probe.dart';
export 'src/config/suwayomi_paths.dart';
export 'src/config/vendor_manifest.dart';
export 'src/java/java_resolver.dart';
export 'src/process/managed_instance_identity.dart';
export 'src/process/process_ownership.dart';
export 'src/process/suwayomi_process_failure.dart';
export 'src/process/suwayomi_process_manager.dart'
    show SuwayomiProcessManager, kYomuSuwayomiPort, kSuwayomiRootDirProperty;
export 'src/supervisor/managed_reading_engine_process.dart';
export 'src/supervisor/reading_engine_supervisor.dart';
