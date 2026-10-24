// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $FootChecksTable extends FootChecks
    with TableInfo<$FootChecksTable, FootCheckRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FootChecksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _atMsMeta = const VerificationMeta('atMs');
  @override
  late final GeneratedColumn<int> atMs = GeneratedColumn<int>(
    'at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localDateMeta = const VerificationMeta(
    'localDate',
  );
  @override
  late final GeneratedColumn<String> localDate = GeneratedColumn<String>(
    'local_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<FootCheckAnswer?, String>
  qRedness = GeneratedColumn<String>(
    'q_redness',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<FootCheckAnswer?>($FootChecksTable.$converterqRednessn);
  @override
  late final GeneratedColumnWithTypeConverter<FootCheckAnswer?, String> qWound =
      GeneratedColumn<String>(
        'q_wound',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<FootCheckAnswer?>($FootChecksTable.$converterqWoundn);
  @override
  late final GeneratedColumnWithTypeConverter<FootCheckAnswer?, String>
  qSwelling = GeneratedColumn<String>(
    'q_swelling',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<FootCheckAnswer?>($FootChecksTable.$converterqSwellingn);
  @override
  late final GeneratedColumnWithTypeConverter<FootCheckResult, String> result =
      GeneratedColumn<String>(
        'result',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<FootCheckResult>($FootChecksTable.$converterresult);
  static const VerificationMeta _photoSoleLeftMeta = const VerificationMeta(
    'photoSoleLeft',
  );
  @override
  late final GeneratedColumn<String> photoSoleLeft = GeneratedColumn<String>(
    'photo_sole_left',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _photoSoleRightMeta = const VerificationMeta(
    'photoSoleRight',
  );
  @override
  late final GeneratedColumn<String> photoSoleRight = GeneratedColumn<String>(
    'photo_sole_right',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _photoTopLeftMeta = const VerificationMeta(
    'photoTopLeft',
  );
  @override
  late final GeneratedColumn<String> photoTopLeft = GeneratedColumn<String>(
    'photo_top_left',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _photoTopRightMeta = const VerificationMeta(
    'photoTopRight',
  );
  @override
  late final GeneratedColumn<String> photoTopRight = GeneratedColumn<String>(
    'photo_top_right',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _answerOnlyMeta = const VerificationMeta(
    'answerOnly',
  );
  @override
  late final GeneratedColumn<bool> answerOnly = GeneratedColumn<bool>(
    'answer_only',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("answer_only" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    atMs,
    localDate,
    qRedness,
    qWound,
    qSwelling,
    result,
    photoSoleLeft,
    photoSoleRight,
    photoTopLeft,
    photoTopRight,
    answerOnly,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'foot_checks';
  @override
  VerificationContext validateIntegrity(
    Insertable<FootCheckRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('at_ms')) {
      context.handle(
        _atMsMeta,
        atMs.isAcceptableOrUnknown(data['at_ms']!, _atMsMeta),
      );
    } else if (isInserting) {
      context.missing(_atMsMeta);
    }
    if (data.containsKey('local_date')) {
      context.handle(
        _localDateMeta,
        localDate.isAcceptableOrUnknown(data['local_date']!, _localDateMeta),
      );
    } else if (isInserting) {
      context.missing(_localDateMeta);
    }
    if (data.containsKey('photo_sole_left')) {
      context.handle(
        _photoSoleLeftMeta,
        photoSoleLeft.isAcceptableOrUnknown(
          data['photo_sole_left']!,
          _photoSoleLeftMeta,
        ),
      );
    }
    if (data.containsKey('photo_sole_right')) {
      context.handle(
        _photoSoleRightMeta,
        photoSoleRight.isAcceptableOrUnknown(
          data['photo_sole_right']!,
          _photoSoleRightMeta,
        ),
      );
    }
    if (data.containsKey('photo_top_left')) {
      context.handle(
        _photoTopLeftMeta,
        photoTopLeft.isAcceptableOrUnknown(
          data['photo_top_left']!,
          _photoTopLeftMeta,
        ),
      );
    }
    if (data.containsKey('photo_top_right')) {
      context.handle(
        _photoTopRightMeta,
        photoTopRight.isAcceptableOrUnknown(
          data['photo_top_right']!,
          _photoTopRightMeta,
        ),
      );
    }
    if (data.containsKey('answer_only')) {
      context.handle(
        _answerOnlyMeta,
        answerOnly.isAcceptableOrUnknown(data['answer_only']!, _answerOnlyMeta),
      );
    } else if (isInserting) {
      context.missing(_answerOnlyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FootCheckRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FootCheckRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      atMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}at_ms'],
      )!,
      localDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_date'],
      )!,
      qRedness: $FootChecksTable.$converterqRednessn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}q_redness'],
        ),
      ),
      qWound: $FootChecksTable.$converterqWoundn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}q_wound'],
        ),
      ),
      qSwelling: $FootChecksTable.$converterqSwellingn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}q_swelling'],
        ),
      ),
      result: $FootChecksTable.$converterresult.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}result'],
        )!,
      ),
      photoSoleLeft: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_sole_left'],
      ),
      photoSoleRight: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_sole_right'],
      ),
      photoTopLeft: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_top_left'],
      ),
      photoTopRight: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_top_right'],
      ),
      answerOnly: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}answer_only'],
      )!,
    );
  }

  @override
  $FootChecksTable createAlias(String alias) {
    return $FootChecksTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<FootCheckAnswer, String, String>
  $converterqRedness = const EnumNameConverter<FootCheckAnswer>(
    FootCheckAnswer.values,
  );
  static JsonTypeConverter2<FootCheckAnswer?, String?, String?>
  $converterqRednessn = JsonTypeConverter2.asNullable($converterqRedness);
  static JsonTypeConverter2<FootCheckAnswer, String, String> $converterqWound =
      const EnumNameConverter<FootCheckAnswer>(FootCheckAnswer.values);
  static JsonTypeConverter2<FootCheckAnswer?, String?, String?>
  $converterqWoundn = JsonTypeConverter2.asNullable($converterqWound);
  static JsonTypeConverter2<FootCheckAnswer, String, String>
  $converterqSwelling = const EnumNameConverter<FootCheckAnswer>(
    FootCheckAnswer.values,
  );
  static JsonTypeConverter2<FootCheckAnswer?, String?, String?>
  $converterqSwellingn = JsonTypeConverter2.asNullable($converterqSwelling);
  static JsonTypeConverter2<FootCheckResult, String, String> $converterresult =
      const EnumNameConverter<FootCheckResult>(FootCheckResult.values);
}

class FootCheckRow extends DataClass implements Insertable<FootCheckRow> {
  final int id;
  final int atMs;
  final String localDate;
  final FootCheckAnswer? qRedness;
  final FootCheckAnswer? qWound;
  final FootCheckAnswer? qSwelling;
  final FootCheckResult result;
  final String? photoSoleLeft;
  final String? photoSoleRight;
  final String? photoTopLeft;
  final String? photoTopRight;
  final bool answerOnly;
  const FootCheckRow({
    required this.id,
    required this.atMs,
    required this.localDate,
    this.qRedness,
    this.qWound,
    this.qSwelling,
    required this.result,
    this.photoSoleLeft,
    this.photoSoleRight,
    this.photoTopLeft,
    this.photoTopRight,
    required this.answerOnly,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['at_ms'] = Variable<int>(atMs);
    map['local_date'] = Variable<String>(localDate);
    if (!nullToAbsent || qRedness != null) {
      map['q_redness'] = Variable<String>(
        $FootChecksTable.$converterqRednessn.toSql(qRedness),
      );
    }
    if (!nullToAbsent || qWound != null) {
      map['q_wound'] = Variable<String>(
        $FootChecksTable.$converterqWoundn.toSql(qWound),
      );
    }
    if (!nullToAbsent || qSwelling != null) {
      map['q_swelling'] = Variable<String>(
        $FootChecksTable.$converterqSwellingn.toSql(qSwelling),
      );
    }
    {
      map['result'] = Variable<String>(
        $FootChecksTable.$converterresult.toSql(result),
      );
    }
    if (!nullToAbsent || photoSoleLeft != null) {
      map['photo_sole_left'] = Variable<String>(photoSoleLeft);
    }
    if (!nullToAbsent || photoSoleRight != null) {
      map['photo_sole_right'] = Variable<String>(photoSoleRight);
    }
    if (!nullToAbsent || photoTopLeft != null) {
      map['photo_top_left'] = Variable<String>(photoTopLeft);
    }
    if (!nullToAbsent || photoTopRight != null) {
      map['photo_top_right'] = Variable<String>(photoTopRight);
    }
    map['answer_only'] = Variable<bool>(answerOnly);
    return map;
  }

  FootChecksCompanion toCompanion(bool nullToAbsent) {
    return FootChecksCompanion(
      id: Value(id),
      atMs: Value(atMs),
      localDate: Value(localDate),
      qRedness: qRedness == null && nullToAbsent
          ? const Value.absent()
          : Value(qRedness),
      qWound: qWound == null && nullToAbsent
          ? const Value.absent()
          : Value(qWound),
      qSwelling: qSwelling == null && nullToAbsent
          ? const Value.absent()
          : Value(qSwelling),
      result: Value(result),
      photoSoleLeft: photoSoleLeft == null && nullToAbsent
          ? const Value.absent()
          : Value(photoSoleLeft),
      photoSoleRight: photoSoleRight == null && nullToAbsent
          ? const Value.absent()
          : Value(photoSoleRight),
      photoTopLeft: photoTopLeft == null && nullToAbsent
          ? const Value.absent()
          : Value(photoTopLeft),
      photoTopRight: photoTopRight == null && nullToAbsent
          ? const Value.absent()
          : Value(photoTopRight),
      answerOnly: Value(answerOnly),
    );
  }

  factory FootCheckRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FootCheckRow(
      id: serializer.fromJson<int>(json['id']),
      atMs: serializer.fromJson<int>(json['atMs']),
      localDate: serializer.fromJson<String>(json['localDate']),
      qRedness: $FootChecksTable.$converterqRednessn.fromJson(
        serializer.fromJson<String?>(json['qRedness']),
      ),
      qWound: $FootChecksTable.$converterqWoundn.fromJson(
        serializer.fromJson<String?>(json['qWound']),
      ),
      qSwelling: $FootChecksTable.$converterqSwellingn.fromJson(
        serializer.fromJson<String?>(json['qSwelling']),
      ),
      result: $FootChecksTable.$converterresult.fromJson(
        serializer.fromJson<String>(json['result']),
      ),
      photoSoleLeft: serializer.fromJson<String?>(json['photoSoleLeft']),
      photoSoleRight: serializer.fromJson<String?>(json['photoSoleRight']),
      photoTopLeft: serializer.fromJson<String?>(json['photoTopLeft']),
      photoTopRight: serializer.fromJson<String?>(json['photoTopRight']),
      answerOnly: serializer.fromJson<bool>(json['answerOnly']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'atMs': serializer.toJson<int>(atMs),
      'localDate': serializer.toJson<String>(localDate),
      'qRedness': serializer.toJson<String?>(
        $FootChecksTable.$converterqRednessn.toJson(qRedness),
      ),
      'qWound': serializer.toJson<String?>(
        $FootChecksTable.$converterqWoundn.toJson(qWound),
      ),
      'qSwelling': serializer.toJson<String?>(
        $FootChecksTable.$converterqSwellingn.toJson(qSwelling),
      ),
      'result': serializer.toJson<String>(
        $FootChecksTable.$converterresult.toJson(result),
      ),
      'photoSoleLeft': serializer.toJson<String?>(photoSoleLeft),
      'photoSoleRight': serializer.toJson<String?>(photoSoleRight),
      'photoTopLeft': serializer.toJson<String?>(photoTopLeft),
      'photoTopRight': serializer.toJson<String?>(photoTopRight),
      'answerOnly': serializer.toJson<bool>(answerOnly),
    };
  }

  FootCheckRow copyWith({
    int? id,
    int? atMs,
    String? localDate,
    Value<FootCheckAnswer?> qRedness = const Value.absent(),
    Value<FootCheckAnswer?> qWound = const Value.absent(),
    Value<FootCheckAnswer?> qSwelling = const Value.absent(),
    FootCheckResult? result,
    Value<String?> photoSoleLeft = const Value.absent(),
    Value<String?> photoSoleRight = const Value.absent(),
    Value<String?> photoTopLeft = const Value.absent(),
    Value<String?> photoTopRight = const Value.absent(),
    bool? answerOnly,
  }) => FootCheckRow(
    id: id ?? this.id,
    atMs: atMs ?? this.atMs,
    localDate: localDate ?? this.localDate,
    qRedness: qRedness.present ? qRedness.value : this.qRedness,
    qWound: qWound.present ? qWound.value : this.qWound,
    qSwelling: qSwelling.present ? qSwelling.value : this.qSwelling,
    result: result ?? this.result,
    photoSoleLeft: photoSoleLeft.present
        ? photoSoleLeft.value
        : this.photoSoleLeft,
    photoSoleRight: photoSoleRight.present
        ? photoSoleRight.value
        : this.photoSoleRight,
    photoTopLeft: photoTopLeft.present ? photoTopLeft.value : this.photoTopLeft,
    photoTopRight: photoTopRight.present
        ? photoTopRight.value
        : this.photoTopRight,
    answerOnly: answerOnly ?? this.answerOnly,
  );
  FootCheckRow copyWithCompanion(FootChecksCompanion data) {
    return FootCheckRow(
      id: data.id.present ? data.id.value : this.id,
      atMs: data.atMs.present ? data.atMs.value : this.atMs,
      localDate: data.localDate.present ? data.localDate.value : this.localDate,
      qRedness: data.qRedness.present ? data.qRedness.value : this.qRedness,
      qWound: data.qWound.present ? data.qWound.value : this.qWound,
      qSwelling: data.qSwelling.present ? data.qSwelling.value : this.qSwelling,
      result: data.result.present ? data.result.value : this.result,
      photoSoleLeft: data.photoSoleLeft.present
          ? data.photoSoleLeft.value
          : this.photoSoleLeft,
      photoSoleRight: data.photoSoleRight.present
          ? data.photoSoleRight.value
          : this.photoSoleRight,
      photoTopLeft: data.photoTopLeft.present
          ? data.photoTopLeft.value
          : this.photoTopLeft,
      photoTopRight: data.photoTopRight.present
          ? data.photoTopRight.value
          : this.photoTopRight,
      answerOnly: data.answerOnly.present
          ? data.answerOnly.value
          : this.answerOnly,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FootCheckRow(')
          ..write('id: $id, ')
          ..write('atMs: $atMs, ')
          ..write('localDate: $localDate, ')
          ..write('qRedness: $qRedness, ')
          ..write('qWound: $qWound, ')
          ..write('qSwelling: $qSwelling, ')
          ..write('result: $result, ')
          ..write('photoSoleLeft: $photoSoleLeft, ')
          ..write('photoSoleRight: $photoSoleRight, ')
          ..write('photoTopLeft: $photoTopLeft, ')
          ..write('photoTopRight: $photoTopRight, ')
          ..write('answerOnly: $answerOnly')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    atMs,
    localDate,
    qRedness,
    qWound,
    qSwelling,
    result,
    photoSoleLeft,
    photoSoleRight,
    photoTopLeft,
    photoTopRight,
    answerOnly,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FootCheckRow &&
          other.id == this.id &&
          other.atMs == this.atMs &&
          other.localDate == this.localDate &&
          other.qRedness == this.qRedness &&
          other.qWound == this.qWound &&
          other.qSwelling == this.qSwelling &&
          other.result == this.result &&
          other.photoSoleLeft == this.photoSoleLeft &&
          other.photoSoleRight == this.photoSoleRight &&
          other.photoTopLeft == this.photoTopLeft &&
          other.photoTopRight == this.photoTopRight &&
          other.answerOnly == this.answerOnly);
}

class FootChecksCompanion extends UpdateCompanion<FootCheckRow> {
  final Value<int> id;
  final Value<int> atMs;
  final Value<String> localDate;
  final Value<FootCheckAnswer?> qRedness;
  final Value<FootCheckAnswer?> qWound;
  final Value<FootCheckAnswer?> qSwelling;
  final Value<FootCheckResult> result;
  final Value<String?> photoSoleLeft;
  final Value<String?> photoSoleRight;
  final Value<String?> photoTopLeft;
  final Value<String?> photoTopRight;
  final Value<bool> answerOnly;
  const FootChecksCompanion({
    this.id = const Value.absent(),
    this.atMs = const Value.absent(),
    this.localDate = const Value.absent(),
    this.qRedness = const Value.absent(),
    this.qWound = const Value.absent(),
    this.qSwelling = const Value.absent(),
    this.result = const Value.absent(),
    this.photoSoleLeft = const Value.absent(),
    this.photoSoleRight = const Value.absent(),
    this.photoTopLeft = const Value.absent(),
    this.photoTopRight = const Value.absent(),
    this.answerOnly = const Value.absent(),
  });
  FootChecksCompanion.insert({
    this.id = const Value.absent(),
    required int atMs,
    required String localDate,
    this.qRedness = const Value.absent(),
    this.qWound = const Value.absent(),
    this.qSwelling = const Value.absent(),
    required FootCheckResult result,
    this.photoSoleLeft = const Value.absent(),
    this.photoSoleRight = const Value.absent(),
    this.photoTopLeft = const Value.absent(),
    this.photoTopRight = const Value.absent(),
    required bool answerOnly,
  }) : atMs = Value(atMs),
       localDate = Value(localDate),
       result = Value(result),
       answerOnly = Value(answerOnly);
  static Insertable<FootCheckRow> custom({
    Expression<int>? id,
    Expression<int>? atMs,
    Expression<String>? localDate,
    Expression<String>? qRedness,
    Expression<String>? qWound,
    Expression<String>? qSwelling,
    Expression<String>? result,
    Expression<String>? photoSoleLeft,
    Expression<String>? photoSoleRight,
    Expression<String>? photoTopLeft,
    Expression<String>? photoTopRight,
    Expression<bool>? answerOnly,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (atMs != null) 'at_ms': atMs,
      if (localDate != null) 'local_date': localDate,
      if (qRedness != null) 'q_redness': qRedness,
      if (qWound != null) 'q_wound': qWound,
      if (qSwelling != null) 'q_swelling': qSwelling,
      if (result != null) 'result': result,
      if (photoSoleLeft != null) 'photo_sole_left': photoSoleLeft,
      if (photoSoleRight != null) 'photo_sole_right': photoSoleRight,
      if (photoTopLeft != null) 'photo_top_left': photoTopLeft,
      if (photoTopRight != null) 'photo_top_right': photoTopRight,
      if (answerOnly != null) 'answer_only': answerOnly,
    });
  }

  FootChecksCompanion copyWith({
    Value<int>? id,
    Value<int>? atMs,
    Value<String>? localDate,
    Value<FootCheckAnswer?>? qRedness,
    Value<FootCheckAnswer?>? qWound,
    Value<FootCheckAnswer?>? qSwelling,
    Value<FootCheckResult>? result,
    Value<String?>? photoSoleLeft,
    Value<String?>? photoSoleRight,
    Value<String?>? photoTopLeft,
    Value<String?>? photoTopRight,
    Value<bool>? answerOnly,
  }) {
    return FootChecksCompanion(
      id: id ?? this.id,
      atMs: atMs ?? this.atMs,
      localDate: localDate ?? this.localDate,
      qRedness: qRedness ?? this.qRedness,
      qWound: qWound ?? this.qWound,
      qSwelling: qSwelling ?? this.qSwelling,
      result: result ?? this.result,
      photoSoleLeft: photoSoleLeft ?? this.photoSoleLeft,
      photoSoleRight: photoSoleRight ?? this.photoSoleRight,
      photoTopLeft: photoTopLeft ?? this.photoTopLeft,
      photoTopRight: photoTopRight ?? this.photoTopRight,
      answerOnly: answerOnly ?? this.answerOnly,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (atMs.present) {
      map['at_ms'] = Variable<int>(atMs.value);
    }
    if (localDate.present) {
      map['local_date'] = Variable<String>(localDate.value);
    }
    if (qRedness.present) {
      map['q_redness'] = Variable<String>(
        $FootChecksTable.$converterqRednessn.toSql(qRedness.value),
      );
    }
    if (qWound.present) {
      map['q_wound'] = Variable<String>(
        $FootChecksTable.$converterqWoundn.toSql(qWound.value),
      );
    }
    if (qSwelling.present) {
      map['q_swelling'] = Variable<String>(
        $FootChecksTable.$converterqSwellingn.toSql(qSwelling.value),
      );
    }
    if (result.present) {
      map['result'] = Variable<String>(
        $FootChecksTable.$converterresult.toSql(result.value),
      );
    }
    if (photoSoleLeft.present) {
      map['photo_sole_left'] = Variable<String>(photoSoleLeft.value);
    }
    if (photoSoleRight.present) {
      map['photo_sole_right'] = Variable<String>(photoSoleRight.value);
    }
    if (photoTopLeft.present) {
      map['photo_top_left'] = Variable<String>(photoTopLeft.value);
    }
    if (photoTopRight.present) {
      map['photo_top_right'] = Variable<String>(photoTopRight.value);
    }
    if (answerOnly.present) {
      map['answer_only'] = Variable<bool>(answerOnly.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FootChecksCompanion(')
          ..write('id: $id, ')
          ..write('atMs: $atMs, ')
          ..write('localDate: $localDate, ')
          ..write('qRedness: $qRedness, ')
          ..write('qWound: $qWound, ')
          ..write('qSwelling: $qSwelling, ')
          ..write('result: $result, ')
          ..write('photoSoleLeft: $photoSoleLeft, ')
          ..write('photoSoleRight: $photoSoleRight, ')
          ..write('photoTopLeft: $photoTopLeft, ')
          ..write('photoTopRight: $photoTopRight, ')
          ..write('answerOnly: $answerOnly')
          ..write(')'))
        .toString();
  }
}

class $AlertsTable extends Alerts with TableInfo<$AlertsTable, AlertRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlertsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<AlertKind, String> code =
      GeneratedColumn<String>(
        'code',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<AlertKind>($AlertsTable.$convertercode);
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<int> level = GeneratedColumn<int>(
    'level',
    aliasedName,
    false,
    check: () => ComparableExpr(level).isBetweenValues(1, 5),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<PatientLevel, String>
  patientStatus = GeneratedColumn<String>(
    'patient_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<PatientLevel>($AlertsTable.$converterpatientStatus);
  @override
  late final GeneratedColumnWithTypeConverter<FootSide?, String> side =
      GeneratedColumn<String>(
        'side',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<FootSide?>($AlertsTable.$convertersiden);
  static const VerificationMeta _zoneMeta = const VerificationMeta('zone');
  @override
  late final GeneratedColumn<String> zone = GeneratedColumn<String>(
    'zone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TempSite?, String> site =
      GeneratedColumn<String>(
        'site',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<TempSite?>($AlertsTable.$convertersiten);
  static const VerificationMeta _measuredValueMeta = const VerificationMeta(
    'measuredValue',
  );
  @override
  late final GeneratedColumn<double> measuredValue = GeneratedColumn<double>(
    'measured_value',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thresholdMeta = const VerificationMeta(
    'threshold',
  );
  @override
  late final GeneratedColumn<double> threshold = GeneratedColumn<double>(
    'threshold',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gaitClassMeta = const VerificationMeta(
    'gaitClass',
  );
  @override
  late final GeneratedColumn<String> gaitClass = GeneratedColumn<String>(
    'gait_class',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gaitConfidenceMeta = const VerificationMeta(
    'gaitConfidence',
  );
  @override
  late final GeneratedColumn<double> gaitConfidence = GeneratedColumn<double>(
    'gait_confidence',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, Object?>?, String>
  details = GeneratedColumn<String>(
    'details',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<Map<String, Object?>?>($AlertsTable.$converterdetailsn);
  static const VerificationMeta _atMsMeta = const VerificationMeta('atMs');
  @override
  late final GeneratedColumn<int> atMs = GeneratedColumn<int>(
    'at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localDateMeta = const VerificationMeta(
    'localDate',
  );
  @override
  late final GeneratedColumn<String> localDate = GeneratedColumn<String>(
    'local_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readAtMsMeta = const VerificationMeta(
    'readAtMs',
  );
  @override
  late final GeneratedColumn<int> readAtMs = GeneratedColumn<int>(
    'read_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _captureStampMeta = const VerificationMeta(
    'captureStamp',
  );
  @override
  late final GeneratedColumn<String> captureStamp = GeneratedColumn<String>(
    'capture_stamp',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _footCheckIdMeta = const VerificationMeta(
    'footCheckId',
  );
  @override
  late final GeneratedColumn<int> footCheckId = GeneratedColumn<int>(
    'foot_check_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES foot_checks (id) ON DELETE SET NULL',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    code,
    level,
    patientStatus,
    side,
    zone,
    site,
    measuredValue,
    threshold,
    gaitClass,
    gaitConfidence,
    details,
    atMs,
    localDate,
    readAtMs,
    captureStamp,
    footCheckId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'alerts';
  @override
  VerificationContext validateIntegrity(
    Insertable<AlertRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('level')) {
      context.handle(
        _levelMeta,
        level.isAcceptableOrUnknown(data['level']!, _levelMeta),
      );
    } else if (isInserting) {
      context.missing(_levelMeta);
    }
    if (data.containsKey('zone')) {
      context.handle(
        _zoneMeta,
        zone.isAcceptableOrUnknown(data['zone']!, _zoneMeta),
      );
    }
    if (data.containsKey('measured_value')) {
      context.handle(
        _measuredValueMeta,
        measuredValue.isAcceptableOrUnknown(
          data['measured_value']!,
          _measuredValueMeta,
        ),
      );
    }
    if (data.containsKey('threshold')) {
      context.handle(
        _thresholdMeta,
        threshold.isAcceptableOrUnknown(data['threshold']!, _thresholdMeta),
      );
    }
    if (data.containsKey('gait_class')) {
      context.handle(
        _gaitClassMeta,
        gaitClass.isAcceptableOrUnknown(data['gait_class']!, _gaitClassMeta),
      );
    }
    if (data.containsKey('gait_confidence')) {
      context.handle(
        _gaitConfidenceMeta,
        gaitConfidence.isAcceptableOrUnknown(
          data['gait_confidence']!,
          _gaitConfidenceMeta,
        ),
      );
    }
    if (data.containsKey('at_ms')) {
      context.handle(
        _atMsMeta,
        atMs.isAcceptableOrUnknown(data['at_ms']!, _atMsMeta),
      );
    } else if (isInserting) {
      context.missing(_atMsMeta);
    }
    if (data.containsKey('local_date')) {
      context.handle(
        _localDateMeta,
        localDate.isAcceptableOrUnknown(data['local_date']!, _localDateMeta),
      );
    } else if (isInserting) {
      context.missing(_localDateMeta);
    }
    if (data.containsKey('read_at_ms')) {
      context.handle(
        _readAtMsMeta,
        readAtMs.isAcceptableOrUnknown(data['read_at_ms']!, _readAtMsMeta),
      );
    }
    if (data.containsKey('capture_stamp')) {
      context.handle(
        _captureStampMeta,
        captureStamp.isAcceptableOrUnknown(
          data['capture_stamp']!,
          _captureStampMeta,
        ),
      );
    }
    if (data.containsKey('foot_check_id')) {
      context.handle(
        _footCheckIdMeta,
        footCheckId.isAcceptableOrUnknown(
          data['foot_check_id']!,
          _footCheckIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AlertRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlertRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      code: $AlertsTable.$convertercode.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}code'],
        )!,
      ),
      level: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}level'],
      )!,
      patientStatus: $AlertsTable.$converterpatientStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}patient_status'],
        )!,
      ),
      side: $AlertsTable.$convertersiden.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}side'],
        ),
      ),
      zone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}zone'],
      ),
      site: $AlertsTable.$convertersiten.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}site'],
        ),
      ),
      measuredValue: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}measured_value'],
      ),
      threshold: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}threshold'],
      ),
      gaitClass: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gait_class'],
      ),
      gaitConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}gait_confidence'],
      ),
      details: $AlertsTable.$converterdetailsn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}details'],
        ),
      ),
      atMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}at_ms'],
      )!,
      localDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_date'],
      )!,
      readAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}read_at_ms'],
      ),
      captureStamp: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}capture_stamp'],
      ),
      footCheckId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}foot_check_id'],
      ),
    );
  }

  @override
  $AlertsTable createAlias(String alias) {
    return $AlertsTable(attachedDatabase, alias);
  }

  static TypeConverter<AlertKind, String> $convertercode =
      const _AlertKindConverter();
  static JsonTypeConverter2<PatientLevel, String, String>
  $converterpatientStatus = const EnumNameConverter<PatientLevel>(
    PatientLevel.values,
  );
  static JsonTypeConverter2<FootSide, String, String> $converterside =
      const EnumNameConverter<FootSide>(FootSide.values);
  static JsonTypeConverter2<FootSide?, String?, String?> $convertersiden =
      JsonTypeConverter2.asNullable($converterside);
  static JsonTypeConverter2<TempSite, String, String> $convertersite =
      const EnumNameConverter<TempSite>(TempSite.values);
  static JsonTypeConverter2<TempSite?, String?, String?> $convertersiten =
      JsonTypeConverter2.asNullable($convertersite);
  static TypeConverter<Map<String, Object?>, String> $converterdetails =
      const _JsonMapConverter();
  static TypeConverter<Map<String, Object?>?, String?> $converterdetailsn =
      NullAwareTypeConverter.wrap($converterdetails);
}

class AlertRow extends DataClass implements Insertable<AlertRow> {
  final int id;

  /// `AlertKind.wireName`: the contract code, or `FOOT_CHECK_FINDING`.
  final AlertKind code;

  /// Internal level 1–5, from the code.
  final int level;
  final PatientLevel patientStatus;
  final FootSide? side;
  final String? zone;
  final TempSite? site;
  final double? measuredValue;
  final double? threshold;
  final String? gaitClass;
  final double? gaitConfidence;
  final Map<String, Object?>? details;
  final int atMs;
  final String localDate;
  final int? readAtMs;

  /// The research capture's time stamp (`captureStampOf`). An alert with
  /// one is study data: retention never deletes it.
  final String? captureStamp;
  final int? footCheckId;
  const AlertRow({
    required this.id,
    required this.code,
    required this.level,
    required this.patientStatus,
    this.side,
    this.zone,
    this.site,
    this.measuredValue,
    this.threshold,
    this.gaitClass,
    this.gaitConfidence,
    this.details,
    required this.atMs,
    required this.localDate,
    this.readAtMs,
    this.captureStamp,
    this.footCheckId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['code'] = Variable<String>($AlertsTable.$convertercode.toSql(code));
    }
    map['level'] = Variable<int>(level);
    {
      map['patient_status'] = Variable<String>(
        $AlertsTable.$converterpatientStatus.toSql(patientStatus),
      );
    }
    if (!nullToAbsent || side != null) {
      map['side'] = Variable<String>($AlertsTable.$convertersiden.toSql(side));
    }
    if (!nullToAbsent || zone != null) {
      map['zone'] = Variable<String>(zone);
    }
    if (!nullToAbsent || site != null) {
      map['site'] = Variable<String>($AlertsTable.$convertersiten.toSql(site));
    }
    if (!nullToAbsent || measuredValue != null) {
      map['measured_value'] = Variable<double>(measuredValue);
    }
    if (!nullToAbsent || threshold != null) {
      map['threshold'] = Variable<double>(threshold);
    }
    if (!nullToAbsent || gaitClass != null) {
      map['gait_class'] = Variable<String>(gaitClass);
    }
    if (!nullToAbsent || gaitConfidence != null) {
      map['gait_confidence'] = Variable<double>(gaitConfidence);
    }
    if (!nullToAbsent || details != null) {
      map['details'] = Variable<String>(
        $AlertsTable.$converterdetailsn.toSql(details),
      );
    }
    map['at_ms'] = Variable<int>(atMs);
    map['local_date'] = Variable<String>(localDate);
    if (!nullToAbsent || readAtMs != null) {
      map['read_at_ms'] = Variable<int>(readAtMs);
    }
    if (!nullToAbsent || captureStamp != null) {
      map['capture_stamp'] = Variable<String>(captureStamp);
    }
    if (!nullToAbsent || footCheckId != null) {
      map['foot_check_id'] = Variable<int>(footCheckId);
    }
    return map;
  }

  AlertsCompanion toCompanion(bool nullToAbsent) {
    return AlertsCompanion(
      id: Value(id),
      code: Value(code),
      level: Value(level),
      patientStatus: Value(patientStatus),
      side: side == null && nullToAbsent ? const Value.absent() : Value(side),
      zone: zone == null && nullToAbsent ? const Value.absent() : Value(zone),
      site: site == null && nullToAbsent ? const Value.absent() : Value(site),
      measuredValue: measuredValue == null && nullToAbsent
          ? const Value.absent()
          : Value(measuredValue),
      threshold: threshold == null && nullToAbsent
          ? const Value.absent()
          : Value(threshold),
      gaitClass: gaitClass == null && nullToAbsent
          ? const Value.absent()
          : Value(gaitClass),
      gaitConfidence: gaitConfidence == null && nullToAbsent
          ? const Value.absent()
          : Value(gaitConfidence),
      details: details == null && nullToAbsent
          ? const Value.absent()
          : Value(details),
      atMs: Value(atMs),
      localDate: Value(localDate),
      readAtMs: readAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(readAtMs),
      captureStamp: captureStamp == null && nullToAbsent
          ? const Value.absent()
          : Value(captureStamp),
      footCheckId: footCheckId == null && nullToAbsent
          ? const Value.absent()
          : Value(footCheckId),
    );
  }

  factory AlertRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlertRow(
      id: serializer.fromJson<int>(json['id']),
      code: serializer.fromJson<AlertKind>(json['code']),
      level: serializer.fromJson<int>(json['level']),
      patientStatus: $AlertsTable.$converterpatientStatus.fromJson(
        serializer.fromJson<String>(json['patientStatus']),
      ),
      side: $AlertsTable.$convertersiden.fromJson(
        serializer.fromJson<String?>(json['side']),
      ),
      zone: serializer.fromJson<String?>(json['zone']),
      site: $AlertsTable.$convertersiten.fromJson(
        serializer.fromJson<String?>(json['site']),
      ),
      measuredValue: serializer.fromJson<double?>(json['measuredValue']),
      threshold: serializer.fromJson<double?>(json['threshold']),
      gaitClass: serializer.fromJson<String?>(json['gaitClass']),
      gaitConfidence: serializer.fromJson<double?>(json['gaitConfidence']),
      details: serializer.fromJson<Map<String, Object?>?>(json['details']),
      atMs: serializer.fromJson<int>(json['atMs']),
      localDate: serializer.fromJson<String>(json['localDate']),
      readAtMs: serializer.fromJson<int?>(json['readAtMs']),
      captureStamp: serializer.fromJson<String?>(json['captureStamp']),
      footCheckId: serializer.fromJson<int?>(json['footCheckId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'code': serializer.toJson<AlertKind>(code),
      'level': serializer.toJson<int>(level),
      'patientStatus': serializer.toJson<String>(
        $AlertsTable.$converterpatientStatus.toJson(patientStatus),
      ),
      'side': serializer.toJson<String?>(
        $AlertsTable.$convertersiden.toJson(side),
      ),
      'zone': serializer.toJson<String?>(zone),
      'site': serializer.toJson<String?>(
        $AlertsTable.$convertersiten.toJson(site),
      ),
      'measuredValue': serializer.toJson<double?>(measuredValue),
      'threshold': serializer.toJson<double?>(threshold),
      'gaitClass': serializer.toJson<String?>(gaitClass),
      'gaitConfidence': serializer.toJson<double?>(gaitConfidence),
      'details': serializer.toJson<Map<String, Object?>?>(details),
      'atMs': serializer.toJson<int>(atMs),
      'localDate': serializer.toJson<String>(localDate),
      'readAtMs': serializer.toJson<int?>(readAtMs),
      'captureStamp': serializer.toJson<String?>(captureStamp),
      'footCheckId': serializer.toJson<int?>(footCheckId),
    };
  }

  AlertRow copyWith({
    int? id,
    AlertKind? code,
    int? level,
    PatientLevel? patientStatus,
    Value<FootSide?> side = const Value.absent(),
    Value<String?> zone = const Value.absent(),
    Value<TempSite?> site = const Value.absent(),
    Value<double?> measuredValue = const Value.absent(),
    Value<double?> threshold = const Value.absent(),
    Value<String?> gaitClass = const Value.absent(),
    Value<double?> gaitConfidence = const Value.absent(),
    Value<Map<String, Object?>?> details = const Value.absent(),
    int? atMs,
    String? localDate,
    Value<int?> readAtMs = const Value.absent(),
    Value<String?> captureStamp = const Value.absent(),
    Value<int?> footCheckId = const Value.absent(),
  }) => AlertRow(
    id: id ?? this.id,
    code: code ?? this.code,
    level: level ?? this.level,
    patientStatus: patientStatus ?? this.patientStatus,
    side: side.present ? side.value : this.side,
    zone: zone.present ? zone.value : this.zone,
    site: site.present ? site.value : this.site,
    measuredValue: measuredValue.present
        ? measuredValue.value
        : this.measuredValue,
    threshold: threshold.present ? threshold.value : this.threshold,
    gaitClass: gaitClass.present ? gaitClass.value : this.gaitClass,
    gaitConfidence: gaitConfidence.present
        ? gaitConfidence.value
        : this.gaitConfidence,
    details: details.present ? details.value : this.details,
    atMs: atMs ?? this.atMs,
    localDate: localDate ?? this.localDate,
    readAtMs: readAtMs.present ? readAtMs.value : this.readAtMs,
    captureStamp: captureStamp.present ? captureStamp.value : this.captureStamp,
    footCheckId: footCheckId.present ? footCheckId.value : this.footCheckId,
  );
  AlertRow copyWithCompanion(AlertsCompanion data) {
    return AlertRow(
      id: data.id.present ? data.id.value : this.id,
      code: data.code.present ? data.code.value : this.code,
      level: data.level.present ? data.level.value : this.level,
      patientStatus: data.patientStatus.present
          ? data.patientStatus.value
          : this.patientStatus,
      side: data.side.present ? data.side.value : this.side,
      zone: data.zone.present ? data.zone.value : this.zone,
      site: data.site.present ? data.site.value : this.site,
      measuredValue: data.measuredValue.present
          ? data.measuredValue.value
          : this.measuredValue,
      threshold: data.threshold.present ? data.threshold.value : this.threshold,
      gaitClass: data.gaitClass.present ? data.gaitClass.value : this.gaitClass,
      gaitConfidence: data.gaitConfidence.present
          ? data.gaitConfidence.value
          : this.gaitConfidence,
      details: data.details.present ? data.details.value : this.details,
      atMs: data.atMs.present ? data.atMs.value : this.atMs,
      localDate: data.localDate.present ? data.localDate.value : this.localDate,
      readAtMs: data.readAtMs.present ? data.readAtMs.value : this.readAtMs,
      captureStamp: data.captureStamp.present
          ? data.captureStamp.value
          : this.captureStamp,
      footCheckId: data.footCheckId.present
          ? data.footCheckId.value
          : this.footCheckId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlertRow(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('level: $level, ')
          ..write('patientStatus: $patientStatus, ')
          ..write('side: $side, ')
          ..write('zone: $zone, ')
          ..write('site: $site, ')
          ..write('measuredValue: $measuredValue, ')
          ..write('threshold: $threshold, ')
          ..write('gaitClass: $gaitClass, ')
          ..write('gaitConfidence: $gaitConfidence, ')
          ..write('details: $details, ')
          ..write('atMs: $atMs, ')
          ..write('localDate: $localDate, ')
          ..write('readAtMs: $readAtMs, ')
          ..write('captureStamp: $captureStamp, ')
          ..write('footCheckId: $footCheckId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    code,
    level,
    patientStatus,
    side,
    zone,
    site,
    measuredValue,
    threshold,
    gaitClass,
    gaitConfidence,
    details,
    atMs,
    localDate,
    readAtMs,
    captureStamp,
    footCheckId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlertRow &&
          other.id == this.id &&
          other.code == this.code &&
          other.level == this.level &&
          other.patientStatus == this.patientStatus &&
          other.side == this.side &&
          other.zone == this.zone &&
          other.site == this.site &&
          other.measuredValue == this.measuredValue &&
          other.threshold == this.threshold &&
          other.gaitClass == this.gaitClass &&
          other.gaitConfidence == this.gaitConfidence &&
          other.details == this.details &&
          other.atMs == this.atMs &&
          other.localDate == this.localDate &&
          other.readAtMs == this.readAtMs &&
          other.captureStamp == this.captureStamp &&
          other.footCheckId == this.footCheckId);
}

class AlertsCompanion extends UpdateCompanion<AlertRow> {
  final Value<int> id;
  final Value<AlertKind> code;
  final Value<int> level;
  final Value<PatientLevel> patientStatus;
  final Value<FootSide?> side;
  final Value<String?> zone;
  final Value<TempSite?> site;
  final Value<double?> measuredValue;
  final Value<double?> threshold;
  final Value<String?> gaitClass;
  final Value<double?> gaitConfidence;
  final Value<Map<String, Object?>?> details;
  final Value<int> atMs;
  final Value<String> localDate;
  final Value<int?> readAtMs;
  final Value<String?> captureStamp;
  final Value<int?> footCheckId;
  const AlertsCompanion({
    this.id = const Value.absent(),
    this.code = const Value.absent(),
    this.level = const Value.absent(),
    this.patientStatus = const Value.absent(),
    this.side = const Value.absent(),
    this.zone = const Value.absent(),
    this.site = const Value.absent(),
    this.measuredValue = const Value.absent(),
    this.threshold = const Value.absent(),
    this.gaitClass = const Value.absent(),
    this.gaitConfidence = const Value.absent(),
    this.details = const Value.absent(),
    this.atMs = const Value.absent(),
    this.localDate = const Value.absent(),
    this.readAtMs = const Value.absent(),
    this.captureStamp = const Value.absent(),
    this.footCheckId = const Value.absent(),
  });
  AlertsCompanion.insert({
    this.id = const Value.absent(),
    required AlertKind code,
    required int level,
    required PatientLevel patientStatus,
    this.side = const Value.absent(),
    this.zone = const Value.absent(),
    this.site = const Value.absent(),
    this.measuredValue = const Value.absent(),
    this.threshold = const Value.absent(),
    this.gaitClass = const Value.absent(),
    this.gaitConfidence = const Value.absent(),
    this.details = const Value.absent(),
    required int atMs,
    required String localDate,
    this.readAtMs = const Value.absent(),
    this.captureStamp = const Value.absent(),
    this.footCheckId = const Value.absent(),
  }) : code = Value(code),
       level = Value(level),
       patientStatus = Value(patientStatus),
       atMs = Value(atMs),
       localDate = Value(localDate);
  static Insertable<AlertRow> custom({
    Expression<int>? id,
    Expression<String>? code,
    Expression<int>? level,
    Expression<String>? patientStatus,
    Expression<String>? side,
    Expression<String>? zone,
    Expression<String>? site,
    Expression<double>? measuredValue,
    Expression<double>? threshold,
    Expression<String>? gaitClass,
    Expression<double>? gaitConfidence,
    Expression<String>? details,
    Expression<int>? atMs,
    Expression<String>? localDate,
    Expression<int>? readAtMs,
    Expression<String>? captureStamp,
    Expression<int>? footCheckId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (code != null) 'code': code,
      if (level != null) 'level': level,
      if (patientStatus != null) 'patient_status': patientStatus,
      if (side != null) 'side': side,
      if (zone != null) 'zone': zone,
      if (site != null) 'site': site,
      if (measuredValue != null) 'measured_value': measuredValue,
      if (threshold != null) 'threshold': threshold,
      if (gaitClass != null) 'gait_class': gaitClass,
      if (gaitConfidence != null) 'gait_confidence': gaitConfidence,
      if (details != null) 'details': details,
      if (atMs != null) 'at_ms': atMs,
      if (localDate != null) 'local_date': localDate,
      if (readAtMs != null) 'read_at_ms': readAtMs,
      if (captureStamp != null) 'capture_stamp': captureStamp,
      if (footCheckId != null) 'foot_check_id': footCheckId,
    });
  }

  AlertsCompanion copyWith({
    Value<int>? id,
    Value<AlertKind>? code,
    Value<int>? level,
    Value<PatientLevel>? patientStatus,
    Value<FootSide?>? side,
    Value<String?>? zone,
    Value<TempSite?>? site,
    Value<double?>? measuredValue,
    Value<double?>? threshold,
    Value<String?>? gaitClass,
    Value<double?>? gaitConfidence,
    Value<Map<String, Object?>?>? details,
    Value<int>? atMs,
    Value<String>? localDate,
    Value<int?>? readAtMs,
    Value<String?>? captureStamp,
    Value<int?>? footCheckId,
  }) {
    return AlertsCompanion(
      id: id ?? this.id,
      code: code ?? this.code,
      level: level ?? this.level,
      patientStatus: patientStatus ?? this.patientStatus,
      side: side ?? this.side,
      zone: zone ?? this.zone,
      site: site ?? this.site,
      measuredValue: measuredValue ?? this.measuredValue,
      threshold: threshold ?? this.threshold,
      gaitClass: gaitClass ?? this.gaitClass,
      gaitConfidence: gaitConfidence ?? this.gaitConfidence,
      details: details ?? this.details,
      atMs: atMs ?? this.atMs,
      localDate: localDate ?? this.localDate,
      readAtMs: readAtMs ?? this.readAtMs,
      captureStamp: captureStamp ?? this.captureStamp,
      footCheckId: footCheckId ?? this.footCheckId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(
        $AlertsTable.$convertercode.toSql(code.value),
      );
    }
    if (level.present) {
      map['level'] = Variable<int>(level.value);
    }
    if (patientStatus.present) {
      map['patient_status'] = Variable<String>(
        $AlertsTable.$converterpatientStatus.toSql(patientStatus.value),
      );
    }
    if (side.present) {
      map['side'] = Variable<String>(
        $AlertsTable.$convertersiden.toSql(side.value),
      );
    }
    if (zone.present) {
      map['zone'] = Variable<String>(zone.value);
    }
    if (site.present) {
      map['site'] = Variable<String>(
        $AlertsTable.$convertersiten.toSql(site.value),
      );
    }
    if (measuredValue.present) {
      map['measured_value'] = Variable<double>(measuredValue.value);
    }
    if (threshold.present) {
      map['threshold'] = Variable<double>(threshold.value);
    }
    if (gaitClass.present) {
      map['gait_class'] = Variable<String>(gaitClass.value);
    }
    if (gaitConfidence.present) {
      map['gait_confidence'] = Variable<double>(gaitConfidence.value);
    }
    if (details.present) {
      map['details'] = Variable<String>(
        $AlertsTable.$converterdetailsn.toSql(details.value),
      );
    }
    if (atMs.present) {
      map['at_ms'] = Variable<int>(atMs.value);
    }
    if (localDate.present) {
      map['local_date'] = Variable<String>(localDate.value);
    }
    if (readAtMs.present) {
      map['read_at_ms'] = Variable<int>(readAtMs.value);
    }
    if (captureStamp.present) {
      map['capture_stamp'] = Variable<String>(captureStamp.value);
    }
    if (footCheckId.present) {
      map['foot_check_id'] = Variable<int>(footCheckId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlertsCompanion(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('level: $level, ')
          ..write('patientStatus: $patientStatus, ')
          ..write('side: $side, ')
          ..write('zone: $zone, ')
          ..write('site: $site, ')
          ..write('measuredValue: $measuredValue, ')
          ..write('threshold: $threshold, ')
          ..write('gaitClass: $gaitClass, ')
          ..write('gaitConfidence: $gaitConfidence, ')
          ..write('details: $details, ')
          ..write('atMs: $atMs, ')
          ..write('localDate: $localDate, ')
          ..write('readAtMs: $readAtMs, ')
          ..write('captureStamp: $captureStamp, ')
          ..write('footCheckId: $footCheckId')
          ..write(')'))
        .toString();
  }
}

class $TemperatureReadingsTable extends TemperatureReadings
    with TableInfo<$TemperatureReadingsTable, TemperatureRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TemperatureReadingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _atMsMeta = const VerificationMeta('atMs');
  @override
  late final GeneratedColumn<int> atMs = GeneratedColumn<int>(
    'at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localDateMeta = const VerificationMeta(
    'localDate',
  );
  @override
  late final GeneratedColumn<String> localDate = GeneratedColumn<String>(
    'local_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<FootSide, String> side =
      GeneratedColumn<String>(
        'side',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<FootSide>($TemperatureReadingsTable.$converterside);
  static const VerificationMeta _forefootCMeta = const VerificationMeta(
    'forefootC',
  );
  @override
  late final GeneratedColumn<double> forefootC = GeneratedColumn<double>(
    'forefoot_c',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heelCMeta = const VerificationMeta('heelC');
  @override
  late final GeneratedColumn<double> heelC = GeneratedColumn<double>(
    'heel_c',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TempQuality, String> quality =
      GeneratedColumn<String>(
        'quality',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<TempQuality>($TemperatureReadingsTable.$converterquality);
  static const VerificationMeta _timeFromArrivalMeta = const VerificationMeta(
    'timeFromArrival',
  );
  @override
  late final GeneratedColumn<bool> timeFromArrival = GeneratedColumn<bool>(
    'time_from_arrival',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("time_from_arrival" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    atMs,
    localDate,
    side,
    forefootC,
    heelC,
    quality,
    timeFromArrival,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'temperature_readings';
  @override
  VerificationContext validateIntegrity(
    Insertable<TemperatureRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('at_ms')) {
      context.handle(
        _atMsMeta,
        atMs.isAcceptableOrUnknown(data['at_ms']!, _atMsMeta),
      );
    } else if (isInserting) {
      context.missing(_atMsMeta);
    }
    if (data.containsKey('local_date')) {
      context.handle(
        _localDateMeta,
        localDate.isAcceptableOrUnknown(data['local_date']!, _localDateMeta),
      );
    } else if (isInserting) {
      context.missing(_localDateMeta);
    }
    if (data.containsKey('forefoot_c')) {
      context.handle(
        _forefootCMeta,
        forefootC.isAcceptableOrUnknown(data['forefoot_c']!, _forefootCMeta),
      );
    }
    if (data.containsKey('heel_c')) {
      context.handle(
        _heelCMeta,
        heelC.isAcceptableOrUnknown(data['heel_c']!, _heelCMeta),
      );
    }
    if (data.containsKey('time_from_arrival')) {
      context.handle(
        _timeFromArrivalMeta,
        timeFromArrival.isAcceptableOrUnknown(
          data['time_from_arrival']!,
          _timeFromArrivalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timeFromArrivalMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TemperatureRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TemperatureRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      atMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}at_ms'],
      )!,
      localDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_date'],
      )!,
      side: $TemperatureReadingsTable.$converterside.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}side'],
        )!,
      ),
      forefootC: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}forefoot_c'],
      ),
      heelC: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}heel_c'],
      ),
      quality: $TemperatureReadingsTable.$converterquality.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}quality'],
        )!,
      ),
      timeFromArrival: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}time_from_arrival'],
      )!,
    );
  }

  @override
  $TemperatureReadingsTable createAlias(String alias) {
    return $TemperatureReadingsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<FootSide, String, String> $converterside =
      const EnumNameConverter<FootSide>(FootSide.values);
  static JsonTypeConverter2<TempQuality, String, String> $converterquality =
      const EnumNameConverter<TempQuality>(TempQuality.values);
}

class TemperatureRow extends DataClass implements Insertable<TemperatureRow> {
  final int id;
  final int atMs;
  final String localDate;
  final FootSide side;
  final double? forefootC;
  final double? heelC;
  final TempQuality quality;
  final bool timeFromArrival;
  const TemperatureRow({
    required this.id,
    required this.atMs,
    required this.localDate,
    required this.side,
    this.forefootC,
    this.heelC,
    required this.quality,
    required this.timeFromArrival,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['at_ms'] = Variable<int>(atMs);
    map['local_date'] = Variable<String>(localDate);
    {
      map['side'] = Variable<String>(
        $TemperatureReadingsTable.$converterside.toSql(side),
      );
    }
    if (!nullToAbsent || forefootC != null) {
      map['forefoot_c'] = Variable<double>(forefootC);
    }
    if (!nullToAbsent || heelC != null) {
      map['heel_c'] = Variable<double>(heelC);
    }
    {
      map['quality'] = Variable<String>(
        $TemperatureReadingsTable.$converterquality.toSql(quality),
      );
    }
    map['time_from_arrival'] = Variable<bool>(timeFromArrival);
    return map;
  }

  TemperatureReadingsCompanion toCompanion(bool nullToAbsent) {
    return TemperatureReadingsCompanion(
      id: Value(id),
      atMs: Value(atMs),
      localDate: Value(localDate),
      side: Value(side),
      forefootC: forefootC == null && nullToAbsent
          ? const Value.absent()
          : Value(forefootC),
      heelC: heelC == null && nullToAbsent
          ? const Value.absent()
          : Value(heelC),
      quality: Value(quality),
      timeFromArrival: Value(timeFromArrival),
    );
  }

  factory TemperatureRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TemperatureRow(
      id: serializer.fromJson<int>(json['id']),
      atMs: serializer.fromJson<int>(json['atMs']),
      localDate: serializer.fromJson<String>(json['localDate']),
      side: $TemperatureReadingsTable.$converterside.fromJson(
        serializer.fromJson<String>(json['side']),
      ),
      forefootC: serializer.fromJson<double?>(json['forefootC']),
      heelC: serializer.fromJson<double?>(json['heelC']),
      quality: $TemperatureReadingsTable.$converterquality.fromJson(
        serializer.fromJson<String>(json['quality']),
      ),
      timeFromArrival: serializer.fromJson<bool>(json['timeFromArrival']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'atMs': serializer.toJson<int>(atMs),
      'localDate': serializer.toJson<String>(localDate),
      'side': serializer.toJson<String>(
        $TemperatureReadingsTable.$converterside.toJson(side),
      ),
      'forefootC': serializer.toJson<double?>(forefootC),
      'heelC': serializer.toJson<double?>(heelC),
      'quality': serializer.toJson<String>(
        $TemperatureReadingsTable.$converterquality.toJson(quality),
      ),
      'timeFromArrival': serializer.toJson<bool>(timeFromArrival),
    };
  }

  TemperatureRow copyWith({
    int? id,
    int? atMs,
    String? localDate,
    FootSide? side,
    Value<double?> forefootC = const Value.absent(),
    Value<double?> heelC = const Value.absent(),
    TempQuality? quality,
    bool? timeFromArrival,
  }) => TemperatureRow(
    id: id ?? this.id,
    atMs: atMs ?? this.atMs,
    localDate: localDate ?? this.localDate,
    side: side ?? this.side,
    forefootC: forefootC.present ? forefootC.value : this.forefootC,
    heelC: heelC.present ? heelC.value : this.heelC,
    quality: quality ?? this.quality,
    timeFromArrival: timeFromArrival ?? this.timeFromArrival,
  );
  TemperatureRow copyWithCompanion(TemperatureReadingsCompanion data) {
    return TemperatureRow(
      id: data.id.present ? data.id.value : this.id,
      atMs: data.atMs.present ? data.atMs.value : this.atMs,
      localDate: data.localDate.present ? data.localDate.value : this.localDate,
      side: data.side.present ? data.side.value : this.side,
      forefootC: data.forefootC.present ? data.forefootC.value : this.forefootC,
      heelC: data.heelC.present ? data.heelC.value : this.heelC,
      quality: data.quality.present ? data.quality.value : this.quality,
      timeFromArrival: data.timeFromArrival.present
          ? data.timeFromArrival.value
          : this.timeFromArrival,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TemperatureRow(')
          ..write('id: $id, ')
          ..write('atMs: $atMs, ')
          ..write('localDate: $localDate, ')
          ..write('side: $side, ')
          ..write('forefootC: $forefootC, ')
          ..write('heelC: $heelC, ')
          ..write('quality: $quality, ')
          ..write('timeFromArrival: $timeFromArrival')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    atMs,
    localDate,
    side,
    forefootC,
    heelC,
    quality,
    timeFromArrival,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TemperatureRow &&
          other.id == this.id &&
          other.atMs == this.atMs &&
          other.localDate == this.localDate &&
          other.side == this.side &&
          other.forefootC == this.forefootC &&
          other.heelC == this.heelC &&
          other.quality == this.quality &&
          other.timeFromArrival == this.timeFromArrival);
}

class TemperatureReadingsCompanion extends UpdateCompanion<TemperatureRow> {
  final Value<int> id;
  final Value<int> atMs;
  final Value<String> localDate;
  final Value<FootSide> side;
  final Value<double?> forefootC;
  final Value<double?> heelC;
  final Value<TempQuality> quality;
  final Value<bool> timeFromArrival;
  const TemperatureReadingsCompanion({
    this.id = const Value.absent(),
    this.atMs = const Value.absent(),
    this.localDate = const Value.absent(),
    this.side = const Value.absent(),
    this.forefootC = const Value.absent(),
    this.heelC = const Value.absent(),
    this.quality = const Value.absent(),
    this.timeFromArrival = const Value.absent(),
  });
  TemperatureReadingsCompanion.insert({
    this.id = const Value.absent(),
    required int atMs,
    required String localDate,
    required FootSide side,
    this.forefootC = const Value.absent(),
    this.heelC = const Value.absent(),
    required TempQuality quality,
    required bool timeFromArrival,
  }) : atMs = Value(atMs),
       localDate = Value(localDate),
       side = Value(side),
       quality = Value(quality),
       timeFromArrival = Value(timeFromArrival);
  static Insertable<TemperatureRow> custom({
    Expression<int>? id,
    Expression<int>? atMs,
    Expression<String>? localDate,
    Expression<String>? side,
    Expression<double>? forefootC,
    Expression<double>? heelC,
    Expression<String>? quality,
    Expression<bool>? timeFromArrival,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (atMs != null) 'at_ms': atMs,
      if (localDate != null) 'local_date': localDate,
      if (side != null) 'side': side,
      if (forefootC != null) 'forefoot_c': forefootC,
      if (heelC != null) 'heel_c': heelC,
      if (quality != null) 'quality': quality,
      if (timeFromArrival != null) 'time_from_arrival': timeFromArrival,
    });
  }

  TemperatureReadingsCompanion copyWith({
    Value<int>? id,
    Value<int>? atMs,
    Value<String>? localDate,
    Value<FootSide>? side,
    Value<double?>? forefootC,
    Value<double?>? heelC,
    Value<TempQuality>? quality,
    Value<bool>? timeFromArrival,
  }) {
    return TemperatureReadingsCompanion(
      id: id ?? this.id,
      atMs: atMs ?? this.atMs,
      localDate: localDate ?? this.localDate,
      side: side ?? this.side,
      forefootC: forefootC ?? this.forefootC,
      heelC: heelC ?? this.heelC,
      quality: quality ?? this.quality,
      timeFromArrival: timeFromArrival ?? this.timeFromArrival,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (atMs.present) {
      map['at_ms'] = Variable<int>(atMs.value);
    }
    if (localDate.present) {
      map['local_date'] = Variable<String>(localDate.value);
    }
    if (side.present) {
      map['side'] = Variable<String>(
        $TemperatureReadingsTable.$converterside.toSql(side.value),
      );
    }
    if (forefootC.present) {
      map['forefoot_c'] = Variable<double>(forefootC.value);
    }
    if (heelC.present) {
      map['heel_c'] = Variable<double>(heelC.value);
    }
    if (quality.present) {
      map['quality'] = Variable<String>(
        $TemperatureReadingsTable.$converterquality.toSql(quality.value),
      );
    }
    if (timeFromArrival.present) {
      map['time_from_arrival'] = Variable<bool>(timeFromArrival.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TemperatureReadingsCompanion(')
          ..write('id: $id, ')
          ..write('atMs: $atMs, ')
          ..write('localDate: $localDate, ')
          ..write('side: $side, ')
          ..write('forefootC: $forefootC, ')
          ..write('heelC: $heelC, ')
          ..write('quality: $quality, ')
          ..write('timeFromArrival: $timeFromArrival')
          ..write(')'))
        .toString();
  }
}

class $DailySummariesTable extends DailySummaries
    with TableInfo<$DailySummariesTable, DailySummaryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailySummariesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localDateMeta = const VerificationMeta(
    'localDate',
  );
  @override
  late final GeneratedColumn<String> localDate = GeneratedColumn<String>(
    'local_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stepsMeta = const VerificationMeta('steps');
  @override
  late final GeneratedColumn<int> steps = GeneratedColumn<int>(
    'steps',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _walkingMinMeta = const VerificationMeta(
    'walkingMin',
  );
  @override
  late final GeneratedColumn<int> walkingMin = GeneratedColumn<int>(
    'walking_min',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wornMinMeta = const VerificationMeta(
    'wornMin',
  );
  @override
  late final GeneratedColumn<int> wornMin = GeneratedColumn<int>(
    'worn_min',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxDeltaForefootCMeta = const VerificationMeta(
    'maxDeltaForefootC',
  );
  @override
  late final GeneratedColumn<double> maxDeltaForefootC =
      GeneratedColumn<double>(
        'max_delta_forefoot_c',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _maxDeltaHeelCMeta = const VerificationMeta(
    'maxDeltaHeelC',
  );
  @override
  late final GeneratedColumn<double> maxDeltaHeelC = GeneratedColumn<double>(
    'max_delta_heel_c',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _alertsL1Meta = const VerificationMeta(
    'alertsL1',
  );
  @override
  late final GeneratedColumn<int> alertsL1 = GeneratedColumn<int>(
    'alerts_l1',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _alertsL2Meta = const VerificationMeta(
    'alertsL2',
  );
  @override
  late final GeneratedColumn<int> alertsL2 = GeneratedColumn<int>(
    'alerts_l2',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _alertsL3Meta = const VerificationMeta(
    'alertsL3',
  );
  @override
  late final GeneratedColumn<int> alertsL3 = GeneratedColumn<int>(
    'alerts_l3',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _alertsL4Meta = const VerificationMeta(
    'alertsL4',
  );
  @override
  late final GeneratedColumn<int> alertsL4 = GeneratedColumn<int>(
    'alerts_l4',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _alertsL5Meta = const VerificationMeta(
    'alertsL5',
  );
  @override
  late final GeneratedColumn<int> alertsL5 = GeneratedColumn<int>(
    'alerts_l5',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _footCheckDoneMeta = const VerificationMeta(
    'footCheckDone',
  );
  @override
  late final GeneratedColumn<bool> footCheckDone = GeneratedColumn<bool>(
    'foot_check_done',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("foot_check_done" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
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
    localDate,
    steps,
    walkingMin,
    wornMin,
    maxDeltaForefootC,
    maxDeltaHeelC,
    alertsL1,
    alertsL2,
    alertsL3,
    alertsL4,
    alertsL5,
    footCheckDone,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_summary';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailySummaryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_date')) {
      context.handle(
        _localDateMeta,
        localDate.isAcceptableOrUnknown(data['local_date']!, _localDateMeta),
      );
    } else if (isInserting) {
      context.missing(_localDateMeta);
    }
    if (data.containsKey('steps')) {
      context.handle(
        _stepsMeta,
        steps.isAcceptableOrUnknown(data['steps']!, _stepsMeta),
      );
    }
    if (data.containsKey('walking_min')) {
      context.handle(
        _walkingMinMeta,
        walkingMin.isAcceptableOrUnknown(data['walking_min']!, _walkingMinMeta),
      );
    }
    if (data.containsKey('worn_min')) {
      context.handle(
        _wornMinMeta,
        wornMin.isAcceptableOrUnknown(data['worn_min']!, _wornMinMeta),
      );
    }
    if (data.containsKey('max_delta_forefoot_c')) {
      context.handle(
        _maxDeltaForefootCMeta,
        maxDeltaForefootC.isAcceptableOrUnknown(
          data['max_delta_forefoot_c']!,
          _maxDeltaForefootCMeta,
        ),
      );
    }
    if (data.containsKey('max_delta_heel_c')) {
      context.handle(
        _maxDeltaHeelCMeta,
        maxDeltaHeelC.isAcceptableOrUnknown(
          data['max_delta_heel_c']!,
          _maxDeltaHeelCMeta,
        ),
      );
    }
    if (data.containsKey('alerts_l1')) {
      context.handle(
        _alertsL1Meta,
        alertsL1.isAcceptableOrUnknown(data['alerts_l1']!, _alertsL1Meta),
      );
    }
    if (data.containsKey('alerts_l2')) {
      context.handle(
        _alertsL2Meta,
        alertsL2.isAcceptableOrUnknown(data['alerts_l2']!, _alertsL2Meta),
      );
    }
    if (data.containsKey('alerts_l3')) {
      context.handle(
        _alertsL3Meta,
        alertsL3.isAcceptableOrUnknown(data['alerts_l3']!, _alertsL3Meta),
      );
    }
    if (data.containsKey('alerts_l4')) {
      context.handle(
        _alertsL4Meta,
        alertsL4.isAcceptableOrUnknown(data['alerts_l4']!, _alertsL4Meta),
      );
    }
    if (data.containsKey('alerts_l5')) {
      context.handle(
        _alertsL5Meta,
        alertsL5.isAcceptableOrUnknown(data['alerts_l5']!, _alertsL5Meta),
      );
    }
    if (data.containsKey('foot_check_done')) {
      context.handle(
        _footCheckDoneMeta,
        footCheckDone.isAcceptableOrUnknown(
          data['foot_check_done']!,
          _footCheckDoneMeta,
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
  Set<GeneratedColumn> get $primaryKey => {localDate};
  @override
  DailySummaryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailySummaryRow(
      localDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_date'],
      )!,
      steps: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}steps'],
      ),
      walkingMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}walking_min'],
      ),
      wornMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}worn_min'],
      ),
      maxDeltaForefootC: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}max_delta_forefoot_c'],
      ),
      maxDeltaHeelC: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}max_delta_heel_c'],
      ),
      alertsL1: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}alerts_l1'],
      )!,
      alertsL2: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}alerts_l2'],
      )!,
      alertsL3: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}alerts_l3'],
      )!,
      alertsL4: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}alerts_l4'],
      )!,
      alertsL5: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}alerts_l5'],
      )!,
      footCheckDone: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}foot_check_done'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $DailySummariesTable createAlias(String alias) {
    return $DailySummariesTable(attachedDatabase, alias);
  }
}

class DailySummaryRow extends DataClass implements Insertable<DailySummaryRow> {
  final String localDate;
  final int? steps;
  final int? walkingMin;
  final int? wornMin;
  final double? maxDeltaForefootC;
  final double? maxDeltaHeelC;
  final int alertsL1;
  final int alertsL2;
  final int alertsL3;
  final int alertsL4;
  final int alertsL5;
  final bool footCheckDone;
  final int updatedAtMs;
  const DailySummaryRow({
    required this.localDate,
    this.steps,
    this.walkingMin,
    this.wornMin,
    this.maxDeltaForefootC,
    this.maxDeltaHeelC,
    required this.alertsL1,
    required this.alertsL2,
    required this.alertsL3,
    required this.alertsL4,
    required this.alertsL5,
    required this.footCheckDone,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_date'] = Variable<String>(localDate);
    if (!nullToAbsent || steps != null) {
      map['steps'] = Variable<int>(steps);
    }
    if (!nullToAbsent || walkingMin != null) {
      map['walking_min'] = Variable<int>(walkingMin);
    }
    if (!nullToAbsent || wornMin != null) {
      map['worn_min'] = Variable<int>(wornMin);
    }
    if (!nullToAbsent || maxDeltaForefootC != null) {
      map['max_delta_forefoot_c'] = Variable<double>(maxDeltaForefootC);
    }
    if (!nullToAbsent || maxDeltaHeelC != null) {
      map['max_delta_heel_c'] = Variable<double>(maxDeltaHeelC);
    }
    map['alerts_l1'] = Variable<int>(alertsL1);
    map['alerts_l2'] = Variable<int>(alertsL2);
    map['alerts_l3'] = Variable<int>(alertsL3);
    map['alerts_l4'] = Variable<int>(alertsL4);
    map['alerts_l5'] = Variable<int>(alertsL5);
    map['foot_check_done'] = Variable<bool>(footCheckDone);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  DailySummariesCompanion toCompanion(bool nullToAbsent) {
    return DailySummariesCompanion(
      localDate: Value(localDate),
      steps: steps == null && nullToAbsent
          ? const Value.absent()
          : Value(steps),
      walkingMin: walkingMin == null && nullToAbsent
          ? const Value.absent()
          : Value(walkingMin),
      wornMin: wornMin == null && nullToAbsent
          ? const Value.absent()
          : Value(wornMin),
      maxDeltaForefootC: maxDeltaForefootC == null && nullToAbsent
          ? const Value.absent()
          : Value(maxDeltaForefootC),
      maxDeltaHeelC: maxDeltaHeelC == null && nullToAbsent
          ? const Value.absent()
          : Value(maxDeltaHeelC),
      alertsL1: Value(alertsL1),
      alertsL2: Value(alertsL2),
      alertsL3: Value(alertsL3),
      alertsL4: Value(alertsL4),
      alertsL5: Value(alertsL5),
      footCheckDone: Value(footCheckDone),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory DailySummaryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailySummaryRow(
      localDate: serializer.fromJson<String>(json['localDate']),
      steps: serializer.fromJson<int?>(json['steps']),
      walkingMin: serializer.fromJson<int?>(json['walkingMin']),
      wornMin: serializer.fromJson<int?>(json['wornMin']),
      maxDeltaForefootC: serializer.fromJson<double?>(
        json['maxDeltaForefootC'],
      ),
      maxDeltaHeelC: serializer.fromJson<double?>(json['maxDeltaHeelC']),
      alertsL1: serializer.fromJson<int>(json['alertsL1']),
      alertsL2: serializer.fromJson<int>(json['alertsL2']),
      alertsL3: serializer.fromJson<int>(json['alertsL3']),
      alertsL4: serializer.fromJson<int>(json['alertsL4']),
      alertsL5: serializer.fromJson<int>(json['alertsL5']),
      footCheckDone: serializer.fromJson<bool>(json['footCheckDone']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localDate': serializer.toJson<String>(localDate),
      'steps': serializer.toJson<int?>(steps),
      'walkingMin': serializer.toJson<int?>(walkingMin),
      'wornMin': serializer.toJson<int?>(wornMin),
      'maxDeltaForefootC': serializer.toJson<double?>(maxDeltaForefootC),
      'maxDeltaHeelC': serializer.toJson<double?>(maxDeltaHeelC),
      'alertsL1': serializer.toJson<int>(alertsL1),
      'alertsL2': serializer.toJson<int>(alertsL2),
      'alertsL3': serializer.toJson<int>(alertsL3),
      'alertsL4': serializer.toJson<int>(alertsL4),
      'alertsL5': serializer.toJson<int>(alertsL5),
      'footCheckDone': serializer.toJson<bool>(footCheckDone),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  DailySummaryRow copyWith({
    String? localDate,
    Value<int?> steps = const Value.absent(),
    Value<int?> walkingMin = const Value.absent(),
    Value<int?> wornMin = const Value.absent(),
    Value<double?> maxDeltaForefootC = const Value.absent(),
    Value<double?> maxDeltaHeelC = const Value.absent(),
    int? alertsL1,
    int? alertsL2,
    int? alertsL3,
    int? alertsL4,
    int? alertsL5,
    bool? footCheckDone,
    int? updatedAtMs,
  }) => DailySummaryRow(
    localDate: localDate ?? this.localDate,
    steps: steps.present ? steps.value : this.steps,
    walkingMin: walkingMin.present ? walkingMin.value : this.walkingMin,
    wornMin: wornMin.present ? wornMin.value : this.wornMin,
    maxDeltaForefootC: maxDeltaForefootC.present
        ? maxDeltaForefootC.value
        : this.maxDeltaForefootC,
    maxDeltaHeelC: maxDeltaHeelC.present
        ? maxDeltaHeelC.value
        : this.maxDeltaHeelC,
    alertsL1: alertsL1 ?? this.alertsL1,
    alertsL2: alertsL2 ?? this.alertsL2,
    alertsL3: alertsL3 ?? this.alertsL3,
    alertsL4: alertsL4 ?? this.alertsL4,
    alertsL5: alertsL5 ?? this.alertsL5,
    footCheckDone: footCheckDone ?? this.footCheckDone,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  DailySummaryRow copyWithCompanion(DailySummariesCompanion data) {
    return DailySummaryRow(
      localDate: data.localDate.present ? data.localDate.value : this.localDate,
      steps: data.steps.present ? data.steps.value : this.steps,
      walkingMin: data.walkingMin.present
          ? data.walkingMin.value
          : this.walkingMin,
      wornMin: data.wornMin.present ? data.wornMin.value : this.wornMin,
      maxDeltaForefootC: data.maxDeltaForefootC.present
          ? data.maxDeltaForefootC.value
          : this.maxDeltaForefootC,
      maxDeltaHeelC: data.maxDeltaHeelC.present
          ? data.maxDeltaHeelC.value
          : this.maxDeltaHeelC,
      alertsL1: data.alertsL1.present ? data.alertsL1.value : this.alertsL1,
      alertsL2: data.alertsL2.present ? data.alertsL2.value : this.alertsL2,
      alertsL3: data.alertsL3.present ? data.alertsL3.value : this.alertsL3,
      alertsL4: data.alertsL4.present ? data.alertsL4.value : this.alertsL4,
      alertsL5: data.alertsL5.present ? data.alertsL5.value : this.alertsL5,
      footCheckDone: data.footCheckDone.present
          ? data.footCheckDone.value
          : this.footCheckDone,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailySummaryRow(')
          ..write('localDate: $localDate, ')
          ..write('steps: $steps, ')
          ..write('walkingMin: $walkingMin, ')
          ..write('wornMin: $wornMin, ')
          ..write('maxDeltaForefootC: $maxDeltaForefootC, ')
          ..write('maxDeltaHeelC: $maxDeltaHeelC, ')
          ..write('alertsL1: $alertsL1, ')
          ..write('alertsL2: $alertsL2, ')
          ..write('alertsL3: $alertsL3, ')
          ..write('alertsL4: $alertsL4, ')
          ..write('alertsL5: $alertsL5, ')
          ..write('footCheckDone: $footCheckDone, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    localDate,
    steps,
    walkingMin,
    wornMin,
    maxDeltaForefootC,
    maxDeltaHeelC,
    alertsL1,
    alertsL2,
    alertsL3,
    alertsL4,
    alertsL5,
    footCheckDone,
    updatedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailySummaryRow &&
          other.localDate == this.localDate &&
          other.steps == this.steps &&
          other.walkingMin == this.walkingMin &&
          other.wornMin == this.wornMin &&
          other.maxDeltaForefootC == this.maxDeltaForefootC &&
          other.maxDeltaHeelC == this.maxDeltaHeelC &&
          other.alertsL1 == this.alertsL1 &&
          other.alertsL2 == this.alertsL2 &&
          other.alertsL3 == this.alertsL3 &&
          other.alertsL4 == this.alertsL4 &&
          other.alertsL5 == this.alertsL5 &&
          other.footCheckDone == this.footCheckDone &&
          other.updatedAtMs == this.updatedAtMs);
}

class DailySummariesCompanion extends UpdateCompanion<DailySummaryRow> {
  final Value<String> localDate;
  final Value<int?> steps;
  final Value<int?> walkingMin;
  final Value<int?> wornMin;
  final Value<double?> maxDeltaForefootC;
  final Value<double?> maxDeltaHeelC;
  final Value<int> alertsL1;
  final Value<int> alertsL2;
  final Value<int> alertsL3;
  final Value<int> alertsL4;
  final Value<int> alertsL5;
  final Value<bool> footCheckDone;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const DailySummariesCompanion({
    this.localDate = const Value.absent(),
    this.steps = const Value.absent(),
    this.walkingMin = const Value.absent(),
    this.wornMin = const Value.absent(),
    this.maxDeltaForefootC = const Value.absent(),
    this.maxDeltaHeelC = const Value.absent(),
    this.alertsL1 = const Value.absent(),
    this.alertsL2 = const Value.absent(),
    this.alertsL3 = const Value.absent(),
    this.alertsL4 = const Value.absent(),
    this.alertsL5 = const Value.absent(),
    this.footCheckDone = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailySummariesCompanion.insert({
    required String localDate,
    this.steps = const Value.absent(),
    this.walkingMin = const Value.absent(),
    this.wornMin = const Value.absent(),
    this.maxDeltaForefootC = const Value.absent(),
    this.maxDeltaHeelC = const Value.absent(),
    this.alertsL1 = const Value.absent(),
    this.alertsL2 = const Value.absent(),
    this.alertsL3 = const Value.absent(),
    this.alertsL4 = const Value.absent(),
    this.alertsL5 = const Value.absent(),
    this.footCheckDone = const Value.absent(),
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : localDate = Value(localDate),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<DailySummaryRow> custom({
    Expression<String>? localDate,
    Expression<int>? steps,
    Expression<int>? walkingMin,
    Expression<int>? wornMin,
    Expression<double>? maxDeltaForefootC,
    Expression<double>? maxDeltaHeelC,
    Expression<int>? alertsL1,
    Expression<int>? alertsL2,
    Expression<int>? alertsL3,
    Expression<int>? alertsL4,
    Expression<int>? alertsL5,
    Expression<bool>? footCheckDone,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localDate != null) 'local_date': localDate,
      if (steps != null) 'steps': steps,
      if (walkingMin != null) 'walking_min': walkingMin,
      if (wornMin != null) 'worn_min': wornMin,
      if (maxDeltaForefootC != null) 'max_delta_forefoot_c': maxDeltaForefootC,
      if (maxDeltaHeelC != null) 'max_delta_heel_c': maxDeltaHeelC,
      if (alertsL1 != null) 'alerts_l1': alertsL1,
      if (alertsL2 != null) 'alerts_l2': alertsL2,
      if (alertsL3 != null) 'alerts_l3': alertsL3,
      if (alertsL4 != null) 'alerts_l4': alertsL4,
      if (alertsL5 != null) 'alerts_l5': alertsL5,
      if (footCheckDone != null) 'foot_check_done': footCheckDone,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailySummariesCompanion copyWith({
    Value<String>? localDate,
    Value<int?>? steps,
    Value<int?>? walkingMin,
    Value<int?>? wornMin,
    Value<double?>? maxDeltaForefootC,
    Value<double?>? maxDeltaHeelC,
    Value<int>? alertsL1,
    Value<int>? alertsL2,
    Value<int>? alertsL3,
    Value<int>? alertsL4,
    Value<int>? alertsL5,
    Value<bool>? footCheckDone,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return DailySummariesCompanion(
      localDate: localDate ?? this.localDate,
      steps: steps ?? this.steps,
      walkingMin: walkingMin ?? this.walkingMin,
      wornMin: wornMin ?? this.wornMin,
      maxDeltaForefootC: maxDeltaForefootC ?? this.maxDeltaForefootC,
      maxDeltaHeelC: maxDeltaHeelC ?? this.maxDeltaHeelC,
      alertsL1: alertsL1 ?? this.alertsL1,
      alertsL2: alertsL2 ?? this.alertsL2,
      alertsL3: alertsL3 ?? this.alertsL3,
      alertsL4: alertsL4 ?? this.alertsL4,
      alertsL5: alertsL5 ?? this.alertsL5,
      footCheckDone: footCheckDone ?? this.footCheckDone,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localDate.present) {
      map['local_date'] = Variable<String>(localDate.value);
    }
    if (steps.present) {
      map['steps'] = Variable<int>(steps.value);
    }
    if (walkingMin.present) {
      map['walking_min'] = Variable<int>(walkingMin.value);
    }
    if (wornMin.present) {
      map['worn_min'] = Variable<int>(wornMin.value);
    }
    if (maxDeltaForefootC.present) {
      map['max_delta_forefoot_c'] = Variable<double>(maxDeltaForefootC.value);
    }
    if (maxDeltaHeelC.present) {
      map['max_delta_heel_c'] = Variable<double>(maxDeltaHeelC.value);
    }
    if (alertsL1.present) {
      map['alerts_l1'] = Variable<int>(alertsL1.value);
    }
    if (alertsL2.present) {
      map['alerts_l2'] = Variable<int>(alertsL2.value);
    }
    if (alertsL3.present) {
      map['alerts_l3'] = Variable<int>(alertsL3.value);
    }
    if (alertsL4.present) {
      map['alerts_l4'] = Variable<int>(alertsL4.value);
    }
    if (alertsL5.present) {
      map['alerts_l5'] = Variable<int>(alertsL5.value);
    }
    if (footCheckDone.present) {
      map['foot_check_done'] = Variable<bool>(footCheckDone.value);
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
    return (StringBuffer('DailySummariesCompanion(')
          ..write('localDate: $localDate, ')
          ..write('steps: $steps, ')
          ..write('walkingMin: $walkingMin, ')
          ..write('wornMin: $wornMin, ')
          ..write('maxDeltaForefootC: $maxDeltaForefootC, ')
          ..write('maxDeltaHeelC: $maxDeltaHeelC, ')
          ..write('alertsL1: $alertsL1, ')
          ..write('alertsL2: $alertsL2, ')
          ..write('alertsL3: $alertsL3, ')
          ..write('alertsL4: $alertsL4, ')
          ..write('alertsL5: $alertsL5, ')
          ..write('footCheckDone: $footCheckDone, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $FootChecksTable footChecks = $FootChecksTable(this);
  late final $AlertsTable alerts = $AlertsTable(this);
  late final $TemperatureReadingsTable temperatureReadings =
      $TemperatureReadingsTable(this);
  late final $DailySummariesTable dailySummaries = $DailySummariesTable(this);
  late final Index alertsAt = Index(
    'alerts_at',
    'CREATE INDEX alerts_at ON alerts (at_ms)',
  );
  late final Index alertsReadAt = Index(
    'alerts_read_at',
    'CREATE INDEX alerts_read_at ON alerts (read_at_ms)',
  );
  late final Index alertsCapture = Index(
    'alerts_capture',
    'CREATE INDEX alerts_capture ON alerts (capture_stamp)',
  );
  late final Index temperatureSideAt = Index(
    'temperature_side_at',
    'CREATE INDEX temperature_side_at ON temperature_readings (side, at_ms)',
  );
  late final Index temperatureDate = Index(
    'temperature_date',
    'CREATE INDEX temperature_date ON temperature_readings (local_date)',
  );
  late final Index footChecksDate = Index(
    'foot_checks_date',
    'CREATE INDEX foot_checks_date ON foot_checks (local_date)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    footChecks,
    alerts,
    temperatureReadings,
    dailySummaries,
    alertsAt,
    alertsReadAt,
    alertsCapture,
    temperatureSideAt,
    temperatureDate,
    footChecksDate,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'foot_checks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('alerts', kind: UpdateKind.update)],
    ),
  ]);
}

typedef $$FootChecksTableCreateCompanionBuilder = FootChecksCompanion Function({
  Value<int> id,
  required int atMs,
  required String localDate,
  Value<FootCheckAnswer?> qRedness,
  Value<FootCheckAnswer?> qWound,
  Value<FootCheckAnswer?> qSwelling,
  required FootCheckResult result,
  Value<String?> photoSoleLeft,
  Value<String?> photoSoleRight,
  Value<String?> photoTopLeft,
  Value<String?> photoTopRight,
  required bool answerOnly,
});
typedef $$FootChecksTableUpdateCompanionBuilder = FootChecksCompanion Function({
  Value<int> id,
  Value<int> atMs,
  Value<String> localDate,
  Value<FootCheckAnswer?> qRedness,
  Value<FootCheckAnswer?> qWound,
  Value<FootCheckAnswer?> qSwelling,
  Value<FootCheckResult> result,
  Value<String?> photoSoleLeft,
  Value<String?> photoSoleRight,
  Value<String?> photoTopLeft,
  Value<String?> photoTopRight,
  Value<bool> answerOnly,
});

final class $$FootChecksTableReferences
    extends BaseReferences<_$AppDatabase, $FootChecksTable, FootCheckRow> {
  $$FootChecksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$AlertsTable, List<AlertRow>> _alertsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.alerts,
    aliasName: 'foot_checks__id__alerts__foot_check_id',
  );

  $$AlertsTableProcessedTableManager get alertsRefs {
    final manager = $$AlertsTableTableManager(
      $_db,
      $_db.alerts,
    ).filter((f) => f.footCheckId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_alertsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$FootChecksTableFilterComposer
    extends Composer<_$AppDatabase, $FootChecksTable> {
  $$FootChecksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get atMs => $composableBuilder(
    column: $table.atMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<FootCheckAnswer?, FootCheckAnswer, String>
  get qRedness => $composableBuilder(
    column: $table.qRedness,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<FootCheckAnswer?, FootCheckAnswer, String>
  get qWound => $composableBuilder(
    column: $table.qWound,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<FootCheckAnswer?, FootCheckAnswer, String>
  get qSwelling => $composableBuilder(
    column: $table.qSwelling,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<FootCheckResult, FootCheckResult, String>
  get result => $composableBuilder(
    column: $table.result,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get photoSoleLeft => $composableBuilder(
    column: $table.photoSoleLeft,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoSoleRight => $composableBuilder(
    column: $table.photoSoleRight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoTopLeft => $composableBuilder(
    column: $table.photoTopLeft,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoTopRight => $composableBuilder(
    column: $table.photoTopRight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get answerOnly => $composableBuilder(
    column: $table.answerOnly,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> alertsRefs(
    Expression<bool> Function($$AlertsTableFilterComposer f) f,
  ) {
    final $$AlertsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.alerts,
      getReferencedColumn: (t) => t.footCheckId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AlertsTableFilterComposer(
            $db: $db,
            $table: $db.alerts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FootChecksTableOrderingComposer
    extends Composer<_$AppDatabase, $FootChecksTable> {
  $$FootChecksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get atMs => $composableBuilder(
    column: $table.atMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get qRedness => $composableBuilder(
    column: $table.qRedness,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get qWound => $composableBuilder(
    column: $table.qWound,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get qSwelling => $composableBuilder(
    column: $table.qSwelling,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get result => $composableBuilder(
    column: $table.result,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoSoleLeft => $composableBuilder(
    column: $table.photoSoleLeft,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoSoleRight => $composableBuilder(
    column: $table.photoSoleRight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoTopLeft => $composableBuilder(
    column: $table.photoTopLeft,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoTopRight => $composableBuilder(
    column: $table.photoTopRight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get answerOnly => $composableBuilder(
    column: $table.answerOnly,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FootChecksTableAnnotationComposer
    extends Composer<_$AppDatabase, $FootChecksTable> {
  $$FootChecksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get atMs =>
      $composableBuilder(column: $table.atMs, builder: (column) => column);

  GeneratedColumn<String> get localDate =>
      $composableBuilder(column: $table.localDate, builder: (column) => column);

  GeneratedColumnWithTypeConverter<FootCheckAnswer?, String> get qRedness =>
      $composableBuilder(column: $table.qRedness, builder: (column) => column);

  GeneratedColumnWithTypeConverter<FootCheckAnswer?, String> get qWound =>
      $composableBuilder(column: $table.qWound, builder: (column) => column);

  GeneratedColumnWithTypeConverter<FootCheckAnswer?, String> get qSwelling =>
      $composableBuilder(column: $table.qSwelling, builder: (column) => column);

  GeneratedColumnWithTypeConverter<FootCheckResult, String> get result =>
      $composableBuilder(column: $table.result, builder: (column) => column);

  GeneratedColumn<String> get photoSoleLeft => $composableBuilder(
    column: $table.photoSoleLeft,
    builder: (column) => column,
  );

  GeneratedColumn<String> get photoSoleRight => $composableBuilder(
    column: $table.photoSoleRight,
    builder: (column) => column,
  );

  GeneratedColumn<String> get photoTopLeft => $composableBuilder(
    column: $table.photoTopLeft,
    builder: (column) => column,
  );

  GeneratedColumn<String> get photoTopRight => $composableBuilder(
    column: $table.photoTopRight,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get answerOnly => $composableBuilder(
    column: $table.answerOnly,
    builder: (column) => column,
  );

  Expression<T> alertsRefs<T extends Object>(
    Expression<T> Function($$AlertsTableAnnotationComposer a) f,
  ) {
    final $$AlertsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.alerts,
      getReferencedColumn: (t) => t.footCheckId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AlertsTableAnnotationComposer(
            $db: $db,
            $table: $db.alerts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FootChecksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FootChecksTable,
          FootCheckRow,
          $$FootChecksTableFilterComposer,
          $$FootChecksTableOrderingComposer,
          $$FootChecksTableAnnotationComposer,
          $$FootChecksTableCreateCompanionBuilder,
          $$FootChecksTableUpdateCompanionBuilder,
          (FootCheckRow, $$FootChecksTableReferences),
          FootCheckRow,
          PrefetchHooks Function({bool alertsRefs})
        > {
  $$FootChecksTableTableManager(_$AppDatabase db, $FootChecksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FootChecksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FootChecksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FootChecksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> atMs = const Value.absent(),
                Value<String> localDate = const Value.absent(),
                Value<FootCheckAnswer?> qRedness = const Value.absent(),
                Value<FootCheckAnswer?> qWound = const Value.absent(),
                Value<FootCheckAnswer?> qSwelling = const Value.absent(),
                Value<FootCheckResult> result = const Value.absent(),
                Value<String?> photoSoleLeft = const Value.absent(),
                Value<String?> photoSoleRight = const Value.absent(),
                Value<String?> photoTopLeft = const Value.absent(),
                Value<String?> photoTopRight = const Value.absent(),
                Value<bool> answerOnly = const Value.absent(),
              }) => FootChecksCompanion(
                id: id,
                atMs: atMs,
                localDate: localDate,
                qRedness: qRedness,
                qWound: qWound,
                qSwelling: qSwelling,
                result: result,
                photoSoleLeft: photoSoleLeft,
                photoSoleRight: photoSoleRight,
                photoTopLeft: photoTopLeft,
                photoTopRight: photoTopRight,
                answerOnly: answerOnly,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int atMs,
                required String localDate,
                Value<FootCheckAnswer?> qRedness = const Value.absent(),
                Value<FootCheckAnswer?> qWound = const Value.absent(),
                Value<FootCheckAnswer?> qSwelling = const Value.absent(),
                required FootCheckResult result,
                Value<String?> photoSoleLeft = const Value.absent(),
                Value<String?> photoSoleRight = const Value.absent(),
                Value<String?> photoTopLeft = const Value.absent(),
                Value<String?> photoTopRight = const Value.absent(),
                required bool answerOnly,
              }) => FootChecksCompanion.insert(
                id: id,
                atMs: atMs,
                localDate: localDate,
                qRedness: qRedness,
                qWound: qWound,
                qSwelling: qSwelling,
                result: result,
                photoSoleLeft: photoSoleLeft,
                photoSoleRight: photoSoleRight,
                photoTopLeft: photoTopLeft,
                photoTopRight: photoTopRight,
                answerOnly: answerOnly,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FootChecksTable, FootCheckRow>(table),
                  $$FootChecksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({alertsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (alertsRefs) db.alerts],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (alertsRefs)
                    await $_getPrefetchedDataByColumns<
                      FootCheckRow,
                      $FootChecksTable,
                      AlertRow,
                      $AlertsTable
                    >(
                      currentTable: table,
                      referencedTable: $$FootChecksTableReferences
                          ._alertsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$FootChecksTableReferences(db, table, p0).alertsRefs,
                      currentColumn: 'id',
                      referencedColumn: 'foot_check_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$FootChecksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FootChecksTable,
      FootCheckRow,
      $$FootChecksTableFilterComposer,
      $$FootChecksTableOrderingComposer,
      $$FootChecksTableAnnotationComposer,
      $$FootChecksTableCreateCompanionBuilder,
      $$FootChecksTableUpdateCompanionBuilder,
      (FootCheckRow, $$FootChecksTableReferences),
      FootCheckRow,
      PrefetchHooks Function({bool alertsRefs})
    >;
typedef $$AlertsTableCreateCompanionBuilder = AlertsCompanion Function({
  Value<int> id,
  required AlertKind code,
  required int level,
  required PatientLevel patientStatus,
  Value<FootSide?> side,
  Value<String?> zone,
  Value<TempSite?> site,
  Value<double?> measuredValue,
  Value<double?> threshold,
  Value<String?> gaitClass,
  Value<double?> gaitConfidence,
  Value<Map<String, Object?>?> details,
  required int atMs,
  required String localDate,
  Value<int?> readAtMs,
  Value<String?> captureStamp,
  Value<int?> footCheckId,
});
typedef $$AlertsTableUpdateCompanionBuilder = AlertsCompanion Function({
  Value<int> id,
  Value<AlertKind> code,
  Value<int> level,
  Value<PatientLevel> patientStatus,
  Value<FootSide?> side,
  Value<String?> zone,
  Value<TempSite?> site,
  Value<double?> measuredValue,
  Value<double?> threshold,
  Value<String?> gaitClass,
  Value<double?> gaitConfidence,
  Value<Map<String, Object?>?> details,
  Value<int> atMs,
  Value<String> localDate,
  Value<int?> readAtMs,
  Value<String?> captureStamp,
  Value<int?> footCheckId,
});

final class $$AlertsTableReferences
    extends BaseReferences<_$AppDatabase, $AlertsTable, AlertRow> {
  $$AlertsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $FootChecksTable _footCheckIdTable(_$AppDatabase db) =>
      db.footChecks.createAlias('alerts__foot_check_id__foot_checks__id');

  $$FootChecksTableProcessedTableManager? get footCheckId {
    final $_column = $_itemColumn<int>('foot_check_id');
    if ($_column == null) return null;
    final manager = $$FootChecksTableTableManager(
      $_db,
      $_db.footChecks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_footCheckIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AlertsTableFilterComposer
    extends Composer<_$AppDatabase, $AlertsTable> {
  $$AlertsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AlertKind, AlertKind, String> get code =>
      $composableBuilder(
        column: $table.code,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PatientLevel, PatientLevel, String>
  get patientStatus => $composableBuilder(
    column: $table.patientStatus,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<FootSide?, FootSide, String> get side =>
      $composableBuilder(
        column: $table.side,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get zone => $composableBuilder(
    column: $table.zone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TempSite?, TempSite, String> get site =>
      $composableBuilder(
        column: $table.site,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<double> get measuredValue => $composableBuilder(
    column: $table.measuredValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get threshold => $composableBuilder(
    column: $table.threshold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gaitClass => $composableBuilder(
    column: $table.gaitClass,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get gaitConfidence => $composableBuilder(
    column: $table.gaitConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    Map<String, Object?>?,
    Map<String, Object>?,
    String
  >
  get details => $composableBuilder(
    column: $table.details,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get atMs => $composableBuilder(
    column: $table.atMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get readAtMs => $composableBuilder(
    column: $table.readAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get captureStamp => $composableBuilder(
    column: $table.captureStamp,
    builder: (column) => ColumnFilters(column),
  );

  $$FootChecksTableFilterComposer get footCheckId {
    final $$FootChecksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.footCheckId,
      referencedTable: $db.footChecks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FootChecksTableFilterComposer(
            $db: $db,
            $table: $db.footChecks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AlertsTableOrderingComposer
    extends Composer<_$AppDatabase, $AlertsTable> {
  $$AlertsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get patientStatus => $composableBuilder(
    column: $table.patientStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get side => $composableBuilder(
    column: $table.side,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get zone => $composableBuilder(
    column: $table.zone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get site => $composableBuilder(
    column: $table.site,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get measuredValue => $composableBuilder(
    column: $table.measuredValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get threshold => $composableBuilder(
    column: $table.threshold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gaitClass => $composableBuilder(
    column: $table.gaitClass,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get gaitConfidence => $composableBuilder(
    column: $table.gaitConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get details => $composableBuilder(
    column: $table.details,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get atMs => $composableBuilder(
    column: $table.atMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get readAtMs => $composableBuilder(
    column: $table.readAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get captureStamp => $composableBuilder(
    column: $table.captureStamp,
    builder: (column) => ColumnOrderings(column),
  );

  $$FootChecksTableOrderingComposer get footCheckId {
    final $$FootChecksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.footCheckId,
      referencedTable: $db.footChecks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FootChecksTableOrderingComposer(
            $db: $db,
            $table: $db.footChecks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AlertsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlertsTable> {
  $$AlertsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AlertKind, String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<int> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PatientLevel, String> get patientStatus =>
      $composableBuilder(
        column: $table.patientStatus,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<FootSide?, String> get side =>
      $composableBuilder(column: $table.side, builder: (column) => column);

  GeneratedColumn<String> get zone =>
      $composableBuilder(column: $table.zone, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TempSite?, String> get site =>
      $composableBuilder(column: $table.site, builder: (column) => column);

  GeneratedColumn<double> get measuredValue => $composableBuilder(
    column: $table.measuredValue,
    builder: (column) => column,
  );

  GeneratedColumn<double> get threshold =>
      $composableBuilder(column: $table.threshold, builder: (column) => column);

  GeneratedColumn<String> get gaitClass =>
      $composableBuilder(column: $table.gaitClass, builder: (column) => column);

  GeneratedColumn<double> get gaitConfidence => $composableBuilder(
    column: $table.gaitConfidence,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Map<String, Object?>?, String> get details =>
      $composableBuilder(column: $table.details, builder: (column) => column);

  GeneratedColumn<int> get atMs =>
      $composableBuilder(column: $table.atMs, builder: (column) => column);

  GeneratedColumn<String> get localDate =>
      $composableBuilder(column: $table.localDate, builder: (column) => column);

  GeneratedColumn<int> get readAtMs =>
      $composableBuilder(column: $table.readAtMs, builder: (column) => column);

  GeneratedColumn<String> get captureStamp => $composableBuilder(
    column: $table.captureStamp,
    builder: (column) => column,
  );

  $$FootChecksTableAnnotationComposer get footCheckId {
    final $$FootChecksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.footCheckId,
      referencedTable: $db.footChecks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FootChecksTableAnnotationComposer(
            $db: $db,
            $table: $db.footChecks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AlertsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AlertsTable,
          AlertRow,
          $$AlertsTableFilterComposer,
          $$AlertsTableOrderingComposer,
          $$AlertsTableAnnotationComposer,
          $$AlertsTableCreateCompanionBuilder,
          $$AlertsTableUpdateCompanionBuilder,
          (AlertRow, $$AlertsTableReferences),
          AlertRow,
          PrefetchHooks Function({bool footCheckId})
        > {
  $$AlertsTableTableManager(_$AppDatabase db, $AlertsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlertsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlertsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlertsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<AlertKind> code = const Value.absent(),
                Value<int> level = const Value.absent(),
                Value<PatientLevel> patientStatus = const Value.absent(),
                Value<FootSide?> side = const Value.absent(),
                Value<String?> zone = const Value.absent(),
                Value<TempSite?> site = const Value.absent(),
                Value<double?> measuredValue = const Value.absent(),
                Value<double?> threshold = const Value.absent(),
                Value<String?> gaitClass = const Value.absent(),
                Value<double?> gaitConfidence = const Value.absent(),
                Value<Map<String, Object?>?> details = const Value.absent(),
                Value<int> atMs = const Value.absent(),
                Value<String> localDate = const Value.absent(),
                Value<int?> readAtMs = const Value.absent(),
                Value<String?> captureStamp = const Value.absent(),
                Value<int?> footCheckId = const Value.absent(),
              }) => AlertsCompanion(
                id: id,
                code: code,
                level: level,
                patientStatus: patientStatus,
                side: side,
                zone: zone,
                site: site,
                measuredValue: measuredValue,
                threshold: threshold,
                gaitClass: gaitClass,
                gaitConfidence: gaitConfidence,
                details: details,
                atMs: atMs,
                localDate: localDate,
                readAtMs: readAtMs,
                captureStamp: captureStamp,
                footCheckId: footCheckId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required AlertKind code,
                required int level,
                required PatientLevel patientStatus,
                Value<FootSide?> side = const Value.absent(),
                Value<String?> zone = const Value.absent(),
                Value<TempSite?> site = const Value.absent(),
                Value<double?> measuredValue = const Value.absent(),
                Value<double?> threshold = const Value.absent(),
                Value<String?> gaitClass = const Value.absent(),
                Value<double?> gaitConfidence = const Value.absent(),
                Value<Map<String, Object?>?> details = const Value.absent(),
                required int atMs,
                required String localDate,
                Value<int?> readAtMs = const Value.absent(),
                Value<String?> captureStamp = const Value.absent(),
                Value<int?> footCheckId = const Value.absent(),
              }) => AlertsCompanion.insert(
                id: id,
                code: code,
                level: level,
                patientStatus: patientStatus,
                side: side,
                zone: zone,
                site: site,
                measuredValue: measuredValue,
                threshold: threshold,
                gaitClass: gaitClass,
                gaitConfidence: gaitConfidence,
                details: details,
                atMs: atMs,
                localDate: localDate,
                readAtMs: readAtMs,
                captureStamp: captureStamp,
                footCheckId: footCheckId,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AlertsTable, AlertRow>(table),
                  $$AlertsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({footCheckId = false}) {
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
                    if (footCheckId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.footCheckId,
                        referencedTable: $$AlertsTableReferences
                            ._footCheckIdTable(db),
                        referencedColumn: $$AlertsTableReferences
                            ._footCheckIdTable(db)
                            .id,
                      ) as T;
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

typedef $$AlertsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AlertsTable,
      AlertRow,
      $$AlertsTableFilterComposer,
      $$AlertsTableOrderingComposer,
      $$AlertsTableAnnotationComposer,
      $$AlertsTableCreateCompanionBuilder,
      $$AlertsTableUpdateCompanionBuilder,
      (AlertRow, $$AlertsTableReferences),
      AlertRow,
      PrefetchHooks Function({bool footCheckId})
    >;
typedef $$TemperatureReadingsTableCreateCompanionBuilder =
    TemperatureReadingsCompanion Function({
      Value<int> id,
      required int atMs,
      required String localDate,
      required FootSide side,
      Value<double?> forefootC,
      Value<double?> heelC,
      required TempQuality quality,
      required bool timeFromArrival,
    });
typedef $$TemperatureReadingsTableUpdateCompanionBuilder =
    TemperatureReadingsCompanion Function({
      Value<int> id,
      Value<int> atMs,
      Value<String> localDate,
      Value<FootSide> side,
      Value<double?> forefootC,
      Value<double?> heelC,
      Value<TempQuality> quality,
      Value<bool> timeFromArrival,
    });

class $$TemperatureReadingsTableFilterComposer
    extends Composer<_$AppDatabase, $TemperatureReadingsTable> {
  $$TemperatureReadingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get atMs => $composableBuilder(
    column: $table.atMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<FootSide, FootSide, String> get side =>
      $composableBuilder(
        column: $table.side,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<double> get forefootC => $composableBuilder(
    column: $table.forefootC,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get heelC => $composableBuilder(
    column: $table.heelC,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TempQuality, TempQuality, String>
  get quality => $composableBuilder(
    column: $table.quality,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<bool> get timeFromArrival => $composableBuilder(
    column: $table.timeFromArrival,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TemperatureReadingsTableOrderingComposer
    extends Composer<_$AppDatabase, $TemperatureReadingsTable> {
  $$TemperatureReadingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get atMs => $composableBuilder(
    column: $table.atMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get side => $composableBuilder(
    column: $table.side,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get forefootC => $composableBuilder(
    column: $table.forefootC,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get heelC => $composableBuilder(
    column: $table.heelC,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quality => $composableBuilder(
    column: $table.quality,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get timeFromArrival => $composableBuilder(
    column: $table.timeFromArrival,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TemperatureReadingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TemperatureReadingsTable> {
  $$TemperatureReadingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get atMs =>
      $composableBuilder(column: $table.atMs, builder: (column) => column);

  GeneratedColumn<String> get localDate =>
      $composableBuilder(column: $table.localDate, builder: (column) => column);

  GeneratedColumnWithTypeConverter<FootSide, String> get side =>
      $composableBuilder(column: $table.side, builder: (column) => column);

  GeneratedColumn<double> get forefootC =>
      $composableBuilder(column: $table.forefootC, builder: (column) => column);

  GeneratedColumn<double> get heelC =>
      $composableBuilder(column: $table.heelC, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TempQuality, String> get quality =>
      $composableBuilder(column: $table.quality, builder: (column) => column);

  GeneratedColumn<bool> get timeFromArrival => $composableBuilder(
    column: $table.timeFromArrival,
    builder: (column) => column,
  );
}

class $$TemperatureReadingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TemperatureReadingsTable,
          TemperatureRow,
          $$TemperatureReadingsTableFilterComposer,
          $$TemperatureReadingsTableOrderingComposer,
          $$TemperatureReadingsTableAnnotationComposer,
          $$TemperatureReadingsTableCreateCompanionBuilder,
          $$TemperatureReadingsTableUpdateCompanionBuilder,
          (
            TemperatureRow,
            BaseReferences<
              _$AppDatabase,
              $TemperatureReadingsTable,
              TemperatureRow
            >,
          ),
          TemperatureRow,
          PrefetchHooks Function()
        > {
  $$TemperatureReadingsTableTableManager(
    _$AppDatabase db,
    $TemperatureReadingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TemperatureReadingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TemperatureReadingsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$TemperatureReadingsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> atMs = const Value.absent(),
                Value<String> localDate = const Value.absent(),
                Value<FootSide> side = const Value.absent(),
                Value<double?> forefootC = const Value.absent(),
                Value<double?> heelC = const Value.absent(),
                Value<TempQuality> quality = const Value.absent(),
                Value<bool> timeFromArrival = const Value.absent(),
              }) => TemperatureReadingsCompanion(
                id: id,
                atMs: atMs,
                localDate: localDate,
                side: side,
                forefootC: forefootC,
                heelC: heelC,
                quality: quality,
                timeFromArrival: timeFromArrival,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int atMs,
                required String localDate,
                required FootSide side,
                Value<double?> forefootC = const Value.absent(),
                Value<double?> heelC = const Value.absent(),
                required TempQuality quality,
                required bool timeFromArrival,
              }) => TemperatureReadingsCompanion.insert(
                id: id,
                atMs: atMs,
                localDate: localDate,
                side: side,
                forefootC: forefootC,
                heelC: heelC,
                quality: quality,
                timeFromArrival: timeFromArrival,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TemperatureReadingsTable, TemperatureRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $TemperatureReadingsTable,
                    TemperatureRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TemperatureReadingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TemperatureReadingsTable,
      TemperatureRow,
      $$TemperatureReadingsTableFilterComposer,
      $$TemperatureReadingsTableOrderingComposer,
      $$TemperatureReadingsTableAnnotationComposer,
      $$TemperatureReadingsTableCreateCompanionBuilder,
      $$TemperatureReadingsTableUpdateCompanionBuilder,
      (
        TemperatureRow,
        BaseReferences<
          _$AppDatabase,
          $TemperatureReadingsTable,
          TemperatureRow
        >,
      ),
      TemperatureRow,
      PrefetchHooks Function()
    >;
typedef $$DailySummariesTableCreateCompanionBuilder =
    DailySummariesCompanion Function({
      required String localDate,
      Value<int?> steps,
      Value<int?> walkingMin,
      Value<int?> wornMin,
      Value<double?> maxDeltaForefootC,
      Value<double?> maxDeltaHeelC,
      Value<int> alertsL1,
      Value<int> alertsL2,
      Value<int> alertsL3,
      Value<int> alertsL4,
      Value<int> alertsL5,
      Value<bool> footCheckDone,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$DailySummariesTableUpdateCompanionBuilder =
    DailySummariesCompanion Function({
      Value<String> localDate,
      Value<int?> steps,
      Value<int?> walkingMin,
      Value<int?> wornMin,
      Value<double?> maxDeltaForefootC,
      Value<double?> maxDeltaHeelC,
      Value<int> alertsL1,
      Value<int> alertsL2,
      Value<int> alertsL3,
      Value<int> alertsL4,
      Value<int> alertsL5,
      Value<bool> footCheckDone,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$DailySummariesTableFilterComposer
    extends Composer<_$AppDatabase, $DailySummariesTable> {
  $$DailySummariesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get steps => $composableBuilder(
    column: $table.steps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get walkingMin => $composableBuilder(
    column: $table.walkingMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wornMin => $composableBuilder(
    column: $table.wornMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get maxDeltaForefootC => $composableBuilder(
    column: $table.maxDeltaForefootC,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get maxDeltaHeelC => $composableBuilder(
    column: $table.maxDeltaHeelC,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get alertsL1 => $composableBuilder(
    column: $table.alertsL1,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get alertsL2 => $composableBuilder(
    column: $table.alertsL2,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get alertsL3 => $composableBuilder(
    column: $table.alertsL3,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get alertsL4 => $composableBuilder(
    column: $table.alertsL4,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get alertsL5 => $composableBuilder(
    column: $table.alertsL5,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get footCheckDone => $composableBuilder(
    column: $table.footCheckDone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DailySummariesTableOrderingComposer
    extends Composer<_$AppDatabase, $DailySummariesTable> {
  $$DailySummariesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get steps => $composableBuilder(
    column: $table.steps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get walkingMin => $composableBuilder(
    column: $table.walkingMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wornMin => $composableBuilder(
    column: $table.wornMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get maxDeltaForefootC => $composableBuilder(
    column: $table.maxDeltaForefootC,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get maxDeltaHeelC => $composableBuilder(
    column: $table.maxDeltaHeelC,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get alertsL1 => $composableBuilder(
    column: $table.alertsL1,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get alertsL2 => $composableBuilder(
    column: $table.alertsL2,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get alertsL3 => $composableBuilder(
    column: $table.alertsL3,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get alertsL4 => $composableBuilder(
    column: $table.alertsL4,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get alertsL5 => $composableBuilder(
    column: $table.alertsL5,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get footCheckDone => $composableBuilder(
    column: $table.footCheckDone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailySummariesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailySummariesTable> {
  $$DailySummariesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localDate =>
      $composableBuilder(column: $table.localDate, builder: (column) => column);

  GeneratedColumn<int> get steps =>
      $composableBuilder(column: $table.steps, builder: (column) => column);

  GeneratedColumn<int> get walkingMin => $composableBuilder(
    column: $table.walkingMin,
    builder: (column) => column,
  );

  GeneratedColumn<int> get wornMin =>
      $composableBuilder(column: $table.wornMin, builder: (column) => column);

  GeneratedColumn<double> get maxDeltaForefootC => $composableBuilder(
    column: $table.maxDeltaForefootC,
    builder: (column) => column,
  );

  GeneratedColumn<double> get maxDeltaHeelC => $composableBuilder(
    column: $table.maxDeltaHeelC,
    builder: (column) => column,
  );

  GeneratedColumn<int> get alertsL1 =>
      $composableBuilder(column: $table.alertsL1, builder: (column) => column);

  GeneratedColumn<int> get alertsL2 =>
      $composableBuilder(column: $table.alertsL2, builder: (column) => column);

  GeneratedColumn<int> get alertsL3 =>
      $composableBuilder(column: $table.alertsL3, builder: (column) => column);

  GeneratedColumn<int> get alertsL4 =>
      $composableBuilder(column: $table.alertsL4, builder: (column) => column);

  GeneratedColumn<int> get alertsL5 =>
      $composableBuilder(column: $table.alertsL5, builder: (column) => column);

  GeneratedColumn<bool> get footCheckDone => $composableBuilder(
    column: $table.footCheckDone,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$DailySummariesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailySummariesTable,
          DailySummaryRow,
          $$DailySummariesTableFilterComposer,
          $$DailySummariesTableOrderingComposer,
          $$DailySummariesTableAnnotationComposer,
          $$DailySummariesTableCreateCompanionBuilder,
          $$DailySummariesTableUpdateCompanionBuilder,
          (
            DailySummaryRow,
            BaseReferences<
              _$AppDatabase,
              $DailySummariesTable,
              DailySummaryRow
            >,
          ),
          DailySummaryRow,
          PrefetchHooks Function()
        > {
  $$DailySummariesTableTableManager(
    _$AppDatabase db,
    $DailySummariesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailySummariesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailySummariesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailySummariesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> localDate = const Value.absent(),
                Value<int?> steps = const Value.absent(),
                Value<int?> walkingMin = const Value.absent(),
                Value<int?> wornMin = const Value.absent(),
                Value<double?> maxDeltaForefootC = const Value.absent(),
                Value<double?> maxDeltaHeelC = const Value.absent(),
                Value<int> alertsL1 = const Value.absent(),
                Value<int> alertsL2 = const Value.absent(),
                Value<int> alertsL3 = const Value.absent(),
                Value<int> alertsL4 = const Value.absent(),
                Value<int> alertsL5 = const Value.absent(),
                Value<bool> footCheckDone = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailySummariesCompanion(
                localDate: localDate,
                steps: steps,
                walkingMin: walkingMin,
                wornMin: wornMin,
                maxDeltaForefootC: maxDeltaForefootC,
                maxDeltaHeelC: maxDeltaHeelC,
                alertsL1: alertsL1,
                alertsL2: alertsL2,
                alertsL3: alertsL3,
                alertsL4: alertsL4,
                alertsL5: alertsL5,
                footCheckDone: footCheckDone,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String localDate,
                Value<int?> steps = const Value.absent(),
                Value<int?> walkingMin = const Value.absent(),
                Value<int?> wornMin = const Value.absent(),
                Value<double?> maxDeltaForefootC = const Value.absent(),
                Value<double?> maxDeltaHeelC = const Value.absent(),
                Value<int> alertsL1 = const Value.absent(),
                Value<int> alertsL2 = const Value.absent(),
                Value<int> alertsL3 = const Value.absent(),
                Value<int> alertsL4 = const Value.absent(),
                Value<int> alertsL5 = const Value.absent(),
                Value<bool> footCheckDone = const Value.absent(),
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => DailySummariesCompanion.insert(
                localDate: localDate,
                steps: steps,
                walkingMin: walkingMin,
                wornMin: wornMin,
                maxDeltaForefootC: maxDeltaForefootC,
                maxDeltaHeelC: maxDeltaHeelC,
                alertsL1: alertsL1,
                alertsL2: alertsL2,
                alertsL3: alertsL3,
                alertsL4: alertsL4,
                alertsL5: alertsL5,
                footCheckDone: footCheckDone,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DailySummariesTable, DailySummaryRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $DailySummariesTable,
                    DailySummaryRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailySummariesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailySummariesTable,
      DailySummaryRow,
      $$DailySummariesTableFilterComposer,
      $$DailySummariesTableOrderingComposer,
      $$DailySummariesTableAnnotationComposer,
      $$DailySummariesTableCreateCompanionBuilder,
      $$DailySummariesTableUpdateCompanionBuilder,
      (
        DailySummaryRow,
        BaseReferences<_$AppDatabase, $DailySummariesTable, DailySummaryRow>,
      ),
      DailySummaryRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$FootChecksTableTableManager get footChecks =>
      $$FootChecksTableTableManager(_db, _db.footChecks);
  $$AlertsTableTableManager get alerts =>
      $$AlertsTableTableManager(_db, _db.alerts);
  $$TemperatureReadingsTableTableManager get temperatureReadings =>
      $$TemperatureReadingsTableTableManager(_db, _db.temperatureReadings);
  $$DailySummariesTableTableManager get dailySummaries =>
      $$DailySummariesTableTableManager(_db, _db.dailySummaries);
}
