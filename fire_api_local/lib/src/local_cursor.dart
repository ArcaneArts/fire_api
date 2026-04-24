part of 'fire_api_local_base.dart';

extension _LocalDatabaseCursors on LocalFirestoreDatabase {
  int _compareDocuments(
    CollectionReference reference,
    _LocalStoredDocument a,
    _LocalStoredDocument b,
  ) {
    int fieldComparison = reference.qOrderBy == null
        ? 0
        : _LocalValueComparator.compare(
            a.data.valueAtPath(reference.qOrderBy!),
            b.data.valueAtPath(reference.qOrderBy!),
          );
    int directedComparison = reference.descending
        ? -fieldComparison
        : fieldComparison;
    return directedComparison == 0
        ? a.documentId.compareTo(b.documentId)
        : directedComparison;
  }

  List<_LocalStoredDocument> _applyDocumentCursors(
    CollectionReference reference,
    List<_LocalStoredDocument> documents,
  ) {
    List<_LocalStoredDocument> current = documents;
    current = _applyStartDocumentCursor(
      current,
      reference.qStartAt,
      includeCursor: true,
    );
    current = _applyStartDocumentCursor(
      current,
      reference.qStartAfter,
      includeCursor: false,
    );
    current = _applyEndDocumentCursor(
      current,
      reference.qEndAt,
      includeCursor: true,
    );
    return _applyEndDocumentCursor(
      current,
      reference.qEndBefore,
      includeCursor: false,
    );
  }

  List<_LocalStoredDocument> _applyStartDocumentCursor(
    List<_LocalStoredDocument> documents,
    DocumentSnapshot? cursor, {
    required bool includeCursor,
  }) {
    if (cursor == null) return documents;

    int index = documents.indexWhere(
      (document) => document.path == _storagePath(cursor.reference.path),
    );
    if (index < 0) return documents;

    return documents.skip(includeCursor ? index : index + 1).toList();
  }

  List<_LocalStoredDocument> _applyEndDocumentCursor(
    List<_LocalStoredDocument> documents,
    DocumentSnapshot? cursor, {
    required bool includeCursor,
  }) {
    if (cursor == null) return documents;

    int index = documents.indexWhere(
      (document) => document.path == _storagePath(cursor.reference.path),
    );
    if (index < 0) return documents;

    return documents.take(includeCursor ? index + 1 : index).toList();
  }

  List<_LocalStoredDocument> _applyValueCursors(
    CollectionReference reference,
    List<_LocalStoredDocument> documents,
  ) {
    List<_LocalStoredDocument> current = documents;
    current = _applyStartValueCursor(
      reference,
      current,
      reference.qStartAtValues,
      includeCursor: true,
    );
    current = _applyStartValueCursor(
      reference,
      current,
      reference.qStartAfterValues,
      includeCursor: false,
    );
    current = _applyEndValueCursor(
      reference,
      current,
      reference.qEndAtValues,
      includeCursor: true,
    );
    return _applyEndValueCursor(
      reference,
      current,
      reference.qEndBeforeValues,
      includeCursor: false,
    );
  }

  List<_LocalStoredDocument> _applyStartValueCursor(
    CollectionReference reference,
    List<_LocalStoredDocument> documents,
    Iterable<Object?>? values, {
    required bool includeCursor,
  }) {
    if (values == null) return documents;

    return documents
        .where(
          (document) =>
              _cursorComparison(reference, document, values) >
              (includeCursor ? -1 : 0),
        )
        .toList();
  }

  List<_LocalStoredDocument> _applyEndValueCursor(
    CollectionReference reference,
    List<_LocalStoredDocument> documents,
    Iterable<Object?>? values, {
    required bool includeCursor,
  }) {
    if (values == null) return documents;

    return documents
        .where(
          (document) =>
              _cursorComparison(reference, document, values) <
              (includeCursor ? 1 : 0),
        )
        .toList();
  }

  int _cursorComparison(
    CollectionReference reference,
    _LocalStoredDocument document,
    Iterable<Object?> values,
  ) {
    List<Object?> cursorValues = values.toList();
    if (reference.qOrderBy == null) {
      return _LocalValueComparator.compareLists(<Object?>[
        document.documentId,
      ], cursorValues);
    }

    int fieldComparison = _LocalValueComparator.compare(
      document.data.valueAtPath(reference.qOrderBy!),
      cursorValues.isEmpty ? null : cursorValues.first,
    );
    int directedFieldComparison = reference.descending
        ? -fieldComparison
        : fieldComparison;
    if (directedFieldComparison != 0 || cursorValues.length < 2) {
      return directedFieldComparison;
    }

    return _LocalValueComparator.compare(document.documentId, cursorValues[1]);
  }
}
