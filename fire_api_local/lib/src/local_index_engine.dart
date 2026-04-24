part of 'fire_api_local_base.dart';

extension _LocalDatabaseIndexEngine on LocalFirestoreDatabase {
  List<_LocalStoredDocument> _loadCompositeIndexedDocuments(
    CollectionReference reference,
    List<Clause> clauses,
  ) {
    debugCompositeIndexPlans++;
    List<List<String>> documentPathGroups = <List<String>>[];
    for (Clause clause in clauses) {
      List<String>? documentPaths = _loadIndexedDocumentPaths(
        reference,
        clause,
      );
      if (documentPaths == null) {
        return _loadIndexedDocuments(reference, reference.bestIndexableClause!);
      }

      documentPathGroups.add(documentPaths);
    }

    documentPathGroups.sort(
      (List<String> a, List<String> b) => a.length.compareTo(b.length),
    );
    Set<String> intersection = documentPathGroups.first.toSet();
    for (List<String> documentPaths in documentPathGroups.skip(1)) {
      intersection = intersection.intersection(documentPaths.toSet());
      if (intersection.isEmpty) break;
    }

    List<String> documentPaths = intersection.toList()..sort();
    return documentPaths
        .map(_loadStoredDocumentByStoragePath)
        .whereType<_LocalStoredDocument>()
        .toList();
  }

  List<_LocalStoredDocument> _loadIndexedDocuments(
    CollectionReference reference,
    Clause clause,
  ) {
    List<String>? documentPaths = _loadIndexedDocumentPaths(reference, clause);
    if (documentPaths == null) return _loadCollectionDocuments(reference);

    return documentPaths
        .map(_loadStoredDocumentByStoragePath)
        .whereType<_LocalStoredDocument>()
        .toList();
  }

  List<String>? _loadIndexedDocumentPaths(
    CollectionReference reference,
    Clause clause,
  ) {
    if (clause.operator.isLocalIndexRange) {
      return _loadRangeIndexedDocumentPaths(reference, clause);
    }

    return _loadEqualityIndexedDocumentPaths(reference, clause);
  }

  List<String>? _loadEqualityIndexedDocumentPaths(
    CollectionReference reference,
    Clause clause,
  ) {
    List<_LocalIndexedFieldValue> values =
        _LocalIndexedFieldValue.forQueryValue(clause.value);
    if (values.isEmpty) return null;
    String table =
        clause.operator == ClauseOperator.arrayContains ||
            clause.operator == ClauseOperator.arrayContainsAny
        ? 'document_array_fields'
        : 'document_scalar_fields';

    List<Object?> parameters = <Object?>[
      _collectionStoragePath(reference),
      clause.field,
      values.first.valueType,
      values.first.valueText,
      values.first.valueNumber,
      values.first.valueBool,
    ];
    String where =
        'collection_path = ? AND field_path = ? AND '
        'value_type = ? AND value_text IS ? AND value_number IS ? AND '
        'value_bool IS ?';
    for (_LocalIndexedFieldValue value in values.skip(1)) {
      where =
          '$where OR collection_path = ? AND field_path = ? AND '
          'value_type = ? AND value_text IS ? AND value_number IS ? AND '
          'value_bool IS ?';
      parameters.addAll(<Object?>[
        _collectionStoragePath(reference),
        clause.field,
        value.valueType,
        value.valueText,
        value.valueNumber,
        value.valueBool,
      ]);
    }

    sql.ResultSet rows = _database.select(
      'SELECT DISTINCT document_path FROM $table WHERE $where',
      parameters,
    );
    List<String> documentPaths =
        rows.map((row) => row['document_path'] as String).toList()..sort();
    debugIndexCandidateReads += documentPaths.length;
    return documentPaths;
  }

  List<String>? _loadRangeIndexedDocumentPaths(
    CollectionReference reference,
    Clause clause,
  ) {
    _LocalIndexedFieldValue? value = _LocalIndexedFieldValue.tryCreate(
      clause.value,
    );
    if (value == null || !value.supportsRange) {
      return null;
    }

    sql.ResultSet rows = _database.select(
      'SELECT DISTINCT document_path FROM document_scalar_fields '
      'WHERE collection_path = ? AND field_path = ? AND value_type = ? '
      'AND ${value.rangeColumn} ${clause.operator.rangeSqlOperator} ?',
      <Object?>[
        _collectionStoragePath(reference),
        clause.field,
        value.valueType,
        value.rangeValue,
      ],
    );
    List<String> documentPaths =
        rows.map((row) => row['document_path'] as String).toList()..sort();
    debugIndexCandidateReads += documentPaths.length;
    return documentPaths;
  }

  List<_LocalStoredDocument> _loadOrderIndexedDocuments(
    CollectionReference reference,
  ) {
    String direction = reference.descending ? 'DESC' : 'ASC';
    sql.ResultSet rows = _database.select(
      'SELECT document_path FROM document_scalar_fields '
      'WHERE collection_path = ? AND field_path = ? '
      'ORDER BY CASE value_type '
      'WHEN "null" THEN 0 '
      'WHEN "bool" THEN 1 '
      'WHEN "number" THEN 2 '
      'WHEN "string" THEN 3 '
      'ELSE 99 END $direction, '
      'value_bool $direction, value_number $direction, '
      'value_text $direction, document_id $direction',
      <Object?>[_collectionStoragePath(reference), reference.qOrderBy],
    );
    Set<String> seen = <String>{};
    List<String> documentPaths = <String>[
      for (sql.Row row in rows)
        if (seen.add(row['document_path'] as String))
          row['document_path'] as String,
    ];
    debugIndexCandidateReads += documentPaths.length;
    return documentPaths
        .map(_loadStoredDocumentByStoragePath)
        .whereType<_LocalStoredDocument>()
        .toList();
  }

  _LocalStoredDocument? _loadStoredDocumentByStoragePath(String path) {
    sql.ResultSet rows = _database.select(
      'SELECT path, collection_path, document_id, data_json, update_time '
      'FROM documents WHERE path = ?',
      <Object?>[path],
    );
    return rows.isEmpty
        ? null
        : _LocalStoredDocument.fromRow(rows.first, db: this);
  }

  void _replaceIndexedFields({
    required String path,
    required String collectionPath,
    required String documentId,
    required DocumentData data,
  }) {
    _database.execute(
      'DELETE FROM document_fields WHERE document_path = ?',
      <Object?>[path],
    );
    _database.execute(
      'DELETE FROM document_scalar_fields WHERE document_path = ?',
      <Object?>[path],
    );
    _database.execute(
      'DELETE FROM document_array_fields WHERE document_path = ?',
      <Object?>[path],
    );
    for (_LocalIndexedFieldEntry entry in _LocalIndexedFieldEntry.flatten(
      data,
    )) {
      _insertIndexedFieldEntry(
        table: 'document_fields',
        path: path,
        collectionPath: collectionPath,
        documentId: documentId,
        entry: entry,
      );
      _insertIndexedFieldEntry(
        table: entry.arrayElement
            ? 'document_array_fields'
            : 'document_scalar_fields',
        path: path,
        collectionPath: collectionPath,
        documentId: documentId,
        entry: entry,
      );
    }
  }

  void _insertIndexedFieldEntry({
    required String table,
    required String path,
    required String collectionPath,
    required String documentId,
    required _LocalIndexedFieldEntry entry,
  }) {
    _database.execute(
      'INSERT OR IGNORE INTO $table '
      '(collection_path, field_path, value_type, value_text, value_number, '
      'value_bool, document_path, document_id) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        collectionPath,
        entry.fieldPath,
        entry.value.valueType,
        entry.value.valueText,
        entry.value.valueNumber,
        entry.value.valueBool,
        path,
        documentId,
      ],
    );
  }
}
