part of 'fire_api_local_base.dart';

extension _LocalDatabaseQueryEngine on LocalFirestoreDatabase {
  List<_LocalStoredDocument> _loadCollectionDocuments(
    CollectionReference reference,
  ) {
    debugCollectionScans++;
    sql.ResultSet rows = _database.select(
      'SELECT path, collection_path, document_id, data_json, update_time '
      'FROM documents WHERE collection_path = ? ORDER BY document_id ASC',
      <Object?>[_collectionStoragePath(reference)],
    );
    return rows
        .map((row) => _LocalStoredDocument.fromRow(row, db: this))
        .toList();
  }

  List<_LocalStoredDocument> _queryStoredDocuments(
    CollectionReference reference,
  ) {
    _ensureOpen();
    _validateQuery(reference);
    List<_LocalStoredDocument> documents = _loadCandidateDocuments(reference)
        .where((document) => _matchesClauses(document.data, reference.clauses))
        .toList();
    documents.sort((a, b) => _compareDocuments(reference, a, b));
    documents = _applyDocumentCursors(reference, documents);
    documents = _applyValueCursors(reference, documents);
    return reference.qLimit == null
        ? documents
        : documents.take(reference.qLimit!).toList();
  }

  bool _matchesClauses(DocumentData data, List<Clause> clauses) =>
      clauses.every((clause) => _LocalQueryMatcher.matches(data, clause));

  List<_LocalStoredDocument> _loadCandidateDocuments(
    CollectionReference reference,
  ) {
    List<Clause> clauses = reference.localIndexableClauses;
    if (clauses.length > 1) {
      return _loadCompositeIndexedDocuments(reference, clauses);
    }

    if (clauses.length == 1) {
      return _loadIndexedDocuments(reference, clauses.single);
    }

    return reference.qOrderBy == null
        ? _loadCollectionDocuments(reference)
        : _loadOrderIndexedDocuments(reference);
  }
}
