library fire_api;

import 'dart:math';

typedef DocumentData = Map<String, dynamic>;

const String _chars =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
Random _random = Random();

String _chargen([int len = 20]) {
  StringBuffer buffer = StringBuffer();

  for (int i = 0; i < len; i++) {
    buffer.write(_chars[_random.nextInt(_chars.length)]);
  }

  return buffer.toString();
}

FirestoreDatabase? _instance;

abstract class FirestoreDatabase {
  static FirestoreDatabase get instance => _instance!;

  FirestoreDatabase() {
    _instance = this;
  }

  CollectionReference collection(String path) =>
      CollectionReference(path, this);

  DocumentReference document(String path) => DocumentReference(path, this);

  Future<int> countDocumentsInCollection(CollectionReference reference);

  Future<List<DocumentSnapshot>> getDocumentsInCollection(
      CollectionReference reference);

  Stream<List<DocumentSnapshot>> streamDocumentsInCollection(
      CollectionReference reference);

  Future<void> deleteDocument(DocumentReference path);

  Stream<DocumentSnapshot> streamDocument(DocumentReference ref);

  Future<DocumentSnapshot> getDocument(DocumentReference ref);

  Future<void> setDocument(DocumentReference ref, DocumentData data);

  Future<void> updateDocument(DocumentReference ref, DocumentData data);

  Future<void> setDocumentAtomic(
      DocumentReference ref, DocumentData Function(DocumentData? data) txn);
}

abstract class FirestoreReference {
  final FirestoreDatabase db;
  final String path;
  String get id => path.split('/').last;

  FirestoreReference(this.path, this.db);

  FirestoreReference get parent;

  bool get hasParent => path.split('/').length > 1;
}

class DocumentSnapshot {
  final DocumentReference reference;
  final DocumentData? data;
  final dynamic metadata;
  String get id => reference.id;
  String get path => reference.path;

  DocumentSnapshot(this.reference, this.data, [this.metadata]);

  bool get exists => data != null;
}

enum ClauseOperator {
  lessThan, // <
  lessThanOrEqual, // <=
  equal, // ==
  greaterThan, // >
  greaterThanOrEqual, // >=
  notEqual, // !=
  arrayContains, // array-contains
  arrayContainsAny, // array-contains-any
  isIn, // in
  notIn // not-in
}

class Clause {
  final String field;
  final ClauseOperator operator;
  final dynamic value;

  Clause(this.field, this.operator, this.value);
}

class CollectionReference extends FirestoreReference {
  final int? qLimit;
  final String? qOrderBy;
  final bool descending;
  final List<Clause> clauses;
  final DocumentSnapshot? qStartAfter;
  final DocumentSnapshot? qEndBefore;
  final DocumentSnapshot? qStartAt;
  final DocumentSnapshot? qEndAt;

  CollectionReference(super.path, super.db,
      {this.qLimit,
      this.qOrderBy,
      this.descending = false,
      this.clauses = const [],
      this.qStartAfter,
      this.qEndBefore,
      this.qStartAt,
      this.qEndAt});

  DocumentReference doc(String documentId) => db.document('$path/$documentId');

  CollectionReference where(
          String field, ClauseOperator operator, dynamic value) =>
      CollectionReference(path, db,
          qLimit: qLimit,
          qOrderBy: qOrderBy,
          descending: descending,
          clauses: [...clauses, Clause(field, operator, value)],
          qStartAfter: qStartAfter,
          qEndBefore: qEndBefore,
          qStartAt: qStartAt,
          qEndAt: qEndAt);

  CollectionReference whereLessThan(String field, dynamic value) =>
      where(field, ClauseOperator.lessThan, value);

  CollectionReference whereLessThanOrEqual(String field, dynamic value) =>
      where(field, ClauseOperator.lessThanOrEqual, value);

  CollectionReference whereEqual(String field, dynamic value) =>
      where(field, ClauseOperator.equal, value);

  CollectionReference whereGreaterThan(String field, dynamic value) =>
      where(field, ClauseOperator.greaterThan, value);

  CollectionReference whereGreaterThanOrEqual(String field, dynamic value) =>
      where(field, ClauseOperator.greaterThanOrEqual, value);

  CollectionReference whereNotEqual(String field, dynamic value) =>
      where(field, ClauseOperator.notEqual, value);

  CollectionReference whereArrayContains(String field, dynamic value) =>
      where(field, ClauseOperator.arrayContains, value);

  CollectionReference whereArrayContainsAny(
          String field, List<dynamic> values) =>
      where(field, ClauseOperator.arrayContainsAny, values);

  CollectionReference whereIn(String field, List<dynamic> values) =>
      where(field, ClauseOperator.isIn, values);

  CollectionReference whereNotIn(String field, List<dynamic> values) =>
      where(field, ClauseOperator.notIn, values);

  CollectionReference orderBy(String field, {bool descending = false}) =>
      CollectionReference(path, db,
          qLimit: qLimit,
          qOrderBy: field,
          descending: descending,
          clauses: clauses,
          qStartAfter: qStartAfter,
          qEndBefore: qEndBefore,
          qStartAt: qStartAt,
          qEndAt: qEndAt);

  CollectionReference limit(int limit) => CollectionReference(path, db,
      qLimit: limit,
      qOrderBy: qOrderBy,
      descending: descending,
      clauses: clauses,
      qStartAfter: qStartAfter,
      qEndBefore: qEndBefore,
      qStartAt: qStartAt,
      qEndAt: qEndAt);

  CollectionReference startAfter(DocumentSnapshot doc) =>
      CollectionReference(path, db,
          qLimit: qLimit,
          qOrderBy: qOrderBy,
          descending: descending,
          clauses: clauses,
          qStartAfter: doc,
          qEndBefore: qEndBefore,
          qStartAt: qStartAt,
          qEndAt: qEndAt);

  CollectionReference endBefore(DocumentSnapshot doc) =>
      CollectionReference(path, db,
          qLimit: qLimit,
          qOrderBy: qOrderBy,
          descending: descending,
          clauses: clauses,
          qStartAfter: qStartAfter,
          qEndBefore: doc,
          qStartAt: qStartAt,
          qEndAt: qEndAt);

  CollectionReference startAt(DocumentSnapshot doc) =>
      CollectionReference(path, db,
          qLimit: qLimit,
          qOrderBy: qOrderBy,
          descending: descending,
          clauses: clauses,
          qStartAfter: qStartAfter,
          qEndBefore: qEndBefore,
          qStartAt: doc,
          qEndAt: qEndAt);

  CollectionReference endAt(DocumentSnapshot doc) =>
      CollectionReference(path, db,
          qLimit: qLimit,
          qOrderBy: qOrderBy,
          descending: descending,
          clauses: clauses,
          qStartAfter: qStartAfter,
          qEndBefore: qEndBefore,
          qStartAt: qStartAt,
          qEndAt: doc);

  Stream<List<DocumentSnapshot>> get stream =>
      db.streamDocumentsInCollection(this);

  Future<List<DocumentSnapshot>> get() => db.getDocumentsInCollection(this);

  Future<int> count() => db.countDocumentsInCollection(this);

  Future<DocumentReference> add(DocumentData data) async {
    DocumentReference ref = doc(_chargen());
    await ref.set(data);
    return ref;
  }

  @override
  FirestoreReference get parent => DocumentReference(
        path.split('/').sublist(0, path.split('/').length - 1).join('/'),
        db,
      );
}

class DocumentReference extends FirestoreReference {
  DocumentReference(super.path, super.db);

  CollectionReference collection(String collectionId) =>
      db.collection('$path/$collectionId');

  Future<void> delete() => db.deleteDocument(this);

  Stream<DocumentSnapshot> get stream => db.streamDocument(this);

  Future<DocumentSnapshot> get() => db.getDocument(this);

  Future<void> set(DocumentData data) => db.setDocument(this, data);

  Future<void> update(DocumentData data) => db.updateDocument(this, data);

  Future<void> setAtomic(DocumentData Function(DocumentData? data) txn) =>
      db.setDocumentAtomic(this, txn);

  @override
  FirestoreReference get parent => CollectionReference(
        path.split('/').sublist(0, path.split('/').length - 1).join('/'),
        db,
      );
}

enum FieldValueType {
  serverTimestamp,
  delete,
  arrayUnion,
  arrayRemove,
  increment,
  decrement
}

class FieldValue {
  final FieldValueType type;
  final List<dynamic>? elements;

  FieldValue.serverTimestamp()
      : type = FieldValueType.serverTimestamp,
        elements = null;

  FieldValue.delete()
      : type = FieldValueType.delete,
        elements = null;

  FieldValue.arrayUnion(List<dynamic> e)
      : type = FieldValueType.arrayUnion,
        elements = e;

  FieldValue.arrayRemove(List<dynamic> e)
      : type = FieldValueType.arrayRemove,
        elements = e;

  FieldValue.increment([num value = 1])
      : type = FieldValueType.increment,
        elements = [value];

  FieldValue.decrement([num value = 1])
      : type = FieldValueType.decrement,
        elements = [value];
}

// void test(){
//   ModelTree tree = ModelTree([
//     TModelCollection(id: "user", io: UserIO(), children: [
//       TAbsoluteModel(collection: "data", id: "settings", io: UserSettingsIO()),
//       TAbsoluteModel(collection: "data", id: "capabilities", io: UserCapabilitiesIO()),
//     ]),
//     TModelCollection(id: "library", io: LibraryIO(), children: [
//       TModelCollection(id: "guide", io: GuideIO(), children: [
//         TAbsoluteModel(collection: "data", id: "data", io: GuideDataIO()),
//         TAbsoluteModel(collection: "data", id: "manifest", io: GuideManifestIO()),
//       ]),
//     ]),
//   ]);
// }

class ModelTree {
  final List<TModel> models;

  ModelTree(this.models);
}

abstract class TModel {
  final String id;
  final TModelIO io;
  final List<TModel> children;

  const TModel({required this.id, required this.io, this.children = const []});
}

class TModelCollection extends TModel {
  const TModelCollection(
      {required super.id, required super.io, super.children = const []});
}

class TAbsoluteModel extends TModel {
  final String collection;

  const TAbsoluteModel(
      {required this.collection,
      required super.id,
      required super.io,
      super.children = const []});
}

abstract class TModelIO {
  Map<String, dynamic> toMap();

  void fromMap(Map<String, dynamic> data);
}
