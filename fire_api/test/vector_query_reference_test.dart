import 'package:fire_api/fire_api.dart';
import 'package:test/test.dart';

void main() {
  group('VectorQueryReference', () {
    test('findNearest returns ranked vector query snapshots', () async {
      _FakeFirestoreDatabase db = _FakeFirestoreDatabase();
      CollectionReference reference =
          db.collection('items').whereEqual('color', 'red');

      List<VectorQueryDocumentSnapshot> results = await reference
          .findNearest(
            vectorField: 'embedding_field',
            queryVector: const VectorValue([1, 2, 3]),
            limit: 3,
            distanceMeasure: VectorDistanceMeasure.euclidean,
            distanceResultField: 'vector_distance',
          )
          .get();

      expect(db.lastVectorQuery, isNotNull);
      expect(db.lastVectorQuery!.reference.path, 'items');
      expect(db.lastVectorQuery!.vectorField, 'embedding_field');
      expect(db.lastVectorQuery!.limit, 3);
      expect(
          db.lastVectorQuery!.distanceMeasure, VectorDistanceMeasure.euclidean);
      expect(db.lastVectorQuery!.distanceResultField, 'vector_distance');
      expect(results, hasLength(1));
      expect(results.single, isA<VectorQueryDocumentSnapshot>());
      expect(results.single.id, 'item-1');
      expect(results.single.rank, 1);
      expect(results.single.score, 0.25);
      expect(results.single.scoreField, 'vector_distance');
      expect(results.single.data!['vector_distance'], 0.25);
    });

    test('findNearest captures score without exposing the implicit score field',
        () async {
      _FakeFirestoreDatabase db = _FakeFirestoreDatabase();

      List<VectorQueryDocumentSnapshot> results = await db
          .collection('items')
          .findNearest(
            vectorField: 'embedding_field',
            queryVector: const VectorValue([1, 2, 3]),
            limit: 3,
            distanceMeasure: VectorDistanceMeasure.euclidean,
          )
          .get();

      expect(results, hasLength(1));
      expect(results.single.rank, 1);
      expect(results.single.score, 0.25);
      expect(results.single.scoreField, isNull);
      expect(
        results.single.data!.containsKey(
          VectorQueryReference.implicitDistanceResultField,
        ),
        isFalse,
      );
    });

    test('findNearest rejects CollectionReference.limit', () {
      _FakeFirestoreDatabase db = _FakeFirestoreDatabase();

      expect(
        () => db.collection('items').limit(10).findNearest(
              vectorField: 'embedding_field',
              queryVector: const VectorValue([1, 2, 3]),
              limit: 3,
              distanceMeasure: VectorDistanceMeasure.euclidean,
            ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

class _FakeFirestoreDatabase extends FirestoreDatabase {
  VectorQueryReference? lastVectorQuery;

  @override
  Future<int> countDocumentsInCollection(CollectionReference reference) =>
      Future.value(0);

  @override
  Future<void> deleteDocument(DocumentReference path) => Future.value();

  @override
  Future<DocumentSnapshot> getDocument(DocumentReference ref,
          {bool cached = false}) =>
      Future.value(DocumentSnapshot(ref, null));

  @override
  Future<DocumentSnapshot> getDocumentCachedOnly(DocumentReference ref) =>
      Future.value(DocumentSnapshot(ref, null));

  @override
  Future<List<DocumentSnapshot>> getDocumentsInCollection(
          CollectionReference reference) =>
      Future.value(const []);

  @override
  Future<List<DocumentSnapshot>> getNearestDocumentsInCollection(
      VectorQueryReference reference) {
    lastVectorQuery = reference;
    return Future.value([
      DocumentSnapshot(
        reference.reference.doc('item-1'),
        {
          reference.resolvedDistanceResultField: 0.25,
        },
      ),
    ]);
  }

  @override
  Future<void> setDocument(DocumentReference ref, DocumentData data) =>
      Future.value();

  @override
  Future<void> setDocumentAtomic(DocumentReference ref,
          DocumentData Function(DocumentData? data) txn) =>
      Future.value();

  @override
  Stream<DocumentSnapshot> streamDocument(DocumentReference ref) =>
      const Stream.empty();

  @override
  Stream<List<DocumentSnapshot>> streamDocumentsInCollection(
          CollectionReference reference) =>
      const Stream.empty();

  @override
  Future<double> sumDocumentsInCollection(
          CollectionReference reference, String field) =>
      Future.value(0);

  @override
  Future<void> updateDocument(DocumentReference ref, DocumentData data) =>
      Future.value();

  @override
  Future<void> updateDocumentAtomic(DocumentReference ref,
          Map<String, dynamic> Function(DocumentData? data) txn) =>
      Future.value();
}
