import 'package:fire_api/fire_api.dart';
import 'package:test/test.dart';

void main() {
  group('VectorQueryReference', () {
    test('findNearest returns a get-only vector query wrapper', () async {
      final db = _FakeFirestoreDatabase();
      final reference = db.collection('items').whereEqual('color', 'red');

      final results = await reference
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
      expect(results.single.id, 'item-1');
    });

    test('findNearest rejects CollectionReference.limit', () {
      final db = _FakeFirestoreDatabase();

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
        {'vector_distance': 0.25},
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
