part of 'fire_api_local_base.dart';

extension _LocalDatabaseStorage on LocalFirestoreDatabase {
  void _ensureOpen() {
    if (_closed) {
      throw StateError('LocalFirestoreDatabase is already closed.');
    }
  }

  void _migrate() {
    _database.execute('PRAGMA busy_timeout = 5000');
    _database.execute('PRAGMA journal_mode = WAL');
    _database.execute('''
CREATE TABLE IF NOT EXISTS documents (
  path TEXT PRIMARY KEY,
  collection_path TEXT NOT NULL,
  document_id TEXT NOT NULL,
  data_json TEXT NOT NULL,
  update_time INTEGER NOT NULL
)
''');
    _database.execute(
      'CREATE INDEX IF NOT EXISTS documents_collection_idx '
      'ON documents(collection_path, document_id)',
    );
    _database.execute('''
CREATE TABLE IF NOT EXISTS document_changes (
  version INTEGER PRIMARY KEY,
  path TEXT NOT NULL,
  collection_path TEXT NOT NULL,
  document_id TEXT NOT NULL,
  change_type TEXT NOT NULL,
  data_json TEXT,
  created_at INTEGER NOT NULL
)
''');
    _database.execute(
      'CREATE INDEX IF NOT EXISTS document_changes_collection_idx '
      'ON document_changes(collection_path, version)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS document_changes_path_idx '
      'ON document_changes(path, version)',
    );
    _database.execute('''
CREATE TABLE IF NOT EXISTS document_vectors (
  collection_path TEXT NOT NULL,
  field_path TEXT NOT NULL,
  dimension INTEGER NOT NULL,
  magnitude REAL NOT NULL,
  vector_json TEXT NOT NULL,
  document_path TEXT NOT NULL,
  document_id TEXT NOT NULL,
  PRIMARY KEY (collection_path, field_path, document_path)
)
''');
    _database.execute(
      'CREATE INDEX IF NOT EXISTS document_vectors_lookup_idx '
      'ON document_vectors(collection_path, field_path, dimension)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS document_vectors_document_idx '
      'ON document_vectors(document_path)',
    );
    _createFieldIndexTable('document_fields');
    _createFieldIndexTable('document_scalar_fields');
    _createFieldIndexTable('document_array_fields');
    _backfillSeparatedIndexes();
  }

  void _createFieldIndexTable(String table) {
    _database.execute('''
CREATE TABLE IF NOT EXISTS $table (
  collection_path TEXT NOT NULL,
  field_path TEXT NOT NULL,
  value_type TEXT NOT NULL,
  value_text TEXT,
  value_number REAL,
  value_bool INTEGER,
  document_path TEXT NOT NULL,
  document_id TEXT NOT NULL,
  PRIMARY KEY (collection_path, field_path, value_type, value_text, value_number, value_bool, document_path)
)
''');
    _database.execute(
      'CREATE INDEX IF NOT EXISTS ${table}_lookup_idx '
      'ON $table(collection_path, field_path, value_type, '
      'value_text, value_number, value_bool)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS ${table}_document_idx '
      'ON $table(document_path)',
    );
  }

  void _backfillSeparatedIndexes() {
    sql.ResultSet indexRows = _database.select(
      'SELECT '
      '(SELECT COUNT(*) FROM document_scalar_fields) AS scalar_count, '
      '(SELECT COUNT(*) FROM document_array_fields) AS array_count, '
      '(SELECT COUNT(*) FROM document_vectors) AS vector_count',
    );
    int scalarCount = _countFromSql(indexRows.first['scalar_count']);
    int arrayCount = _countFromSql(indexRows.first['array_count']);
    int vectorCount = _countFromSql(indexRows.first['vector_count']);
    bool shouldBackfillFields = scalarCount == 0 && arrayCount == 0;
    bool shouldBackfillVectors = vectorCount == 0;
    if (!shouldBackfillFields && !shouldBackfillVectors) return;

    sql.ResultSet documentRows = _database.select(
      'SELECT path, collection_path, document_id, data_json FROM documents',
    );
    for (sql.Row row in documentRows) {
      DocumentData data = _LocalDocumentCodec.decode(
        row['data_json'] as String,
        db: this,
      );
      if (shouldBackfillFields) {
        _replaceIndexedFields(
          path: row['path'] as String,
          collectionPath: row['collection_path'] as String,
          documentId: row['document_id'] as String,
          data: data,
        );
      }
      if (shouldBackfillVectors) {
        _replaceVectorFields(
          path: row['path'] as String,
          collectionPath: row['collection_path'] as String,
          documentId: row['document_id'] as String,
          data: data,
        );
      }
    }
  }

  int _countFromSql(Object? value) => value is int
      ? value
      : value is num
      ? value.toInt()
      : 0;

  void _loadVersion() {
    sql.ResultSet rows = _database.select(
      'SELECT MAX(version) AS version FROM ('
      'SELECT COALESCE(MAX(update_time), 0) AS version FROM documents '
      'UNION ALL '
      'SELECT COALESCE(MAX(version), 0) AS version FROM document_changes'
      ')',
    );
    Object? value = rows.first['version'];
    _version = value is int ? value : 0;
  }

  int _nextVersion() {
    _version++;
    return _version;
  }

  T _runTransaction<T>(T Function() callback) {
    _database.execute('BEGIN IMMEDIATE');
    try {
      T value = callback();
      _database.execute('COMMIT');
      return value;
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  String _storagePath(String path) => effectivePath(path);

  String _collectionStoragePath(CollectionReference reference) =>
      _storagePath(reference.path);

  String _collectionPathForDocumentPath(String path) {
    List<String> segments = path.split('/');
    return segments.sublist(0, segments.length - 1).join('/');
  }

  DocumentSnapshot _snapshotFor(DocumentReference ref) => DocumentSnapshot(
    ref,
    _readDocumentData(ref),
    metadata: _readDocumentMetadata(ref),
  );

  DocumentData? _readDocumentData(DocumentReference ref) {
    sql.ResultSet rows = _database.select(
      'SELECT data_json FROM documents WHERE path = ?',
      <Object?>[_storagePath(ref.path)],
    );
    if (rows.isEmpty) return null;

    return _LocalDocumentCodec.decode(
      rows.first['data_json'] as String,
      db: this,
    );
  }

  _LocalDocumentMetadata? _readDocumentMetadata(DocumentReference ref) {
    sql.ResultSet rows = _database.select(
      'SELECT path, collection_path, document_id, update_time '
      'FROM documents WHERE path = ?',
      <Object?>[_storagePath(ref.path)],
    );
    if (rows.isEmpty) return null;

    return _LocalDocumentMetadata.fromRow(rows.first);
  }

  void _upsertDocument(DocumentReference ref, DocumentData data) {
    String path = _storagePath(ref.path);
    String collectionPath = _collectionPathForDocumentPath(path);
    bool existed = _readDocumentData(ref) != null;
    int version = _nextVersion();
    _database.execute(
      'INSERT OR REPLACE INTO documents '
      '(path, collection_path, document_id, data_json, update_time) '
      'VALUES (?, ?, ?, ?, ?)',
      <Object?>[
        path,
        collectionPath,
        ref.id,
        _LocalDocumentCodec.encode(data),
        version,
      ],
    );
    _replaceIndexedFields(
      path: path,
      collectionPath: collectionPath,
      documentId: ref.id,
      data: data,
    );
    _replaceVectorFields(
      path: path,
      collectionPath: collectionPath,
      documentId: ref.id,
      data: data,
    );
    _recordDocumentChange(
      path: path,
      collectionPath: collectionPath,
      documentId: ref.id,
      version: version,
      changeType: existed
          ? DocumentChangeType.modified
          : DocumentChangeType.added,
      data: data,
    );
  }
}
