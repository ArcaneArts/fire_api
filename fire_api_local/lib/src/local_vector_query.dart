part of 'fire_api_local_base.dart';

extension _LocalDatabaseVectorQuery on LocalFirestoreDatabase {
  void _replaceVectorFields({
    required String path,
    required String collectionPath,
    required String documentId,
    required DocumentData data,
  }) {
    _database.execute(
      'DELETE FROM document_vectors WHERE document_path = ?',
      <Object?>[path],
    );
    for (_LocalVectorEntry entry in _LocalVectorEntry.flatten(data)) {
      List<double> vector = entry.vector.toArray();
      _database.execute(
        'INSERT OR REPLACE INTO document_vectors '
        '(collection_path, field_path, dimension, magnitude, vector_json, '
        'document_path, document_id) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          collectionPath,
          entry.fieldPath,
          vector.length,
          _LocalVectorMath.magnitude(vector),
          convert.jsonEncode(vector),
          path,
          documentId,
        ],
      );
    }
  }

  List<_LocalVectorCandidate> _queryVectorDocuments(
    VectorQueryReference reference,
  ) {
    Map<String, _LocalStoredDocument> documentsByPath =
        <String, _LocalStoredDocument>{
          for (_LocalStoredDocument document in _queryStoredDocuments(
            reference.reference,
          ))
            document.path: document,
        };
    List<_LocalVectorCandidate> candidates = <_LocalVectorCandidate>[];
    for (_LocalStoredVector vector in _loadStoredVectors(
      reference,
      allowedPaths: documentsByPath.keys.toSet(),
    )) {
      _LocalStoredDocument? document = documentsByPath[vector.documentPath];
      if (document == null) continue;

      _LocalVectorCandidate? candidate = _LocalVectorCandidate.tryCreate(
        reference: reference,
        document: document,
        vector: vector.vector,
      );
      if (candidate != null) {
        candidates.add(candidate);
      }
    }
    candidates = candidates
        .where(
          (candidate) =>
              reference.distanceThreshold == null ||
              _LocalVectorMath.passesThreshold(
                reference.distanceMeasure,
                candidate.score,
                reference.distanceThreshold!,
              ),
        )
        .toList();
    candidates.sort(
      (a, b) => _LocalVectorMath.compareCandidates(
        reference.distanceMeasure,
        a.score,
        b.score,
      ),
    );
    return candidates.take(reference.limit).toList();
  }

  List<_LocalStoredVector> _loadStoredVectors(
    VectorQueryReference reference, {
    required Set<String> allowedPaths,
  }) {
    if (allowedPaths.isEmpty) return const <_LocalStoredVector>[];
    if (allowedPaths.length > 900) {
      sql.ResultSet rows = _database.select(
        'SELECT document_path, document_id, vector_json '
        'FROM document_vectors '
        'WHERE collection_path = ? AND field_path = ? AND dimension = ?',
        <Object?>[
          _collectionStoragePath(reference.reference),
          reference.vectorField,
          reference.queryVector.toArray().length,
        ],
      );
      return rows
          .map(_LocalStoredVector.fromRow)
          .where((vector) => allowedPaths.contains(vector.documentPath))
          .toList();
    }

    String placeholders = List<String>.filled(
      allowedPaths.length,
      '?',
    ).join(', ');
    sql.ResultSet rows = _database.select(
      'SELECT document_path, document_id, vector_json '
      'FROM document_vectors '
      'WHERE collection_path = ? AND field_path = ? AND dimension = ? '
      'AND document_path IN ($placeholders)',
      <Object?>[
        _collectionStoragePath(reference.reference),
        reference.vectorField,
        reference.queryVector.toArray().length,
        ...allowedPaths,
      ],
    );
    return rows.map(_LocalStoredVector.fromRow).toList();
  }
}
