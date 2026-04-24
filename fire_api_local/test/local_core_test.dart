import 'dart:io';
import 'dart:typed_data';

import 'package:fire_api/fire_api.dart';
import 'package:fire_api_local/fire_api_local.dart';
import 'package:test/test.dart';

void main() {
  group('LocalFirestoreDatabase core documents', () {
    late LocalFirestoreDatabase db;

    setUp(() {
      db = LocalFirestoreDatabase.memory();
    });

    tearDown(() {
      db.close();
    });

    test('sets and gets documents with vectors', () async {
      DocumentReference ref = db.collection('items').doc('a');

      await ref.set(<String, dynamic>{
        'name': 'alpha',
        'vector': const VectorValue(vector: <double>[1, 2, 3]),
      });

      DocumentSnapshot snapshot = await ref.get();

      expect(snapshot.exists, isTrue);
      expect(snapshot.data?['name'], 'alpha');
      expect(
        snapshot.data?['vector'],
        const VectorValue(vector: <double>[1, 2, 3]),
      );
    });

    test('persists documents in file databases', () async {
      Directory directory = await Directory.systemTemp.createTemp(
        'fire_api_local_test_',
      );
      String path = '${directory.path}/local.sqlite';
      LocalFirestoreDatabase first = LocalFirestoreDatabase.open(path);
      await first.collection('items').doc('a').set(<String, dynamic>{
        'name': 'alpha',
      });
      first.close();

      LocalFirestoreDatabase second = LocalFirestoreDatabase.open(path);
      DocumentSnapshot snapshot = await second
          .collection('items')
          .doc('a')
          .get();
      second.close();
      await directory.delete(recursive: true);

      expect(snapshot.data?['name'], 'alpha');
    });

    test('updates dotted paths and field transforms', () async {
      DocumentReference ref = db.collection('items').doc('a');
      await ref.set(<String, dynamic>{
        'count': 1,
        'tags': <String>['red'],
        'nested': <String, dynamic>{'enabled': false},
        'remove': true,
      });

      await ref.update(<String, dynamic>{
        'count': FieldValue.increment(2),
        'down': FieldValue.decrement(1),
        'tags': FieldValue.arrayUnion(<String>['red', 'blue', 'green']),
        'removedTags': FieldValue.arrayRemove(<String>['green']),
        'nested.enabled': true,
        'remove': FieldValue.delete(),
        'time': FieldValue.serverTimestamp(),
      });

      DocumentSnapshot snapshot = await ref.get();

      expect(snapshot.data?['count'], 3);
      expect(snapshot.data?['down'], -1);
      expect(snapshot.data?['tags'], <dynamic>['red', 'blue', 'green']);
      expect(snapshot.data?['removedTags'], <dynamic>[]);
      expect(snapshot.data?['nested'], <String, dynamic>{'enabled': true});
      expect(snapshot.data?.containsKey('remove'), isFalse);
      expect(snapshot.data?['time'], isA<DateTime>());
    });

    test('round trips special values nested in maps and arrays', () async {
      DocumentReference ref = db.collection('items').doc('special');
      DateTime timestamp = DateTime.utc(2026, 4, 23, 12, 30, 5);
      Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 255]);
      LocalGeoPoint point = const LocalGeoPoint(
        latitude: 39.7392,
        longitude: -104.9903,
      );
      DocumentReference linked = db.collection('items').doc('linked');

      await ref.set(<String, dynamic>{
        'timestamp': timestamp,
        'bytes': bytes,
        'point': point,
        'ref': linked,
        'nested': <String, dynamic>{
          'values': <dynamic>[timestamp, bytes, point, linked],
        },
      });

      DocumentSnapshot snapshot = await ref.get();
      Map<String, dynamic> nested = Map<String, dynamic>.from(
        snapshot.data?['nested'] as Map,
      );
      List<dynamic> nestedValues = nested['values'] as List<dynamic>;

      expect(snapshot.data?['timestamp'], timestamp);
      expect(snapshot.data?['bytes'], orderedEquals(bytes));
      expect(snapshot.data?['point'], point);
      expect((snapshot.data?['ref'] as DocumentReference).path, linked.path);
      expect(nestedValues[0], timestamp);
      expect(nestedValues[1], orderedEquals(bytes));
      expect(nestedValues[2], point);
      expect((nestedValues[3] as DocumentReference).path, linked.path);
      expect(
        await db.collection('items').whereEqual('timestamp', timestamp).count(),
        1,
      );
      expect(
        await db.collection('items').whereEqual('point', point).count(),
        1,
      );
      expect(await db.collection('items').whereEqual('ref', linked).count(), 1);
      expect(
        await db.collection('items').whereEqual('bytes', bytes).count(),
        1,
      );
    });

    test('normalizes non-utc datetimes to utc instants', () async {
      DocumentReference ref = db.collection('items').doc('time');
      DateTime timestamp = DateTime(2026, 4, 23, 8, 30, 5);

      await ref.set(<String, dynamic>{'timestamp': timestamp});

      DocumentSnapshot snapshot = await ref.get();
      DateTime stored = snapshot.data?['timestamp'] as DateTime;

      expect(stored.isUtc, isTrue);
      expect(stored, timestamp.toUtc());
    });

    test('rejects unsupported document values before writing', () async {
      DocumentReference ref = db.collection('items').doc('bad');

      expect(
        () => ref.set(<String, dynamic>{'unsupported': Object()}),
        throwsUnsupportedError,
      );
      expect((await ref.get()).exists, isFalse);
    });

    test('paginates documents through DocumentPage', () async {
      for (int i = 0; i < 5; i++) {
        await db.collection('items').doc('item-$i').set(<String, dynamic>{
          'index': i,
        });
      }

      DocumentPage? first = await db.getDocumentPageInCollection(
        reference: db.collection('items').orderBy('index'),
        pageSize: 2,
      );
      DocumentPage? second = await first?.nextPage();
      DocumentPage? third = await second?.nextPage();
      DocumentPage? fourth = await third?.nextPage();

      expect(first?.documents.map((document) => document.id), <String>[
        'item-0',
        'item-1',
      ]);
      expect(second?.documents.map((document) => document.id), <String>[
        'item-2',
        'item-3',
      ]);
      expect(third?.documents.map((document) => document.id), <String>[
        'item-4',
      ]);
      expect(fourth, isNull);
    });

    test('supports subcollections and root prefixes', () async {
      LocalFirestoreDatabase prefixed = LocalFirestoreDatabase.memory(
        rootPrefix: 'tenant-a',
      );
      await prefixed
          .collection('parents')
          .doc('p1')
          .collection('children')
          .doc('c1')
          .set(<String, dynamic>{'name': 'child'});

      List<DocumentSnapshot> children = await prefixed
          .collection('parents')
          .doc('p1')
          .collection('children')
          .get();
      prefixed.close();

      expect(children.map((document) => document.path), <String>[
        'parents/p1/children/c1',
      ]);
      expect(children.single.data?['name'], 'child');
    });

    test('deletes batches and only matching ids', () async {
      for (String id in <String>['a', 'b', 'c', 'd']) {
        await db.collection('items').doc(id).set(<String, dynamic>{'id': id});
      }

      await db
          .collection('items')
          .deleteAll(only: <String>{'b', 'd', 'missing'}, batchSize: 1);

      expect(
        await db.collection('items').listIds(batchSize: 2).toList(),
        <String>['a', 'c'],
      );
      await db.collection('items').deleteAll(batchSize: 1);
      expect(await db.collection('items').count(), 0);
    });

    test('supports atomic set and update callbacks', () async {
      DocumentReference ref = db.collection('items').doc('a');

      await ref.setAtomic(
        (data) => <String, dynamic>{'count': (data?['count'] as int? ?? 0) + 1},
      );
      await ref.updateAtomic(
        (data) => <String, dynamic>{'count': (data?['count'] as int? ?? 0) + 4},
      );

      DocumentSnapshot snapshot = await ref.get();

      expect(snapshot.data?['count'], 5);
    });
  });
}
