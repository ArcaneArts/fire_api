import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:fire_api/fire_api.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';

DocumentReference _doc(
        FirestoreDatabase db, cf.DocumentReference<DocumentData> ref) =>
    DocumentReference(ref.path, db);

extension _XDocumentReference on DocumentReference {
  cf.DocumentReference<DocumentData> get _ref =>
      cf.FirebaseFirestore.instance.doc(db.effectivePath(path));
}

extension _XCollectionReference on CollectionReference {
  cf.Query<DocumentData> get _ref {
    cf.Query<DocumentData> d =
        cf.FirebaseFirestore.instance.collection(db.effectivePath(path));

    for (Clause i in clauses) {
      final value = _encodeFirestoreValue(i.value);
      d = d.where(i.field,
          arrayContains:
              i.operator == ClauseOperator.arrayContains ? value : null,
          arrayContainsAny:
              i.operator == ClauseOperator.arrayContainsAny ? value : null,
          isGreaterThan:
              i.operator == ClauseOperator.greaterThan ? value : null,
          isGreaterThanOrEqualTo:
              i.operator == ClauseOperator.greaterThanOrEqual ? value : null,
          isEqualTo: i.operator == ClauseOperator.equal ? value : null,
          isLessThan: i.operator == ClauseOperator.lessThan ? value : null,
          isLessThanOrEqualTo:
              i.operator == ClauseOperator.lessThanOrEqual ? value : null,
          isNotEqualTo: i.operator == ClauseOperator.notEqual ? value : null,
          whereIn: i.operator == ClauseOperator.isIn ? value : null,
          whereNotIn: i.operator == ClauseOperator.notIn ? value : null);
    }

    if (qOrderBy != null) {
      d = d.orderBy(qOrderBy!, descending: descending);
    }

    if (qLimit != null) {
      d = d.limit(qLimit!);
    }

    if (qStartAfter?.metadata != null) {
      d = d.startAfterDocument(qStartAfter!.metadata);
    }

    if (qEndBefore?.metadata != null) {
      d = d.endBeforeDocument(qEndBefore!.metadata);
    }

    if (qStartAt?.metadata != null) {
      d = d.startAtDocument(qStartAt!.metadata);
    }

    if (qEndAt?.metadata != null) {
      d = d.endAtDocument(qEndAt!.metadata);
    }

    if (qStartAfterValues != null) {
      d = d.endAt(qStartAfterValues!);
    }

    if (qEndBeforeValues != null) {
      d = d.endBefore(qEndBeforeValues!);
    }

    if (qStartAtValues != null) {
      d = d.startAt(qStartAtValues!);
    }

    if (qEndAtValues != null) {
      d = d.endAt(qEndAtValues!);
    }

    return d;
  }
}

dynamic _convertValueRecursive(
  dynamic value,
  dynamic Function(dynamic) converter,
) {
  if (value is Map) {
    return value.map<String, dynamic>((key, innerValue) => MapEntry(
          key as String,
          _convertValueRecursive(innerValue, converter),
        ));
  }

  if (value is List) {
    return value
        .map((innerValue) => _convertValueRecursive(innerValue, converter))
        .toList();
  }

  return converter(value);
}

dynamic _decodeFirestoreValue(dynamic value) => _convertValueRecursive(
      value,
      (x) => x is cf.VectorValue ? VectorValue(x.toArray()) : x,
    );

dynamic _encodeFirestoreValue(dynamic value) => _convertValueRecursive(
      value,
      (x) => x is VectorValue ? cf.VectorValue(x.toArray()) : x,
    );

DocumentData? _decodeFirestoreDocumentData(DocumentData? data) => data == null
    ? null
    : Map<String, dynamic>.from(_decodeFirestoreValue(data) as Map);

DocumentData _encodeFirestoreDocumentData(DocumentData data) =>
    Map<String, dynamic>.from(_encodeFirestoreValue(data) as Map);

dynamic _encodeFirestoreUpdateValue(dynamic value) {
  if (value is! FieldValue) {
    return _encodeFirestoreValue(value);
  }

  return switch (value.type) {
    FieldValueType.delete => cf.FieldValue.delete(),
    FieldValueType.increment =>
      cf.FieldValue.increment(value.elements![0] as num),
    FieldValueType.decrement =>
      cf.FieldValue.increment(-(value.elements![0] as num)),
    FieldValueType.arrayUnion =>
      cf.FieldValue.arrayUnion(_encodeFirestoreValue(value.elements!) as List),
    FieldValueType.arrayRemove =>
      cf.FieldValue.arrayRemove(_encodeFirestoreValue(value.elements!) as List),
    FieldValueType.serverTimestamp => cf.FieldValue.serverTimestamp(),
  };
}

class FirebaseFireStorage extends FireStorage {
  @override
  Future<Map<String, String>> getMetadata(String bucket, String path) =>
      FirebaseStorage.instance.ref(path).getMetadata().then((value) => {
            if (value.cacheControl != null) "cacheControl": value.cacheControl!,
            if (value.contentDisposition != null)
              "contentDisposition": value.contentDisposition!,
            if (value.contentEncoding != null)
              "contentEncoding": value.contentEncoding!,
            if (value.contentLanguage != null)
              "contentLanguage": value.contentLanguage!,
            if (value.contentType != null) "contentType": value.contentType!,
            ...value.customMetadata?.map((k, v) => MapEntry(k, v)) ?? {},
          });

  @override
  Future<Uint8List> read(String bucket, String path) => FirebaseStorage.instance
      .ref(path)
      .getData(10485760 * 128)
      .then((d) => d!);

  @override
  Future<void> setMetadata(
          String bucket, String path, Map<String, String> metadata) =>
      FirebaseStorage.instance.ref(path).updateMetadata(SettableMetadata(
          cacheControl: metadata["cacheControl"],
          contentDisposition: metadata["contentDisposition"],
          contentEncoding: metadata["contentEncoding"],
          contentLanguage: metadata["contentLanguage"],
          contentType: metadata["contentType"],
          customMetadata: metadata.entries
              .where((e) => ![
                    "cacheControl",
                    "contentDisposition",
                    "contentEncoding",
                    "contentLanguage",
                    "contentType"
                  ].contains(e.key))
              .fold<Map<String, String>>({}, (p, e) => p..[e.key] = e.value)));

  @override
  Future<void> write(String bucket, String path, Uint8List data) =>
      FirebaseStorage.instance.ref(path).putData(data).then((_) => null);

  @override
  Future<void> delete(String bucket, String path) =>
      FirebaseStorage.instance.ref(path).delete();

  @override
  Future<void> upload(String bucket, String path, String file) =>
      FirebaseStorage.instance.ref(path).putFile(File(file));

  @override
  Future<void> download(String bucket, String path, String file) async {
    HttpClient httpClient = HttpClient();
    HttpClientRequest request = await httpClient.getUrl(
        Uri.parse(await FirebaseStorage.instance.ref(path).getDownloadURL()));
    HttpClientResponse response = await request.close();
    File outFile = File(file)..createSync(recursive: true);
    IOSink sink = outFile.openWrite();
    await response.pipe(sink);
    await sink.flush();
    await sink.close();
    httpClient.close();
  }
}

class FirebaseFirestoreDatabase extends FirestoreDatabase {
  bool useWindowsAtomicPatch = true;

  FirebaseFirestoreDatabase({super.rootPrefix = ''});

  static FirestoreDatabase create() => FirebaseFirestoreDatabase();

  @override
  Future<int> countDocumentsInCollection(CollectionReference reference) =>
      reference._ref.count().get().then((value) => value.count ?? 0);

  @override
  Future<double> sumDocumentsInCollection(
          CollectionReference reference, String field) =>
      reference._ref
          .aggregate(cf.sum(field))
          .get()
          .then((v) => v.getSum(field) ?? 0);

  @override
  Future<void> deleteDocument(DocumentReference path) => path._ref.delete();

  @override
  Future<DocumentSnapshot> getDocument(DocumentReference ref,
      {bool cached = false}) async {
    Future<DocumentSnapshot> g(bool c) => ref._ref
        .get(cf.GetOptions(
            source: c
                ? kIsWeb
                    ? cf.Source.serverAndCache
                    : cf.Source.cache
                : cf.Source.serverAndCache))
        .then((value) => DocumentSnapshot(ref,
            value.exists ? _decodeFirestoreDocumentData(value.data()) : null,
            metadata: value));

    if (cached) {
      DocumentSnapshot d = await g(true);

      if (d.exists) {
        return d;
      }
    }

    return g(false);
  }

  @override
  Future<List<DocumentSnapshot>> getDocumentsInCollection(
          CollectionReference reference) =>
      reference._ref.get().then((value) => value.docs
          .map((e) => DocumentSnapshot(_doc(this, e.reference),
              e.exists ? _decodeFirestoreDocumentData(e.data()) : null,
              metadata: e))
          .toList());

  @override
  Future<void> setDocument(DocumentReference ref, DocumentData data) =>
      ref._ref.set(_encodeFirestoreDocumentData(data));

  @override
  Stream<DocumentSnapshot> streamDocument(DocumentReference ref) =>
      ref._ref.snapshots().map((event) => DocumentSnapshot(
          ref, event.exists ? _decodeFirestoreDocumentData(event.data()) : null,
          metadata: event));

  @override
  Stream<List<DocumentSnapshot>> streamDocumentsInCollection(
          CollectionReference reference) =>
      reference._ref.snapshots().map((event) => event.docs
          .map((e) => DocumentSnapshot(_doc(this, e.reference),
              e.exists ? _decodeFirestoreDocumentData(e.data()) : null,
              metadata: e,
              changeType: switch (event.docChanges
                  .where((c) => c.doc.reference.path == e.reference.path)
                  .firstOrNull
                  ?.type) {
                cf.DocumentChangeType.added => DocumentChangeType.added,
                cf.DocumentChangeType.modified => DocumentChangeType.modified,
                cf.DocumentChangeType.removed => DocumentChangeType.removed,
                _ => null,
              }))
          .toList());

  @override
  Future<void> updateDocument(DocumentReference ref, DocumentData data) =>
      ref._ref.update(data.map((k, v) {
        return MapEntry<String, dynamic>(k, _encodeFirestoreUpdateValue(v));
      }));

  @override
  Future<void> updateDocumentAtomic(DocumentReference ref,
      Map<String, dynamic> Function(DocumentData? data) txn) async {
    if (useWindowsAtomicPatch && _isWindows) {
      cf.DocumentSnapshot<DocumentData> fromDb = await ref._ref.get();

      if (fromDb.exists) {
        await ref._ref.update(
            _encodeFirestoreDocumentData(txn(_decodeFirestoreDocumentData(
          fromDb.data(),
        ))));
      }

      return;
    }

    return cf.FirebaseFirestore.instance.runTransaction((t) async {
      cf.DocumentSnapshot<DocumentData> fromDb = await t.get(ref._ref);
      t.update(
          ref._ref,
          _encodeFirestoreDocumentData(
              txn(_decodeFirestoreDocumentData(fromDb.data()))));
    });
  }

  @override
  Future<void> setDocumentAtomic(DocumentReference ref,
      DocumentData Function(DocumentData? data) txn) async {
    if (useWindowsAtomicPatch && _isWindows) {
      cf.DocumentSnapshot<DocumentData> fromDb = await ref._ref.get();

      if (fromDb.exists) {
        await ref._ref.set(_encodeFirestoreDocumentData(txn(
          _decodeFirestoreDocumentData(fromDb.data()),
        )));
      }

      return;
    }

    return cf.FirebaseFirestore.instance.runTransaction((t) async {
      cf.DocumentSnapshot<DocumentData> fromDb = await t.get(ref._ref);
      t.set(
          ref._ref,
          _encodeFirestoreDocumentData(
              txn(_decodeFirestoreDocumentData(fromDb.data()))));
    });
  }

  bool get _isWindows => !kIsWeb && Platform.isWindows;

  @override
  Future<DocumentSnapshot> getDocumentCachedOnly(DocumentReference ref) => ref
      ._ref
      .get(const cf.GetOptions(
          source: kIsWeb ? cf.Source.serverAndCache : cf.Source.cache))
      .then((value) => DocumentSnapshot(
          ref, value.exists ? _decodeFirestoreDocumentData(value.data()) : null,
          metadata: value));
}
