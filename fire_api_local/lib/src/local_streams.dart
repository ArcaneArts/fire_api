part of 'fire_api_local_base.dart';

extension _LocalDatabaseStreams on LocalFirestoreDatabase {
  void _removeDocumentController(
    String path,
    StreamController<DocumentSnapshot> controller,
  ) {
    Set<StreamController<DocumentSnapshot>>? controllers =
        _documentControllers[path];
    controllers?.remove(controller);
    if (controllers?.isEmpty ?? false) {
      _documentControllers.remove(path);
    }
  }

  void _notifyDocument(DocumentReference ref) {
    Set<StreamController<DocumentSnapshot>> controllers =
        _documentControllers[ref.path] ??
        <StreamController<DocumentSnapshot>>{};
    if (controllers.isEmpty) return;

    DocumentSnapshot snapshot = _snapshotFor(ref);
    for (StreamController<DocumentSnapshot> controller
        in controllers.toList()) {
      if (!controller.isClosed) {
        controller.add(snapshot);
      }
    }
  }

  void _notifyCollections() {
    for (_LocalCollectionStreamBinding binding
        in _collectionControllers.toList()) {
      if (!binding.controller.isClosed) {
        _emitCollectionBinding(binding);
      }
    }
  }

  void _emitCollectionBinding(_LocalCollectionStreamBinding binding) {
    List<_LocalStoredDocument> documents = _queryStoredDocuments(
      binding.reference,
    );
    List<_LocalStoredDocument> removedDocuments = binding.removedDocuments(
      documents,
    );
    bool hasChanges =
        removedDocuments.isNotEmpty ||
        documents.any(
          (_LocalStoredDocument document) =>
              binding.changeTypeFor(document) != null,
        );
    if (binding.hasEmitted && !hasChanges) return;

    List<DocumentSnapshot> snapshots = documents
        .map(
          (document) => document.toSnapshot(
            reference: binding.reference,
            changeType: binding.changeTypeFor(document),
          ),
        )
        .toList();
    snapshots.addAll(
      removedDocuments.map(
        (_LocalStoredDocument document) => document.toSnapshot(
          reference: binding.reference,
          changeType: DocumentChangeType.removed,
        ),
      ),
    );
    binding.remember(documents);
    binding.hasEmitted = true;
    binding.controller.add(snapshots);
  }
}
