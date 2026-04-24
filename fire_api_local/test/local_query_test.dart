import 'package:fire_api/fire_api.dart';
import 'package:fire_api_local/fire_api_local.dart';
import 'package:test/test.dart';

void main() {
  group('LocalFirestoreDatabase queries', () {
    late LocalFirestoreDatabase db;

    setUp(() {
      db = LocalFirestoreDatabase.memory();
    });

    tearDown(() {
      db.close();
    });

    test('filters with every shared clause operator', () async {
      await db.collection('items').doc('a').set(<String, dynamic>{
        'type': 'fruit',
        'score': 2,
        'tags': <String>['red', 'round'],
      });
      await db.collection('items').doc('b').set(<String, dynamic>{
        'type': 'fruit',
        'score': 3,
        'tags': <String>['yellow'],
      });
      await db.collection('items').doc('c').set(<String, dynamic>{
        'type': 'tool',
        'score': 10,
        'tags': <String>['red', 'metal'],
      });

      expect(
        await db
            .collection('items')
            .whereLessThan('score', 3)
            .get()
            .then((documents) => documents.map((document) => document.id)),
        <String>['a'],
      );
      expect(
        await db
            .collection('items')
            .whereLessThanOrEqual('score', 3)
            .get()
            .then((documents) => documents.map((document) => document.id)),
        <String>['a', 'b'],
      );
      expect(
        await db
            .collection('items')
            .whereGreaterThan('score', 3)
            .get()
            .then((documents) => documents.map((document) => document.id)),
        <String>['c'],
      );
      expect(
        await db
            .collection('items')
            .whereGreaterThanOrEqual('score', 3)
            .get()
            .then((documents) => documents.map((document) => document.id)),
        <String>['b', 'c'],
      );
      expect(
        await db
            .collection('items')
            .whereNotEqual('type', 'fruit')
            .get()
            .then((documents) => documents.map((document) => document.id)),
        <String>['c'],
      );
      expect(
        await db
            .collection('items')
            .whereArrayContains('tags', 'red')
            .get()
            .then((documents) => documents.map((document) => document.id)),
        <String>['a', 'c'],
      );
      expect(
        await db
            .collection('items')
            .whereArrayContainsAny('tags', <String>['yellow', 'metal'])
            .get()
            .then((documents) => documents.map((document) => document.id)),
        <String>['b', 'c'],
      );
      expect(
        await db
            .collection('items')
            .whereIn('type', <String>['tool'])
            .get()
            .then((documents) => documents.map((document) => document.id)),
        <String>['c'],
      );
      expect(
        await db
            .collection('items')
            .whereNotIn('type', <String>['tool'])
            .get()
            .then((documents) => documents.map((document) => document.id)),
        <String>['a', 'b'],
      );
    });

    test('validates unsupported Firestore query combinations', () async {
      await db.collection('items').doc('a').set(<String, dynamic>{
        'score': 1,
        'name': 'alpha',
        'tags': <String>['red'],
      });

      await expectLater(
        db
            .collection('items')
            .whereGreaterThan('score', 0)
            .orderBy('name')
            .get(),
        throwsStateError,
      );
      await expectLater(
        db.collection('items').whereIn('score', <int>[1]).whereArrayContainsAny(
          'tags',
          <String>['red'],
        ).get(),
        throwsStateError,
      );
      await expectLater(
        db.collection('items').whereIn('score', <int>[]).get(),
        throwsStateError,
      );
      await expectLater(
        db.collection('items').whereArrayContainsAny('tags', <String>[]).get(),
        throwsStateError,
      );
      await expectLater(
        db
            .collection('items')
            .whereArrayContains('tags', 'red')
            .whereArrayContains('otherTags', 'round')
            .get(),
        throwsStateError,
      );
      await expectLater(
        db
            .collection('items')
            .whereNotIn('score', <int>[1])
            .whereNotEqual('name', 'beta')
            .get(),
        throwsStateError,
      );
    });

    test('orders, limits, counts, sums, and lists ids', () async {
      await db.collection('items').doc('a').set(<String, dynamic>{
        'type': 'fruit',
        'score': 2,
      });
      await db.collection('items').doc('b').set(<String, dynamic>{
        'type': 'fruit',
        'score': 3,
      });
      await db.collection('items').doc('c').set(<String, dynamic>{
        'type': 'tool',
        'score': 10,
      });

      CollectionReference query = db
          .collection('items')
          .whereEqual('type', 'fruit')
          .orderBy('score', descending: true)
          .limit(1);
      List<DocumentSnapshot> documents = await query.get();

      expect(documents.map((document) => document.id), <String>['b']);
      expect(
        await db.collection('items').whereEqual('type', 'fruit').count(),
        2,
      );
      expect(await db.collection('items').sum('score'), 15);
      expect(
        await db.collection('items').listIds(batchSize: 2).toList(),
        <String>['a', 'b', 'c'],
      );
    });

    test('supports document and value cursors', () async {
      await db.collection('items').doc('a').set(<String, dynamic>{'score': 1});
      await db.collection('items').doc('b').set(<String, dynamic>{'score': 2});
      await db.collection('items').doc('bb').set(<String, dynamic>{'score': 2});
      await db.collection('items').doc('c').set(<String, dynamic>{'score': 3});

      CollectionReference ordered = db.collection('items').orderBy('score');
      CollectionReference descending = db
          .collection('items')
          .orderBy('score', descending: true);
      List<DocumentSnapshot> all = await ordered.get();

      expect(
        await ordered
            .startAfter(all.first)
            .get()
            .then((documents) => documents.map((document) => document.id)),
        <String>['b', 'bb', 'c'],
      );
      expect(
        await ordered
            .endBefore(all.last)
            .get()
            .then((documents) => documents.map((document) => document.id)),
        <String>['a', 'b', 'bb'],
      );
      expect(
        await ordered
            .startAtValues(<Object?>[2])
            .get()
            .then((documents) => documents.map((document) => document.id)),
        <String>['b', 'bb', 'c'],
      );
      expect(
        await ordered
            .startAfterValues(<Object?>[2, 'b'])
            .get()
            .then((documents) => documents.map((document) => document.id)),
        <String>['bb', 'c'],
      );
      expect(
        await ordered
            .endBeforeValues(<Object?>[3])
            .get()
            .then((documents) => documents.map((document) => document.id)),
        <String>['a', 'b', 'bb'],
      );
      expect(
        await descending
            .startAfterValues(<Object?>[3])
            .get()
            .then((documents) => documents.map((document) => document.id)),
        <String>['b', 'bb', 'a'],
      );
      expect(
        await descending
            .startAfterValues(<Object?>[2, 'b'])
            .get()
            .then((documents) => documents.map((document) => document.id)),
        <String>['bb', 'a'],
      );
    });
  });
}
