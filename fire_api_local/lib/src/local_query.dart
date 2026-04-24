part of 'fire_api_local_base.dart';

class _LocalQueryMatcher {
  const _LocalQueryMatcher._();

  static bool matches(DocumentData data, Clause clause) {
    dynamic value = data.valueAtPath(clause.field);
    dynamic queryValue = convertSerializedVectorValuesToRuntime(clause.value);
    return switch (clause.operator) {
      ClauseOperator.lessThan =>
        _LocalValueComparator.compare(value, queryValue) < 0,
      ClauseOperator.lessThanOrEqual =>
        _LocalValueComparator.compare(value, queryValue) <= 0,
      ClauseOperator.equal => _LocalValueComparator.equals(value, queryValue),
      ClauseOperator.greaterThan =>
        _LocalValueComparator.compare(value, queryValue) > 0,
      ClauseOperator.greaterThanOrEqual =>
        _LocalValueComparator.compare(value, queryValue) >= 0,
      ClauseOperator.notEqual =>
        value != null && !_LocalValueComparator.equals(value, queryValue),
      ClauseOperator.arrayContains =>
        value is List &&
            value.any((item) => _LocalValueComparator.equals(item, queryValue)),
      ClauseOperator.arrayContainsAny =>
        value is List &&
            queryValue is List &&
            queryValue.any(
              (item) => value.any(
                (existing) => _LocalValueComparator.equals(existing, item),
              ),
            ),
      ClauseOperator.isIn =>
        queryValue is List &&
            queryValue.any((item) => _LocalValueComparator.equals(value, item)),
      ClauseOperator.notIn =>
        value != null &&
            queryValue is List &&
            !queryValue.any(
              (item) => _LocalValueComparator.equals(value, item),
            ),
    };
  }
}

class _LocalValueComparator {
  const _LocalValueComparator._();

  static bool equals(dynamic a, dynamic b) {
    dynamic left = convertSerializedVectorValuesToRuntime(a);
    dynamic right = convertSerializedVectorValuesToRuntime(b);
    if (left is VectorValue && right is VectorValue) {
      return left == right;
    }

    if (left is Uint8List && right is Uint8List) {
      return left.length == right.length &&
          Iterable<int>.generate(
            left.length,
          ).every((index) => left[index] == right[index]);
    }

    if (left is DocumentReference && right is DocumentReference) {
      return left.path == right.path;
    }

    if (left is List && right is List) {
      return left.length == right.length &&
          Iterable<int>.generate(
            left.length,
          ).every((index) => equals(left[index], right[index]));
    }

    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.entries.every(
            (entry) =>
                right.containsKey(entry.key) &&
                equals(entry.value, right[entry.key]),
          );
    }

    return left == right;
  }

  static int compare(dynamic a, dynamic b) {
    dynamic left = convertSerializedVectorValuesToRuntime(a);
    dynamic right = convertSerializedVectorValuesToRuntime(b);
    if (left == null && right == null) return 0;
    if (left == null) return -1;
    if (right == null) return 1;
    if (left is num && right is num) return left.compareTo(right);
    if (left is String && right is String) return left.compareTo(right);
    if (left is DateTime && right is DateTime) {
      return left.toUtc().microsecondsSinceEpoch.compareTo(
        right.toUtc().microsecondsSinceEpoch,
      );
    }
    if (left is DocumentReference && right is DocumentReference) {
      return left.path.compareTo(right.path);
    }
    if (left is LocalGeoPoint && right is LocalGeoPoint) {
      int latitudeComparison = left.latitude.compareTo(right.latitude);
      return latitudeComparison == 0
          ? left.longitude.compareTo(right.longitude)
          : latitudeComparison;
    }
    if (left is Uint8List && right is Uint8List) {
      return compareLists(left, right);
    }
    if (left is bool && right is bool) {
      return left == right
          ? 0
          : left
          ? 1
          : -1;
    }

    return left.toString().compareTo(right.toString());
  }

  static int compareLists(List<Object?> a, List<Object?> b) {
    int length = math.min(a.length, b.length);
    for (int i = 0; i < length; i++) {
      int comparison = compare(a[i], b[i]);
      if (comparison != 0) return comparison;
    }

    return a.length.compareTo(b.length);
  }
}

extension _XDocumentDataPath on DocumentData {
  dynamic valueAtPath(String path) {
    dynamic current = this;
    for (String segment in path.split('.')) {
      if (current is! Map) return null;
      current = current[segment];
    }
    return current;
  }

  void setValueAtPath(String path, dynamic value, {FirestoreDatabase? db}) {
    List<String> segments = path.split('.');
    Map<String, dynamic> current = this;
    for (int i = 0; i < segments.length - 1; i++) {
      String segment = segments[i];
      dynamic next = current[segment];
      if (next is! Map<String, dynamic>) {
        next = <String, dynamic>{};
        current[segment] = next;
      }
      current = next;
    }
    current[segments.last] = _LocalDocumentCodec.cloneValue(value, db: db);
  }

  void removeValueAtPath(String path) {
    List<String> segments = path.split('.');
    Map<String, dynamic> current = this;
    for (int i = 0; i < segments.length - 1; i++) {
      dynamic next = current[segments[i]];
      if (next is! Map<String, dynamic>) return;
      current = next;
    }
    current.remove(segments.last);
  }
}

extension _XListFirstOrNull on List<dynamic> {
  dynamic get firstOrNull => isEmpty ? null : first;
}
