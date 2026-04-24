part of 'fire_api_local_base.dart';

class _LocalAggregationFilter {
  final String table;
  final String whereSql;
  final List<Object?> parameters;

  const _LocalAggregationFilter({
    required this.table,
    required this.whereSql,
    required this.parameters,
  });
}

extension _LocalDatabaseAggregation on LocalFirestoreDatabase {
  int _countDocuments(CollectionReference reference) {
    _ensureOpen();
    _validateQuery(reference);
    int? indexedCount = _countIndexedDocuments(reference);
    return indexedCount ?? _queryStoredDocuments(reference).length;
  }

  double _sumDocuments(CollectionReference reference, String field) {
    _ensureOpen();
    _validateQuery(reference);
    double? indexedSum = _sumIndexedDocuments(reference, field);
    if (indexedSum != null) return indexedSum;

    return _queryStoredDocuments(reference).fold<double>(0.0, (
      double sum,
      _LocalStoredDocument document,
    ) {
      dynamic value = document.data.valueAtPath(field);
      return value is num ? sum + value.toDouble() : sum;
    });
  }

  int? _countIndexedDocuments(CollectionReference reference) {
    if (!_canUseDirectAggregation(reference)) return null;
    List<_LocalAggregationFilter>? filters = _aggregationFiltersForReference(
      reference,
    );
    if (filters == null) return null;

    List<Object?> parameters = <Object?>[_collectionStoragePath(reference)];
    String whereSql = 'documents.collection_path = ?';
    for (int i = 0; i < filters.length; i++) {
      _LocalAggregationFilter filter = filters[i];
      whereSql =
          '$whereSql AND EXISTS ('
          'SELECT 1 FROM ${filter.table} AS filter_$i '
          'WHERE filter_$i.document_path = documents.path '
          'AND (${filter.whereSql})'
          ')';
      parameters.addAll(filter.parameters);
    }

    sql.ResultSet rows = _database.select(
      'SELECT COUNT(*) AS total FROM documents AS documents WHERE $whereSql',
      parameters,
    );
    return _intFromSql(rows.first['total']);
  }

  double? _sumIndexedDocuments(CollectionReference reference, String field) {
    if (!_canUseDirectAggregation(reference)) return null;
    List<_LocalAggregationFilter>? filters = _aggregationFiltersForReference(
      reference,
    );
    if (filters == null) return null;

    List<Object?> parameters = <Object?>[
      _collectionStoragePath(reference),
      field,
      'number',
    ];
    String whereSql =
        'sum_fields.collection_path = ? '
        'AND sum_fields.field_path = ? '
        'AND sum_fields.value_type = ?';
    for (int i = 0; i < filters.length; i++) {
      _LocalAggregationFilter filter = filters[i];
      whereSql =
          '$whereSql AND EXISTS ('
          'SELECT 1 FROM ${filter.table} AS filter_$i '
          'WHERE filter_$i.document_path = sum_fields.document_path '
          'AND (${filter.whereSql})'
          ')';
      parameters.addAll(filter.parameters);
    }

    sql.ResultSet rows = _database.select(
      'SELECT COALESCE(SUM(sum_fields.value_number), 0.0) AS total '
      'FROM document_scalar_fields AS sum_fields '
      'WHERE $whereSql',
      parameters,
    );
    return _doubleFromSql(rows.first['total']);
  }

  bool _canUseDirectAggregation(CollectionReference reference) =>
      reference.qOrderBy == null &&
      reference.qLimit == null &&
      reference.qStartAt == null &&
      reference.qStartAfter == null &&
      reference.qEndAt == null &&
      reference.qEndBefore == null &&
      reference.qStartAtValues == null &&
      reference.qStartAfterValues == null &&
      reference.qEndAtValues == null &&
      reference.qEndBeforeValues == null;

  List<_LocalAggregationFilter>? _aggregationFiltersForReference(
    CollectionReference reference,
  ) {
    List<_LocalAggregationFilter> filters = <_LocalAggregationFilter>[];
    for (int i = 0; i < reference.clauses.length; i++) {
      _LocalAggregationFilter? filter = _aggregationFilterForClause(
        reference,
        reference.clauses[i],
        alias: 'filter_$i',
      );
      if (filter == null) return null;

      filters.add(filter);
    }
    if (filters.length > 1) {
      debugCompositeIndexPlans++;
    }

    return filters;
  }

  _LocalAggregationFilter? _aggregationFilterForClause(
    CollectionReference reference,
    Clause clause, {
    required String alias,
  }) {
    if (clause.operator.isLocalIndexRange) {
      return _rangeAggregationFilter(reference, clause, alias: alias);
    }

    if (!clause.operator.isLocalIndexEquality) return null;

    List<_LocalIndexedFieldValue> values =
        _LocalIndexedFieldValue.forQueryValue(clause.value);
    if (values.isEmpty) return null;

    String table =
        clause.operator == ClauseOperator.arrayContains ||
            clause.operator == ClauseOperator.arrayContainsAny
        ? 'document_array_fields'
        : 'document_scalar_fields';
    List<String> parts = <String>[];
    List<Object?> parameters = <Object?>[];
    for (_LocalIndexedFieldValue value in values) {
      parts.add(
        '$alias.collection_path = ? AND $alias.field_path = ? AND '
        '$alias.value_type = ? AND $alias.value_text IS ? AND '
        '$alias.value_number IS ? AND $alias.value_bool IS ?',
      );
      parameters.addAll(<Object?>[
        _collectionStoragePath(reference),
        clause.field,
        value.valueType,
        value.valueText,
        value.valueNumber,
        value.valueBool,
      ]);
    }

    return _LocalAggregationFilter(
      table: table,
      whereSql: parts.map((String part) => '($part)').join(' OR '),
      parameters: parameters,
    );
  }

  _LocalAggregationFilter? _rangeAggregationFilter(
    CollectionReference reference,
    Clause clause, {
    required String alias,
  }) {
    _LocalIndexedFieldValue? value = _LocalIndexedFieldValue.tryCreate(
      clause.value,
    );
    if (value == null || !value.supportsRange) return null;

    return _LocalAggregationFilter(
      table: 'document_scalar_fields',
      whereSql:
          '$alias.collection_path = ? AND $alias.field_path = ? AND '
          '$alias.value_type = ? AND '
          '$alias.${value.rangeColumn} ${clause.operator.rangeSqlOperator} ?',
      parameters: <Object?>[
        _collectionStoragePath(reference),
        clause.field,
        value.valueType,
        value.rangeValue,
      ],
    );
  }

  int _intFromSql(Object? value) => value is int
      ? value
      : value is num
      ? value.toInt()
      : 0;

  double _doubleFromSql(Object? value) => value is num ? value.toDouble() : 0.0;
}
