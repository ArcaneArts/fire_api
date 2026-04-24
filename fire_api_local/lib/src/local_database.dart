part of 'fire_api_local_base.dart';

class LocalFirestoreDatabase extends FirestoreDatabase {
  final sql.Database _database;
  final Map<String, Set<StreamController<DocumentSnapshot>>>
  _documentControllers = <String, Set<StreamController<DocumentSnapshot>>>{};
  final Set<_LocalCollectionStreamBinding> _collectionControllers =
      <_LocalCollectionStreamBinding>{};
  int debugIndexCandidateReads = 0;
  int debugCollectionScans = 0;
  int debugCompositeIndexPlans = 0;
  int _version = 0;
  int _lastSeenChangeVersion = 0;
  Timer? _changePoller;
  bool _closed = false;

  LocalFirestoreDatabase._({
    required sql.Database database,
    Duration? changePollingInterval,
    super.rootPrefix = '',
  }) : _database = database,
       super() {
    _migrate();
    _loadVersion();
    _lastSeenChangeVersion = _version;
    if (changePollingInterval != null) {
      _changePoller = Timer.periodic(
        changePollingInterval,
        (_) => _pollExternalChanges(),
      );
    }
  }

  factory LocalFirestoreDatabase.memory({String rootPrefix = ''}) =>
      LocalFirestoreDatabase._(
        database: sql.sqlite3.openInMemory(),
        rootPrefix: rootPrefix,
      );

  factory LocalFirestoreDatabase.open(
    String path, {
    String rootPrefix = '',
    Duration? changePollingInterval = const Duration(milliseconds: 250),
  }) => LocalFirestoreDatabase._(
    database: sql.sqlite3.open(path),
    changePollingInterval: changePollingInterval,
    rootPrefix: rootPrefix,
  );

  @override
  Future<int> countDocumentsInCollection(CollectionReference reference) =>
      Future<int>.value(_countDocuments(reference));

  @override
  Future<void> deleteDocument(DocumentReference path) {
    _ensureOpen();
    DocumentData? previousData = _readDocumentData(path);
    bool existed = previousData != null;
    String storagePath = _storagePath(path.path);
    int? version = existed ? _nextVersion() : null;
    String collectionPath = _collectionPathForDocumentPath(storagePath);
    _database.execute('DELETE FROM documents WHERE path = ?', <Object?>[
      storagePath,
    ]);
    _database.execute(
      'DELETE FROM document_fields WHERE document_path = ?',
      <Object?>[storagePath],
    );
    _database.execute(
      'DELETE FROM document_scalar_fields WHERE document_path = ?',
      <Object?>[storagePath],
    );
    _database.execute(
      'DELETE FROM document_array_fields WHERE document_path = ?',
      <Object?>[storagePath],
    );
    _database.execute(
      'DELETE FROM document_vectors WHERE document_path = ?',
      <Object?>[storagePath],
    );

    if (existed) {
      _recordDocumentChange(
        path: storagePath,
        collectionPath: collectionPath,
        documentId: path.id,
        version: version!,
        changeType: DocumentChangeType.removed,
        data: previousData,
      );
      _notifyDocument(path);
      _notifyCollections();
    }

    return Future<void>.value();
  }

  @override
  Future<DocumentSnapshot> getDocument(
    DocumentReference ref, {
    bool cached = false,
  }) => Future<DocumentSnapshot>.value(_snapshotFor(ref));

  @override
  Future<DocumentSnapshot> getDocumentCachedOnly(DocumentReference ref) =>
      getDocument(ref, cached: true);

  @override
  Future<List<DocumentSnapshot>> getDocumentsInCollection(
    CollectionReference reference,
  ) => Future<List<DocumentSnapshot>>.value(
    _queryStoredDocuments(
      reference,
    ).map((document) => document.toSnapshot(reference: reference)).toList(),
  );

  @override
  Future<List<DocumentSnapshot>> getNearestDocumentsInCollection(
    VectorQueryReference reference,
  ) => Future<List<DocumentSnapshot>>.value(
    _queryVectorDocuments(
      reference,
    ).map((candidate) => candidate.snapshot).toList(),
  );

  @override
  Future<void> setDocument(DocumentReference ref, DocumentData data) {
    _ensureOpen();
    _upsertDocument(ref, _LocalDocumentPatch.applySet(data, db: this));
    _notifyDocument(ref);
    _notifyCollections();
    return Future<void>.value();
  }

  @override
  Future<void> setDocumentAtomic(
    DocumentReference ref,
    DocumentData Function(DocumentData? data) txn,
  ) {
    _ensureOpen();
    _runTransaction(() {
      _upsertDocument(
        ref,
        _LocalDocumentPatch.applySet(txn(_readDocumentData(ref)), db: this),
      );
    });
    _notifyDocument(ref);
    _notifyCollections();
    return Future<void>.value();
  }

  @override
  Stream<DocumentSnapshot> streamDocument(DocumentReference ref) {
    _ensureOpen();
    late StreamController<DocumentSnapshot> controller;
    controller = StreamController<DocumentSnapshot>.broadcast(
      onListen: () => getDocument(ref).then(controller.add),
      onCancel: () => _removeDocumentController(ref.path, controller),
    );
    _documentControllers
        .putIfAbsent(ref.path, () => <StreamController<DocumentSnapshot>>{})
        .add(controller);
    return controller.stream;
  }

  @override
  Stream<List<DocumentSnapshot>> streamDocumentsInCollection(
    CollectionReference reference,
  ) {
    _ensureOpen();
    late StreamController<List<DocumentSnapshot>> controller;
    late _LocalCollectionStreamBinding binding;
    controller = StreamController<List<DocumentSnapshot>>.broadcast(
      onListen: () => _emitCollectionBinding(binding),
      onCancel: () => _collectionControllers.remove(binding),
    );
    binding = _LocalCollectionStreamBinding(
      reference: reference,
      controller: controller,
    );
    _collectionControllers.add(binding);
    return controller.stream;
  }

  @override
  Future<double> sumDocumentsInCollection(
    CollectionReference reference,
    String field,
  ) => Future<double>.value(_sumDocuments(reference, field));

  @override
  Future<void> updateDocument(DocumentReference ref, DocumentData data) {
    _ensureOpen();
    DocumentData? current = _readDocumentData(ref);
    if (current == null) {
      throw StateError('Cannot update missing local document: ${ref.path}');
    }

    _upsertDocument(
      ref,
      _LocalDocumentPatch.applyUpdate(current, data, db: this),
    );
    _notifyDocument(ref);
    _notifyCollections();
    return Future<void>.value();
  }

  @override
  Future<void> updateDocumentAtomic(
    DocumentReference ref,
    Map<String, dynamic> Function(DocumentData? data) txn,
  ) {
    _ensureOpen();
    _runTransaction(() {
      DocumentData? current = _readDocumentData(ref);
      if (current == null) {
        throw StateError('Cannot update missing local document: ${ref.path}');
      }

      _upsertDocument(
        ref,
        _LocalDocumentPatch.applyUpdate(current, txn(current), db: this),
      );
    });
    _notifyDocument(ref);
    _notifyCollections();
    return Future<void>.value();
  }

  void close() {
    if (_closed) return;

    for (Set<StreamController<DocumentSnapshot>> controllers
        in _documentControllers.values) {
      for (StreamController<DocumentSnapshot> controller in controllers) {
        controller.close();
      }
    }

    for (_LocalCollectionStreamBinding binding in _collectionControllers) {
      binding.controller.close();
    }

    _changePoller?.cancel();
    _documentControllers.clear();
    _collectionControllers.clear();
    _database.dispose();
    _closed = true;
  }
}
