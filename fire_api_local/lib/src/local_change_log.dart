part of 'fire_api_local_base.dart';

class _LocalChangeStreamBinding {
  final LocalFirestoreDatabase db;
  final Duration pollInterval;
  final String? collectionPath;
  final String? documentPath;
  int cursor;
  StreamController<LocalDocumentChange>? controller;
  Timer? timer;

  _LocalChangeStreamBinding({
    required this.db,
    required this.cursor,
    required this.pollInterval,
    this.collectionPath,
    this.documentPath,
  });

  void start(StreamController<LocalDocumentChange> streamController) {
    controller = streamController;
    emitChanges();
    timer = Timer.periodic(pollInterval, (_) => emitChanges());
  }

  void emitChanges() {
    StreamController<LocalDocumentChange>? currentController = controller;
    if (currentController == null || currentController.isClosed) return;

    for (LocalDocumentChange change in db.changesSince(
      cursor,
      collectionPath: collectionPath,
      documentPath: documentPath,
    )) {
      cursor = change.version;
      currentController.add(change);
    }
  }

  void cancel() => timer?.cancel();
}

extension LocalFirestoreDatabaseChangeLog on LocalFirestoreDatabase {
  List<LocalDocumentChange> changesSince(
    int version, {
    String? collectionPath,
    String? documentPath,
  }) {
    _ensureOpen();
    List<Object?> parameters = <Object?>[version];
    String where = 'version > ?';
    if (collectionPath != null) {
      where = '$where AND collection_path = ?';
      parameters.add(_storagePath(collectionPath));
    }
    if (documentPath != null) {
      where = '$where AND path = ?';
      parameters.add(_storagePath(documentPath));
    }

    sql.ResultSet rows = _database.select(
      'SELECT version, path, collection_path, document_id, change_type, '
      'data_json, created_at FROM document_changes '
      'WHERE $where ORDER BY version ASC',
      parameters,
    );
    return rows
        .map((row) => LocalDocumentChange.fromRow(row, db: this))
        .toList();
  }

  Stream<LocalDocumentChange> streamChangesSince(
    int version, {
    Duration pollInterval = const Duration(milliseconds: 250),
    String? collectionPath,
    String? documentPath,
  }) {
    _ensureOpen();
    _LocalChangeStreamBinding binding = _LocalChangeStreamBinding(
      db: this,
      cursor: version,
      pollInterval: pollInterval,
      collectionPath: collectionPath,
      documentPath: documentPath,
    );
    late StreamController<LocalDocumentChange> controller;
    controller = StreamController<LocalDocumentChange>(
      onListen: () => binding.start(controller),
      onCancel: binding.cancel,
    );
    return controller.stream;
  }

  void _recordDocumentChange({
    required String path,
    required String collectionPath,
    required String documentId,
    required int version,
    required DocumentChangeType changeType,
    required DocumentData? data,
  }) {
    _database.execute(
      'INSERT INTO document_changes '
      '(version, path, collection_path, document_id, change_type, data_json, '
      'created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        version,
        path,
        collectionPath,
        documentId,
        changeType.name,
        data == null ? null : _LocalDocumentCodec.encode(data),
        DateTime.now().microsecondsSinceEpoch,
      ],
    );
    _lastSeenChangeVersion = math.max(_lastSeenChangeVersion, version);
  }

  void _pollExternalChanges() {
    if (_closed) return;

    List<LocalDocumentChange> changes = changesSince(_lastSeenChangeVersion);
    if (changes.isEmpty) return;

    _lastSeenChangeVersion = changes.last.version;
    Set<String> documentPaths = changes
        .map((change) => change.path)
        .where((path) => rootPrefix.isEmpty || path.startsWith('$rootPrefix/'))
        .toSet();
    for (String path in documentPaths) {
      String visiblePath = rootPrefix.isEmpty
          ? path
          : path.substring(rootPrefix.length + 1);
      _notifyDocument(document(visiblePath));
    }
    _notifyCollections();
  }
}
