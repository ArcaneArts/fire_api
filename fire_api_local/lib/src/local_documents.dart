part of 'fire_api_local_base.dart';

class _LocalStoredDocument {
  final String path;
  final String collectionPath;
  final String documentId;
  final DocumentData data;
  final int updateTime;

  const _LocalStoredDocument({
    required this.path,
    required this.collectionPath,
    required this.documentId,
    required this.data,
    required this.updateTime,
  });

  factory _LocalStoredDocument.fromRow(
    sql.Row row, {
    required FirestoreDatabase db,
  }) => _LocalStoredDocument(
    path: row['path'] as String,
    collectionPath: row['collection_path'] as String,
    documentId: row['document_id'] as String,
    data: _LocalDocumentCodec.decode(row['data_json'] as String, db: db),
    updateTime: row['update_time'] as int,
  );

  DocumentSnapshot toSnapshot({
    required CollectionReference reference,
    DocumentChangeType? changeType,
  }) => DocumentSnapshot(
    reference.doc(documentId),
    _LocalDocumentCodec.clone(data, db: reference.db),
    metadata: _LocalDocumentMetadata(
      path: path,
      collectionPath: collectionPath,
      documentId: documentId,
      updateTime: updateTime,
    ),
    changeType: changeType,
  );
}

class _LocalDocumentMetadata {
  final String path;
  final String collectionPath;
  final String documentId;
  final int updateTime;

  const _LocalDocumentMetadata({
    required this.path,
    required this.collectionPath,
    required this.documentId,
    required this.updateTime,
  });

  factory _LocalDocumentMetadata.fromRow(sql.Row row) => _LocalDocumentMetadata(
    path: row['path'] as String,
    collectionPath: row['collection_path'] as String,
    documentId: row['document_id'] as String,
    updateTime: row['update_time'] as int,
  );
}

class _LocalCollectionStreamBinding {
  final CollectionReference reference;
  final StreamController<List<DocumentSnapshot>> controller;
  final Map<String, _LocalStoredDocument> previousDocuments =
      <String, _LocalStoredDocument>{};
  bool hasEmitted = false;

  _LocalCollectionStreamBinding({
    required this.reference,
    required this.controller,
  });

  DocumentChangeType? changeTypeFor(_LocalStoredDocument document) {
    _LocalStoredDocument? previousDocument = previousDocuments[document.path];
    if (previousDocument == null) return DocumentChangeType.added;
    return previousDocument.updateTime == document.updateTime
        ? null
        : DocumentChangeType.modified;
  }

  List<_LocalStoredDocument> removedDocuments(
    List<_LocalStoredDocument> documents,
  ) {
    Set<String> currentPaths = documents
        .map((_LocalStoredDocument document) => document.path)
        .toSet();
    return previousDocuments.values
        .where(
          (_LocalStoredDocument document) =>
              !currentPaths.contains(document.path),
        )
        .toList();
  }

  void remember(List<_LocalStoredDocument> documents) {
    previousDocuments
      ..clear()
      ..addEntries(
        documents.map((document) => MapEntry(document.path, document)),
      );
  }
}
