library fire_api_flutter;

import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:fire_api/fire_api.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

DocumentReference _doc(
        FirestoreDatabase db, cf.DocumentReference<DocumentData> ref) =>
    DocumentReference(ref.path, db);

extension _XDocumentReference on DocumentReference {
  cf.DocumentReference<DocumentData> get _ref =>
      cf.FirebaseFirestore.instance.doc(path);
}

extension _XCollectionReference on CollectionReference {
  cf.Query<DocumentData> get _ref {
    cf.Query<DocumentData> d = cf.FirebaseFirestore.instance.collection(path);

    for (Clause i in clauses) {
      d = d.where(i.field,
          arrayContains:
              i.operator == ClauseOperator.arrayContains ? i.value : null,
          arrayContainsAny:
              i.operator == ClauseOperator.arrayContainsAny ? i.value : null,
          isGreaterThan:
              i.operator == ClauseOperator.greaterThan ? i.value : null,
          isGreaterThanOrEqualTo:
              i.operator == ClauseOperator.greaterThanOrEqual ? i.value : null,
          isEqualTo: i.operator == ClauseOperator.equal ? i.value : null,
          isLessThan: i.operator == ClauseOperator.lessThan ? i.value : null,
          isLessThanOrEqualTo:
              i.operator == ClauseOperator.lessThanOrEqual ? i.value : null,
          isNotEqualTo: i.operator == ClauseOperator.notEqual ? i.value : null,
          whereIn: i.operator == ClauseOperator.isIn ? i.value : null,
          whereNotIn: i.operator == ClauseOperator.notIn ? i.value : null);
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
}

class FirebaseFirestoreDatabase extends FirestoreDatabase {
  static FirestoreDatabase create() => FirebaseFirestoreDatabase();

  @override
  Future<int> countDocumentsInCollection(CollectionReference reference) =>
      reference._ref.count().get().then((value) => value.count ?? 0);

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
        .then((value) => DocumentSnapshot(
            ref, value.exists ? value.data() : null,
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
          .map((e) => DocumentSnapshot(
              _doc(this, e.reference), e.exists ? e.data() : null,
              metadata: e))
          .toList());

  @override
  Future<void> setDocument(DocumentReference ref, DocumentData data) =>
      ref._ref.set(data);

  @override
  Stream<DocumentSnapshot> streamDocument(DocumentReference ref) => ref._ref
      .snapshots()
      .map((event) => DocumentSnapshot(ref, event.exists ? event.data() : null,
          metadata: event));

  @override
  Stream<List<DocumentSnapshot>> streamDocumentsInCollection(
          CollectionReference reference) =>
      reference._ref.snapshots().map((event) => event.docs
          .map((e) => DocumentSnapshot(
              _doc(this, e.reference), e.exists ? e.data() : null,
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
        if (v is FieldValue) {
          return switch (v.type) {
            FieldValueType.delete =>
              MapEntry<String, dynamic>(k, cf.FieldValue.delete()),
            FieldValueType.increment => MapEntry<String, dynamic>(
                k, cf.FieldValue.increment(v.elements![0] as num)),
            FieldValueType.decrement => MapEntry<String, dynamic>(
                k, cf.FieldValue.increment(-v.elements![0] as num)),
            FieldValueType.arrayUnion => MapEntry<String, dynamic>(
                k, cf.FieldValue.arrayUnion(v.elements!)),
            FieldValueType.arrayRemove => MapEntry<String, dynamic>(
                k, cf.FieldValue.arrayRemove(v.elements!)),
            FieldValueType.serverTimestamp =>
              MapEntry<String, dynamic>(k, cf.FieldValue.serverTimestamp()),
          };
        }

        return MapEntry<String, dynamic>(k, v);
      }));

  @override
  Future<void> setDocumentAtomic(DocumentReference ref,
          DocumentData Function(DocumentData? data) txn) =>
      cf.FirebaseFirestore.instance.runTransaction((t) async {
        cf.DocumentSnapshot<DocumentData> fromDb = await t.get(ref._ref);
        t.update(ref._ref, txn(fromDb.exists ? fromDb.data() : null));
      });

  @override
  Future<DocumentSnapshot> getDocumentCachedOnly(DocumentReference ref) => ref
      ._ref
      .get(const cf.GetOptions(
          source: kIsWeb ? cf.Source.serverAndCache : cf.Source.cache))
      .then((value) => DocumentSnapshot(ref, value.exists ? value.data() : null,
          metadata: value));
}
