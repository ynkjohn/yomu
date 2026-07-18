import 'dart:typed_data';

import 'package:collection/collection.dart';

/// Opaque media identity. Implementations may carry private transport details,
/// but consumers cannot inspect or turn it into an upstream URL.
abstract interface class MediaReference {}

/// Bounded media result returned by the engine adapter.
final class MediaPayload {
  MediaPayload({required List<int> bytes, this.contentType})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  final Uint8List bytes;
  final String? contentType;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaPayload &&
          const ListEquality<int>().equals(bytes, other.bytes) &&
          contentType == other.contentType;

  @override
  int get hashCode =>
      Object.hash(const ListEquality<int>().hash(bytes), contentType);
}

abstract interface class EngineMediaGateway {
  Future<MediaPayload> fetch(MediaReference reference, {required int maxBytes});
}
