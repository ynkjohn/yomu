/// Where a catalog item is executed.
///
/// In the MVP, declarative Source Builder sources run inside Yomu and do
/// **not** appear inside Suwayomi. Tachiyomi/Mihon/Keiyoushi extensions run
/// only on Suwayomi.
enum SourceOrigin {
  /// Mihon/Tachiyomi extension hosted by Suwayomi-Server.
  suwayomiExtension,

  /// Declarative SourceSpec published by Yomu Source Builder.
  yomuSpec,
}

extension SourceOriginX on SourceOrigin {
  String get badgeLabel => switch (this) {
        SourceOrigin.suwayomiExtension => 'Extensão',
        SourceOrigin.yomuSpec => 'Fonte Yomu',
      };

  /// True when the work is backed by Suwayomi library/progress APIs.
  bool get usesSuwayomiEngine => this == SourceOrigin.suwayomiExtension;
}
