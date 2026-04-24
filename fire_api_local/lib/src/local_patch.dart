part of 'fire_api_local_base.dart';

class _LocalDocumentPatch {
  const _LocalDocumentPatch._();

  static DocumentData applySet(DocumentData data, {FirestoreDatabase? db}) {
    DocumentData next = <String, dynamic>{};
    for (MapEntry<String, dynamic> entry in data.entries) {
      if (entry.value is FieldValue) {
        _applyFieldValue(next, entry.key, entry.value as FieldValue, db: db);
      } else {
        next[entry.key] = _LocalDocumentCodec.cloneValue(entry.value, db: db);
      }
    }
    return next;
  }

  static DocumentData applyUpdate(
    DocumentData current,
    DocumentData patch, {
    FirestoreDatabase? db,
  }) {
    DocumentData next = _LocalDocumentCodec.clone(current, db: db);
    for (MapEntry<String, dynamic> entry in patch.entries) {
      if (entry.value is FieldValue) {
        _applyFieldValue(next, entry.key, entry.value as FieldValue, db: db);
      } else {
        next.setValueAtPath(entry.key, entry.value, db: db);
      }
    }
    return next;
  }

  static void _applyFieldValue(
    DocumentData data,
    String path,
    FieldValue value, {
    FirestoreDatabase? db,
  }) {
    if (value.type == FieldValueType.delete) {
      data.removeValueAtPath(path);
      return;
    }

    dynamic next = switch (value.type) {
      FieldValueType.serverTimestamp => DateTime.now().toUtc(),
      FieldValueType.arrayUnion => _arrayUnion(
        data.valueAtPath(path),
        value.elements ?? const <dynamic>[],
        db: db,
      ),
      FieldValueType.arrayRemove => _arrayRemove(
        data.valueAtPath(path),
        value.elements ?? const <dynamic>[],
        db: db,
      ),
      FieldValueType.increment => _increment(
        data.valueAtPath(path),
        value.elements?.firstOrNull ?? 1,
      ),
      FieldValueType.decrement => _increment(
        data.valueAtPath(path),
        -((value.elements?.firstOrNull ?? 1) as num),
      ),
      FieldValueType.delete => null,
    };
    data.setValueAtPath(path, next, db: db);
  }

  static List<dynamic> _arrayUnion(
    dynamic current,
    List<dynamic> elements, {
    FirestoreDatabase? db,
  }) {
    List<dynamic> next = current is List
        ? current
              .map((element) => _LocalDocumentCodec.cloneValue(element, db: db))
              .toList()
        : <dynamic>[];
    for (dynamic element in elements) {
      dynamic cloned = _LocalDocumentCodec.cloneValue(element, db: db);
      if (!next.any(
        (existing) => _LocalValueComparator.equals(existing, cloned),
      )) {
        next.add(cloned);
      }
    }
    return next;
  }

  static List<dynamic> _arrayRemove(
    dynamic current,
    List<dynamic> elements, {
    FirestoreDatabase? db,
  }) {
    if (current is! List) return <dynamic>[];

    return current
        .where(
          (existing) => !elements.any(
            (element) => _LocalValueComparator.equals(existing, element),
          ),
        )
        .map((element) => _LocalDocumentCodec.cloneValue(element, db: db))
        .toList();
  }

  static num _increment(dynamic current, dynamic deltaValue) {
    num currentNumber = current is num ? current : 0;
    num delta = deltaValue is num ? deltaValue : 0;
    num result = currentNumber + delta;
    return currentNumber is int && delta is int ? result.toInt() : result;
  }
}
