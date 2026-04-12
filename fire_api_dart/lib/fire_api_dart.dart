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
  final http.Client? client;
  final String project;
  final String database;

  GoogleCloudFirestoreDatabase(this.api, this.project,
      {this.client, this.database = "(default)"});

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
        FirestoreApi(resolvedAuthClient), await projectId,
        client: resolvedAuthClient, database: database);
  }

  String get _dbx => "projects/$project/databases/$database";
  String get _dx => "$_dbx/documents";

  ProjectsDatabasesDocumentsResource get _documents =>
      api.projects.databases.documents;

  @override
  Future<int> countDocumentsInCollection(CollectionReference reference) async {
    if (client == null) {
      return _documents
          .runAggregationQuery(
              RunAggregationQueryRequest(
                structuredAggregationQuery: StructuredAggregationQuery(
                    structuredQuery: reference.toQuery,
                    aggregations: [
                      Aggregation(
                        alias: "count",
                        count: reference.qLimit == null
                            ? Count()
                            : Count(
                                upTo: reference.qLimit!.toString(),
                              ),
                      )
                    ]),
              ),
              reference.path.contains('/')
                  ? '$_dx/${reference.parent.path}/'
                  : _dx)
          .then((r) => int.parse(
              r.first.result!.aggregateFields!["count"]!.integerValue!));
    }

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
    if (client == null) {
      return _documents
          .runAggregationQuery(
        RunAggregationQueryRequest(
          structuredAggregationQuery: StructuredAggregationQuery(
            structuredQuery: reference.toQuery,
            aggregations: <Aggregation>[
              Aggregation(
                alias: 'sum',
                sum: Sum(
                  field: FieldReference(fieldPath: field),
                ),
              ),
            ],
          ),
        ),
        reference.path.contains('/') ? '$_dx/${reference.parent.path}/' : _dx,
      )
          .then((List<RunAggregationQueryResponseElement> responses) {
        Iterable<RunAggregationQueryResponseElement> withResult =
            responses.where((r) => r.result != null);

        if (withResult.isEmpty) {
          return 0.0;
        }

        AggregationResult aggregation =
            withResult.first.result as AggregationResult;

        Value? value = aggregation.aggregateFields?['sum'];
        if (value == null) {
          return 0.0;
        }

        if (value.integerValue != null) {
          return int.parse(value.integerValue!).toDouble();
        }

        return value.doubleValue ?? 0.0;
      });
    }

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
    if (client == null) {
      return _documents
          .runQuery(
              RunQueryRequest(
                structuredQuery: reference.toQuery,
              ),
              reference.path.contains("/")
                  ? "$_dx/${reference.parent.path}/"
                  : _dx)
          .then((r) => r
              .where((i) => i.document != null && i.document!.exists)
              .map((i) => DocumentSnapshot(
                  reference.doc(i.document!.name!.split("/").last),
                  i.document!.data,
                  metadata: i.document!))
              .toList());
    }

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
  Future<List<DocumentSnapshot>> getNearestDocumentsInCollection(
      VectorQueryReference reference) async {
    try {
      if (client == null) {
        return _documents
            .runQuery(
                RunQueryRequest(
                  structuredQuery: reference.toQuery,
                ),
                reference.reference.path.contains("/")
                    ? "$_dx/${reference.reference.parent.path}/"
                    : _dx)
            .then((r) => r
                .where((i) => i.document != null && i.document!.exists)
                .map((i) => DocumentSnapshot(
                    reference.reference.doc(i.document!.name!.split("/").last),
                    i.document!.data,
                    metadata: i.document!))
                .toList());
      }

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
          .where(_documentExists)
          .map((document) => _documentSnapshotFromJson(
                reference.reference
                    .doc((document['name'] as String).split('/').last),
                document,
              ))
          .toList();
    } catch (error) {
      final indexHint = _tryBuildMissingVectorIndexErrorMessage(
        error,
        projectId: project,
        databaseId: database,
        reference: reference,
      );
      if (indexHint != null) {
        throw StateError(indexHint);
      }

      rethrow;
    }
  }

  @override
  Future<void> updateDocumentAtomic(
    DocumentReference ref,
    Map<String, dynamic> Function(DocumentData? data) txn,
  ) async {
    if (client == null) {
      String txnId =
          (await _documents.beginTransaction(BeginTransactionRequest(), _dbx))
              .transaction!;

      DocumentData? current;
      try {
        Document doc = await _documents.get(
          "$_dx/${ref.path}",
          transaction: txnId,
        );
        current = doc.data;
      } catch (_) {
        current = null;
      }

      Map<String, dynamic> patch = txn(current);

      if (patch.isEmpty) {
        await _documents.commit(
          CommitRequest(
            writes: [],
            transaction: txnId,
          ),
          _dbx,
        );
        return;
      }

      List<FieldTransform> transforms = <FieldTransform>[];
      Map<String, dynamic> directValues = <String, dynamic>{};
      List<String> mask = <String>[];

      patch.forEach((String path, dynamic value) {
        if (value is FieldValue) {
          switch (value.type) {
            case FieldValueType.serverTimestamp:
              transforms.add(FieldTransform(
                  fieldPath: path, setToServerValue: "REQUEST_TIME"));
              break;

            case FieldValueType.arrayUnion:
              transforms.add(FieldTransform(
                fieldPath: path,
                appendMissingElements: ArrayValue(
                  values: value.elements!.map(_toValue).toList(),
                ),
              ));
              break;

            case FieldValueType.arrayRemove:
              transforms.add(FieldTransform(
                fieldPath: path,
                removeAllFromArray: ArrayValue(
                  values: value.elements!.map(_toValue).toList(),
                ),
              ));
              break;

            case FieldValueType.increment:
            case FieldValueType.decrement:
              num delta = value.elements!.first;
              transforms.add(FieldTransform(
                fieldPath: path,
                increment: Value(
                  integerValue: delta is int ? delta.toString() : null,
                  doubleValue: delta is int ? null : delta.toDouble(),
                ),
              ));
              break;

            case FieldValueType.delete:
              mask.add(path);
              break;
          }
        } else {
          directValues[path] = value;
          mask.add(path);
        }
      });

      List<Write> writes = <Write>[];

      if (transforms.isNotEmpty) {
        writes.add(
          Write(
            transform: DocumentTransform(
              document: "$_dx/${ref.path}",
              fieldTransforms: transforms,
            ),
          ),
        );
      }

      if (mask.isNotEmpty) {
        writes.add(
          Write(
            updateMask: DocumentMask(fieldPaths: mask),
            update: Document(
              name: "$_dx/${ref.path}",
              fields: directValues._toValueMap(),
            ),
          ),
        );
      }

      await _documents.commit(
        CommitRequest(
          writes: writes,
          transaction: txnId,
        ),
        _dbx,
      );
      return;
    }

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
    if (client == null) {
      String txnId =
          (await _documents.beginTransaction(BeginTransactionRequest(), _dbx))
              .transaction!;
      DocumentData? data =
          (await _documents.get("$_dx/${ref.path}", transaction: txnId)).data;
      await _documents.commit(
        CommitRequest(
          writes: [
            Write(
              update: Document(
                name: "$_dx/${ref.path}",
                fields: txn(data)._toValueMap(),
              ),
            ),
          ],
          transaction: txnId,
        ),
        _dbx,
      );
      return;
    }

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
  Future<void> deleteDocument(DocumentReference path) {
    if (client == null) {
      return _documents.commit(
          CommitRequest(writes: [Write(delete: "$_dx/${path.path}")]), _dbx);
    }

    return _commitWrites([
      {
        'delete': '$_dx/${path.path}',
      },
    ]);
  }

  @override
  Future<DocumentSnapshot> getDocument(DocumentReference ref,
      {bool cached = false}) async {
    if (client == null) {
      try {
        Document d = await _documents.get("$_dx/${ref.path}");
        return DocumentSnapshot(ref, d.data, metadata: d);
      } catch (e) {
        return DocumentSnapshot(ref, null);
      }
    }

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
  Future<void> setDocument(DocumentReference ref, DocumentData data) {
    if (client == null) {
      return _documents.commit(
        CommitRequest(
          writes: [
            Write(
              update: Document(
                name: "$_dx/${ref.path}",
                fields: data._toValueMap(),
              ),
            ),
          ],
        ),
        _dbx,
      );
    }

    return _commitWrites([
      {
        'update': {
          'name': '$_dx/${ref.path}',
          'fields': _toFirestoreFieldsJson(data),
        },
      },
    ]);
  }

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
      DocumentReference ref, Map<String, dynamic> data) {
    if (client == null) {
      final mask = DocumentMask(fieldPaths: [
        ...data.entries.where((e) => e.value is! FieldValue).map((e) => e.key),
        ...data.entries
            .where((e) =>
                e.value is FieldValue &&
                (e.value as FieldValue).type == FieldValueType.delete)
            .map((e) => e.key),
      ]);

      final hasTransforms = data.values
          .any((e) => e is FieldValue && e.type != FieldValueType.delete);

      final hasUpdateOrDelete = data.values
          .any((e) => e is! FieldValue || (e.type == FieldValueType.delete));

      return _documents.commit(
        CommitRequest(writes: [
          if (hasTransforms)
            Write(
              transform: DocumentTransform(
                document: "$_dx/${ref.path}",
                fieldTransforms: [
                  ...data.entries
                      .where((e) =>
                          e.value is FieldValue &&
                          (e.value as FieldValue).type != FieldValueType.delete)
                      .map((e) {
                    final fv = e.value as FieldValue;
                    return FieldTransform(
                      fieldPath: e.key,
                      setToServerValue:
                          fv.type == FieldValueType.serverTimestamp
                              ? "REQUEST_TIME"
                              : null,
                      appendMissingElements:
                          fv.type == FieldValueType.arrayUnion
                              ? ArrayValue(
                                  values: fv.elements!.map(_toValue).toList())
                              : null,
                      removeAllFromArray: fv.type == FieldValueType.arrayRemove
                          ? ArrayValue(
                              values: fv.elements!.map(_toValue).toList())
                          : null,
                      increment: fv.type == FieldValueType.increment
                          ? Value(
                              integerValue: fv.elements![0] is int
                                  ? fv.elements![0].toString()
                                  : null,
                              doubleValue: fv.elements![0] is! int
                                  ? (fv.elements![0] as num).toDouble()
                                  : null,
                            )
                          : fv.type == FieldValueType.decrement
                              ? Value(
                                  integerValue: fv.elements![0] is int
                                      ? (-(fv.elements![0] as int)).toString()
                                      : null,
                                  doubleValue: fv.elements![0] is! int
                                      ? -(fv.elements![0] as num).toDouble()
                                      : null,
                                )
                              : null,
                    );
                  }),
                ],
              ),
              currentDocument: Precondition(exists: true),
            ),
          if (hasUpdateOrDelete)
            Write(
              updateMask: mask,
              update: Document(
                name: "$_dx/${ref.path}",
                fields: _buildTypedNestedFields(
                  Map.fromEntries(
                    data.entries.where((e) => e.value is! FieldValue),
                  ),
                ),
              ),
              currentDocument: Precondition(exists: true),
            ),
        ]),
        _dbx,
      );
    }

    return _commitWrites(_buildUpdateWrites(ref.path, data));
  }

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
    final httpClient = client;
    if (httpClient == null) {
      throw StateError(
          'A raw HTTP client is required for Firestore vector support.');
    }

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
      'GET' => await httpClient.get(uri),
      'POST' => await httpClient.post(
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
        metadata: _documentMetadataFromJson(document),
      );
}

extension _XClause on Clause {
  FieldFilter get toFilter => FieldFilter(
        field: FieldReference(fieldPath: field),
        op: operator.op,
        value: _toValue(value),
      );

  Map<String, dynamic> get toFilterJson => {
        'field': {'fieldPath': field},
        'op': operator.op,
        'value': _toFirestoreValueJson(value),
      };
}

extension _XCollectionReference on CollectionReference {
  StructuredQuery get toQuery => StructuredQuery(
      from: [CollectionSelector(collectionId: id)],
      limit: qLimit,
      startAt: qStartAtValues != null
          ? Cursor(
              values: qStartAtValues!.map((v) => _toValue(v)).toList(),
              before: false)
          : qStartAfterValues != null
              ? Cursor(
                  values: qStartAfterValues!.map((v) => _toValue(v)).toList(),
                  before: true)
              : qStartAt?.metadata is Document
                  ? Cursor(
                      values: (qStartAt!.metadata.data ?? {}).values.toList(),
                      before: false)
                  : qStartAfter?.metadata is Document
                      ? Cursor(
                          values: (qStartAfter!.metadata.data ?? {})
                              .values
                              .toList(),
                          before: true,
                        )
                      : null,
      endAt: qEndAtValues != null
          ? Cursor(
              values: qEndAtValues!.map((v) => _toValue(v)).toList(),
              before: true)
          : qEndBeforeValues != null
              ? Cursor(
                  values: qEndBeforeValues!.map((v) => _toValue(v)).toList(),
                  before: false)
              : qEndAt?.metadata is Document
                  ? Cursor(
                      values: (qEndAt!.metadata.data ?? {}).values.toList(),
                      before: true)
                  : qEndBefore?.metadata is Document
                      ? Cursor(
                          values:
                              (qEndBefore!.metadata.data ?? {}).values.toList(),
                          before: false,
                        )
                      : null,
      orderBy: qOrderBy != null
          ? [
              Order(
                direction: descending ? "DESCENDING" : "ASCENDING",
                field: FieldReference(fieldPath: qOrderBy),
              )
            ]
          : null,
      where: clauses.isNotEmpty
          ? Filter(
              compositeFilter: clauses.length > 1
                  ? CompositeFilter(
                      op: "AND",
                      filters: clauses
                          .map((e) => Filter(fieldFilter: e.toFilter))
                          .toList())
                  : null,
              fieldFilter: clauses.length == 1 ? clauses[0].toFilter : null,
            )
          : null);

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

extension _XVectorQueryReference on VectorQueryReference {
  StructuredQuery get toQuery => reference.toQuery
    ..findNearest = FindNearest(
      vectorField: FieldReference(fieldPath: vectorField),
      queryVector: _toValue(queryVector),
      limit: limit,
      distanceMeasure: distanceMeasure.firestoreValue,
      distanceResultField: distanceResultField,
      distanceThreshold: distanceThreshold,
    );

  Map<String, dynamic> get toQueryJson => {
        ...reference.toQueryJson,
        'findNearest': {
          'vectorField': {'fieldPath': vectorField},
          'queryVector': _toFirestoreValueJson(queryVector),
          'limit': limit,
          'distanceMeasure': distanceMeasure.firestoreValue,
          if (distanceResultField != null)
            'distanceResultField': distanceResultField,
          if (distanceThreshold != null) 'distanceThreshold': distanceThreshold,
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

extension _XVectorDistanceMeasure on VectorDistanceMeasure {
  String get firestoreValue => switch (this) {
        VectorDistanceMeasure.euclidean => 'EUCLIDEAN',
        VectorDistanceMeasure.cosine => 'COSINE',
        VectorDistanceMeasure.dotProduct => 'DOT_PRODUCT',
      };
}

dynamic _fromValue(Value v) {
  if (v.nullValue != null) return null;
  if (v.stringValue != null) return v.stringValue;
  if (v.integerValue != null) return int.tryParse(v.integerValue!) ?? 0;
  if (v.doubleValue != null) return v.doubleValue;
  if (v.booleanValue != null) return v.booleanValue;
  if (v.arrayValue != null) {
    return v.arrayValue?.values?.map(_fromValue).toList();
  }
  if (v.mapValue != null) {
    if (_isTypedVectorValue(v)) {
      return _decodeTypedVectorValue(v.mapValue!.fields!);
    }
    return v.mapValue?.fields?._toDynamicMap();
  }
  throw Exception("Unsupported type: ${v.toJson()}");
}

Value _toValue(dynamic v) {
  return v == null
      ? Value(nullValue: "NULL_VALUE")
      : switch (v) {
          VectorValue _ => _toTypedVectorValue(v),
          String _ => Value(stringValue: v),
          int _ => Value(integerValue: v.toString()),
          double _ => Value(doubleValue: v),
          bool _ => Value(booleanValue: v),
          List _ =>
            Value(arrayValue: ArrayValue(values: v.map(_toValue).toList())),
          Map _ => Value(
              mapValue:
                  MapValue(fields: v.map((k, v) => MapEntry(k, _toValue(v))))),
          _ => throw Exception("Unsupported type: ${v.runtimeType}"),
        };
}

Map<String, dynamic> _toFirestoreValueJson(dynamic value) {
  if (value == null) {
    return {'nullValue': 'NULL_VALUE'};
  }

  return switch (value) {
    VectorValue _ => _toFirestoreVectorValueJson(value),
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
  if (_isFirestoreVectorValueJson(value)) {
    final mapValue = Map<String, dynamic>.from(value['mapValue'] as Map);
    final fields =
        Map<String, dynamic>.from((mapValue['fields'] as Map?) ?? {});
    return _decodeFirestoreVectorFieldsJson(fields);
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

dynamic _documentMetadataFromJson(Map<String, dynamic> document) =>
    _hasLegacyVectorValue(document) ? document : Document.fromJson(document);

bool _hasLegacyVectorValue(dynamic value) {
  if (value is Map) {
    if (value.containsKey('vectorValue')) {
      return true;
    }

    return value.values.any(_hasLegacyVectorValue);
  }

  if (value is List) {
    return value.any(_hasLegacyVectorValue);
  }

  return false;
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

bool _isTypedVectorValue(Value value) {
  final fields = value.mapValue?.fields;
  return fields != null &&
      fields[_firestoreVectorTypeKey]?.stringValue ==
          _firestoreVectorTypeSentinel;
}

Value _toTypedVectorValue(VectorValue value) => Value(
      mapValue: MapValue(
        fields: {
          _firestoreVectorTypeKey:
              Value(stringValue: _firestoreVectorTypeSentinel),
          _firestoreVectorValueKey: Value(
            arrayValue: ArrayValue(
              values: value
                  .toArray()
                  .map((item) => Value(doubleValue: item.toDouble()))
                  .toList(),
            ),
          ),
        },
      ),
    );

VectorValue _decodeTypedVectorValue(Map<String, Value> fields) => VectorValue(
      ((fields[_firestoreVectorValueKey]?.arrayValue?.values) ?? const [])
          .map((item) => (_fromValue(item) as num?)?.toDouble() ?? 0.0)
          .toList(),
    );

Map<String, dynamic> _toFirestoreVectorValueJson(VectorValue value) => {
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
    };

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

VectorValue _decodeFirestoreVectorFieldsJson(Map<String, dynamic> fields) =>
    VectorValue(
      (((fields[_firestoreVectorValueKey] as Map?)?['arrayValue']
                  as Map?)?['values'] as List? ??
              const [])
          .map((item) =>
              _fromFirestoreValueJson(Map<String, dynamic>.from(item as Map))
                  as num)
          .map((item) => item.toDouble())
          .toList(),
    );

Map<String, Value> _buildTypedNestedFields(Map<String, dynamic> flatData) {
  final root = <String, Value>{};

  for (final entry in flatData.entries) {
    final segments = entry.key.split('.');
    var current = root;
    for (var i = 0; i < segments.length - 1; i++) {
      final seg = segments[i];
      if (!current.containsKey(seg) || current[seg]!.mapValue == null) {
        current[seg] = Value(mapValue: MapValue(fields: {}));
      }
      current = current[seg]!.mapValue!.fields!;
    }
    current[segments.last] = _toValue(entry.value);
  }

  return root;
}

extension _XMapStringVal on Map<String, Value> {
  Map<String, dynamic> _toDynamicMap() =>
      map((k, v) => MapEntry(k, _fromValue(v)));
}

extension _XMapStringDyn on Map<String, dynamic> {
  Map<String, Value> _toValueMap() => map((k, v) => MapEntry(k, _toValue(v)));
}

extension _XDocument on Document {
  bool get exists => fields != null;

  Map<String, dynamic>? get data => fields?._toDynamicMap();
}

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
