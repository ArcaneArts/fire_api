import 'dart:convert' as convert;
import 'dart:io';
import 'dart:typed_data';

import 'package:chunked_stream/chunked_stream.dart';
import 'package:fire_api/fire_api.dart';
import 'package:google_cloud/google_cloud.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis/storage/v1.dart' as s;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

class GoogleCloudFireStorage extends FireStorage {
  final s.StorageApi storageApi;

  GoogleCloudFireStorage(this.storageApi);

  static Future<GoogleCloudFireStorage> create() async {
    return GoogleCloudFireStorage(s.StorageApi(
        await clientViaApplicationDefaultCredentials(
            scopes: [s.StorageApi.devstorageReadWriteScope])));
  }

  @override
  Future<Uint8List> read(String bucket, String path) async {
    final media = await storageApi.objects.get(
      bucket,
      path,
      downloadOptions: s.DownloadOptions.fullMedia,
    ) as s.Media;
    return await readByteStream(media.stream);
  }

  @override
  Future<void> upload(String bucket, String path, String file) async {
    Stream<List<int>> stream = File(file).openRead();
    int length = await File(file).length();
    s.Media media = s.Media(stream, length);
    s.Object object = s.Object()..name = path;
    await storageApi.objects.insert(object, bucket, uploadMedia: media);
  }

  @override
  Future<void> download(String bucket, String path, String file) async {
    final media = await storageApi.objects.get(
      bucket,
      path,
      downloadOptions: s.DownloadOptions.fullMedia,
    ) as s.Media;

    await _readByteStreamIntoFile(media.stream, File(file));
  }

  Future<void> _readByteStreamIntoFile(
    Stream<List<int>> input,
    File file, {
    int? maxSize,
  }) async {
    if (maxSize != null && maxSize < 0) {
      throw ArgumentError.value(maxSize, 'maxSize must be positive, if given');
    }

    await file.create(recursive: true);
    IOSink sink = file.openWrite();
    int written = 0;
    await for (List<int> chunk in input) {
      sink.add(chunk);
      written += chunk.length;
      if (maxSize != null && written > maxSize) {
        throw MaximumSizeExceeded(maxSize);
      }
    }

    await sink.flush();
    await sink.close();
  }

  @override
  Future<void> write(String bucket, String path, Uint8List data) async {
    final media = s.Media(Stream.value(data), data.length);
    await storageApi.objects.insert(
      s.Object(),
      bucket,
      uploadMedia: media,
      name: path,
    );
  }

  @override
  Future<Map<String, String>> getMetadata(String bucket, String path) async {
    s.Object object = await storageApi.objects.get(bucket, path) as s.Object;
    Map<String, String> metadata = {};

    // Add standard metadata
    if (object.contentType != null) {
      metadata['contentType'] = object.contentType!;
    }
    if (object.cacheControl != null) {
      metadata['cacheControl'] = object.cacheControl!;
    }
    if (object.contentDisposition != null) {
      metadata['contentDisposition'] = object.contentDisposition!;
    }
    if (object.contentEncoding != null) {
      metadata['contentEncoding'] = object.contentEncoding!;
    }
    if (object.contentLanguage != null) {
      metadata['contentLanguage'] = object.contentLanguage!;
    }

    if (object.metadata != null) {
      metadata.addAll(object.metadata!);
    }

    return metadata;
  }

  @override
  Future<void> setMetadata(
      String bucket, String path, Map<String, String> metadata) async {
    s.Object object = await storageApi.objects.get(bucket, path) as s.Object;
    object.contentType = metadata['contentType'];
    object.cacheControl = metadata['cacheControl'];
    object.contentDisposition = metadata['contentDisposition'];
    object.contentEncoding = metadata['contentEncoding'];
    object.contentLanguage = metadata['contentLanguage'];
    List<String> smk = [
      'contentType',
      'cacheControl',
      'contentDisposition',
      'contentEncoding',
      'contentLanguage'
    ];
    Map<String, String> customMetadata = Map<String, String>.from(metadata)
      ..removeWhere((key, value) => smk.contains(key));
    object.metadata = customMetadata;

    await storageApi.objects.patch(object, bucket, path);
  }

  @override
  Future<void> delete(String bucket, String path) => storageApi.objects.delete(
        bucket,
        path,
      );
}

class GoogleCloudFirestoreDatabase extends FirestoreDatabase {
  final FirestoreApi api;
  final http.Client client;
  final String project;
  final String database;

  GoogleCloudFirestoreDatabase(this.api, this.client, this.project,
      {this.database = "(default)"});

  /// To use Firestore, you need to either make sure
  /// you are running in a google cloud environment or provide a service account key file.
  ///
  /// <br/>
  ///
  /// If you are not running on google and want to easily test ensure the following
  /// environment variables are set when running. (in intellij, you can set them in the run configuration)
  /// 1. `GCP_PROJECT=<project_id>`
  /// 2. `GOOGLE_APPLICATION_CREDENTIALS=<path_to_service_account_key.json>`
  ///
  /// <br/>
  ///
  /// If you need a custom database name, other than "(default)", or custom auth provider: copy the source
  /// of this class then modify the create() call in onStart() to pass the custom database name or custom auth
  static Future<FirestoreDatabase> create(
      {AuthClient? auth, String database = "(default)"}) async {
    Future<String> projectId = computeProjectId();
    Future<AuthClient> authClient = auth == null
        ? clientViaApplicationDefaultCredentials(
            scopes: [FirestoreApi.datastoreScope])
        : Future.value(auth);
    final resolvedAuthClient = await authClient;
    return GoogleCloudFirestoreDatabase(
        FirestoreApi(resolvedAuthClient), resolvedAuthClient, await projectId,
        database: database);
  }

  String get _dbx => "projects/$project/databases/$database";
  String get _dx => "$_dbx/documents";

  ProjectsDatabasesDocumentsResource get _documents =>
      api.projects.databases.documents;

  @override
  Future<int> countDocumentsInCollection(CollectionReference reference) async {
    final response = await _postFirestoreJson(
      '${_queryParentPath(reference)}:runAggregationQuery',
      body: {
        'structuredAggregationQuery': {
          'structuredQuery': reference.toQueryJson,
          'aggregations': [
            {
              'alias': 'count',
              'count': {
                if (reference.qLimit != null)
                  'upTo': reference.qLimit.toString(),
              },
            },
          ],
        },
      },
    );

    final aggregateFields = _firstAggregationFields(response);
    return int.parse(
      (aggregateFields['count'] as Map<String, dynamic>)['integerValue']
          as String,
    );
  }

  @override
  Future<double> sumDocumentsInCollection(
    CollectionReference reference,
    String field,
  ) async {
    final response = await _postFirestoreJson(
      '${_queryParentPath(reference)}:runAggregationQuery',
      body: {
        'structuredAggregationQuery': {
          'structuredQuery': reference.toQueryJson,
          'aggregations': [
            {
              'alias': 'sum',
              'sum': {
                'field': {'fieldPath': field},
              },
            },
          ],
        },
      },
    );

    final aggregateFields = _firstAggregationFields(response);
    final value = aggregateFields['sum'] as Map<String, dynamic>?;
    if (value == null) {
      return 0.0;
    }

    if (value['integerValue'] != null) {
      return int.parse(value['integerValue'] as String).toDouble();
    }

    return (value['doubleValue'] as num?)?.toDouble() ?? 0.0;
  }

  @override
  Future<List<DocumentSnapshot>> getDocumentsInCollection(
      CollectionReference reference) async {
    final response = await _postFirestoreJson(
      '${_queryParentPath(reference)}:runQuery',
      body: {
        'structuredQuery': reference.toQueryJson,
      },
    );

    return (response as List)
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .where((entry) => entry['document'] is Map)
        .map((entry) => Map<String, dynamic>.from(entry['document'] as Map))
        .where(_documentExists)
        .map((document) => _documentSnapshotFromJson(
              reference.doc((document['name'] as String).split('/').last),
              document,
            ))
        .toList();
  }

  @override
  Future<void> updateDocumentAtomic(
    DocumentReference ref,
    Map<String, dynamic> Function(DocumentData? data) txn,
  ) async {
    String txnId =
        (await _documents.beginTransaction(BeginTransactionRequest(), _dbx))
            .transaction!;

    final current = await _getDocumentData(
      ref.path,
      transaction: txnId,
      allowMissing: true,
    );

    Map<String, dynamic> patch = txn(current);

    if (patch.isEmpty) {
      await _commitWrites(
        const [],
        transaction: txnId,
      );
      return;
    }

    await _commitWrites(
      _buildUpdateWrites(ref.path, patch, atomic: false),
      transaction: txnId,
    );
  }

  @override
  Future<void> setDocumentAtomic(DocumentReference ref,
      DocumentData Function(DocumentData? data) txn) async {
    String txnId =
        (await _documents.beginTransaction(BeginTransactionRequest(), _dbx))
            .transaction!;

    final current = await _getDocumentData(ref.path,
        transaction: txnId, allowMissing: true);

    await _commitWrites(
      [
        {
          'update': {
            'name': '$_dx/${ref.path}',
            'fields': _toFirestoreFieldsJson(txn(current)),
          },
        },
      ],
      transaction: txnId,
    );
  }

  @override
  Future<void> deleteDocument(DocumentReference path) => _commitWrites([
        {
          'delete': '$_dx/${path.path}',
        },
      ]);

  @override
  Future<DocumentSnapshot> getDocument(DocumentReference ref,
      {bool cached = false}) async {
    try {
      final document = await _getDocumentJson(ref.path);
      return _documentSnapshotFromJson(ref, document);
    } catch (e) {
      if (e is _FirestoreRestException && e.statusCode == 404) {
        return DocumentSnapshot(ref, null);
      }
      return DocumentSnapshot(ref, null);
    }
  }

  @override
  Future<void> setDocument(DocumentReference ref, DocumentData data) =>
      _commitWrites([
        {
          'update': {
            'name': '$_dx/${ref.path}',
            'fields': _toFirestoreFieldsJson(data),
          },
        },
      ]);

  @override
  Stream<DocumentSnapshot> streamDocument(DocumentReference ref) =>
      throw UnimplementedError(
          "streamDocument not supported using Firestore REST apis through google cloud");

  @override
  Stream<List<DocumentSnapshot>> streamDocumentsInCollection(
          CollectionReference reference) =>
      throw UnimplementedError(
          "streamDocumentsInCollection not supported using Firestore REST apis through google cloud");

  @override
  Future<void> updateDocument(
          DocumentReference ref, Map<String, dynamic> data) =>
      _commitWrites(_buildUpdateWrites(ref.path, data));

  @override
  Future<DocumentSnapshot> getDocumentCachedOnly(DocumentReference ref) =>
      Future.value(DocumentSnapshot(ref, null));

  String _queryParentPath(CollectionReference reference) =>
      reference.path.contains('/') ? '$_dx/${reference.parent.path}' : _dx;

  Future<dynamic> _postFirestoreJson(
    String path, {
    required Map<String, dynamic> body,
    Map<String, String>? queryParameters,
  }) =>
      _requestFirestoreJson(
        'POST',
        path,
        body: body,
        queryParameters: queryParameters,
      );

  Future<dynamic> _requestFirestoreJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
  }) async {
    final filteredQueryParameters = {
      for (final entry in (queryParameters ?? const {}).entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    };
    final baseUri = Uri.parse(
      'https://firestore.googleapis.com/v1/${Uri.encodeFull(path)}',
    );
    final uri = filteredQueryParameters.isEmpty
        ? baseUri
        : baseUri.replace(queryParameters: filteredQueryParameters);

    final response = switch (method) {
      'GET' => await client.get(uri),
      'POST' => await client.post(
          uri,
          headers: {'content-type': 'application/json'},
          body: body == null ? null : convert.jsonEncode(body),
        ),
      _ => throw UnsupportedError('Unsupported Firestore method: $method'),
    };

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _FirestoreRestException(
        method: method,
        uri: uri,
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    if (response.body.isEmpty) {
      return null;
    }

    return convert.jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> _getDocumentJson(
    String path, {
    String? transaction,
    bool allowMissing = false,
  }) async {
    try {
      final response = await _requestFirestoreJson(
        'GET',
        '$_dx/$path',
        queryParameters: {
          if (transaction != null) 'transaction': transaction,
        },
      );

      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      if (allowMissing && e is _FirestoreRestException && e.statusCode == 404) {
        return {};
      }

      rethrow;
    }
  }

  Future<DocumentData?> _getDocumentData(
    String path, {
    String? transaction,
    bool allowMissing = false,
  }) async {
    final document = await _getDocumentJson(
      path,
      transaction: transaction,
      allowMissing: allowMissing,
    );

    return document.isEmpty ? null : _documentDataFromJson(document);
  }

  Future<void> _commitWrites(
    List<Map<String, dynamic>> writes, {
    String? transaction,
  }) =>
      _postFirestoreJson(
        '$_dbx/documents:commit',
        body: {
          'writes': writes,
          if (transaction != null) 'transaction': transaction,
        },
      );

  List<Map<String, dynamic>> _buildUpdateWrites(
    String path,
    Map<String, dynamic> data, {
    bool atomic = true,
  }) {
    final mask = <String>[
      ...data.entries.where((e) => e.value is! FieldValue).map((e) => e.key),
      ...data.entries
          .where((e) =>
              e.value is FieldValue &&
              (e.value as FieldValue).type == FieldValueType.delete)
          .map((e) => e.key),
    ];

    final hasTransforms = data.values
        .any((e) => e is FieldValue && e.type != FieldValueType.delete);
    final hasUpdateOrDelete = data.values
        .any((e) => e is! FieldValue || e.type == FieldValueType.delete);
    final precondition = atomic ? <String, dynamic>{'exists': true} : null;
    final writes = <Map<String, dynamic>>[];

    if (hasTransforms) {
      writes.add({
        'transform': {
          'document': '$_dx/$path',
          'fieldTransforms': [
            for (final entry in data.entries.where((e) =>
                e.value is FieldValue &&
                (e.value as FieldValue).type != FieldValueType.delete))
              _fieldTransformJson(entry.key, entry.value as FieldValue),
          ],
        },
        if (precondition != null) 'currentDocument': precondition,
      });
    }

    if (hasUpdateOrDelete) {
      writes.add({
        'updateMask': {
          'fieldPaths': mask,
        },
        'update': {
          'name': '$_dx/$path',
          'fields': _buildNestedFieldsJson(
            Map<String, dynamic>.fromEntries(
              data.entries.where((e) => e.value is! FieldValue),
            ),
          ),
        },
        if (precondition != null) 'currentDocument': precondition,
      });
    }

    return writes;
  }

  Map<String, dynamic> _fieldTransformJson(String path, FieldValue value) =>
      switch (value.type) {
        FieldValueType.serverTimestamp => {
            'fieldPath': path,
            'setToServerValue': 'REQUEST_TIME',
          },
        FieldValueType.arrayUnion => {
            'fieldPath': path,
            'appendMissingElements': {
              'values': value.elements!.map(_toFirestoreValueJson).toList(),
            },
          },
        FieldValueType.arrayRemove => {
            'fieldPath': path,
            'removeAllFromArray': {
              'values': value.elements!.map(_toFirestoreValueJson).toList(),
            },
          },
        FieldValueType.increment => {
            'fieldPath': path,
            'increment': _toFirestoreValueJson(value.elements!.first),
          },
        FieldValueType.decrement => {
            'fieldPath': path,
            'increment': _toFirestoreValueJson(
              -(value.elements!.first as num),
            ),
          },
        FieldValueType.delete => throw ArgumentError(
            'Delete field values are not transforms.',
          ),
      };

  Map<String, dynamic> _buildNestedFieldsJson(Map<String, dynamic> flatData) {
    final root = <String, dynamic>{};

    for (final entry in flatData.entries) {
      final segments = entry.key.split('.');
      var current = root;

      for (var i = 0; i < segments.length - 1; i++) {
        final segment = segments[i];
        current = (current.putIfAbsent(
                segment,
                () => {
                      'mapValue': {'fields': <String, dynamic>{}},
                    }) as Map<String, dynamic>)['mapValue']['fields']
            as Map<String, dynamic>;
      }

      current[segments.last] = _toFirestoreValueJson(entry.value);
    }

    return root;
  }

  Map<String, dynamic> _firstAggregationFields(dynamic response) {
    final results = (response as List)
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .where((entry) => entry['result'] is Map)
        .map((entry) => Map<String, dynamic>.from(entry['result'] as Map))
        .where((entry) => entry['aggregateFields'] is Map);

    if (results.isEmpty) {
      return const {};
    }

    return Map<String, dynamic>.from(
      results.first['aggregateFields'] as Map,
    );
  }

  DocumentSnapshot _documentSnapshotFromJson(
    DocumentReference ref,
    Map<String, dynamic> document,
  ) =>
      DocumentSnapshot(
        ref,
        _documentDataFromJson(document),
        metadata: document,
      );
}

extension _XClause on Clause {
  Map<String, dynamic> get toFilterJson => {
        'field': {'fieldPath': field},
        'op': operator.op,
        'value': _toFirestoreValueJson(value),
      };
}

extension _XCollectionReference on CollectionReference {
  Map<String, dynamic> get toQueryJson => {
        'from': [
          {'collectionId': id},
        ],
        if (qLimit != null) 'limit': qLimit,
        if (qStartAtValues != null)
          'startAt': {
            'values': qStartAtValues!.map(_toFirestoreValueJson).toList(),
            'before': false,
          }
        else if (qStartAfterValues != null)
          'startAt': {
            'values': qStartAfterValues!.map(_toFirestoreValueJson).toList(),
            'before': true,
          }
        else if (qStartAt?.data != null)
          'startAt': {
            'values':
                qStartAt!.data!.values.map(_toFirestoreValueJson).toList(),
            'before': false,
          }
        else if (qStartAfter?.data != null)
          'startAt': {
            'values':
                qStartAfter!.data!.values.map(_toFirestoreValueJson).toList(),
            'before': true,
          },
        if (qEndAtValues != null)
          'endAt': {
            'values': qEndAtValues!.map(_toFirestoreValueJson).toList(),
            'before': true,
          }
        else if (qEndBeforeValues != null)
          'endAt': {
            'values': qEndBeforeValues!.map(_toFirestoreValueJson).toList(),
            'before': false,
          }
        else if (qEndAt?.data != null)
          'endAt': {
            'values': qEndAt!.data!.values.map(_toFirestoreValueJson).toList(),
            'before': true,
          }
        else if (qEndBefore?.data != null)
          'endAt': {
            'values':
                qEndBefore!.data!.values.map(_toFirestoreValueJson).toList(),
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

extension _XFieldOp on ClauseOperator {
  String get op => switch (this) {
        ClauseOperator.lessThan => "LESS_THAN",
        ClauseOperator.lessThanOrEqual => "LESS_THAN_OR_EQUAL",
        ClauseOperator.greaterThan => "GREATER_THAN",
        ClauseOperator.greaterThanOrEqual => "GREATER_THAN_OR_EQUAL",
        ClauseOperator.equal => "EQUAL",
        ClauseOperator.arrayContains => "ARRAY_CONTAINS",
        // TODO: Verify these (below) actually work unverified
        ClauseOperator.notEqual => "NOT_EQUAL",
        ClauseOperator.arrayContainsAny => "ARRAY_CONTAINS_ANY",
        ClauseOperator.isIn => "IN",
        ClauseOperator.notIn => "NOT_IN",
      };
}

Map<String, dynamic> _toFirestoreValueJson(dynamic value) {
  if (value == null) {
    return {'nullValue': 'NULL_VALUE'};
  }

  return switch (value) {
    VectorValue _ => {
        'vectorValue': {
          'values': value.toArray(),
        },
      },
    String _ => {'stringValue': value},
    int _ => {'integerValue': value.toString()},
    double _ => {'doubleValue': value},
    bool _ => {'booleanValue': value},
    List _ => {
        'arrayValue': {
          'values': value.map(_toFirestoreValueJson).toList(),
        },
      },
    Map _ => {
        'mapValue': {
          'fields': Map<String, dynamic>.fromEntries(
            value.entries.map(
              (entry) => MapEntry(
                entry.key as String,
                _toFirestoreValueJson(entry.value),
              ),
            ),
          ),
        },
      },
    _ => throw Exception('Unsupported type: ${value.runtimeType}'),
  };
}

dynamic _fromFirestoreValueJson(Map<String, dynamic> value) {
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
  if (value['arrayValue'] != null) {
    final array = Map<String, dynamic>.from(value['arrayValue'] as Map);
    return ((array['values'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => _fromFirestoreValueJson(Map<String, dynamic>.from(item)))
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
                _fromFirestoreValueJson(
                  Map<String, dynamic>.from(entry.value as Map),
                ),
              ),
            ),
          )
        : <String, dynamic>{};
  }

  throw Exception('Unsupported type: $value');
}

Map<String, dynamic> _toFirestoreFieldsJson(Map<String, dynamic> data) =>
    Map<String, dynamic>.fromEntries(
      data.entries.map(
        (entry) => MapEntry(entry.key, _toFirestoreValueJson(entry.value)),
      ),
    );

Map<String, dynamic>? _documentDataFromJson(Map<String, dynamic> document) {
  final fields = document['fields'];
  if (fields is! Map) {
    return null;
  }

  return Map<String, dynamic>.fromEntries(
    fields.entries.map(
      (entry) => MapEntry(
        entry.key as String,
        _fromFirestoreValueJson(Map<String, dynamic>.from(entry.value as Map)),
      ),
    ),
  );
}

bool _documentExists(Map<String, dynamic> document) =>
    document['fields'] != null;

class _FirestoreRestException implements Exception {
  final String method;
  final Uri uri;
  final int statusCode;
  final String body;

  const _FirestoreRestException({
    required this.method,
    required this.uri,
    required this.statusCode,
    required this.body,
  });

  @override
  String toString() =>
      'Firestore request failed [$statusCode] $method $uri: $body';
}
