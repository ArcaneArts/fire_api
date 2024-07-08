library fire_api_dart;

import 'package:fire_api/fire_api.dart';
import 'package:google_cloud/google_cloud.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';

class GoogleCloudFirestoreDatabase extends FirestoreDatabase {
  final FirestoreApi api;
  final String project;
  final String database;

  GoogleCloudFirestoreDatabase(this.api, this.project,
      {this.database = "(default)"});

  /// To use Firestore, you need to either make sure
  /// you are running in a google cloud environment or provide a service account key file.
  ///
  /// <br/>
  ///
  /// If you are not running on google and want to easily test ensure the following
  /// environment variables are set when running. (in intellij, you can set them in the run configuration)
  /// 1. GCP_PROJECT=<project_id>
  /// 2. GOOGLE_APPLICATION_CREDENTIALS=<path_to_service_account_key.json>
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
    return GoogleCloudFirestoreDatabase(
        FirestoreApi(await authClient), await projectId,
        database: database);
  }

  String get _dbx => "projects/$project/databases/$database";
  String get _dx => "$_dbx/documents";

  ProjectsDatabasesDocumentsResource get _documents =>
      api.projects.databases.documents;

  @override
  Future<int> countDocumentsInCollection(CollectionReference reference) =>
      _documents
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
              _dbx)
          .then((r) => int.parse(
              r.first.result!.aggregateFields!["count"]!.integerValue!));

  @override
  Future<List<DocumentSnapshot>> getDocumentsInCollection(
          CollectionReference reference) =>
      _documents
          .runQuery(
              RunQueryRequest(
                structuredQuery: reference.toQuery,
              ),
              _dx)
          .then((r) => r
              .map((i) => DocumentSnapshot(
                  reference.doc(i.document!.name!.split("/").last),
                  i.document!.data,
                  metadata: i.document!))
              .toList());

  @override
  Future<void> setDocumentAtomic(DocumentReference ref,
      DocumentData Function(DocumentData? data) txn) async {
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
  }

  @override
  Future<void> deleteDocument(DocumentReference path) => _documents.commit(
      CommitRequest(writes: [Write(delete: "$_dx/${path.path}")]), _dbx);

  @override
  Future<DocumentSnapshot> getDocument(DocumentReference ref,
      {bool cached = false}) async {
    try {
      Document d = await _documents.get("$_dx/${ref.path}");
      return DocumentSnapshot(ref, d.data, metadata: d);
    } catch (e) {
      return DocumentSnapshot(ref, null);
    }
  }

  @override
  Future<void> setDocument(DocumentReference ref, DocumentData data) =>
      _documents.commit(
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
  Future<void> updateDocument(DocumentReference ref, DocumentData data) =>
      _documents.commit(
          CommitRequest(writes: [
            if (data.values.any((e) => e is FieldValue))
              Write(
                transform: DocumentTransform(
                  document: "$_dx/${ref.path}",
                  fieldTransforms: [
                    ...data.entries
                        .where((e) => e.value is FieldValue)
                        .map((e) {
                      FieldValue fv = e.value as FieldValue;
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
                        removeAllFromArray:
                            fv.type == FieldValueType.arrayRemove
                                ? ArrayValue(
                                    values: fv.elements!.map(_toValue).toList())
                                : null,
                        increment: fv.type == FieldValueType.increment
                            ? Value(
                                integerValue: fv.elements![0]! is int
                                    ? fv.elements![0].toString()
                                    : null,
                                doubleValue: fv.elements![0]! is! int
                                    ? (fv.elements![0] as num).toDouble()
                                    : null,
                              )
                            : fv.type == FieldValueType.decrement
                                ? Value(
                                    integerValue: fv.elements![0]! is int
                                        ? (-(fv.elements![0] as int)).toString()
                                        : null,
                                    doubleValue: fv.elements![0]! is! int
                                        ? -(fv.elements![0] as num).toDouble()
                                        : null,
                                  )
                                : null,
                      );
                    })
                  ],
                ),
              ),
            if (data.values.any((e) => e is! FieldValue))
              Write(
                updateMask: DocumentMask(
                    fieldPaths: data.entries
                        .where((e) => e.value is! FieldValue)
                        .map((e) => e.key)
                        .toList()),
                update: Document(
                  name: "$_dx/${ref.path}",
                  fields: Map.fromEntries(
                          data.entries.where((e) => e.value is! FieldValue))
                      ._toValueMap(),
                ),
              ),
          ]),
          _dbx);

  @override
  Future<DocumentSnapshot> getDocumentCachedOnly(DocumentReference ref) =>
      Future.value(DocumentSnapshot(ref, null));
}

extension _XClause on Clause {
  FieldFilter get toFilter => FieldFilter(
        field: FieldReference(fieldPath: field),
        op: operator.op,
        value: _toValue(value),
      );
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

dynamic _fromValue(Value v) {
  if (v.nullValue != null) return null;
  if (v.stringValue != null) return v.stringValue;
  if (v.integerValue != null) return int.tryParse(v.integerValue!) ?? 0;
  if (v.doubleValue != null) return v.doubleValue;
  if (v.booleanValue != null) return v.booleanValue;
  if (v.arrayValue != null) {
    return v.arrayValue?.values?.map(_fromValue).toList();
  }
  if (v.mapValue != null) return v.mapValue?.fields?._toDynamicMap();
  throw Exception("Unsupported type: ${v.toJson()}");
}

Value _toValue(dynamic v) {
  return v == null
      ? Value(nullValue: "NULL_VALUE")
      : switch (v) {
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

extension _XMapStringVal on Map<String, Value> {
  Map<String, dynamic> _toDynamicMap() =>
      map((k, v) => MapEntry(k, _fromValue(v)));
}

extension _XMapStringDyn on Map<String, dynamic> {
  Map<String, Value> _toValueMap() => map((k, v) => MapEntry(k, _toValue(v)));
}

extension _XPathString on String {
  String? get parent => contains("/")
      ? split("/").sublist(0, split("/").length - 1).join("/")
      : null;
}

extension _XDocument on Document {
  bool get exists => fields != null;

  Map<String, dynamic>? get data => fields?._toDynamicMap();
}
