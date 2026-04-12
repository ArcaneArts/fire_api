import 'dart:convert' as convert;

import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:fire_api/fire_api.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
      d = d.startAfter(qStartAfterValues!);
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

Future<String?> _defaultFirestoreIdTokenProvider() async {
  final user =
      fa.FirebaseAuth.instanceFor(app: cf.FirebaseFirestore.instance.app)
          .currentUser;
  return user?.getIdToken();
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
  final http.Client client;
  final Future<String?> Function() idTokenProvider;
  final String databaseId;

  FirebaseFirestoreDatabase({
    super.rootPrefix = '',
    http.Client? client,
    Future<String?> Function()? idTokenProvider,
    this.databaseId = '(default)',
  })  : client = client ?? http.Client(),
        idTokenProvider = idTokenProvider ?? _defaultFirestoreIdTokenProvider;

  static FirestoreDatabase create({
    String rootPrefix = '',
    http.Client? client,
    Future<String?> Function()? idTokenProvider,
    String databaseId = '(default)',
  }) =>
      FirebaseFirestoreDatabase(
        rootPrefix: rootPrefix,
        client: client,
        idTokenProvider: idTokenProvider,
        databaseId: databaseId,
      );

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
  Future<List<DocumentSnapshot>> getNearestDocumentsInCollection(
      VectorQueryReference reference) async {
    try {
      final response = await _postFirestoreJson(
        '${_queryParentPath(reference.reference)}:runQuery',
        body: {
          'structuredQuery': reference.toQueryJson,
        },
      );

      return (response as List)
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .where((entry) => entry['document'] is Map)
          .map((entry) => Map<String, dynamic>.from(entry['document'] as Map))
          .where((entry) => entry['fields'] is Map)
          .map((document) => DocumentSnapshot(
                reference.reference
                    .doc((document['name'] as String).split('/').last),
                _decodeFirestoreRestDocumentData(document),
                metadata: document,
              ))
          .toList();
    } catch (error) {
      final indexHint = _tryBuildMissingVectorIndexErrorMessage(
        error,
        projectId: _projectId,
        databaseId: databaseId,
        reference: reference,
      );
      if (indexHint != null) {
        throw StateError(indexHint);
      }

      rethrow;
    }
  }

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

  String get _projectId {
    final projectId = cf.FirebaseFirestore.instance.app.options.projectId;
    if (projectId.isEmpty) {
      throw StateError(
          'FirebaseFirestore.instance.app.options.projectId is required for vector queries.');
    }
    return projectId;
  }

  String get _dbx => 'projects/$_projectId/databases/$databaseId';
  String get _dx => '$_dbx/documents';

  String _queryParentPath(CollectionReference reference) {
    final effectivePath = reference._effectivePath;
    final segments = effectivePath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.length <= 1) {
      return _dx;
    }

    return '$_dx/${segments.sublist(0, segments.length - 1).join('/')}';
  }

  Future<dynamic> _postFirestoreJson(
    String path, {
    required Map<String, dynamic> body,
  }) =>
      _requestFirestoreJson(
        'POST',
        path,
        body: body,
      );

  Future<dynamic> _requestFirestoreJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(
      'https://firestore.googleapis.com/v1/${Uri.encodeFull(path)}',
    );
    final idToken = await idTokenProvider();
    final headers = <String, String>{
      'content-type': 'application/json',
      if (idToken != null && idToken.isNotEmpty)
        'authorization': 'Bearer $idToken',
    };

    final response = switch (method) {
      'POST' => await client.post(
          uri,
          headers: headers,
          body: body == null ? null : convert.jsonEncode(body),
        ),
      _ => throw UnsupportedError('Unsupported Firestore method: $method'),
    };

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Firestore vector query failed [${response.statusCode}] [${response.body}]',
      );
    }

    if (response.body.isEmpty) {
      return null;
    }

    return convert.jsonDecode(response.body);
  }
}

extension _XRestCollectionReference on CollectionReference {
  String get _effectivePath => db.effectivePath(path);

  Map<String, dynamic> get toQueryJson => {
        'from': [
          {'collectionId': _effectivePath.split('/').last},
        ],
        if (qLimit != null) 'limit': qLimit,
        if (qStartAtValues != null)
          'startAt': {
            'values': qStartAtValues!.map(_encodeFirestoreRestValue).toList(),
            'before': false,
          }
        else if (qStartAfterValues != null)
          'startAt': {
            'values':
                qStartAfterValues!.map(_encodeFirestoreRestValue).toList(),
            'before': true,
          }
        else if (qStartAt?.data != null)
          'startAt': {
            'values':
                qStartAt!.data!.values.map(_encodeFirestoreRestValue).toList(),
            'before': false,
          }
        else if (qStartAfter?.data != null)
          'startAt': {
            'values': qStartAfter!.data!.values
                .map(_encodeFirestoreRestValue)
                .toList(),
            'before': true,
          },
        if (qEndAtValues != null)
          'endAt': {
            'values': qEndAtValues!.map(_encodeFirestoreRestValue).toList(),
            'before': true,
          }
        else if (qEndBeforeValues != null)
          'endAt': {
            'values': qEndBeforeValues!.map(_encodeFirestoreRestValue).toList(),
            'before': false,
          }
        else if (qEndAt?.data != null)
          'endAt': {
            'values':
                qEndAt!.data!.values.map(_encodeFirestoreRestValue).toList(),
            'before': true,
          }
        else if (qEndBefore?.data != null)
          'endAt': {
            'values': qEndBefore!.data!.values
                .map(_encodeFirestoreRestValue)
                .toList(),
            'before': false,
          },
        if (qOrderBy != null)
          'orderBy': [
            {
              'direction': descending ? 'DESCENDING' : 'ASCENDING',
              'field': {'fieldPath': qOrderBy},
            },
          ],
        if (clauses.isNotEmpty)
          'where': clauses.length > 1
              ? {
                  'compositeFilter': {
                    'op': 'AND',
                    'filters': clauses
                        .map((clause) => {'fieldFilter': clause.toFilterJson})
                        .toList(),
                  },
                }
              : {
                  'fieldFilter': clauses.first.toFilterJson,
                },
      };
}

extension _XRestVectorQueryReference on VectorQueryReference {
  Map<String, dynamic> get toQueryJson => {
        ...reference.toQueryJson,
        'findNearest': {
          'vectorField': {'fieldPath': vectorField},
          'queryVector': _encodeFirestoreRestValue(queryVector),
          'limit': limit,
          'distanceMeasure': distanceMeasure.firestoreValue,
          if (distanceResultField != null)
            'distanceResultField': distanceResultField,
          if (distanceThreshold != null) 'distanceThreshold': distanceThreshold,
        },
      };
}

extension _XRestClause on Clause {
  Map<String, dynamic> get toFilterJson => {
        'field': {'fieldPath': field},
        'op': operator.firestoreValue,
        'value': _encodeFirestoreRestValue(value),
      };
}

extension _XRestClauseOperator on ClauseOperator {
  String get firestoreValue => switch (this) {
        ClauseOperator.lessThan => 'LESS_THAN',
        ClauseOperator.lessThanOrEqual => 'LESS_THAN_OR_EQUAL',
        ClauseOperator.equal => 'EQUAL',
        ClauseOperator.greaterThan => 'GREATER_THAN',
        ClauseOperator.greaterThanOrEqual => 'GREATER_THAN_OR_EQUAL',
        ClauseOperator.notEqual => 'NOT_EQUAL',
        ClauseOperator.arrayContains => 'ARRAY_CONTAINS',
        ClauseOperator.arrayContainsAny => 'ARRAY_CONTAINS_ANY',
        ClauseOperator.isIn => 'IN',
        ClauseOperator.notIn => 'NOT_IN',
      };
}

extension _XRestVectorDistanceMeasure on VectorDistanceMeasure {
  String get firestoreValue => switch (this) {
        VectorDistanceMeasure.euclidean => 'EUCLIDEAN',
        VectorDistanceMeasure.cosine => 'COSINE',
        VectorDistanceMeasure.dotProduct => 'DOT_PRODUCT',
      };
}

const String _firestoreVectorTypeKey = '__type__';
const String _firestoreVectorTypeSentinel = '__vector__';
const String _firestoreVectorValueKey = 'value';

String? _tryBuildMissingVectorIndexErrorMessage(
  Object error, {
  required String projectId,
  required String databaseId,
  required VectorQueryReference reference,
}) {
  final raw = error.toString();
  if (!raw.contains('Missing vector index configuration')) {
    return null;
  }

  final collectionGroup = reference.reference.path.split('/').last;
  final fieldConfig = _shellSingleQuote(
    'field-path=${reference.vectorField},vector-config={"dimension":${reference.queryVector.toArray().length},"flat":{}}',
  );

  return [
    'Firestore vector query failed: missing vector index for collection group "$collectionGroup" on field "${reference.vectorField}".',
    '',
    'Create it with:',
    '',
    'gcloud firestore indexes composite create \\',
    '  --project=${_shellSingleQuote(projectId)} \\',
    if (databaseId != '(default)')
      '  --database=${_shellSingleQuote(databaseId)} \\',
    '  --collection-group=${_shellSingleQuote(collectionGroup)} \\',
    '  --query-scope=collection \\',
    '  --field-config=$fieldConfig',
    '',
    'Original Firestore response:',
    raw,
  ].join('\n');
}

String _shellSingleQuote(String value) =>
    "'${value.replaceAll("'", "'\"'\"'")}'";

Map<String, dynamic> _encodeFirestoreRestValue(dynamic value) {
  if (value == null) {
    return {'nullValue': 'NULL_VALUE'};
  }

  return switch (value) {
    VectorValue _ => {
        'mapValue': {
          'fields': {
            _firestoreVectorTypeKey: {
              'stringValue': _firestoreVectorTypeSentinel,
            },
            _firestoreVectorValueKey: {
              'arrayValue': {
                'values': value
                    .toArray()
                    .map((item) => {
                          'doubleValue': item.toDouble(),
                        })
                    .toList(),
              },
            },
          },
        },
      },
    String _ => {'stringValue': value},
    int _ => {'integerValue': value.toString()},
    double _ => {'doubleValue': value},
    bool _ => {'booleanValue': value},
    List _ => {
        'arrayValue': {
          'values': value.map(_encodeFirestoreRestValue).toList(),
        },
      },
    Map _ => {
        'mapValue': {
          'fields': Map<String, dynamic>.fromEntries(
            value.entries.map(
              (entry) => MapEntry(
                entry.key as String,
                _encodeFirestoreRestValue(entry.value),
              ),
            ),
          ),
        },
      },
    _ => throw Exception('Unsupported type: ${value.runtimeType}'),
  };
}

DocumentData? _decodeFirestoreRestDocumentData(Map<String, dynamic> document) {
  final fields = document['fields'];
  if (fields is! Map) {
    return null;
  }

  return Map<String, dynamic>.fromEntries(
    fields.entries.map(
      (entry) => MapEntry(
        entry.key as String,
        _decodeFirestoreRestValue(
            Map<String, dynamic>.from(entry.value as Map)),
      ),
    ),
  );
}

dynamic _decodeFirestoreRestValue(Map<String, dynamic> value) {
  if (value.containsKey('nullValue')) return null;
  if (value['stringValue'] != null) return value['stringValue'];
  if (value['integerValue'] != null) {
    return int.tryParse(value['integerValue'] as String) ?? 0;
  }
  if (value['doubleValue'] != null) {
    return (value['doubleValue'] as num).toDouble();
  }
  if (value['booleanValue'] != null) return value['booleanValue'];
  if (value['vectorValue'] != null) {
    final vector = Map<String, dynamic>.from(value['vectorValue'] as Map);
    return VectorValue(
      ((vector['values'] as List?) ?? const [])
          .map((item) => (item as num).toDouble())
          .toList(),
    );
  }
  if (_isFirestoreVectorValueJson(value)) {
    final mapValue = Map<String, dynamic>.from(value['mapValue'] as Map);
    final fields =
        Map<String, dynamic>.from((mapValue['fields'] as Map?) ?? {});
    return VectorValue(
      ((((fields[_firestoreVectorValueKey] as Map?)?['arrayValue']
                  as Map?)?['values'] as List?) ??
              const [])
          .map((item) => ((item as Map)['doubleValue'] as num).toDouble())
          .toList(),
    );
  }
  if (value['arrayValue'] != null) {
    final array = Map<String, dynamic>.from(value['arrayValue'] as Map);
    return ((array['values'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) =>
            _decodeFirestoreRestValue(Map<String, dynamic>.from(item)))
        .toList();
  }
  if (value['mapValue'] != null) {
    final mapValue = Map<String, dynamic>.from(value['mapValue'] as Map);
    final fields = mapValue['fields'];
    return fields is Map
        ? Map<String, dynamic>.fromEntries(
            fields.entries.map(
              (entry) => MapEntry(
                entry.key as String,
                _decodeFirestoreRestValue(
                  Map<String, dynamic>.from(entry.value as Map),
                ),
              ),
            ),
          )
        : <String, dynamic>{};
  }

  throw Exception('Unsupported type: $value');
}

bool _isFirestoreVectorValueJson(Map<String, dynamic> value) {
  final mapValue = value['mapValue'];
  if (mapValue is! Map) {
    return false;
  }

  final fields = mapValue['fields'];
  if (fields is! Map) {
    return false;
  }

  final typeField = fields[_firestoreVectorTypeKey];
  return typeField is Map &&
      typeField['stringValue'] == _firestoreVectorTypeSentinel;
}
