library fire_api;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:fast_log/fast_log.dart';
import 'package:rxdart/rxdart.dart';

class ReusableStream<T> {
  final bool _debug;
  final String _key;
  final Stream<T> _stream;
  late BehaviorSubject<T> _subject;
  final void Function() _onClosed;
  int _refCount = 0;
  bool closed = false;
  T? realValue;
  int realValueCount = 0;

  ReusableStream(this._stream, this._key, this._onClosed, this._debug) {
    late StreamSubscription<T> subscription;
    _subject = BehaviorSubject(
      onCancel: () {
        _refCount--;
        if (_refCount == 0) {
          _subject.close();
          subscription.cancel();
          closed = true;
          if (_debug) {
            network("[POOL]: Closing stream $_key as it has no more listeners");
          }
          _onClosed();
        } else if (_debug) {
          network(
              "[POOL]: Listener disconnected from $_key. Remaining Listeners $_refCount");
        }
      },
      onListen: () {
        _refCount++;

        if (_debug) {
          network(
              "[POOL]: Listener connected to $_key. Total Listeners $_refCount");
        }
      },
    );
    subscription = _stream.listen((event) {
      realValue = event;
      realValueCount++;
      _subject.add(event);
    });
  }

  void inject(T data) {
    int rvc = realValueCount;
    _subject.add(data);
    Future.delayed(FirestoreDatabase.instance.injectionTimeout, () {
      if (rvc == realValueCount) {
        warn(
            "Injection Timeout on $_key. A set was not received by firestore / cache within 3 seconds, and was not received from the downstream. Reverting injected value as it no longer matches the document stream.");

        if (realValue != null) {
          _subject.add(realValue as T);
        }
      }
    });
  }

  Stream<T> get stream => _subject;
}

class StreamPool {
  final bool _debug;
  final Map<String, ReusableStream> _streams = {};

  StreamPool(this._debug);

  Stream<T> stream<T>(
      FirestoreReference ref, Stream<T> Function() streamFactory) {
    String k = ref.queryKey;
    if (!_streams.containsKey(k)) {
      if (_debug) {
        network("[POOL]: Creating new stream for $k");
      }
      _streams[k] = ReusableStream<T>(
          streamFactory(), k, () => _streams.remove(k), _debug);
    }

    return _streams[k]!.stream as Stream<T>;
  }

  void inject<T>(FirestoreReference ref, DocumentSnapshot snap) =>
      _streams[ref.queryKey]?.inject(snap as T);

  T? hotValue<T>(FirestoreReference ref) =>
      _streams[ref.queryKey]?._subject.valueOrNull as T?;
}

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
FireStorage? _sInstance;

class FireStorageRef {
  final String bucket;
  final String path;

  FireStorageRef(this.bucket, this.path);

  FireStorageRef ref(String path) => FireStorageRef(
      bucket,
      [...this.path.split("/"), ...path.split("/")]
          .where((i) => i.trim().isNotEmpty)
          .join("/"));

  Future<Uint8List> read() => FireStorage.instance.read(bucket, path);

  Future<void> write(Uint8List data) =>
      FireStorage.instance.write(bucket, path, data);

  Future<Map<String, String>> getMetadata() =>
      FireStorage.instance.getMetadata(bucket, path);

  Future<void> setMetadata(Map<String, String> metadata) =>
      FireStorage.instance.setMetadata(bucket, path, metadata);
}

abstract class FireStorage {
  static FireStorage get instance => _sInstance!;

  FireStorage() {
    _sInstance = this;
  }

  FireStorageRef ref(String bucket, String path) =>
      FireStorageRef(bucket, path);

  FireStorageRef bucket(String bucket) => FireStorageRef(bucket, "");

  Future<Uint8List> read(String bucket, String path);

  Future<void> write(String bucket, String path, Uint8List data);

  Future<Map<String, String>> getMetadata(String bucket, String path);

  Future<void> setMetadata(
      String bucket, String path, Map<String, String> metadata);
}

abstract class FirestoreDatabase {
  Duration injectionTimeout = Duration(seconds: 3);
  bool streamPooling = false;
  bool debugLogging = false;
  bool debugPooling = false;
  bool streamLoopbackInjection = false;
  StreamPool? _pool;
  static FirestoreDatabase get instance => _instance!;

  FirestoreDatabase() {
    _instance = this;
  }

  StreamPool get pool => _pool ??= StreamPool(debugPooling);

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

  Future<DocumentSnapshot> getDocumentCachedOnly(DocumentReference ref);

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

  String get queryKey;

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

  @override
  String get queryKey {
    List<String> parts = [
      path,
      if (qLimit != null) "l=$qLimit",
      if (qOrderBy != null) "o=$qOrderBy",
      if (descending) "d",
      if (clauses.isNotEmpty)
        ...clauses.map((c) => "w=<${c.field},${c.operator.index},${c.value}>"),
      if (qStartAfter != null) "sa=${qStartAfter!.metadata}",
      if (qEndBefore != null) "eb=${qEndBefore!.metadata}",
      if (qStartAt != null) "st=${qStartAt!.metadata}",
      if (qEndAt != null) "ea=${qEndAt!.metadata}",
      if (qStartAfterValues != null) "sav=[${qStartAfterValues!.join(",")}]",
      if (qEndBeforeValues != null) "ebv=[${qEndBeforeValues!.join(",")}]",
      if (qStartAtValues != null) "stv=[${qStartAtValues!.join(",")}]",
      if (qEndAtValues != null) "eav=[${qEndAtValues!.join(",")}]"
    ];

    return "collection(${parts.join(",")})";
  }

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
    if (db.streamPooling) {
      return db.pool.stream<List<DocumentSnapshot>>(this, () {
        if (db.debugLogging) {
          network('Opened Stream on all documents in $this');
        }

        return db.streamDocumentsInCollection(this);
      });
    }

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
  String get queryKey => "doc($path)";

  @override
  String toString() => "doc($path)";

  Future<void> delete() {
    if (db.debugLogging) {
      network('Deleting document $this');
    }
    return db.deleteDocument(this);
  }

  DocumentSnapshot? get hotValue =>
      db.streamPooling ? db.pool.hotValue<DocumentSnapshot>(this) : null;

  void injectIntoStream(DocumentSnapshot snap) {
    if (db.streamPooling) {
      db.pool.inject<DocumentSnapshot>(this, snap);
    }
  }

  Stream<DocumentSnapshot> get stream {
    if (db.streamPooling) {
      return db.pool.stream<DocumentSnapshot>(this, () {
        if (db.debugLogging) {
          network('Opened Stream on document $this');
        }

        return db.streamDocument(this);
      });
    }

    if (db.debugLogging) {
      network('Opened Stream on document $this');
    }

    return db.streamDocument(this);
  }

  Future<DocumentSnapshot> getCacheOnly() async {
    if (db.debugLogging) {
      network('[CACHED] Getting document $this');
    }

    DocumentSnapshot d = await db.getDocumentCachedOnly(this);

    if (db.debugLogging) {
      network('[CACHED] Got document ${d.data}');
    }

    return d;
  }

  Future<DocumentSnapshot> get({bool cached = false}) async {
    if (db.debugLogging) {
      network('Getting document $this');
    }

    DocumentSnapshot d = await db.getDocument(this, cached: cached);

    if (db.debugLogging) {
      network('Got document ${d.data}');
    }
    return d;
  }

  Future<void> set(DocumentData data) {
    if (db.debugLogging) {
      network('Setting document $this to $data');
    }
    injectIntoStream(DocumentSnapshot(this, data));
    return db.setDocument(this, data);
  }

  Future<void> update(DocumentData data) => db.updateDocument(this, data);

  Future<void> setAtomic(DocumentData Function(DocumentData? data) txn) {
    if (db.debugLogging) {
      network('Setting document $this atomically');
    }
    return db.setDocumentAtomic(this, (t) {
      DocumentData d = txn(t);
      injectIntoStream(DocumentSnapshot(this, d));
      return d;
    });
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
