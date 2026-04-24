import 'package:fire_api/fire_api.dart';
import 'package:fire_api_local/fire_api_local.dart';
import 'package:test/test.dart';

void main() {
  group('LocalFirestoreDatabase index planning', () {
    late LocalFirestoreDatabase db;

    setUp(() {
      db = LocalFirestoreDatabase.memory();
    });

    tearDown(() {
      db.close();
    });

    test('uses persisted scalar indexes for equality-style filters', () async {
      for (int i = 0; i < 40; i++) {
        await db.collection('items').doc('item-$i').set(<String, dynamic>{
          'kind': i == 17 ? 'target' : 'other',
          'nested': <String, dynamic>{'group': i == 17 ? 'target' : 'other'},
          'tags': <String>[if (i == 17) 'target', 'common'],
        });
      }

      db.debugCollectionScans = 0;
      db.debugIndexCandidateReads = 0;

      List<DocumentSnapshot> equality = await db
          .collection('items')
          .whereEqual('kind', 'target')
          .get();
      List<DocumentSnapshot> nested = await db
          .collection('items')
          .whereEqual('nested.group', 'target')
          .get();
      List<DocumentSnapshot> array = await db
          .collection('items')
          .whereArrayContains('tags', 'target')
          .get();

      expect(equality.map((document) => document.id), <String>['item-17']);
      expect(nested.map((document) => document.id), <String>['item-17']);
      expect(array.map((document) => document.id), <String>['item-17']);
      expect(db.debugCollectionScans, 0);
      expect(db.debugIndexCandidateReads, 3);
    });

    test('keeps scalar indexes in sync after updates and deletes', () async {
      DocumentReference ref = db.collection('items').doc('a');
      await ref.set(<String, dynamic>{'kind': 'old'});
      await ref.update(<String, dynamic>{'kind': 'new'});

      expect(
        await db
            .collection('items')
            .whereEqual('kind', 'old')
            .get()
            .then((documents) => documents.map((document) => document.id)),
        isEmpty,
      );
      expect(
        await db
            .collection('items')
            .whereEqual('kind', 'new')
            .get()
            .then((documents) => documents.map((document) => document.id)),
        <String>['a'],
      );

      await ref.delete();

      expect(
        await db
            .collection('items')
            .whereEqual('kind', 'new')
            .get()
            .then((documents) => documents.map((document) => document.id)),
        isEmpty,
      );
    });

    test('uses persisted scalar indexes for range filters', () async {
      for (int i = 0; i < 50; i++) {
        String padded = i.toString().padLeft(2, '0');
        await db.collection('items').doc('item-$padded').set(<String, dynamic>{
          'score': i,
          'name': 'name-$padded',
        });
      }

      db.debugCollectionScans = 0;
      db.debugIndexCandidateReads = 0;

      List<DocumentSnapshot> numeric = await db
          .collection('items')
          .whereGreaterThanOrEqual('score', 45)
          .get();
      List<DocumentSnapshot> text = await db
          .collection('items')
          .whereLessThan('name', 'name-03')
          .get();

      expect(numeric.map((document) => document.id), <String>[
        'item-45',
        'item-46',
        'item-47',
        'item-48',
        'item-49',
      ]);
      expect(text.map((document) => document.id), <String>[
        'item-00',
        'item-01',
        'item-02',
      ]);
      expect(db.debugCollectionScans, 0);
      expect(db.debugIndexCandidateReads, 8);
    });

    test(
      'falls back to collection scans for unsupported range index values',
      () async {
        await db.collection('items').doc('a').set(<String, dynamic>{
          'active': false,
        });
        await db.collection('items').doc('b').set(<String, dynamic>{
          'active': true,
        });

        db.debugCollectionScans = 0;
        db.debugIndexCandidateReads = 0;

        List<DocumentSnapshot> documents = await db
            .collection('items')
            .whereGreaterThan('active', false)
            .get();

        expect(documents.map((document) => document.id), <String>['b']);
        expect(db.debugCollectionScans, 1);
        expect(db.debugIndexCandidateReads, 0);
      },
    );

    test('uses persisted scalar indexes for orderBy candidates', () async {
      await db.collection('items').doc('missing').set(<String, dynamic>{
        'name': 'missing',
      });
      await db.collection('items').doc('a').set(<String, dynamic>{'score': 2});
      await db.collection('items').doc('b').set(<String, dynamic>{'score': 1});
      await db.collection('items').doc('c').set(<String, dynamic>{'score': 3});

      db.debugCollectionScans = 0;
      db.debugIndexCandidateReads = 0;

      List<DocumentSnapshot> ascending = await db
          .collection('items')
          .orderBy('score')
          .get();
      List<DocumentSnapshot> descending = await db
          .collection('items')
          .orderBy('score', descending: true)
          .get();

      expect(ascending.map((document) => document.id), <String>['b', 'a', 'c']);
      expect(descending.map((document) => document.id), <String>[
        'c',
        'a',
        'b',
      ]);
      expect(db.debugCollectionScans, 0);
      expect(db.debugIndexCandidateReads, 6);
    });

    test('uses composite index plans for multi-clause queries', () async {
      await db.collection('items').doc('match').set(<String, dynamic>{
        'kind': 'fruit',
        'tags': <String>['red'],
        'score': 5,
      });
      await db.collection('items').doc('scalar-tag').set(<String, dynamic>{
        'kind': 'fruit',
        'tags': 'red',
        'score': 5,
      });
      await db.collection('items').doc('array-kind').set(<String, dynamic>{
        'kind': <String>['fruit'],
        'tags': <String>['red'],
        'score': 5,
      });
      await db.collection('items').doc('too-low').set(<String, dynamic>{
        'kind': 'fruit',
        'tags': <String>['red'],
        'score': 1,
      });
      await db.collection('items').doc('wrong-tag').set(<String, dynamic>{
        'kind': 'fruit',
        'tags': <String>['blue'],
        'score': 5,
      });

      db.debugCollectionScans = 0;
      db.debugIndexCandidateReads = 0;
      db.debugCompositeIndexPlans = 0;

      List<DocumentSnapshot> documents = await db
          .collection('items')
          .whereEqual('kind', 'fruit')
          .whereArrayContains('tags', 'red')
          .whereGreaterThan('score', 2)
          .get();

      expect(documents.map((document) => document.id), <String>['match']);
      expect(db.debugCollectionScans, 0);
      expect(db.debugCompositeIndexPlans, 1);
    });

    test(
      'uses persisted indexes for exact count and sum aggregations',
      () async {
        await db.collection('items').doc('a').set(<String, dynamic>{
          'kind': 'fruit',
          'tags': <String>['red'],
          'score': 2,
        });
        await db.collection('items').doc('b').set(<String, dynamic>{
          'kind': <String>['fruit'],
          'tags': 'red',
          'score': 100,
        });
        await db.collection('items').doc('c').set(<String, dynamic>{
          'kind': 'fruit',
          'tags': <String>['blue'],
          'score': 3,
        });
        await db.collection('items').doc('d').set(<String, dynamic>{
          'kind': 'tool',
          'tags': <String>['red'],
          'score': 10,
        });
        await db.collection('items').doc('e').set(<String, dynamic>{
          'kind': 'tool',
          'tags': <String>['blue'],
          'score': <int>[1000],
        });

        db.debugCollectionScans = 0;
        db.debugIndexCandidateReads = 0;
        db.debugCompositeIndexPlans = 0;

        expect(await db.collection('items').count(), 5);
        expect(
          await db.collection('items').whereEqual('kind', 'fruit').count(),
          2,
        );
        expect(
          await db
              .collection('items')
              .whereArrayContains('tags', 'red')
              .count(),
          2,
        );
        expect(
          await db.collection('items').whereGreaterThan('score', 2).count(),
          3,
        );
        expect(await db.collection('items').sum('score'), 115);
        expect(
          await db.collection('items').whereEqual('kind', 'fruit').sum('score'),
          5,
        );
        expect(
          await db
              .collection('items')
              .whereArrayContains('tags', 'red')
              .sum('score'),
          12,
        );
        expect(
          await db
              .collection('items')
              .whereEqual('kind', 'fruit')
              .whereArrayContains('tags', 'red')
              .whereGreaterThan('score', 1)
              .count(),
          1,
        );
        expect(
          await db
              .collection('items')
              .whereEqual('kind', 'fruit')
              .whereArrayContains('tags', 'red')
              .whereGreaterThan('score', 1)
              .sum('score'),
          2,
        );
        expect(db.debugCollectionScans, 0);
        expect(db.debugIndexCandidateReads, 0);
        expect(db.debugCompositeIndexPlans, 2);
      },
    );
  });
}
