library fire_api;

import 'dart:math';

import 'package:fast_log/fast_log.dart';

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
  bool debugLogging = false;
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

  Future<DocumentSnapshot> getDocument(DocumentReference ref,
      {bool cached = false});

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
  final DocumentChangeType? changeType;
  final dynamic metadata;
  String get id => reference.id;
  String get path => reference.path;

  DocumentSnapshot(
    this.reference,
    this.data, {
    this.metadata,
    this.changeType,
  });

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

enum DocumentChangeType { removed, added, modified }

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
  final Iterable<Object?>? qStartAfterValues;
  final Iterable<Object?>? qEndBeforeValues;
  final Iterable<Object?>? qStartAtValues;
  final Iterable<Object?>? qEndAtValues;

  CollectionReference(super.path, super.db,
      {this.qLimit,
      this.qOrderBy,
      this.descending = false,
      this.clauses = const [],
      this.qStartAfter,
      this.qEndBefore,
      this.qStartAt,
      this.qEndAt,
      this.qStartAfterValues,
      this.qEndBeforeValues,
      this.qStartAtValues,
      this.qEndAtValues});

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
          qEndAt: qEndAt,
          qStartAfterValues: qStartAfterValues,
          qEndBeforeValues: qEndBeforeValues,
          qStartAtValues: qStartAtValues,
          qEndAtValues: qEndAtValues);

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
          qEndAt: qEndAt,
          qStartAfterValues: qStartAfterValues,
          qEndBeforeValues: qEndBeforeValues,
          qStartAtValues: qStartAtValues,
          qEndAtValues: qEndAtValues);

  CollectionReference limit(int limit) => CollectionReference(path, db,
      qLimit: limit,
      qOrderBy: qOrderBy,
      descending: descending,
      clauses: clauses,
      qStartAfter: qStartAfter,
      qEndBefore: qEndBefore,
      qStartAt: qStartAt,
      qEndAt: qEndAt,
      qStartAfterValues: qStartAfterValues,
      qEndBeforeValues: qEndBeforeValues,
      qStartAtValues: qStartAtValues,
      qEndAtValues: qEndAtValues);

  CollectionReference startAfter(DocumentSnapshot doc) =>
      CollectionReference(path, db,
          qLimit: qLimit,
          qOrderBy: qOrderBy,
          descending: descending,
          clauses: clauses,
          qStartAfter: doc,
          qEndBefore: qEndBefore,
          qStartAt: qStartAt,
          qEndAt: qEndAt,
          qStartAfterValues: qStartAfterValues,
          qEndBeforeValues: qEndBeforeValues,
          qStartAtValues: qStartAtValues,
          qEndAtValues: qEndAtValues);

  CollectionReference endBefore(DocumentSnapshot doc) =>
      CollectionReference(path, db,
          qLimit: qLimit,
          qOrderBy: qOrderBy,
          descending: descending,
          clauses: clauses,
          qStartAfter: qStartAfter,
          qEndBefore: doc,
          qStartAt: qStartAt,
          qEndAt: qEndAt,
          qStartAfterValues: qStartAfterValues,
          qEndBeforeValues: qEndBeforeValues,
          qStartAtValues: qStartAtValues,
          qEndAtValues: qEndAtValues);

  CollectionReference startAt(DocumentSnapshot doc) =>
      CollectionReference(path, db,
          qLimit: qLimit,
          qOrderBy: qOrderBy,
          descending: descending,
          clauses: clauses,
          qStartAfter: qStartAfter,
          qEndBefore: qEndBefore,
          qStartAt: doc,
          qEndAt: qEndAt,
          qStartAfterValues: qStartAfterValues,
          qEndBeforeValues: qEndBeforeValues,
          qStartAtValues: qStartAtValues,
          qEndAtValues: qEndAtValues);

  CollectionReference endAt(DocumentSnapshot doc) =>
      CollectionReference(path, db,
          qLimit: qLimit,
          qOrderBy: qOrderBy,
          descending: descending,
          clauses: clauses,
          qStartAfter: qStartAfter,
          qEndBefore: qEndBefore,
          qStartAt: qStartAt,
          qEndAt: doc,
          qStartAfterValues: qStartAfterValues,
          qEndBeforeValues: qEndBeforeValues,
          qStartAtValues: qStartAtValues,
          qEndAtValues: qEndAtValues);

  CollectionReference startAfterValues(Iterable<Object?> values) =>
      CollectionReference(path, db,
          qLimit: qLimit,
          qOrderBy: qOrderBy,
          descending: descending,
          clauses: clauses,
          qStartAfter: qStartAfter,
          qEndBefore: qEndBefore,
          qStartAt: qStartAt,
          qEndAt: qEndAt,
          qStartAfterValues: values,
          qEndBeforeValues: qEndBeforeValues,
          qStartAtValues: qStartAtValues,
          qEndAtValues: qEndAtValues);

  CollectionReference endBeforeValues(Iterable<Object?> values) =>
      CollectionReference(path, db,
          qLimit: qLimit,
          qOrderBy: qOrderBy,
          descending: descending,
          clauses: clauses,
          qStartAfter: qStartAfter,
          qEndBefore: qEndBefore,
          qStartAt: qStartAt,
          qEndAt: qEndAt,
          qStartAfterValues: qStartAfterValues,
          qEndBeforeValues: values,
          qStartAtValues: qStartAtValues,
          qEndAtValues: qEndAtValues);

  CollectionReference startAtValues(Iterable<Object?> values) =>
      CollectionReference(path, db,
          qLimit: qLimit,
          qOrderBy: qOrderBy,
          descending: descending,
          clauses: clauses,
          qStartAfter: qStartAfter,
          qEndBefore: qEndBefore,
          qStartAt: qStartAt,
          qEndAt: qEndAt,
          qStartAfterValues: qStartAfterValues,
          qEndBeforeValues: qEndBeforeValues,
          qStartAtValues: values,
          qEndAtValues: qEndAtValues);

  CollectionReference endAtValues(Iterable<Object?> values) =>
      CollectionReference(path, db,
          qLimit: qLimit,
          qOrderBy: qOrderBy,
          descending: descending,
          clauses: clauses,
          qStartAfter: qStartAfter,
          qEndBefore: qEndBefore,
          qStartAt: qStartAt,
          qEndAt: qEndAt,
          qStartAfterValues: qStartAfterValues,
          qEndBeforeValues: qEndBeforeValues,
          qStartAtValues: qStartAtValues,
          qEndAtValues: values);

  Stream<List<DocumentSnapshot>> get stream {
    if (db.debugLogging) {
      network('Opened Stream on all documents in $this');
    }
    return db.streamDocumentsInCollection(this);
  }

  Future<List<DocumentSnapshot>> get() async {
    if (db.debugLogging) {
      network('Getting all documents in $this');
    }

    List<DocumentSnapshot> l = await db.getDocumentsInCollection(this);

    if (db.debugLogging) {
      network('Got ${l.length} documents');
    }

    return l;
  }

  @override
  String toString() =>
      "collection($path)${clauses.isNotEmpty ? "WHERE ${clauses.join(", ")}" : ""} ${qOrderBy != null ? "ORDER BY $qOrderBy ${descending ? "DESC" : "ASC"}" : ""} ${qLimit != null ? "LIMIT $qLimit" : ""} ${qStartAfter != null ? "START AFTER ${qStartAfter!.id}" : ""} ${qEndBefore != null ? "END BEFORE ${qEndBefore!.id}" : ""} ${qStartAt != null ? "START AT ${qStartAt!.id}" : ""} ${qEndAt != null ? "END AT ${qEndAt!.id}" : ""}";

  Future<int> count() async {
    if (db.debugLogging) {
      network('Counting documents $this');
    }
    int c = await db.countDocumentsInCollection(this);

    if (db.debugLogging) {
      network('Counted $c documents');
    }

    return c;
  }

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

  @override
  String toString() => "doc($path)";

  Future<void> delete() {
    if (db.debugLogging) {
      network('Deleting document $this');
    }
    return db.deleteDocument(this);
  }

  Stream<DocumentSnapshot> get stream {
    if (db.debugLogging) {
      network('Opened Stream on document $this');
    }
    return db.streamDocument(this);
  }

  Future<DocumentSnapshot> get({bool cached = false}) async {
    network('Getting document $this');
    DocumentSnapshot d = await db.getDocument(this);
    network('Got document ${d.data}');
    return d;
  }

  Future<void> set(DocumentData data) {
    if (db.debugLogging) {
      network('Setting document $this to $data');
    }
    return db.setDocument(this, data);
  }

  Future<void> update(DocumentData data) => db.updateDocument(this, data);

  Future<void> setAtomic(DocumentData Function(DocumentData? data) txn) {
    if (db.debugLogging) {
      network('Setting document $this atomically');
    }
    return db.setDocumentAtomic(this, txn);
  }

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
