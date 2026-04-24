part of 'fire_api_local_base.dart';

class _LocalVectorCandidate {
  final DocumentSnapshot snapshot;
  final double score;

  const _LocalVectorCandidate({required this.snapshot, required this.score});

  static _LocalVectorCandidate? tryCreate({
    required VectorQueryReference reference,
    required _LocalStoredDocument document,
    VectorValue? vector,
  }) {
    VectorValue? effectiveVector =
        vector ??
        _LocalVectorMath.tryVector(
          document.data.valueAtPath(reference.vectorField),
        );
    if (effectiveVector == null) return null;

    double? score = _LocalVectorMath.distance(
      reference.distanceMeasure,
      reference.queryVector.toArray(),
      effectiveVector.toArray(),
    );
    if (score == null) return null;

    DocumentData data = _LocalDocumentCodec.clone(
      document.data,
      db: reference.db,
    )..[reference.resolvedDistanceResultField] = score;
    return _LocalVectorCandidate(
      snapshot: DocumentSnapshot(
        reference.reference.doc(document.documentId),
        data,
        metadata: _LocalDocumentMetadata(
          path: document.path,
          collectionPath: document.collectionPath,
          documentId: document.documentId,
          updateTime: document.updateTime,
        ),
      ),
      score: score,
    );
  }
}

class _LocalVectorEntry {
  final String fieldPath;
  final VectorValue vector;

  const _LocalVectorEntry({required this.fieldPath, required this.vector});

  static List<_LocalVectorEntry> flatten(DocumentData data) => [
    for (MapEntry<String, dynamic> entry in data.entries)
      ..._flattenValue(entry.key, entry.value),
  ];

  static List<_LocalVectorEntry> _flattenValue(
    String fieldPath,
    dynamic value,
  ) {
    dynamic normalized = convertSerializedVectorValuesToRuntime(value);
    if (normalized is VectorValue) {
      return <_LocalVectorEntry>[
        _LocalVectorEntry(fieldPath: fieldPath, vector: normalized),
      ];
    }

    if (normalized is Map) {
      return <_LocalVectorEntry>[
        for (MapEntry<dynamic, dynamic> entry in normalized.entries)
          ..._flattenValue('$fieldPath.${entry.key}', entry.value),
      ];
    }

    return const <_LocalVectorEntry>[];
  }
}

class _LocalStoredVector {
  final String documentPath;
  final String documentId;
  final VectorValue vector;

  const _LocalStoredVector({
    required this.documentPath,
    required this.documentId,
    required this.vector,
  });

  factory _LocalStoredVector.fromRow(sql.Row row) => _LocalStoredVector(
    documentPath: row['document_path'] as String,
    documentId: row['document_id'] as String,
    vector: VectorValue(
      vector: normalizeVectorNumbers(
        convert.jsonDecode(row['vector_json'] as String),
      ),
    ),
  );
}

class _LocalVectorMath {
  const _LocalVectorMath._();

  static VectorValue? tryVector(dynamic value) {
    dynamic normalized = convertSerializedVectorValuesToRuntime(value);
    return normalized is VectorValue ? normalized : null;
  }

  static double? distance(
    VectorDistanceMeasure measure,
    List<double> query,
    List<double> value,
  ) {
    if (query.length != value.length || query.isEmpty) return null;

    return switch (measure) {
      VectorDistanceMeasure.euclidean => _euclidean(query, value),
      VectorDistanceMeasure.cosine => _cosineDistance(query, value),
      VectorDistanceMeasure.dotProduct => _dotProduct(query, value),
    };
  }

  static bool passesThreshold(
    VectorDistanceMeasure measure,
    double score,
    double threshold,
  ) => measure == VectorDistanceMeasure.dotProduct
      ? score >= threshold
      : score <= threshold;

  static int compareCandidates(
    VectorDistanceMeasure measure,
    double a,
    double b,
  ) => measure == VectorDistanceMeasure.dotProduct
      ? b.compareTo(a)
      : a.compareTo(b);

  static double _euclidean(List<double> a, List<double> b) {
    double sum = 0;
    for (int i = 0; i < a.length; i++) {
      double delta = a[i] - b[i];
      sum += delta * delta;
    }
    return math.sqrt(sum);
  }

  static double _cosineDistance(List<double> a, List<double> b) {
    double dot = 0;
    double aMagnitude = 0;
    double bMagnitude = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      aMagnitude += a[i] * a[i];
      bMagnitude += b[i] * b[i];
    }

    if (aMagnitude == 0 || bMagnitude == 0) {
      return double.infinity;
    }

    return 1 - (dot / (math.sqrt(aMagnitude) * math.sqrt(bMagnitude)));
  }

  static double _dotProduct(List<double> a, List<double> b) {
    double score = 0;
    for (int i = 0; i < a.length; i++) {
      score += a[i] * b[i];
    }
    return score;
  }

  static double magnitude(List<double> vector) {
    double sum = 0;
    for (double value in vector) {
      sum += value * value;
    }
    return math.sqrt(sum);
  }
}
