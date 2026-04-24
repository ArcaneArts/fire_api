import 'dart:async';
import 'dart:io';

import 'package:fire_api/fire_api.dart';
import 'package:fire_api_local/fire_api_local.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:test/test.dart';

void main() {
  group('LocalFirestoreDatabase snapshot streams and change log', () {
    late LocalFirestoreDatabase db;

    setUp(() {
      db = LocalFirestoreDatabase.memory();
    });

    tearDown(() {
      db.close();
    });

    test(
      'persists snapshot change log entries for writes and deletes',
      () async {
        Directory directory = await Directory.systemTemp.createTemp(
          'fire_api_local_change_log_test_',
        );
        String path = '${directory.path}/local.sqlite';
        LocalFirestoreDatabase first = LocalFirestoreDatabase.open(path);
        DocumentReference ref = first.collection('items').doc('a');

        await ref.set(<String, dynamic>{'name': 'alpha'});
        await ref.update(<String, dynamic>{'name': 'beta'});
        await ref.delete();
        first.close();

        sql.Database raw = sql.sqlite3.open(path);
        sql.ResultSet rows = raw.select(
          'SELECT version, change_type, data_json FROM document_changes '
          'ORDER BY version ASC',
        );
        raw.dispose();
        await directory.delete(recursive: true);

        expect(rows.map((row) => row['version']), <int>[1, 2, 3]);
        expect(rows.map((row) => row['change_type']), <String>[
          'added',
          'modified',
          'removed',
        ]);
        expect(rows.last['data_json'] as String, contains('beta'));
      },
    );

    test('replays resumable snapshot changes from persisted log', () async {
      await db.collection('items').doc('a').set(<String, dynamic>{
        'name': 'alpha',
      });
      await db.collection('items').doc('b').set(<String, dynamic>{
        'name': 'beta',
      });
      await db.collection('items').doc('a').delete();

      List<LocalDocumentChange> allChanges = db.changesSince(0);
      List<LocalDocumentChange> resumed = db.changesSince(1);

      expect(
        allChanges.map((change) => change.changeType),
        <DocumentChangeType>[
          DocumentChangeType.added,
          DocumentChangeType.added,
          DocumentChangeType.removed,
        ],
      );
      expect(resumed.map((change) => change.documentId), <String>['b', 'a']);
      expect(resumed.last.data?['name'], 'alpha');
    });

    test('filters persisted changes by collection and document path', () async {
      await db.collection('items').doc('a').set(<String, dynamic>{
        'name': 'alpha',
      });
      await db.collection('items').doc('b').set(<String, dynamic>{
        'name': 'beta',
      });
      await db.collection('other').doc('a').set(<String, dynamic>{
        'name': 'ignored',
      });
      await db.collection('items').doc('a').update(<String, dynamic>{
        'name': 'alpha-2',
      });

      List<LocalDocumentChange> itemChanges = db.changesSince(
        0,
        collectionPath: 'items',
      );
      List<LocalDocumentChange> documentChanges = db.changesSince(
        0,
        documentPath: 'items/a',
      );

      expect(itemChanges.map((change) => change.documentId), <String>[
        'a',
        'b',
        'a',
      ]);
      expect(documentChanges.map((change) => change.changeType), <Object>[
        DocumentChangeType.added,
        DocumentChangeType.modified,
      ]);
      expect(documentChanges.last.data?['name'], 'alpha-2');
    });

    test('streams resumable changes with path filters', () async {
      await db.collection('items').doc('a').set(<String, dynamic>{
        'name': 'alpha',
      });
      await db.collection('other').doc('x').set(<String, dynamic>{
        'name': 'ignored',
      });

      StreamIterator<LocalDocumentChange> stream =
          StreamIterator<LocalDocumentChange>(
            db.streamChangesSince(
              0,
              pollInterval: const Duration(milliseconds: 10),
              collectionPath: 'items',
            ),
          );

      expect(await stream.moveNext(), isTrue);
      expect(stream.current.documentId, 'a');
      await db.collection('items').doc('b').set(<String, dynamic>{
        'name': 'beta',
      });
      expect(await stream.moveNext(), isTrue);
      expect(stream.current.documentId, 'b');
      await stream.cancel();
    });

    test('streams document and collection changes', () async {
      DocumentReference ref = db.collection('items').doc('a');
      StreamIterator<List<DocumentSnapshot>> collectionStream =
          StreamIterator<List<DocumentSnapshot>>(db.collection('items').stream);
      StreamIterator<DocumentSnapshot> documentStream =
          StreamIterator<DocumentSnapshot>(ref.stream);

      expect(await collectionStream.moveNext(), isTrue);
      expect(await documentStream.moveNext(), isTrue);
      expect(collectionStream.current, isEmpty);
      expect(documentStream.current.exists, isFalse);

      await ref.set(<String, dynamic>{'name': 'alpha'});

      expect(await collectionStream.moveNext(), isTrue);
      expect(await documentStream.moveNext(), isTrue);
      List<DocumentSnapshot> collectionEvent = collectionStream.current;
      DocumentSnapshot documentEvent = documentStream.current;

      expect(collectionEvent.map((document) => document.id), <String>['a']);
      expect(collectionEvent.single.changeType, DocumentChangeType.added);
      expect(documentEvent.data?['name'], 'alpha');

      await ref.update(<String, dynamic>{'name': 'beta'});
      expect(await collectionStream.moveNext(), isTrue);
      expect(
        collectionStream.current.single.changeType,
        DocumentChangeType.modified,
      );

      await ref.delete();
      expect(await collectionStream.moveNext(), isTrue);
      expect(collectionStream.current.single.id, 'a');
      expect(
        collectionStream.current.single.changeType,
        DocumentChangeType.removed,
      );
      expect(collectionStream.current.single.data?['name'], 'beta');

      await collectionStream.cancel();
      await documentStream.cancel();
    });

    test('collection streams skip writes outside query snapshots', () async {
      List<List<DocumentSnapshot>> events = <List<DocumentSnapshot>>[];
      StreamSubscription<List<DocumentSnapshot>> subscription = db
          .collection('items')
          .whereEqual('kind', 'target')
          .stream
          .listen(events.add);

      await Future<void>.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.single, isEmpty);

      await db.collection('items').doc('other').set(<String, dynamic>{
        'kind': 'other',
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events.length, 1);

      await db.collection('items').doc('target').set(<String, dynamic>{
        'kind': 'target',
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events.length, 2);
      expect(events.last.single.id, 'target');
      expect(events.last.single.changeType, DocumentChangeType.added);
      await subscription.cancel();
    });

    test('file database streams observe writes from another handle', () async {
      Directory directory = await Directory.systemTemp.createTemp(
        'fire_api_local_cross_process_test_',
      );
      String path = '${directory.path}/local.sqlite';
      LocalFirestoreDatabase writer = LocalFirestoreDatabase.open(
        path,
        changePollingInterval: const Duration(milliseconds: 20),
      );
      LocalFirestoreDatabase watcher = LocalFirestoreDatabase.open(
        path,
        changePollingInterval: const Duration(milliseconds: 20),
      );
      StreamIterator<List<DocumentSnapshot>> stream =
          StreamIterator<List<DocumentSnapshot>>(
            watcher.collection('items').stream,
          );

      expect(await stream.moveNext(), isTrue);
      expect(stream.current, isEmpty);

      await writer.collection('items').doc('a').set(<String, dynamic>{
        'name': 'alpha',
      });

      expect(await stream.moveNext(), isTrue);
      expect(stream.current.single.id, 'a');
      expect(stream.current.single.data?['name'], 'alpha');
      await stream.cancel();
      writer.close();
      watcher.close();
      await directory.delete(recursive: true);
    });
  });
}
