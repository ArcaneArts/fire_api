import 'package:fire_api/fire_api.dart';
import 'package:test/test.dart';

void main() {
  group('CollectionReference.deleteAll', () {
    test('deletes the collection in batches until empty', () async {
      final db = _FakeFirestoreDatabase(
        collections: {
          'items': ['a', 'b', 'c', 'd', 'e'],
        },
      );

      await db.collection('items').deleteAll(batchSize: 2);

      expect(db.remainingIds('items'), isEmpty);
      expect(db.countCalls, 1);
      expect(db.getCollectionCalls, 3);
      expect(db.docGetCalls, 0);
      expect(db.deletedIds, ['a', 'b', 'c', 'd', 'e']);
    });

    test(
        'deletes only matching ids without scanning the whole collection when possible',
        () async {
      final db = _FakeFirestoreDatabase(
        collections: {
          'items': ['a', 'b', 'c', 'd'],
        },
      );

      await db.collection('items').deleteAll(
        only: {'b', 'missing'},
        batchSize: 1,
      );

      expect(db.remainingIds('items'), ['a', 'c', 'd']);
      expect(db.countCalls, 1);
      expect(db.getCollectionCalls, 0);
      expect(db.docGetCalls, 2);
      expect(db.docGetIds, unorderedEquals(['b', 'missing']));
      expect(db.deletedIds, ['b']);
    });

    test('rejects a non-positive batch size', () async {
      final db = _FakeFirestoreDatabase(
        collections: {
          'items': ['a'],
        },
      );

      await expectLater(
        () => db.collection('items').deleteAll(batchSize: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

class _FakeFirestoreDatabase extends FirestoreDatabase {
  final Map<String, Map<String, DocumentData>> _documentsByCollection = {};
  final Map<String, List<String>> _documentOrderByCollection = {};
  final List<String> deletedIds = [];
  final List<String> docGetIds = [];
  int countCalls = 0;
  int getCollectionCalls = 0;
  int docGetCalls = 0;

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

  List<String> remainingIds(String path) {
    final order = _documentOrderByCollection[path] ?? const <String>[];
    final documents =
        _documentsByCollection[path] ?? const <String, DocumentData>{};
    return order.where(documents.containsKey).toList();
  }

  @override
  Future<int> countDocumentsInCollection(CollectionReference reference) async {
    countCalls++;
    return _queryDocuments(reference).length;
  }

  @override
  Future<void> deleteDocument(DocumentReference path) async {
    final collectionPath = _collectionPathFor(path.path);
    final id = path.id;
    final removed = _documentsByCollection[collectionPath]?.remove(id);
    if (removed != null) {
      deletedIds.add(id);
    }
  }

  @override
  Future<DocumentSnapshot> getDocument(DocumentReference ref,
      {bool cached = false}) async {
    docGetCalls++;
    docGetIds.add(ref.id);

    final collectionPath = _collectionPathFor(ref.path);
    final data = _documentsByCollection[collectionPath]?[ref.id];
    return DocumentSnapshot(
      ref,
      data == null ? null : Map<String, dynamic>.from(data),
      metadata: ref.id,
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
