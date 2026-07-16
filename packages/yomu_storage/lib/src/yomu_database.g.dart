// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'yomu_database.dart';

// ignore_for_file: type=lint
class $AppMetaTable extends AppMeta with TableInfo<$AppMetaTable, AppMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
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
  VerificationContext validateIntegrity(
    Insertable<AppMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

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
  $AppMetaTable createAlias(String alias) {
    return $AppMetaTable(attachedDatabase, alias);
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

class $DeviceSessionsTable extends DeviceSessions
    with TableInfo<$DeviceSessionsTable, StoredDeviceSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeviceSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tokenHashMeta = const VerificationMeta(
    'tokenHash',
  );
  @override
  late final GeneratedColumn<String> tokenHash = GeneratedColumn<String>(
    'token_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _deviceNameMeta = const VerificationMeta(
    'deviceName',
  );
  @override
  late final GeneratedColumn<String> deviceName = GeneratedColumn<String>(
    'device_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMsMeta = const VerificationMeta(
    'expiresAtMs',
  );
  @override
  late final GeneratedColumn<int> expiresAtMs = GeneratedColumn<int>(
    'expires_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenAtMsMeta = const VerificationMeta(
    'lastSeenAtMs',
  );
  @override
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
  VerificationContext validateIntegrity(
    Insertable<StoredDeviceSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('token_hash')) {
      context.handle(
        _tokenHashMeta,
        tokenHash.isAcceptableOrUnknown(data['token_hash']!, _tokenHashMeta),
      );
    } else if (isInserting) {
      context.missing(_tokenHashMeta);
    }
    if (data.containsKey('device_name')) {
      context.handle(
        _deviceNameMeta,
        deviceName.isAcceptableOrUnknown(data['device_name']!, _deviceNameMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceNameMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('expires_at_ms')) {
      context.handle(
        _expiresAtMsMeta,
        expiresAtMs.isAcceptableOrUnknown(
          data['expires_at_ms']!,
          _expiresAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMsMeta);
    }
    if (data.containsKey('last_seen_at_ms')) {
      context.handle(
        _lastSeenAtMsMeta,
        lastSeenAtMs.isAcceptableOrUnknown(
          data['last_seen_at_ms']!,
          _lastSeenAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  StoredDeviceSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredDeviceSession(
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
  $DeviceSessionsTable createAlias(String alias) {
    return $DeviceSessionsTable(attachedDatabase, alias);
  }
}

class StoredDeviceSession extends DataClass
    implements Insertable<StoredDeviceSession> {
  final String sessionId;
  final String tokenHash;
  final String deviceName;
  final int createdAtMs;
  final int expiresAtMs;
  final int? lastSeenAtMs;
  const StoredDeviceSession({
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

  factory StoredDeviceSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredDeviceSession(
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

  StoredDeviceSession copyWith({
    String? sessionId,
    String? tokenHash,
    String? deviceName,
    int? createdAtMs,
    int? expiresAtMs,
    Value<int?> lastSeenAtMs = const Value.absent(),
  }) => StoredDeviceSession(
    sessionId: sessionId ?? this.sessionId,
    tokenHash: tokenHash ?? this.tokenHash,
    deviceName: deviceName ?? this.deviceName,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    expiresAtMs: expiresAtMs ?? this.expiresAtMs,
    lastSeenAtMs: lastSeenAtMs.present ? lastSeenAtMs.value : this.lastSeenAtMs,
  );
  StoredDeviceSession copyWithCompanion(DeviceSessionsCompanion data) {
    return StoredDeviceSession(
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
    return (StringBuffer('StoredDeviceSession(')
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
      (other is StoredDeviceSession &&
          other.sessionId == this.sessionId &&
          other.tokenHash == this.tokenHash &&
          other.deviceName == this.deviceName &&
          other.createdAtMs == this.createdAtMs &&
          other.expiresAtMs == this.expiresAtMs &&
          other.lastSeenAtMs == this.lastSeenAtMs);
}

class DeviceSessionsCompanion extends UpdateCompanion<StoredDeviceSession> {
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
  static Insertable<StoredDeviceSession> custom({
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

class $MayaMessagesTable extends MayaMessages
    with TableInfo<$MayaMessagesTable, StoredMayaMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MayaMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
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
  VerificationContext validateIntegrity(
    Insertable<StoredMayaMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('text')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['text']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {messageId};
  @override
  StoredMayaMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredMayaMessage(
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
  $MayaMessagesTable createAlias(String alias) {
    return $MayaMessagesTable(attachedDatabase, alias);
  }
}

class StoredMayaMessage extends DataClass
    implements Insertable<StoredMayaMessage> {
  final String messageId;
  final int sortOrder;
  final String role;
  final String content;
  final int createdAtMs;
  const StoredMayaMessage({
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

  factory StoredMayaMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredMayaMessage(
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

  StoredMayaMessage copyWith({
    String? messageId,
    int? sortOrder,
    String? role,
    String? content,
    int? createdAtMs,
  }) => StoredMayaMessage(
    messageId: messageId ?? this.messageId,
    sortOrder: sortOrder ?? this.sortOrder,
    role: role ?? this.role,
    content: content ?? this.content,
    createdAtMs: createdAtMs ?? this.createdAtMs,
  );
  StoredMayaMessage copyWithCompanion(MayaMessagesCompanion data) {
    return StoredMayaMessage(
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
    return (StringBuffer('StoredMayaMessage(')
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
      (other is StoredMayaMessage &&
          other.messageId == this.messageId &&
          other.sortOrder == this.sortOrder &&
          other.role == this.role &&
          other.content == this.content &&
          other.createdAtMs == this.createdAtMs);
}

class MayaMessagesCompanion extends UpdateCompanion<StoredMayaMessage> {
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
  static Insertable<StoredMayaMessage> custom({
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

class $MayaActionProposalsTable extends MayaActionProposals
    with TableInfo<$MayaActionProposalsTable, StoredMayaProposal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MayaActionProposalsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _proposalIdMeta = const VerificationMeta(
    'proposalId',
  );
  @override
  late final GeneratedColumn<String> proposalId = GeneratedColumn<String>(
    'proposal_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
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
  static const VerificationMeta _proposalOrderMeta = const VerificationMeta(
    'proposalOrder',
  );
  @override
  late final GeneratedColumn<int> proposalOrder = GeneratedColumn<int>(
    'proposal_order',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _confirmedAtMsMeta = const VerificationMeta(
    'confirmedAtMs',
  );
  @override
  late final GeneratedColumn<int> confirmedAtMs = GeneratedColumn<int>(
    'confirmed_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtMsMeta = const VerificationMeta(
    'completedAtMs',
  );
  @override
  late final GeneratedColumn<int> completedAtMs = GeneratedColumn<int>(
    'completed_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
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
  VerificationContext validateIntegrity(
    Insertable<StoredMayaProposal> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('proposal_id')) {
      context.handle(
        _proposalIdMeta,
        proposalId.isAcceptableOrUnknown(data['proposal_id']!, _proposalIdMeta),
      );
    } else if (isInserting) {
      context.missing(_proposalIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    }
    if (data.containsKey('proposal_order')) {
      context.handle(
        _proposalOrderMeta,
        proposalOrder.isAcceptableOrUnknown(
          data['proposal_order']!,
          _proposalOrderMeta,
        ),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('confirmed_at_ms')) {
      context.handle(
        _confirmedAtMsMeta,
        confirmedAtMs.isAcceptableOrUnknown(
          data['confirmed_at_ms']!,
          _confirmedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('completed_at_ms')) {
      context.handle(
        _completedAtMsMeta,
        completedAtMs.isAcceptableOrUnknown(
          data['completed_at_ms']!,
          _completedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {proposalId};
  @override
  StoredMayaProposal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredMayaProposal(
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
  $MayaActionProposalsTable createAlias(String alias) {
    return $MayaActionProposalsTable(attachedDatabase, alias);
  }
}

class StoredMayaProposal extends DataClass
    implements Insertable<StoredMayaProposal> {
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
  const StoredMayaProposal({
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

  factory StoredMayaProposal.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredMayaProposal(
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

  StoredMayaProposal copyWith({
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
  }) => StoredMayaProposal(
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
  StoredMayaProposal copyWithCompanion(MayaActionProposalsCompanion data) {
    return StoredMayaProposal(
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
    return (StringBuffer('StoredMayaProposal(')
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
      (other is StoredMayaProposal &&
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

class MayaActionProposalsCompanion extends UpdateCompanion<StoredMayaProposal> {
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
  static Insertable<StoredMayaProposal> custom({
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

class $MayaProviderSettingsTableTable extends MayaProviderSettingsTable
    with
        TableInfo<$MayaProviderSettingsTableTable, StoredMayaProviderSettings> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MayaProviderSettingsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _settingsIdMeta = const VerificationMeta(
    'settingsId',
  );
  @override
  late final GeneratedColumn<int> settingsId = GeneratedColumn<int>(
    'settings_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isEnabledMeta = const VerificationMeta(
    'isEnabled',
  );
  @override
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
  static const VerificationMeta _providerIdMeta = const VerificationMeta(
    'providerId',
  );
  @override
  late final GeneratedColumn<String> providerId = GeneratedColumn<String>(
    'provider_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelPolicyMeta = const VerificationMeta(
    'modelPolicy',
  );
  @override
  late final GeneratedColumn<String> modelPolicy = GeneratedColumn<String>(
    'model_policy',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _shareRecentHistoryMeta =
      const VerificationMeta('shareRecentHistory');
  @override
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
  static const VerificationMeta _shareLibraryContextMeta =
      const VerificationMeta('shareLibraryContext');
  @override
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
  static const VerificationMeta _consentVersionMeta = const VerificationMeta(
    'consentVersion',
  );
  @override
  late final GeneratedColumn<int> consentVersion = GeneratedColumn<int>(
    'consent_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _consentedAtMsMeta = const VerificationMeta(
    'consentedAtMs',
  );
  @override
  late final GeneratedColumn<int> consentedAtMs = GeneratedColumn<int>(
    'consented_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
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
  VerificationContext validateIntegrity(
    Insertable<StoredMayaProviderSettings> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('settings_id')) {
      context.handle(
        _settingsIdMeta,
        settingsId.isAcceptableOrUnknown(data['settings_id']!, _settingsIdMeta),
      );
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('is_enabled')) {
      context.handle(
        _isEnabledMeta,
        isEnabled.isAcceptableOrUnknown(data['is_enabled']!, _isEnabledMeta),
      );
    } else if (isInserting) {
      context.missing(_isEnabledMeta);
    }
    if (data.containsKey('provider_id')) {
      context.handle(
        _providerIdMeta,
        providerId.isAcceptableOrUnknown(data['provider_id']!, _providerIdMeta),
      );
    }
    if (data.containsKey('model_policy')) {
      context.handle(
        _modelPolicyMeta,
        modelPolicy.isAcceptableOrUnknown(
          data['model_policy']!,
          _modelPolicyMeta,
        ),
      );
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    }
    if (data.containsKey('share_recent_history')) {
      context.handle(
        _shareRecentHistoryMeta,
        shareRecentHistory.isAcceptableOrUnknown(
          data['share_recent_history']!,
          _shareRecentHistoryMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_shareRecentHistoryMeta);
    }
    if (data.containsKey('share_library_context')) {
      context.handle(
        _shareLibraryContextMeta,
        shareLibraryContext.isAcceptableOrUnknown(
          data['share_library_context']!,
          _shareLibraryContextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_shareLibraryContextMeta);
    }
    if (data.containsKey('consent_version')) {
      context.handle(
        _consentVersionMeta,
        consentVersion.isAcceptableOrUnknown(
          data['consent_version']!,
          _consentVersionMeta,
        ),
      );
    }
    if (data.containsKey('consented_at_ms')) {
      context.handle(
        _consentedAtMsMeta,
        consentedAtMs.isAcceptableOrUnknown(
          data['consented_at_ms']!,
          _consentedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {settingsId};
  @override
  StoredMayaProviderSettings map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredMayaProviderSettings(
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
  $MayaProviderSettingsTableTable createAlias(String alias) {
    return $MayaProviderSettingsTableTable(attachedDatabase, alias);
  }
}

class StoredMayaProviderSettings extends DataClass
    implements Insertable<StoredMayaProviderSettings> {
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
  const StoredMayaProviderSettings({
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

  MayaProviderSettingsTableCompanion toCompanion(bool nullToAbsent) {
    return MayaProviderSettingsTableCompanion(
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

  factory StoredMayaProviderSettings.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredMayaProviderSettings(
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

  StoredMayaProviderSettings copyWith({
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
  }) => StoredMayaProviderSettings(
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
  StoredMayaProviderSettings copyWithCompanion(
    MayaProviderSettingsTableCompanion data,
  ) {
    return StoredMayaProviderSettings(
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
    return (StringBuffer('StoredMayaProviderSettings(')
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
      (other is StoredMayaProviderSettings &&
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

class MayaProviderSettingsTableCompanion
    extends UpdateCompanion<StoredMayaProviderSettings> {
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
  const MayaProviderSettingsTableCompanion({
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
  MayaProviderSettingsTableCompanion.insert({
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
  static Insertable<StoredMayaProviderSettings> custom({
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

  MayaProviderSettingsTableCompanion copyWith({
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
    return MayaProviderSettingsTableCompanion(
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
    return (StringBuffer('MayaProviderSettingsTableCompanion(')
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

abstract class _$YomuDatabase extends GeneratedDatabase {
  _$YomuDatabase(QueryExecutor e) : super(e);
  $YomuDatabaseManager get managers => $YomuDatabaseManager(this);
  late final $AppMetaTable appMeta = $AppMetaTable(this);
  late final $DeviceSessionsTable deviceSessions = $DeviceSessionsTable(this);
  late final $MayaMessagesTable mayaMessages = $MayaMessagesTable(this);
  late final $MayaActionProposalsTable mayaActionProposals =
      $MayaActionProposalsTable(this);
  late final $MayaProviderSettingsTableTable mayaProviderSettingsTable =
      $MayaProviderSettingsTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    appMeta,
    deviceSessions,
    mayaMessages,
    mayaActionProposals,
    mayaProviderSettingsTable,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'maya_messages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('maya_action_proposals', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$AppMetaTableCreateCompanionBuilder =
    AppMetaCompanion Function({
      required String key,
      required String value,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$AppMetaTableUpdateCompanionBuilder =
    AppMetaCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$AppMetaTableFilterComposer
    extends Composer<_$YomuDatabase, $AppMetaTable> {
  $$AppMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppMetaTableOrderingComposer
    extends Composer<_$YomuDatabase, $AppMetaTable> {
  $$AppMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppMetaTableAnnotationComposer
    extends Composer<_$YomuDatabase, $AppMetaTable> {
  $$AppMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$AppMetaTableTableManager
    extends
        RootTableManager<
          _$YomuDatabase,
          $AppMetaTable,
          AppMetaData,
          $$AppMetaTableFilterComposer,
          $$AppMetaTableOrderingComposer,
          $$AppMetaTableAnnotationComposer,
          $$AppMetaTableCreateCompanionBuilder,
          $$AppMetaTableUpdateCompanionBuilder,
          (
            AppMetaData,
            BaseReferences<_$YomuDatabase, $AppMetaTable, AppMetaData>,
          ),
          AppMetaData,
          PrefetchHooks Function()
        > {
  $$AppMetaTableTableManager(_$YomuDatabase db, $AppMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppMetaCompanion(
                key: key,
                value: value,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => AppMetaCompanion.insert(
                key: key,
                value: value,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$YomuDatabase,
      $AppMetaTable,
      AppMetaData,
      $$AppMetaTableFilterComposer,
      $$AppMetaTableOrderingComposer,
      $$AppMetaTableAnnotationComposer,
      $$AppMetaTableCreateCompanionBuilder,
      $$AppMetaTableUpdateCompanionBuilder,
      (AppMetaData, BaseReferences<_$YomuDatabase, $AppMetaTable, AppMetaData>),
      AppMetaData,
      PrefetchHooks Function()
    >;
typedef $$DeviceSessionsTableCreateCompanionBuilder =
    DeviceSessionsCompanion Function({
      required String sessionId,
      required String tokenHash,
      required String deviceName,
      required int createdAtMs,
      required int expiresAtMs,
      Value<int?> lastSeenAtMs,
      Value<int> rowid,
    });
typedef $$DeviceSessionsTableUpdateCompanionBuilder =
    DeviceSessionsCompanion Function({
      Value<String> sessionId,
      Value<String> tokenHash,
      Value<String> deviceName,
      Value<int> createdAtMs,
      Value<int> expiresAtMs,
      Value<int?> lastSeenAtMs,
      Value<int> rowid,
    });

class $$DeviceSessionsTableFilterComposer
    extends Composer<_$YomuDatabase, $DeviceSessionsTable> {
  $$DeviceSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tokenHash => $composableBuilder(
    column: $table.tokenHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAtMs => $composableBuilder(
    column: $table.expiresAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSeenAtMs => $composableBuilder(
    column: $table.lastSeenAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DeviceSessionsTableOrderingComposer
    extends Composer<_$YomuDatabase, $DeviceSessionsTable> {
  $$DeviceSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tokenHash => $composableBuilder(
    column: $table.tokenHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAtMs => $composableBuilder(
    column: $table.expiresAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeenAtMs => $composableBuilder(
    column: $table.lastSeenAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DeviceSessionsTableAnnotationComposer
    extends Composer<_$YomuDatabase, $DeviceSessionsTable> {
  $$DeviceSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get tokenHash =>
      $composableBuilder(column: $table.tokenHash, builder: (column) => column);

  GeneratedColumn<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expiresAtMs => $composableBuilder(
    column: $table.expiresAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastSeenAtMs => $composableBuilder(
    column: $table.lastSeenAtMs,
    builder: (column) => column,
  );
}

class $$DeviceSessionsTableTableManager
    extends
        RootTableManager<
          _$YomuDatabase,
          $DeviceSessionsTable,
          StoredDeviceSession,
          $$DeviceSessionsTableFilterComposer,
          $$DeviceSessionsTableOrderingComposer,
          $$DeviceSessionsTableAnnotationComposer,
          $$DeviceSessionsTableCreateCompanionBuilder,
          $$DeviceSessionsTableUpdateCompanionBuilder,
          (
            StoredDeviceSession,
            BaseReferences<
              _$YomuDatabase,
              $DeviceSessionsTable,
              StoredDeviceSession
            >,
          ),
          StoredDeviceSession,
          PrefetchHooks Function()
        > {
  $$DeviceSessionsTableTableManager(
    _$YomuDatabase db,
    $DeviceSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeviceSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DeviceSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DeviceSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> tokenHash = const Value.absent(),
                Value<String> deviceName = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> expiresAtMs = const Value.absent(),
                Value<int?> lastSeenAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeviceSessionsCompanion(
                sessionId: sessionId,
                tokenHash: tokenHash,
                deviceName: deviceName,
                createdAtMs: createdAtMs,
                expiresAtMs: expiresAtMs,
                lastSeenAtMs: lastSeenAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required String tokenHash,
                required String deviceName,
                required int createdAtMs,
                required int expiresAtMs,
                Value<int?> lastSeenAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeviceSessionsCompanion.insert(
                sessionId: sessionId,
                tokenHash: tokenHash,
                deviceName: deviceName,
                createdAtMs: createdAtMs,
                expiresAtMs: expiresAtMs,
                lastSeenAtMs: lastSeenAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DeviceSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$YomuDatabase,
      $DeviceSessionsTable,
      StoredDeviceSession,
      $$DeviceSessionsTableFilterComposer,
      $$DeviceSessionsTableOrderingComposer,
      $$DeviceSessionsTableAnnotationComposer,
      $$DeviceSessionsTableCreateCompanionBuilder,
      $$DeviceSessionsTableUpdateCompanionBuilder,
      (
        StoredDeviceSession,
        BaseReferences<
          _$YomuDatabase,
          $DeviceSessionsTable,
          StoredDeviceSession
        >,
      ),
      StoredDeviceSession,
      PrefetchHooks Function()
    >;
typedef $$MayaMessagesTableCreateCompanionBuilder =
    MayaMessagesCompanion Function({
      required String messageId,
      required int sortOrder,
      required String role,
      required String content,
      required int createdAtMs,
      Value<int> rowid,
    });
typedef $$MayaMessagesTableUpdateCompanionBuilder =
    MayaMessagesCompanion Function({
      Value<String> messageId,
      Value<int> sortOrder,
      Value<String> role,
      Value<String> content,
      Value<int> createdAtMs,
      Value<int> rowid,
    });

final class $$MayaMessagesTableReferences
    extends
        BaseReferences<_$YomuDatabase, $MayaMessagesTable, StoredMayaMessage> {
  $$MayaMessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<
    $MayaActionProposalsTable,
    List<StoredMayaProposal>
  >
  _mayaActionProposalsRefsTable(_$YomuDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.mayaActionProposals,
        aliasName: $_aliasNameGenerator(
          db.mayaMessages.messageId,
          db.mayaActionProposals.messageId,
        ),
      );

  $$MayaActionProposalsTableProcessedTableManager get mayaActionProposalsRefs {
    final manager =
        $$MayaActionProposalsTableTableManager(
          $_db,
          $_db.mayaActionProposals,
        ).filter(
          (f) => f.messageId.messageId.sqlEquals(
            $_itemColumn<String>('message_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _mayaActionProposalsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MayaMessagesTableFilterComposer
    extends Composer<_$YomuDatabase, $MayaMessagesTable> {
  $$MayaMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> mayaActionProposalsRefs(
    Expression<bool> Function($$MayaActionProposalsTableFilterComposer f) f,
  ) {
    final $$MayaActionProposalsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.mayaActionProposals,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MayaActionProposalsTableFilterComposer(
            $db: $db,
            $table: $db.mayaActionProposals,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MayaMessagesTableOrderingComposer
    extends Composer<_$YomuDatabase, $MayaMessagesTable> {
  $$MayaMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MayaMessagesTableAnnotationComposer
    extends Composer<_$YomuDatabase, $MayaMessagesTable> {
  $$MayaMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  Expression<T> mayaActionProposalsRefs<T extends Object>(
    Expression<T> Function($$MayaActionProposalsTableAnnotationComposer a) f,
  ) {
    final $$MayaActionProposalsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.messageId,
          referencedTable: $db.mayaActionProposals,
          getReferencedColumn: (t) => t.messageId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$MayaActionProposalsTableAnnotationComposer(
                $db: $db,
                $table: $db.mayaActionProposals,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$MayaMessagesTableTableManager
    extends
        RootTableManager<
          _$YomuDatabase,
          $MayaMessagesTable,
          StoredMayaMessage,
          $$MayaMessagesTableFilterComposer,
          $$MayaMessagesTableOrderingComposer,
          $$MayaMessagesTableAnnotationComposer,
          $$MayaMessagesTableCreateCompanionBuilder,
          $$MayaMessagesTableUpdateCompanionBuilder,
          (StoredMayaMessage, $$MayaMessagesTableReferences),
          StoredMayaMessage,
          PrefetchHooks Function({bool mayaActionProposalsRefs})
        > {
  $$MayaMessagesTableTableManager(_$YomuDatabase db, $MayaMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MayaMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MayaMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MayaMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> messageId = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MayaMessagesCompanion(
                messageId: messageId,
                sortOrder: sortOrder,
                role: role,
                content: content,
                createdAtMs: createdAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String messageId,
                required int sortOrder,
                required String role,
                required String content,
                required int createdAtMs,
                Value<int> rowid = const Value.absent(),
              }) => MayaMessagesCompanion.insert(
                messageId: messageId,
                sortOrder: sortOrder,
                role: role,
                content: content,
                createdAtMs: createdAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MayaMessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({mayaActionProposalsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (mayaActionProposalsRefs) db.mayaActionProposals,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (mayaActionProposalsRefs)
                    await $_getPrefetchedData<
                      StoredMayaMessage,
                      $MayaMessagesTable,
                      StoredMayaProposal
                    >(
                      currentTable: table,
                      referencedTable: $$MayaMessagesTableReferences
                          ._mayaActionProposalsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$MayaMessagesTableReferences(
                            db,
                            table,
                            p0,
                          ).mayaActionProposalsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.messageId == item.messageId,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$MayaMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$YomuDatabase,
      $MayaMessagesTable,
      StoredMayaMessage,
      $$MayaMessagesTableFilterComposer,
      $$MayaMessagesTableOrderingComposer,
      $$MayaMessagesTableAnnotationComposer,
      $$MayaMessagesTableCreateCompanionBuilder,
      $$MayaMessagesTableUpdateCompanionBuilder,
      (StoredMayaMessage, $$MayaMessagesTableReferences),
      StoredMayaMessage,
      PrefetchHooks Function({bool mayaActionProposalsRefs})
    >;
typedef $$MayaActionProposalsTableCreateCompanionBuilder =
    MayaActionProposalsCompanion Function({
      required String proposalId,
      Value<String?> messageId,
      Value<int?> proposalOrder,
      required String kind,
      required String title,
      required String description,
      required String payloadJson,
      required String status,
      required int createdAtMs,
      Value<int?> confirmedAtMs,
      Value<int?> completedAtMs,
      Value<String?> error,
      Value<int> rowid,
    });
typedef $$MayaActionProposalsTableUpdateCompanionBuilder =
    MayaActionProposalsCompanion Function({
      Value<String> proposalId,
      Value<String?> messageId,
      Value<int?> proposalOrder,
      Value<String> kind,
      Value<String> title,
      Value<String> description,
      Value<String> payloadJson,
      Value<String> status,
      Value<int> createdAtMs,
      Value<int?> confirmedAtMs,
      Value<int?> completedAtMs,
      Value<String?> error,
      Value<int> rowid,
    });

final class $$MayaActionProposalsTableReferences
    extends
        BaseReferences<
          _$YomuDatabase,
          $MayaActionProposalsTable,
          StoredMayaProposal
        > {
  $$MayaActionProposalsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MayaMessagesTable _messageIdTable(_$YomuDatabase db) =>
      db.mayaMessages.createAlias(
        $_aliasNameGenerator(
          db.mayaActionProposals.messageId,
          db.mayaMessages.messageId,
        ),
      );

  $$MayaMessagesTableProcessedTableManager? get messageId {
    final $_column = $_itemColumn<String>('message_id');
    if ($_column == null) return null;
    final manager = $$MayaMessagesTableTableManager(
      $_db,
      $_db.mayaMessages,
    ).filter((f) => f.messageId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_messageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MayaActionProposalsTableFilterComposer
    extends Composer<_$YomuDatabase, $MayaActionProposalsTable> {
  $$MayaActionProposalsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get proposalId => $composableBuilder(
    column: $table.proposalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get proposalOrder => $composableBuilder(
    column: $table.proposalOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get confirmedAtMs => $composableBuilder(
    column: $table.confirmedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedAtMs => $composableBuilder(
    column: $table.completedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  $$MayaMessagesTableFilterComposer get messageId {
    final $$MayaMessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.mayaMessages,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MayaMessagesTableFilterComposer(
            $db: $db,
            $table: $db.mayaMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MayaActionProposalsTableOrderingComposer
    extends Composer<_$YomuDatabase, $MayaActionProposalsTable> {
  $$MayaActionProposalsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get proposalId => $composableBuilder(
    column: $table.proposalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get proposalOrder => $composableBuilder(
    column: $table.proposalOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get confirmedAtMs => $composableBuilder(
    column: $table.confirmedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedAtMs => $composableBuilder(
    column: $table.completedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  $$MayaMessagesTableOrderingComposer get messageId {
    final $$MayaMessagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.mayaMessages,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MayaMessagesTableOrderingComposer(
            $db: $db,
            $table: $db.mayaMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MayaActionProposalsTableAnnotationComposer
    extends Composer<_$YomuDatabase, $MayaActionProposalsTable> {
  $$MayaActionProposalsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get proposalId => $composableBuilder(
    column: $table.proposalId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get proposalOrder => $composableBuilder(
    column: $table.proposalOrder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get confirmedAtMs => $composableBuilder(
    column: $table.confirmedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedAtMs => $composableBuilder(
    column: $table.completedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  $$MayaMessagesTableAnnotationComposer get messageId {
    final $$MayaMessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.mayaMessages,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MayaMessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.mayaMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MayaActionProposalsTableTableManager
    extends
        RootTableManager<
          _$YomuDatabase,
          $MayaActionProposalsTable,
          StoredMayaProposal,
          $$MayaActionProposalsTableFilterComposer,
          $$MayaActionProposalsTableOrderingComposer,
          $$MayaActionProposalsTableAnnotationComposer,
          $$MayaActionProposalsTableCreateCompanionBuilder,
          $$MayaActionProposalsTableUpdateCompanionBuilder,
          (StoredMayaProposal, $$MayaActionProposalsTableReferences),
          StoredMayaProposal,
          PrefetchHooks Function({bool messageId})
        > {
  $$MayaActionProposalsTableTableManager(
    _$YomuDatabase db,
    $MayaActionProposalsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MayaActionProposalsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MayaActionProposalsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$MayaActionProposalsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> proposalId = const Value.absent(),
                Value<String?> messageId = const Value.absent(),
                Value<int?> proposalOrder = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int?> confirmedAtMs = const Value.absent(),
                Value<int?> completedAtMs = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MayaActionProposalsCompanion(
                proposalId: proposalId,
                messageId: messageId,
                proposalOrder: proposalOrder,
                kind: kind,
                title: title,
                description: description,
                payloadJson: payloadJson,
                status: status,
                createdAtMs: createdAtMs,
                confirmedAtMs: confirmedAtMs,
                completedAtMs: completedAtMs,
                error: error,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String proposalId,
                Value<String?> messageId = const Value.absent(),
                Value<int?> proposalOrder = const Value.absent(),
                required String kind,
                required String title,
                required String description,
                required String payloadJson,
                required String status,
                required int createdAtMs,
                Value<int?> confirmedAtMs = const Value.absent(),
                Value<int?> completedAtMs = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MayaActionProposalsCompanion.insert(
                proposalId: proposalId,
                messageId: messageId,
                proposalOrder: proposalOrder,
                kind: kind,
                title: title,
                description: description,
                payloadJson: payloadJson,
                status: status,
                createdAtMs: createdAtMs,
                confirmedAtMs: confirmedAtMs,
                completedAtMs: completedAtMs,
                error: error,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MayaActionProposalsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({messageId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (messageId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.messageId,
                                referencedTable:
                                    $$MayaActionProposalsTableReferences
                                        ._messageIdTable(db),
                                referencedColumn:
                                    $$MayaActionProposalsTableReferences
                                        ._messageIdTable(db)
                                        .messageId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MayaActionProposalsTableProcessedTableManager =
    ProcessedTableManager<
      _$YomuDatabase,
      $MayaActionProposalsTable,
      StoredMayaProposal,
      $$MayaActionProposalsTableFilterComposer,
      $$MayaActionProposalsTableOrderingComposer,
      $$MayaActionProposalsTableAnnotationComposer,
      $$MayaActionProposalsTableCreateCompanionBuilder,
      $$MayaActionProposalsTableUpdateCompanionBuilder,
      (StoredMayaProposal, $$MayaActionProposalsTableReferences),
      StoredMayaProposal,
      PrefetchHooks Function({bool messageId})
    >;
typedef $$MayaProviderSettingsTableTableCreateCompanionBuilder =
    MayaProviderSettingsTableCompanion Function({
      Value<int> settingsId,
      required String mode,
      required bool isEnabled,
      Value<String?> providerId,
      Value<String?> modelPolicy,
      Value<String?> modelId,
      required bool shareRecentHistory,
      required bool shareLibraryContext,
      Value<int?> consentVersion,
      Value<int?> consentedAtMs,
      required int updatedAtMs,
    });
typedef $$MayaProviderSettingsTableTableUpdateCompanionBuilder =
    MayaProviderSettingsTableCompanion Function({
      Value<int> settingsId,
      Value<String> mode,
      Value<bool> isEnabled,
      Value<String?> providerId,
      Value<String?> modelPolicy,
      Value<String?> modelId,
      Value<bool> shareRecentHistory,
      Value<bool> shareLibraryContext,
      Value<int?> consentVersion,
      Value<int?> consentedAtMs,
      Value<int> updatedAtMs,
    });

class $$MayaProviderSettingsTableTableFilterComposer
    extends Composer<_$YomuDatabase, $MayaProviderSettingsTableTable> {
  $$MayaProviderSettingsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get settingsId => $composableBuilder(
    column: $table.settingsId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isEnabled => $composableBuilder(
    column: $table.isEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelPolicy => $composableBuilder(
    column: $table.modelPolicy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get shareRecentHistory => $composableBuilder(
    column: $table.shareRecentHistory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get shareLibraryContext => $composableBuilder(
    column: $table.shareLibraryContext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get consentVersion => $composableBuilder(
    column: $table.consentVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get consentedAtMs => $composableBuilder(
    column: $table.consentedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MayaProviderSettingsTableTableOrderingComposer
    extends Composer<_$YomuDatabase, $MayaProviderSettingsTableTable> {
  $$MayaProviderSettingsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get settingsId => $composableBuilder(
    column: $table.settingsId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isEnabled => $composableBuilder(
    column: $table.isEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelPolicy => $composableBuilder(
    column: $table.modelPolicy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get shareRecentHistory => $composableBuilder(
    column: $table.shareRecentHistory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get shareLibraryContext => $composableBuilder(
    column: $table.shareLibraryContext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get consentVersion => $composableBuilder(
    column: $table.consentVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get consentedAtMs => $composableBuilder(
    column: $table.consentedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MayaProviderSettingsTableTableAnnotationComposer
    extends Composer<_$YomuDatabase, $MayaProviderSettingsTableTable> {
  $$MayaProviderSettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get settingsId => $composableBuilder(
    column: $table.settingsId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<bool> get isEnabled =>
      $composableBuilder(column: $table.isEnabled, builder: (column) => column);

  GeneratedColumn<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get modelPolicy => $composableBuilder(
    column: $table.modelPolicy,
    builder: (column) => column,
  );

  GeneratedColumn<String> get modelId =>
      $composableBuilder(column: $table.modelId, builder: (column) => column);

  GeneratedColumn<bool> get shareRecentHistory => $composableBuilder(
    column: $table.shareRecentHistory,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get shareLibraryContext => $composableBuilder(
    column: $table.shareLibraryContext,
    builder: (column) => column,
  );

  GeneratedColumn<int> get consentVersion => $composableBuilder(
    column: $table.consentVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get consentedAtMs => $composableBuilder(
    column: $table.consentedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$MayaProviderSettingsTableTableTableManager
    extends
        RootTableManager<
          _$YomuDatabase,
          $MayaProviderSettingsTableTable,
          StoredMayaProviderSettings,
          $$MayaProviderSettingsTableTableFilterComposer,
          $$MayaProviderSettingsTableTableOrderingComposer,
          $$MayaProviderSettingsTableTableAnnotationComposer,
          $$MayaProviderSettingsTableTableCreateCompanionBuilder,
          $$MayaProviderSettingsTableTableUpdateCompanionBuilder,
          (
            StoredMayaProviderSettings,
            BaseReferences<
              _$YomuDatabase,
              $MayaProviderSettingsTableTable,
              StoredMayaProviderSettings
            >,
          ),
          StoredMayaProviderSettings,
          PrefetchHooks Function()
        > {
  $$MayaProviderSettingsTableTableTableManager(
    _$YomuDatabase db,
    $MayaProviderSettingsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MayaProviderSettingsTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$MayaProviderSettingsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$MayaProviderSettingsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> settingsId = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<bool> isEnabled = const Value.absent(),
                Value<String?> providerId = const Value.absent(),
                Value<String?> modelPolicy = const Value.absent(),
                Value<String?> modelId = const Value.absent(),
                Value<bool> shareRecentHistory = const Value.absent(),
                Value<bool> shareLibraryContext = const Value.absent(),
                Value<int?> consentVersion = const Value.absent(),
                Value<int?> consentedAtMs = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
              }) => MayaProviderSettingsTableCompanion(
                settingsId: settingsId,
                mode: mode,
                isEnabled: isEnabled,
                providerId: providerId,
                modelPolicy: modelPolicy,
                modelId: modelId,
                shareRecentHistory: shareRecentHistory,
                shareLibraryContext: shareLibraryContext,
                consentVersion: consentVersion,
                consentedAtMs: consentedAtMs,
                updatedAtMs: updatedAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> settingsId = const Value.absent(),
                required String mode,
                required bool isEnabled,
                Value<String?> providerId = const Value.absent(),
                Value<String?> modelPolicy = const Value.absent(),
                Value<String?> modelId = const Value.absent(),
                required bool shareRecentHistory,
                required bool shareLibraryContext,
                Value<int?> consentVersion = const Value.absent(),
                Value<int?> consentedAtMs = const Value.absent(),
                required int updatedAtMs,
              }) => MayaProviderSettingsTableCompanion.insert(
                settingsId: settingsId,
                mode: mode,
                isEnabled: isEnabled,
                providerId: providerId,
                modelPolicy: modelPolicy,
                modelId: modelId,
                shareRecentHistory: shareRecentHistory,
                shareLibraryContext: shareLibraryContext,
                consentVersion: consentVersion,
                consentedAtMs: consentedAtMs,
                updatedAtMs: updatedAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MayaProviderSettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$YomuDatabase,
      $MayaProviderSettingsTableTable,
      StoredMayaProviderSettings,
      $$MayaProviderSettingsTableTableFilterComposer,
      $$MayaProviderSettingsTableTableOrderingComposer,
      $$MayaProviderSettingsTableTableAnnotationComposer,
      $$MayaProviderSettingsTableTableCreateCompanionBuilder,
      $$MayaProviderSettingsTableTableUpdateCompanionBuilder,
      (
        StoredMayaProviderSettings,
        BaseReferences<
          _$YomuDatabase,
          $MayaProviderSettingsTableTable,
          StoredMayaProviderSettings
        >,
      ),
      StoredMayaProviderSettings,
      PrefetchHooks Function()
    >;

class $YomuDatabaseManager {
  final _$YomuDatabase _db;
  $YomuDatabaseManager(this._db);
  $$AppMetaTableTableManager get appMeta =>
      $$AppMetaTableTableManager(_db, _db.appMeta);
  $$DeviceSessionsTableTableManager get deviceSessions =>
      $$DeviceSessionsTableTableManager(_db, _db.deviceSessions);
  $$MayaMessagesTableTableManager get mayaMessages =>
      $$MayaMessagesTableTableManager(_db, _db.mayaMessages);
  $$MayaActionProposalsTableTableManager get mayaActionProposals =>
      $$MayaActionProposalsTableTableManager(_db, _db.mayaActionProposals);
  $$MayaProviderSettingsTableTableTableManager get mayaProviderSettingsTable =>
      $$MayaProviderSettingsTableTableTableManager(
        _db,
        _db.mayaProviderSettingsTable,
      );
}
