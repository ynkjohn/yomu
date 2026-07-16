// dart format width=80
// GENERATED CODE, DO NOT EDIT BY HAND.
// ignore_for_file: type=lint
import 'package:drift/drift.dart';

class AppMeta extends Table with TableInfo<AppMeta, AppMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  AppMeta(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAtMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_meta';
  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppMetaData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  AppMeta createAlias(String alias) {
    return AppMeta(attachedDatabase, alias);
  }
}

class AppMetaData extends DataClass implements Insertable<AppMetaData> {
  final String key;
  final String value;
  final int updatedAtMs;
  const AppMetaData({
    required this.key,
    required this.value,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  AppMetaCompanion toCompanion(bool nullToAbsent) {
    return AppMetaCompanion(
      key: Value(key),
      value: Value(value),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory AppMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppMetaData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  AppMetaData copyWith({String? key, String? value, int? updatedAtMs}) =>
      AppMetaData(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      );
  AppMetaData copyWithCompanion(AppMetaCompanion data) {
    return AppMetaData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppMetaData(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppMetaData &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAtMs == this.updatedAtMs);
}

class AppMetaCompanion extends UpdateCompanion<AppMetaData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const AppMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppMetaCompanion.insert({
    required String key,
    required String value,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<AppMetaData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppMetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return AppMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class DeviceSessions extends Table
    with TableInfo<DeviceSessions, DeviceSessionsData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DeviceSessions(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tokenHash = GeneratedColumn<String>(
    'token_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> deviceName = GeneratedColumn<String>(
    'device_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> expiresAtMs = GeneratedColumn<int>(
    'expires_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> lastSeenAtMs = GeneratedColumn<int>(
    'last_seen_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    tokenHash,
    deviceName,
    createdAtMs,
    expiresAtMs,
    lastSeenAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'device_sessions';
  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  DeviceSessionsData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeviceSessionsData(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      tokenHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}token_hash'],
      )!,
      deviceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_name'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      expiresAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at_ms'],
      )!,
      lastSeenAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_seen_at_ms'],
      ),
    );
  }

  @override
  DeviceSessions createAlias(String alias) {
    return DeviceSessions(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (length(token_hash) = 64 AND token_hash NOT GLOB \'*[^0-9a-f]*\')',
  ];
}

class DeviceSessionsData extends DataClass
    implements Insertable<DeviceSessionsData> {
  final String sessionId;
  final String tokenHash;
  final String deviceName;
  final int createdAtMs;
  final int expiresAtMs;
  final int? lastSeenAtMs;
  const DeviceSessionsData({
    required this.sessionId,
    required this.tokenHash,
    required this.deviceName,
    required this.createdAtMs,
    required this.expiresAtMs,
    this.lastSeenAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['token_hash'] = Variable<String>(tokenHash);
    map['device_name'] = Variable<String>(deviceName);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['expires_at_ms'] = Variable<int>(expiresAtMs);
    if (!nullToAbsent || lastSeenAtMs != null) {
      map['last_seen_at_ms'] = Variable<int>(lastSeenAtMs);
    }
    return map;
  }

  DeviceSessionsCompanion toCompanion(bool nullToAbsent) {
    return DeviceSessionsCompanion(
      sessionId: Value(sessionId),
      tokenHash: Value(tokenHash),
      deviceName: Value(deviceName),
      createdAtMs: Value(createdAtMs),
      expiresAtMs: Value(expiresAtMs),
      lastSeenAtMs: lastSeenAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeenAtMs),
    );
  }

  factory DeviceSessionsData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeviceSessionsData(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      tokenHash: serializer.fromJson<String>(json['tokenHash']),
      deviceName: serializer.fromJson<String>(json['deviceName']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      expiresAtMs: serializer.fromJson<int>(json['expiresAtMs']),
      lastSeenAtMs: serializer.fromJson<int?>(json['lastSeenAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'tokenHash': serializer.toJson<String>(tokenHash),
      'deviceName': serializer.toJson<String>(deviceName),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'expiresAtMs': serializer.toJson<int>(expiresAtMs),
      'lastSeenAtMs': serializer.toJson<int?>(lastSeenAtMs),
    };
  }

  DeviceSessionsData copyWith({
    String? sessionId,
    String? tokenHash,
    String? deviceName,
    int? createdAtMs,
    int? expiresAtMs,
    Value<int?> lastSeenAtMs = const Value.absent(),
  }) => DeviceSessionsData(
    sessionId: sessionId ?? this.sessionId,
    tokenHash: tokenHash ?? this.tokenHash,
    deviceName: deviceName ?? this.deviceName,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    expiresAtMs: expiresAtMs ?? this.expiresAtMs,
    lastSeenAtMs: lastSeenAtMs.present ? lastSeenAtMs.value : this.lastSeenAtMs,
  );
  DeviceSessionsData copyWithCompanion(DeviceSessionsCompanion data) {
    return DeviceSessionsData(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      tokenHash: data.tokenHash.present ? data.tokenHash.value : this.tokenHash,
      deviceName: data.deviceName.present
          ? data.deviceName.value
          : this.deviceName,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      expiresAtMs: data.expiresAtMs.present
          ? data.expiresAtMs.value
          : this.expiresAtMs,
      lastSeenAtMs: data.lastSeenAtMs.present
          ? data.lastSeenAtMs.value
          : this.lastSeenAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeviceSessionsData(')
          ..write('sessionId: $sessionId, ')
          ..write('tokenHash: $tokenHash, ')
          ..write('deviceName: $deviceName, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('expiresAtMs: $expiresAtMs, ')
          ..write('lastSeenAtMs: $lastSeenAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    tokenHash,
    deviceName,
    createdAtMs,
    expiresAtMs,
    lastSeenAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeviceSessionsData &&
          other.sessionId == this.sessionId &&
          other.tokenHash == this.tokenHash &&
          other.deviceName == this.deviceName &&
          other.createdAtMs == this.createdAtMs &&
          other.expiresAtMs == this.expiresAtMs &&
          other.lastSeenAtMs == this.lastSeenAtMs);
}

class DeviceSessionsCompanion extends UpdateCompanion<DeviceSessionsData> {
  final Value<String> sessionId;
  final Value<String> tokenHash;
  final Value<String> deviceName;
  final Value<int> createdAtMs;
  final Value<int> expiresAtMs;
  final Value<int?> lastSeenAtMs;
  final Value<int> rowid;
  const DeviceSessionsCompanion({
    this.sessionId = const Value.absent(),
    this.tokenHash = const Value.absent(),
    this.deviceName = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.expiresAtMs = const Value.absent(),
    this.lastSeenAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DeviceSessionsCompanion.insert({
    required String sessionId,
    required String tokenHash,
    required String deviceName,
    required int createdAtMs,
    required int expiresAtMs,
    this.lastSeenAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       tokenHash = Value(tokenHash),
       deviceName = Value(deviceName),
       createdAtMs = Value(createdAtMs),
       expiresAtMs = Value(expiresAtMs);
  static Insertable<DeviceSessionsData> custom({
    Expression<String>? sessionId,
    Expression<String>? tokenHash,
    Expression<String>? deviceName,
    Expression<int>? createdAtMs,
    Expression<int>? expiresAtMs,
    Expression<int>? lastSeenAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (tokenHash != null) 'token_hash': tokenHash,
      if (deviceName != null) 'device_name': deviceName,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (expiresAtMs != null) 'expires_at_ms': expiresAtMs,
      if (lastSeenAtMs != null) 'last_seen_at_ms': lastSeenAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DeviceSessionsCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? tokenHash,
    Value<String>? deviceName,
    Value<int>? createdAtMs,
    Value<int>? expiresAtMs,
    Value<int?>? lastSeenAtMs,
    Value<int>? rowid,
  }) {
    return DeviceSessionsCompanion(
      sessionId: sessionId ?? this.sessionId,
      tokenHash: tokenHash ?? this.tokenHash,
      deviceName: deviceName ?? this.deviceName,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      expiresAtMs: expiresAtMs ?? this.expiresAtMs,
      lastSeenAtMs: lastSeenAtMs ?? this.lastSeenAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (tokenHash.present) {
      map['token_hash'] = Variable<String>(tokenHash.value);
    }
    if (deviceName.present) {
      map['device_name'] = Variable<String>(deviceName.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (expiresAtMs.present) {
      map['expires_at_ms'] = Variable<int>(expiresAtMs.value);
    }
    if (lastSeenAtMs.present) {
      map['last_seen_at_ms'] = Variable<int>(lastSeenAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeviceSessionsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('tokenHash: $tokenHash, ')
          ..write('deviceName: $deviceName, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('expiresAtMs: $expiresAtMs, ')
          ..write('lastSeenAtMs: $lastSeenAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class MayaMessages extends Table
    with TableInfo<MayaMessages, MayaMessagesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MayaMessages(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    messageId,
    sortOrder,
    role,
    content,
    createdAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'maya_messages';
  @override
  Set<GeneratedColumn> get $primaryKey => {messageId};
  @override
  MayaMessagesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MayaMessagesData(
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
    );
  }

  @override
  MayaMessages createAlias(String alias) {
    return MayaMessages(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (role IN (\'system\', \'user\', \'assistant\'))',
    'CHECK (sort_order >= 0)',
    'CHECK (created_at_ms >= 0)',
  ];
}

class MayaMessagesData extends DataClass
    implements Insertable<MayaMessagesData> {
  final String messageId;
  final int sortOrder;
  final String role;
  final String content;
  final int createdAtMs;
  const MayaMessagesData({
    required this.messageId,
    required this.sortOrder,
    required this.role,
    required this.content,
    required this.createdAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['message_id'] = Variable<String>(messageId);
    map['sort_order'] = Variable<int>(sortOrder);
    map['role'] = Variable<String>(role);
    map['text'] = Variable<String>(content);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    return map;
  }

  MayaMessagesCompanion toCompanion(bool nullToAbsent) {
    return MayaMessagesCompanion(
      messageId: Value(messageId),
      sortOrder: Value(sortOrder),
      role: Value(role),
      content: Value(content),
      createdAtMs: Value(createdAtMs),
    );
  }

  factory MayaMessagesData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MayaMessagesData(
      messageId: serializer.fromJson<String>(json['messageId']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      role: serializer.fromJson<String>(json['role']),
      content: serializer.fromJson<String>(json['content']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'messageId': serializer.toJson<String>(messageId),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'role': serializer.toJson<String>(role),
      'content': serializer.toJson<String>(content),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
    };
  }

  MayaMessagesData copyWith({
    String? messageId,
    int? sortOrder,
    String? role,
    String? content,
    int? createdAtMs,
  }) => MayaMessagesData(
    messageId: messageId ?? this.messageId,
    sortOrder: sortOrder ?? this.sortOrder,
    role: role ?? this.role,
    content: content ?? this.content,
    createdAtMs: createdAtMs ?? this.createdAtMs,
  );
  MayaMessagesData copyWithCompanion(MayaMessagesCompanion data) {
    return MayaMessagesData(
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MayaMessagesData(')
          ..write('messageId: $messageId, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(messageId, sortOrder, role, content, createdAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MayaMessagesData &&
          other.messageId == this.messageId &&
          other.sortOrder == this.sortOrder &&
          other.role == this.role &&
          other.content == this.content &&
          other.createdAtMs == this.createdAtMs);
}

class MayaMessagesCompanion extends UpdateCompanion<MayaMessagesData> {
  final Value<String> messageId;
  final Value<int> sortOrder;
  final Value<String> role;
  final Value<String> content;
  final Value<int> createdAtMs;
  final Value<int> rowid;
  const MayaMessagesCompanion({
    this.messageId = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MayaMessagesCompanion.insert({
    required String messageId,
    required int sortOrder,
    required String role,
    required String content,
    required int createdAtMs,
    this.rowid = const Value.absent(),
  }) : messageId = Value(messageId),
       sortOrder = Value(sortOrder),
       role = Value(role),
       content = Value(content),
       createdAtMs = Value(createdAtMs);
  static Insertable<MayaMessagesData> custom({
    Expression<String>? messageId,
    Expression<int>? sortOrder,
    Expression<String>? role,
    Expression<String>? content,
    Expression<int>? createdAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (messageId != null) 'message_id': messageId,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (role != null) 'role': role,
      if (content != null) 'text': content,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MayaMessagesCompanion copyWith({
    Value<String>? messageId,
    Value<int>? sortOrder,
    Value<String>? role,
    Value<String>? content,
    Value<int>? createdAtMs,
    Value<int>? rowid,
  }) {
    return MayaMessagesCompanion(
      messageId: messageId ?? this.messageId,
      sortOrder: sortOrder ?? this.sortOrder,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (content.present) {
      map['text'] = Variable<String>(content.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MayaMessagesCompanion(')
          ..write('messageId: $messageId, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class MayaActionProposals extends Table
    with TableInfo<MayaActionProposals, MayaActionProposalsData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MayaActionProposals(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> proposalId = GeneratedColumn<String>(
    'proposal_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES maya_messages (message_id) ON DELETE CASCADE',
    ),
  );
  late final GeneratedColumn<int> proposalOrder = GeneratedColumn<int>(
    'proposal_order',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> confirmedAtMs = GeneratedColumn<int>(
    'confirmed_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> completedAtMs = GeneratedColumn<int>(
    'completed_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    proposalId,
    messageId,
    proposalOrder,
    kind,
    title,
    description,
    payloadJson,
    status,
    createdAtMs,
    confirmedAtMs,
    completedAtMs,
    error,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'maya_action_proposals';
  @override
  Set<GeneratedColumn> get $primaryKey => {proposalId};
  @override
  MayaActionProposalsData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MayaActionProposalsData(
      proposalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}proposal_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      ),
      proposalOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}proposal_order'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      confirmedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}confirmed_at_ms'],
      ),
      completedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_at_ms'],
      ),
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
    );
  }

  @override
  MayaActionProposals createAlias(String alias) {
    return MayaActionProposals(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (kind IN (\'openManga\', \'downloadChapter\', \'setInLibrary\'))',
    'CHECK (status IN (\'pending\', \'confirmed\', \'rejected\', \'executed\', \'failed\'))',
    'CHECK (created_at_ms >= 0)',
    'CHECK (proposal_order IS NULL OR proposal_order >= 0)',
    'CHECK ((message_id IS NULL AND proposal_order IS NULL) OR (message_id IS NOT NULL AND proposal_order IS NOT NULL))',
    'CHECK (confirmed_at_ms IS NULL OR confirmed_at_ms >= created_at_ms)',
    'CHECK (completed_at_ms IS NULL OR completed_at_ms >= created_at_ms)',
    'CHECK (confirmed_at_ms IS NULL OR completed_at_ms IS NULL OR completed_at_ms >= confirmed_at_ms)',
    'CHECK ((status = \'pending\' AND confirmed_at_ms IS NULL AND completed_at_ms IS NULL) OR (status = \'confirmed\' AND confirmed_at_ms IS NOT NULL AND completed_at_ms IS NULL) OR (status = \'rejected\' AND confirmed_at_ms IS NULL AND completed_at_ms IS NOT NULL) OR (status = \'executed\' AND confirmed_at_ms IS NOT NULL AND completed_at_ms IS NOT NULL) OR (status = \'failed\' AND completed_at_ms IS NOT NULL))',
    'UNIQUE (message_id, proposal_order)',
  ];
}

class MayaActionProposalsData extends DataClass
    implements Insertable<MayaActionProposalsData> {
  final String proposalId;
  final String? messageId;
  final int? proposalOrder;
  final String kind;
  final String title;
  final String description;
  final String payloadJson;
  final String status;
  final int createdAtMs;
  final int? confirmedAtMs;
  final int? completedAtMs;
  final String? error;
  const MayaActionProposalsData({
    required this.proposalId,
    this.messageId,
    this.proposalOrder,
    required this.kind,
    required this.title,
    required this.description,
    required this.payloadJson,
    required this.status,
    required this.createdAtMs,
    this.confirmedAtMs,
    this.completedAtMs,
    this.error,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['proposal_id'] = Variable<String>(proposalId);
    if (!nullToAbsent || messageId != null) {
      map['message_id'] = Variable<String>(messageId);
    }
    if (!nullToAbsent || proposalOrder != null) {
      map['proposal_order'] = Variable<int>(proposalOrder);
    }
    map['kind'] = Variable<String>(kind);
    map['title'] = Variable<String>(title);
    map['description'] = Variable<String>(description);
    map['payload_json'] = Variable<String>(payloadJson);
    map['status'] = Variable<String>(status);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    if (!nullToAbsent || confirmedAtMs != null) {
      map['confirmed_at_ms'] = Variable<int>(confirmedAtMs);
    }
    if (!nullToAbsent || completedAtMs != null) {
      map['completed_at_ms'] = Variable<int>(completedAtMs);
    }
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    return map;
  }

  MayaActionProposalsCompanion toCompanion(bool nullToAbsent) {
    return MayaActionProposalsCompanion(
      proposalId: Value(proposalId),
      messageId: messageId == null && nullToAbsent
          ? const Value.absent()
          : Value(messageId),
      proposalOrder: proposalOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(proposalOrder),
      kind: Value(kind),
      title: Value(title),
      description: Value(description),
      payloadJson: Value(payloadJson),
      status: Value(status),
      createdAtMs: Value(createdAtMs),
      confirmedAtMs: confirmedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(confirmedAtMs),
      completedAtMs: completedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAtMs),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
    );
  }

  factory MayaActionProposalsData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MayaActionProposalsData(
      proposalId: serializer.fromJson<String>(json['proposalId']),
      messageId: serializer.fromJson<String?>(json['messageId']),
      proposalOrder: serializer.fromJson<int?>(json['proposalOrder']),
      kind: serializer.fromJson<String>(json['kind']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      status: serializer.fromJson<String>(json['status']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      confirmedAtMs: serializer.fromJson<int?>(json['confirmedAtMs']),
      completedAtMs: serializer.fromJson<int?>(json['completedAtMs']),
      error: serializer.fromJson<String?>(json['error']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'proposalId': serializer.toJson<String>(proposalId),
      'messageId': serializer.toJson<String?>(messageId),
      'proposalOrder': serializer.toJson<int?>(proposalOrder),
      'kind': serializer.toJson<String>(kind),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'status': serializer.toJson<String>(status),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'confirmedAtMs': serializer.toJson<int?>(confirmedAtMs),
      'completedAtMs': serializer.toJson<int?>(completedAtMs),
      'error': serializer.toJson<String?>(error),
    };
  }

  MayaActionProposalsData copyWith({
    String? proposalId,
    Value<String?> messageId = const Value.absent(),
    Value<int?> proposalOrder = const Value.absent(),
    String? kind,
    String? title,
    String? description,
    String? payloadJson,
    String? status,
    int? createdAtMs,
    Value<int?> confirmedAtMs = const Value.absent(),
    Value<int?> completedAtMs = const Value.absent(),
    Value<String?> error = const Value.absent(),
  }) => MayaActionProposalsData(
    proposalId: proposalId ?? this.proposalId,
    messageId: messageId.present ? messageId.value : this.messageId,
    proposalOrder: proposalOrder.present
        ? proposalOrder.value
        : this.proposalOrder,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    description: description ?? this.description,
    payloadJson: payloadJson ?? this.payloadJson,
    status: status ?? this.status,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    confirmedAtMs: confirmedAtMs.present
        ? confirmedAtMs.value
        : this.confirmedAtMs,
    completedAtMs: completedAtMs.present
        ? completedAtMs.value
        : this.completedAtMs,
    error: error.present ? error.value : this.error,
  );
  MayaActionProposalsData copyWithCompanion(MayaActionProposalsCompanion data) {
    return MayaActionProposalsData(
      proposalId: data.proposalId.present
          ? data.proposalId.value
          : this.proposalId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      proposalOrder: data.proposalOrder.present
          ? data.proposalOrder.value
          : this.proposalOrder,
      kind: data.kind.present ? data.kind.value : this.kind,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      status: data.status.present ? data.status.value : this.status,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      confirmedAtMs: data.confirmedAtMs.present
          ? data.confirmedAtMs.value
          : this.confirmedAtMs,
      completedAtMs: data.completedAtMs.present
          ? data.completedAtMs.value
          : this.completedAtMs,
      error: data.error.present ? data.error.value : this.error,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MayaActionProposalsData(')
          ..write('proposalId: $proposalId, ')
          ..write('messageId: $messageId, ')
          ..write('proposalOrder: $proposalOrder, ')
          ..write('kind: $kind, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('status: $status, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('confirmedAtMs: $confirmedAtMs, ')
          ..write('completedAtMs: $completedAtMs, ')
          ..write('error: $error')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    proposalId,
    messageId,
    proposalOrder,
    kind,
    title,
    description,
    payloadJson,
    status,
    createdAtMs,
    confirmedAtMs,
    completedAtMs,
    error,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MayaActionProposalsData &&
          other.proposalId == this.proposalId &&
          other.messageId == this.messageId &&
          other.proposalOrder == this.proposalOrder &&
          other.kind == this.kind &&
          other.title == this.title &&
          other.description == this.description &&
          other.payloadJson == this.payloadJson &&
          other.status == this.status &&
          other.createdAtMs == this.createdAtMs &&
          other.confirmedAtMs == this.confirmedAtMs &&
          other.completedAtMs == this.completedAtMs &&
          other.error == this.error);
}

class MayaActionProposalsCompanion
    extends UpdateCompanion<MayaActionProposalsData> {
  final Value<String> proposalId;
  final Value<String?> messageId;
  final Value<int?> proposalOrder;
  final Value<String> kind;
  final Value<String> title;
  final Value<String> description;
  final Value<String> payloadJson;
  final Value<String> status;
  final Value<int> createdAtMs;
  final Value<int?> confirmedAtMs;
  final Value<int?> completedAtMs;
  final Value<String?> error;
  final Value<int> rowid;
  const MayaActionProposalsCompanion({
    this.proposalId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.proposalOrder = const Value.absent(),
    this.kind = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.confirmedAtMs = const Value.absent(),
    this.completedAtMs = const Value.absent(),
    this.error = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MayaActionProposalsCompanion.insert({
    required String proposalId,
    this.messageId = const Value.absent(),
    this.proposalOrder = const Value.absent(),
    required String kind,
    required String title,
    required String description,
    required String payloadJson,
    required String status,
    required int createdAtMs,
    this.confirmedAtMs = const Value.absent(),
    this.completedAtMs = const Value.absent(),
    this.error = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : proposalId = Value(proposalId),
       kind = Value(kind),
       title = Value(title),
       description = Value(description),
       payloadJson = Value(payloadJson),
       status = Value(status),
       createdAtMs = Value(createdAtMs);
  static Insertable<MayaActionProposalsData> custom({
    Expression<String>? proposalId,
    Expression<String>? messageId,
    Expression<int>? proposalOrder,
    Expression<String>? kind,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? payloadJson,
    Expression<String>? status,
    Expression<int>? createdAtMs,
    Expression<int>? confirmedAtMs,
    Expression<int>? completedAtMs,
    Expression<String>? error,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (proposalId != null) 'proposal_id': proposalId,
      if (messageId != null) 'message_id': messageId,
      if (proposalOrder != null) 'proposal_order': proposalOrder,
      if (kind != null) 'kind': kind,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (status != null) 'status': status,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (confirmedAtMs != null) 'confirmed_at_ms': confirmedAtMs,
      if (completedAtMs != null) 'completed_at_ms': completedAtMs,
      if (error != null) 'error': error,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MayaActionProposalsCompanion copyWith({
    Value<String>? proposalId,
    Value<String?>? messageId,
    Value<int?>? proposalOrder,
    Value<String>? kind,
    Value<String>? title,
    Value<String>? description,
    Value<String>? payloadJson,
    Value<String>? status,
    Value<int>? createdAtMs,
    Value<int?>? confirmedAtMs,
    Value<int?>? completedAtMs,
    Value<String?>? error,
    Value<int>? rowid,
  }) {
    return MayaActionProposalsCompanion(
      proposalId: proposalId ?? this.proposalId,
      messageId: messageId ?? this.messageId,
      proposalOrder: proposalOrder ?? this.proposalOrder,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      description: description ?? this.description,
      payloadJson: payloadJson ?? this.payloadJson,
      status: status ?? this.status,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      confirmedAtMs: confirmedAtMs ?? this.confirmedAtMs,
      completedAtMs: completedAtMs ?? this.completedAtMs,
      error: error ?? this.error,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (proposalId.present) {
      map['proposal_id'] = Variable<String>(proposalId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (proposalOrder.present) {
      map['proposal_order'] = Variable<int>(proposalOrder.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (confirmedAtMs.present) {
      map['confirmed_at_ms'] = Variable<int>(confirmedAtMs.value);
    }
    if (completedAtMs.present) {
      map['completed_at_ms'] = Variable<int>(completedAtMs.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MayaActionProposalsCompanion(')
          ..write('proposalId: $proposalId, ')
          ..write('messageId: $messageId, ')
          ..write('proposalOrder: $proposalOrder, ')
          ..write('kind: $kind, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('status: $status, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('confirmedAtMs: $confirmedAtMs, ')
          ..write('completedAtMs: $completedAtMs, ')
          ..write('error: $error, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class MayaProviderSettings extends Table
    with TableInfo<MayaProviderSettings, MayaProviderSettingsData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MayaProviderSettings(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<int> settingsId = GeneratedColumn<int>(
    'settings_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<bool> isEnabled = GeneratedColumn<bool>(
    'is_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_enabled" IN (0, 1))',
    ),
  );
  late final GeneratedColumn<String> providerId = GeneratedColumn<String>(
    'provider_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> modelPolicy = GeneratedColumn<String>(
    'model_policy',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<bool> shareRecentHistory = GeneratedColumn<bool>(
    'share_recent_history',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("share_recent_history" IN (0, 1))',
    ),
  );
  late final GeneratedColumn<bool> shareLibraryContext = GeneratedColumn<bool>(
    'share_library_context',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("share_library_context" IN (0, 1))',
    ),
  );
  late final GeneratedColumn<int> consentVersion = GeneratedColumn<int>(
    'consent_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> consentedAtMs = GeneratedColumn<int>(
    'consented_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    settingsId,
    mode,
    isEnabled,
    providerId,
    modelPolicy,
    modelId,
    shareRecentHistory,
    shareLibraryContext,
    consentVersion,
    consentedAtMs,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'maya_provider_settings';
  @override
  Set<GeneratedColumn> get $primaryKey => {settingsId};
  @override
  MayaProviderSettingsData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MayaProviderSettingsData(
      settingsId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}settings_id'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      isEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_enabled'],
      )!,
      providerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_id'],
      ),
      modelPolicy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_policy'],
      ),
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      ),
      shareRecentHistory: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}share_recent_history'],
      )!,
      shareLibraryContext: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}share_library_context'],
      )!,
      consentVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}consent_version'],
      ),
      consentedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}consented_at_ms'],
      ),
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  MayaProviderSettings createAlias(String alias) {
    return MayaProviderSettings(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK (settings_id = 1)',
    'CHECK (mode IN (\'local\', \'cloud\'))',
    'CHECK (model_policy IS NULL OR model_policy IN (\'provider_default\', \'explicit\'))',
    'CHECK (updated_at_ms >= 0)',
    'CHECK (consented_at_ms IS NULL OR consented_at_ms >= 0)',
    'CHECK (consented_at_ms IS NULL OR consented_at_ms <= updated_at_ms)',
    'CHECK (provider_id IS NULL OR (length(provider_id) BETWEEN 1 AND 64 AND provider_id = trim(provider_id)))',
    'CHECK (model_id IS NULL OR (length(model_id) BETWEEN 1 AND 200 AND model_id = trim(model_id)))',
    'CHECK ((mode = \'local\' AND is_enabled = 0 AND provider_id IS NULL AND model_policy IS NULL AND model_id IS NULL AND share_recent_history = 0 AND share_library_context = 0 AND consent_version IS NULL AND consented_at_ms IS NULL) OR (mode = \'cloud\' AND provider_id IS NOT NULL AND model_policy IS NOT NULL AND consent_version IS NOT NULL AND consent_version > 0 AND consented_at_ms IS NOT NULL AND ((model_policy = \'provider_default\' AND model_id IS NULL) OR (model_policy = \'explicit\' AND model_id IS NOT NULL))))',
  ];
}

class MayaProviderSettingsData extends DataClass
    implements Insertable<MayaProviderSettingsData> {
  final int settingsId;
  final String mode;
  final bool isEnabled;
  final String? providerId;
  final String? modelPolicy;
  final String? modelId;
  final bool shareRecentHistory;
  final bool shareLibraryContext;
  final int? consentVersion;
  final int? consentedAtMs;
  final int updatedAtMs;
  const MayaProviderSettingsData({
    required this.settingsId,
    required this.mode,
    required this.isEnabled,
    this.providerId,
    this.modelPolicy,
    this.modelId,
    required this.shareRecentHistory,
    required this.shareLibraryContext,
    this.consentVersion,
    this.consentedAtMs,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['settings_id'] = Variable<int>(settingsId);
    map['mode'] = Variable<String>(mode);
    map['is_enabled'] = Variable<bool>(isEnabled);
    if (!nullToAbsent || providerId != null) {
      map['provider_id'] = Variable<String>(providerId);
    }
    if (!nullToAbsent || modelPolicy != null) {
      map['model_policy'] = Variable<String>(modelPolicy);
    }
    if (!nullToAbsent || modelId != null) {
      map['model_id'] = Variable<String>(modelId);
    }
    map['share_recent_history'] = Variable<bool>(shareRecentHistory);
    map['share_library_context'] = Variable<bool>(shareLibraryContext);
    if (!nullToAbsent || consentVersion != null) {
      map['consent_version'] = Variable<int>(consentVersion);
    }
    if (!nullToAbsent || consentedAtMs != null) {
      map['consented_at_ms'] = Variable<int>(consentedAtMs);
    }
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  MayaProviderSettingsCompanion toCompanion(bool nullToAbsent) {
    return MayaProviderSettingsCompanion(
      settingsId: Value(settingsId),
      mode: Value(mode),
      isEnabled: Value(isEnabled),
      providerId: providerId == null && nullToAbsent
          ? const Value.absent()
          : Value(providerId),
      modelPolicy: modelPolicy == null && nullToAbsent
          ? const Value.absent()
          : Value(modelPolicy),
      modelId: modelId == null && nullToAbsent
          ? const Value.absent()
          : Value(modelId),
      shareRecentHistory: Value(shareRecentHistory),
      shareLibraryContext: Value(shareLibraryContext),
      consentVersion: consentVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(consentVersion),
      consentedAtMs: consentedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(consentedAtMs),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory MayaProviderSettingsData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MayaProviderSettingsData(
      settingsId: serializer.fromJson<int>(json['settingsId']),
      mode: serializer.fromJson<String>(json['mode']),
      isEnabled: serializer.fromJson<bool>(json['isEnabled']),
      providerId: serializer.fromJson<String?>(json['providerId']),
      modelPolicy: serializer.fromJson<String?>(json['modelPolicy']),
      modelId: serializer.fromJson<String?>(json['modelId']),
      shareRecentHistory: serializer.fromJson<bool>(json['shareRecentHistory']),
      shareLibraryContext: serializer.fromJson<bool>(
        json['shareLibraryContext'],
      ),
      consentVersion: serializer.fromJson<int?>(json['consentVersion']),
      consentedAtMs: serializer.fromJson<int?>(json['consentedAtMs']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'settingsId': serializer.toJson<int>(settingsId),
      'mode': serializer.toJson<String>(mode),
      'isEnabled': serializer.toJson<bool>(isEnabled),
      'providerId': serializer.toJson<String?>(providerId),
      'modelPolicy': serializer.toJson<String?>(modelPolicy),
      'modelId': serializer.toJson<String?>(modelId),
      'shareRecentHistory': serializer.toJson<bool>(shareRecentHistory),
      'shareLibraryContext': serializer.toJson<bool>(shareLibraryContext),
      'consentVersion': serializer.toJson<int?>(consentVersion),
      'consentedAtMs': serializer.toJson<int?>(consentedAtMs),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  MayaProviderSettingsData copyWith({
    int? settingsId,
    String? mode,
    bool? isEnabled,
    Value<String?> providerId = const Value.absent(),
    Value<String?> modelPolicy = const Value.absent(),
    Value<String?> modelId = const Value.absent(),
    bool? shareRecentHistory,
    bool? shareLibraryContext,
    Value<int?> consentVersion = const Value.absent(),
    Value<int?> consentedAtMs = const Value.absent(),
    int? updatedAtMs,
  }) => MayaProviderSettingsData(
    settingsId: settingsId ?? this.settingsId,
    mode: mode ?? this.mode,
    isEnabled: isEnabled ?? this.isEnabled,
    providerId: providerId.present ? providerId.value : this.providerId,
    modelPolicy: modelPolicy.present ? modelPolicy.value : this.modelPolicy,
    modelId: modelId.present ? modelId.value : this.modelId,
    shareRecentHistory: shareRecentHistory ?? this.shareRecentHistory,
    shareLibraryContext: shareLibraryContext ?? this.shareLibraryContext,
    consentVersion: consentVersion.present
        ? consentVersion.value
        : this.consentVersion,
    consentedAtMs: consentedAtMs.present
        ? consentedAtMs.value
        : this.consentedAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  MayaProviderSettingsData copyWithCompanion(
    MayaProviderSettingsCompanion data,
  ) {
    return MayaProviderSettingsData(
      settingsId: data.settingsId.present
          ? data.settingsId.value
          : this.settingsId,
      mode: data.mode.present ? data.mode.value : this.mode,
      isEnabled: data.isEnabled.present ? data.isEnabled.value : this.isEnabled,
      providerId: data.providerId.present
          ? data.providerId.value
          : this.providerId,
      modelPolicy: data.modelPolicy.present
          ? data.modelPolicy.value
          : this.modelPolicy,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      shareRecentHistory: data.shareRecentHistory.present
          ? data.shareRecentHistory.value
          : this.shareRecentHistory,
      shareLibraryContext: data.shareLibraryContext.present
          ? data.shareLibraryContext.value
          : this.shareLibraryContext,
      consentVersion: data.consentVersion.present
          ? data.consentVersion.value
          : this.consentVersion,
      consentedAtMs: data.consentedAtMs.present
          ? data.consentedAtMs.value
          : this.consentedAtMs,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MayaProviderSettingsData(')
          ..write('settingsId: $settingsId, ')
          ..write('mode: $mode, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('providerId: $providerId, ')
          ..write('modelPolicy: $modelPolicy, ')
          ..write('modelId: $modelId, ')
          ..write('shareRecentHistory: $shareRecentHistory, ')
          ..write('shareLibraryContext: $shareLibraryContext, ')
          ..write('consentVersion: $consentVersion, ')
          ..write('consentedAtMs: $consentedAtMs, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    settingsId,
    mode,
    isEnabled,
    providerId,
    modelPolicy,
    modelId,
    shareRecentHistory,
    shareLibraryContext,
    consentVersion,
    consentedAtMs,
    updatedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MayaProviderSettingsData &&
          other.settingsId == this.settingsId &&
          other.mode == this.mode &&
          other.isEnabled == this.isEnabled &&
          other.providerId == this.providerId &&
          other.modelPolicy == this.modelPolicy &&
          other.modelId == this.modelId &&
          other.shareRecentHistory == this.shareRecentHistory &&
          other.shareLibraryContext == this.shareLibraryContext &&
          other.consentVersion == this.consentVersion &&
          other.consentedAtMs == this.consentedAtMs &&
          other.updatedAtMs == this.updatedAtMs);
}

class MayaProviderSettingsCompanion
    extends UpdateCompanion<MayaProviderSettingsData> {
  final Value<int> settingsId;
  final Value<String> mode;
  final Value<bool> isEnabled;
  final Value<String?> providerId;
  final Value<String?> modelPolicy;
  final Value<String?> modelId;
  final Value<bool> shareRecentHistory;
  final Value<bool> shareLibraryContext;
  final Value<int?> consentVersion;
  final Value<int?> consentedAtMs;
  final Value<int> updatedAtMs;
  const MayaProviderSettingsCompanion({
    this.settingsId = const Value.absent(),
    this.mode = const Value.absent(),
    this.isEnabled = const Value.absent(),
    this.providerId = const Value.absent(),
    this.modelPolicy = const Value.absent(),
    this.modelId = const Value.absent(),
    this.shareRecentHistory = const Value.absent(),
    this.shareLibraryContext = const Value.absent(),
    this.consentVersion = const Value.absent(),
    this.consentedAtMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
  });
  MayaProviderSettingsCompanion.insert({
    this.settingsId = const Value.absent(),
    required String mode,
    required bool isEnabled,
    this.providerId = const Value.absent(),
    this.modelPolicy = const Value.absent(),
    this.modelId = const Value.absent(),
    required bool shareRecentHistory,
    required bool shareLibraryContext,
    this.consentVersion = const Value.absent(),
    this.consentedAtMs = const Value.absent(),
    required int updatedAtMs,
  }) : mode = Value(mode),
       isEnabled = Value(isEnabled),
       shareRecentHistory = Value(shareRecentHistory),
       shareLibraryContext = Value(shareLibraryContext),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<MayaProviderSettingsData> custom({
    Expression<int>? settingsId,
    Expression<String>? mode,
    Expression<bool>? isEnabled,
    Expression<String>? providerId,
    Expression<String>? modelPolicy,
    Expression<String>? modelId,
    Expression<bool>? shareRecentHistory,
    Expression<bool>? shareLibraryContext,
    Expression<int>? consentVersion,
    Expression<int>? consentedAtMs,
    Expression<int>? updatedAtMs,
  }) {
    return RawValuesInsertable({
      if (settingsId != null) 'settings_id': settingsId,
      if (mode != null) 'mode': mode,
      if (isEnabled != null) 'is_enabled': isEnabled,
      if (providerId != null) 'provider_id': providerId,
      if (modelPolicy != null) 'model_policy': modelPolicy,
      if (modelId != null) 'model_id': modelId,
      if (shareRecentHistory != null)
        'share_recent_history': shareRecentHistory,
      if (shareLibraryContext != null)
        'share_library_context': shareLibraryContext,
      if (consentVersion != null) 'consent_version': consentVersion,
      if (consentedAtMs != null) 'consented_at_ms': consentedAtMs,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
    });
  }

  MayaProviderSettingsCompanion copyWith({
    Value<int>? settingsId,
    Value<String>? mode,
    Value<bool>? isEnabled,
    Value<String?>? providerId,
    Value<String?>? modelPolicy,
    Value<String?>? modelId,
    Value<bool>? shareRecentHistory,
    Value<bool>? shareLibraryContext,
    Value<int?>? consentVersion,
    Value<int?>? consentedAtMs,
    Value<int>? updatedAtMs,
  }) {
    return MayaProviderSettingsCompanion(
      settingsId: settingsId ?? this.settingsId,
      mode: mode ?? this.mode,
      isEnabled: isEnabled ?? this.isEnabled,
      providerId: providerId ?? this.providerId,
      modelPolicy: modelPolicy ?? this.modelPolicy,
      modelId: modelId ?? this.modelId,
      shareRecentHistory: shareRecentHistory ?? this.shareRecentHistory,
      shareLibraryContext: shareLibraryContext ?? this.shareLibraryContext,
      consentVersion: consentVersion ?? this.consentVersion,
      consentedAtMs: consentedAtMs ?? this.consentedAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (settingsId.present) {
      map['settings_id'] = Variable<int>(settingsId.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (isEnabled.present) {
      map['is_enabled'] = Variable<bool>(isEnabled.value);
    }
    if (providerId.present) {
      map['provider_id'] = Variable<String>(providerId.value);
    }
    if (modelPolicy.present) {
      map['model_policy'] = Variable<String>(modelPolicy.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (shareRecentHistory.present) {
      map['share_recent_history'] = Variable<bool>(shareRecentHistory.value);
    }
    if (shareLibraryContext.present) {
      map['share_library_context'] = Variable<bool>(shareLibraryContext.value);
    }
    if (consentVersion.present) {
      map['consent_version'] = Variable<int>(consentVersion.value);
    }
    if (consentedAtMs.present) {
      map['consented_at_ms'] = Variable<int>(consentedAtMs.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MayaProviderSettingsCompanion(')
          ..write('settingsId: $settingsId, ')
          ..write('mode: $mode, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('providerId: $providerId, ')
          ..write('modelPolicy: $modelPolicy, ')
          ..write('modelId: $modelId, ')
          ..write('shareRecentHistory: $shareRecentHistory, ')
          ..write('shareLibraryContext: $shareLibraryContext, ')
          ..write('consentVersion: $consentVersion, ')
          ..write('consentedAtMs: $consentedAtMs, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }
}

class DatabaseAtV4 extends GeneratedDatabase {
  DatabaseAtV4(QueryExecutor e) : super(e);
  late final AppMeta appMeta = AppMeta(this);
  late final DeviceSessions deviceSessions = DeviceSessions(this);
  late final MayaMessages mayaMessages = MayaMessages(this);
  late final MayaActionProposals mayaActionProposals = MayaActionProposals(
    this,
  );
  late final MayaProviderSettings mayaProviderSettings = MayaProviderSettings(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    appMeta,
    deviceSessions,
    mayaMessages,
    mayaActionProposals,
    mayaProviderSettings,
  ];
  @override
  int get schemaVersion => 4;
}
