part of 'fire_api_local_base.dart';

class _LocalIndexedFieldEntry {
  final String fieldPath;
  final _LocalIndexedFieldValue value;
  final bool arrayElement;

  const _LocalIndexedFieldEntry({
    required this.fieldPath,
    required this.value,
    this.arrayElement = false,
  });

  static List<_LocalIndexedFieldEntry> flatten(DocumentData data) => [
    for (MapEntry<String, dynamic> entry in data.entries)
      ..._flattenValue(entry.key, entry.value),
  ];

  static List<_LocalIndexedFieldEntry> _flattenValue(
    String fieldPath,
    dynamic value,
  ) {
    dynamic normalized = convertSerializedVectorValuesToRuntime(value);
    if (normalized is VectorValue) return const <_LocalIndexedFieldEntry>[];
    if (normalized is Map) {
      return <_LocalIndexedFieldEntry>[
        for (MapEntry<dynamic, dynamic> entry in normalized.entries)
          ..._flattenValue('$fieldPath.${entry.key}', entry.value),
      ];
    }

    _LocalIndexedFieldValue? indexedValue = _LocalIndexedFieldValue.tryCreate(
      normalized,
    );
    if (indexedValue != null) {
      return <_LocalIndexedFieldEntry>[
        _LocalIndexedFieldEntry(fieldPath: fieldPath, value: indexedValue),
      ];
    }

    if (normalized is List) {
      return <_LocalIndexedFieldEntry>[
        for (dynamic item in normalized)
          if (_LocalIndexedFieldValue.tryCreate(item) != null)
            _LocalIndexedFieldEntry(
              fieldPath: fieldPath,
              value: _LocalIndexedFieldValue.tryCreate(item)!,
              arrayElement: true,
            ),
      ];
    }

    return const <_LocalIndexedFieldEntry>[];
  }
}

class _LocalIndexedFieldValue {
  final String valueType;
  final String? valueText;
  final double? valueNumber;
  final int? valueBool;

  const _LocalIndexedFieldValue({
    required this.valueType,
    this.valueText,
    this.valueNumber,
    this.valueBool,
  });

  static _LocalIndexedFieldValue? tryCreate(dynamic value) {
    dynamic normalized = convertSerializedVectorValuesToRuntime(value);
    if (normalized == null) {
      return const _LocalIndexedFieldValue(valueType: 'null');
    }

    if (normalized is String) {
      return _LocalIndexedFieldValue(
        valueType: 'string',
        valueText: normalized,
      );
    }

    if (normalized is DateTime) {
      return _LocalIndexedFieldValue(
        valueType: 'timestamp',
        valueNumber: normalized.toUtc().microsecondsSinceEpoch.toDouble(),
      );
    }

    if (normalized is Uint8List) {
      return _LocalIndexedFieldValue(
        valueType: 'blob',
        valueText: convert.base64Encode(normalized),
      );
    }

    if (normalized is LocalGeoPoint) {
      return _LocalIndexedFieldValue(
        valueType: 'geo_point',
        valueText: '${normalized.latitude},${normalized.longitude}',
      );
    }

    if (normalized is DocumentReference) {
      return _LocalIndexedFieldValue(
        valueType: 'reference',
        valueText: normalized.path,
      );
    }

    if (normalized is num) {
      return _LocalIndexedFieldValue(
        valueType: 'number',
        valueNumber: normalized.toDouble(),
      );
    }

    if (normalized is bool) {
      return _LocalIndexedFieldValue(
        valueType: 'bool',
        valueBool: normalized ? 1 : 0,
      );
    }

    return null;
  }

  static List<_LocalIndexedFieldValue> forQueryValue(dynamic value) {
    dynamic normalized = convertSerializedVectorValuesToRuntime(value);
    _LocalIndexedFieldValue? indexedValue = tryCreate(normalized);
    if (indexedValue != null) {
      return <_LocalIndexedFieldValue>[indexedValue];
    }

    if (normalized is List) {
      return normalized
          .map(tryCreate)
          .whereType<_LocalIndexedFieldValue>()
          .toList();
    }

    return const <_LocalIndexedFieldValue>[];
  }

  bool get supportsRange =>
      valueType == 'number' ||
      valueType == 'string' ||
      valueType == 'timestamp';

  String get rangeColumn =>
      valueType == 'number' ? 'value_number' : 'value_text';

  Object? get rangeValue => valueType == 'number' ? valueNumber : valueText;
}

extension _XCollectionReferenceLocalIndex on CollectionReference {
  Clause? get bestIndexableClause {
    List<Clause> equalityIndexable = localIndexableClauses
        .where((clause) => clause.isLocalEqualityIndexable)
        .toList();
    if (equalityIndexable.isNotEmpty) return equalityIndexable.first;

    List<Clause> rangeIndexable = localIndexableClauses
        .where((clause) => clause.isLocalRangeIndexable)
        .toList();
    return rangeIndexable.isEmpty ? null : rangeIndexable.first;
  }

  List<Clause> get localIndexableClauses => clauses
      .where(
        (clause) =>
            clause.isLocalEqualityIndexable || clause.isLocalRangeIndexable,
      )
      .toList();
}

extension _XClauseLocalIndex on Clause {
  bool get isLocalEqualityIndexable => operator.isLocalIndexEquality
      ? operator.usesListQueryValue
            ? _LocalIndexedFieldValue.forQueryValue(value).isNotEmpty
            : _LocalIndexedFieldValue.tryCreate(value) != null
      : false;

  bool get isLocalRangeIndexable {
    if (!operator.isLocalIndexRange) return false;

    _LocalIndexedFieldValue? indexedValue = _LocalIndexedFieldValue.tryCreate(
      value,
    );
    return indexedValue?.supportsRange ?? false;
  }
}

extension _XClauseOperatorLocalIndex on ClauseOperator {
  bool get isLocalIndexEquality =>
      this == ClauseOperator.equal ||
      this == ClauseOperator.isIn ||
      this == ClauseOperator.arrayContains ||
      this == ClauseOperator.arrayContainsAny;

  bool get isLocalIndexRange =>
      this == ClauseOperator.lessThan ||
      this == ClauseOperator.lessThanOrEqual ||
      this == ClauseOperator.greaterThan ||
      this == ClauseOperator.greaterThanOrEqual;

  bool get usesListQueryValue =>
      this == ClauseOperator.isIn || this == ClauseOperator.arrayContainsAny;

  String get rangeSqlOperator => switch (this) {
    ClauseOperator.lessThan => '<',
    ClauseOperator.lessThanOrEqual => '<=',
    ClauseOperator.greaterThan => '>',
    ClauseOperator.greaterThanOrEqual => '>=',
    _ => throw StateError('Not a local range index operator: $this'),
  };
}
