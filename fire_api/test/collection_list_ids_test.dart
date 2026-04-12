import 'package:fire_api/fire_api.dart';
import 'package:test/test.dart';

void main() {
  group('CollectionReference.listIds', () {
    test('streams ids in batches until the query is exhausted', () async {
      final db = _FakeFirestoreDatabase(
        collections: {
          'items': ['a', 'b', 'c', 'd', 'e'],
        },
      );

      final ids = await db.collection('items').listIds(batchSize: 2).toList();

      expect(ids, ['a', 'b', 'c', 'd', 'e']);
      expect(db.getCollectionCalls, 3);
    });

    test('respects an existing query limit while paging', () async {
      final db = _FakeFirestoreDatabase(
        collections: {
          'items': ['a', 'b', 'c', 'd', 'e'],
        },
      );

      final ids =
          await db.collection('items').limit(3).listIds(batchSize: 2).toList();

      expect(ids, ['a', 'b', 'c']);
      expect(db.getCollectionCalls, 2);
    });

    test('rejects a non-positive batch size', () async {
      final db = _FakeFirestoreDatabase(
        collections: {
          'items': ['a'],
        },
      );

      await expectLater(
        () => db.collection('items').listIds(batchSize: 0).drain<void>(),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

class _FakeFirestoreDatabase extends FirestoreDatabase {
  final Map<String, Map<String, DocumentData>> _documentsByCollection = {};
  final Map<String, List<String>> _documentOrderByCollection = {};
  int getCollectionCalls = 0;

  _FakeFirestoreDatabase({
    required Map<String, List<String>> collections,
  }) {
    for (final entry in collections.entries) {
      _documentOrderByCollection[entry.key] = List<String>.from(entry.value);
      _documentsByCollection[entry.key] = {
        for (final id in entry.value)
          id: {
            'value': id,
          },
      };
    }
  }

  @override
  Future<int> countDocumentsInCollection(CollectionReference reference) =>
      Future.value(_queryDocuments(reference).length);

  @override
  Future<void> deleteDocument(DocumentReference path) => Future.value();

  @override
  Future<DocumentSnapshot> getDocument(DocumentReference ref,
      {bool cached = false}) {
    final collectionPath = _collectionPathFor(ref.path);
    final data = _documentsByCollection[collectionPath]?[ref.id];
    return Future.value(
      DocumentSnapshot(
        ref,
        data == null ? null : Map<String, dynamic>.from(data),
        metadata: ref.id,
      ),
    );
  }

  @override
  Future<DocumentSnapshot> getDocumentCachedOnly(DocumentReference ref) =>
      getDocument(ref, cached: true);

  @override
  Future<List<DocumentSnapshot>> getDocumentsInCollection(
      CollectionReference reference) async {
    getCollectionCalls++;
    final documents = _queryDocuments(reference);
    final limit = reference.qLimit;
    final limitedDocuments =
        limit == null ? documents : documents.take(limit).toList();

    return limitedDocuments
        .map(
          (entry) => DocumentSnapshot(
            reference.doc(entry.key),
            Map<String, dynamic>.from(entry.value),
            metadata: entry.key,
          ),
        )
        .toList();
  }

  List<MapEntry<String, DocumentData>> _queryDocuments(
      CollectionReference reference) {
    final order =
        _documentOrderByCollection[reference.path] ?? const <String>[];
    final documents = _documentsByCollection[reference.path] ??
        const <String, DocumentData>{};
    final startAfterId = reference.qStartAfter?.id;

    var include = startAfterId == null;
    final matches = <MapEntry<String, DocumentData>>[];

    for (final id in order) {
      if (!include) {
        if (id == startAfterId) {
          include = true;
        }
        continue;
      }

      final data = documents[id];
      if (data == null) {
        continue;
      }

      matches.add(MapEntry(id, data));
    }

    return matches;
  }

  String _collectionPathFor(String documentPath) => documentPath
      .split('/')
      .sublist(0, documentPath.split('/').length - 1)
      .join('/');

  @override
  Future<List<DocumentSnapshot>> getNearestDocumentsInCollection(
          VectorQueryReference reference) =>
      Future.value(const []);

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
