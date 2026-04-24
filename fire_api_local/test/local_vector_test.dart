import 'dart:io';

import 'package:fire_api/fire_api.dart';
import 'package:fire_api_local/fire_api_local.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:test/test.dart';

void main() {
  group('LocalFirestoreDatabase vector queries', () {
    late LocalFirestoreDatabase db;

    setUp(() {
      db = LocalFirestoreDatabase.memory();
    });

    tearDown(() {
      db.close();
    });

    test('runs prefiltered nearest vector queries', () async {
      await db.collection('items').doc('near').set(<String, dynamic>{
        'color': 'red',
        'vector': const VectorValue(vector: <double>[1, 0]),
      });
      await db.collection('items').doc('far').set(<String, dynamic>{
        'color': 'red',
        'vector': const VectorValue(vector: <double>[10, 0]),
      });
      await db.collection('items').doc('filtered').set(<String, dynamic>{
        'color': 'blue',
        'vector': const VectorValue(vector: <double>[1, 0]),
      });

      List<VectorQueryDocumentSnapshot> results = await db
          .collection('items')
          .whereEqual('color', 'red')
          .findNearest(
            vectorField: 'vector',
            queryVector: const VectorValue(vector: <double>[0, 0]),
            limit: 2,
            distanceMeasure: VectorDistanceMeasure.euclidean,
          )
          .get();

      expect(results.map((document) => document.id), <String>['near', 'far']);
      expect(results.first.rank, 1);
      expect(results.first.score, 1);
      expect(
        results.first.data!.containsKey(
          VectorQueryReference.implicitDistanceResultField,
        ),
        isFalse,
      );
    });

    test(
      'queries nested vector fields and skips dimension mismatches',
      () async {
        await db.collection('items').doc('near').set(<String, dynamic>{
          'embedding': <String, dynamic>{
            'vector': const VectorValue(vector: <double>[1, 0]),
          },
        });
        await db.collection('items').doc('wrong-dimension').set(
          <String, dynamic>{
            'embedding': <String, dynamic>{
              'vector': const VectorValue(vector: <double>[1, 0, 0]),
            },
          },
        );

        List<VectorQueryDocumentSnapshot> results = await db
            .collection('items')
            .findNearest(
              vectorField: 'embedding.vector',
              queryVector: const VectorValue(vector: <double>[0, 0]),
              limit: 10,
              distanceMeasure: VectorDistanceMeasure.euclidean,
            )
            .get();

        expect(results.map((document) => document.id), <String>['near']);
        expect(results.single.score, 1);
      },
    );

    test('persists vector metadata in side table', () async {
      Directory directory = await Directory.systemTemp.createTemp(
        'fire_api_local_vector_table_test_',
      );
      String path = '${directory.path}/local.sqlite';
      LocalFirestoreDatabase local = LocalFirestoreDatabase.open(path);
      await local.collection('items').doc('a').set(<String, dynamic>{
        'vector': const VectorValue(vector: <double>[3, 4]),
      });
      local.close();

      sql.Database raw = sql.sqlite3.open(path);
      sql.ResultSet rows = raw.select(
        'SELECT field_path, dimension, magnitude, vector_json '
        'FROM document_vectors',
      );
      raw.dispose();
      await directory.delete(recursive: true);

      expect(rows.single['field_path'], 'vector');
      expect(rows.single['dimension'], 2);
      expect(rows.single['magnitude'], 5);
      expect(rows.single['vector_json'], '[3.0,4.0]');
    });

    test('keeps vector side table in sync after updates and deletes', () async {
      Directory directory = await Directory.systemTemp.createTemp(
        'fire_api_local_vector_sync_test_',
      );
      String path = '${directory.path}/local.sqlite';
      LocalFirestoreDatabase local = LocalFirestoreDatabase.open(path);
      DocumentReference ref = local.collection('items').doc('a');

      await ref.set(<String, dynamic>{
        'vector': const VectorValue(vector: <double>[3, 4]),
      });
      await ref.update(<String, dynamic>{
        'vector': const VectorValue(vector: <double>[6, 8, 0]),
      });
      local.close();

      sql.Database raw = sql.sqlite3.open(path);
      sql.ResultSet updatedRows = raw.select(
        'SELECT dimension, magnitude, vector_json FROM document_vectors',
      );
      raw.dispose();

      expect(updatedRows.single['dimension'], 3);
      expect(updatedRows.single['magnitude'], 10);
      expect(updatedRows.single['vector_json'], '[6.0,8.0,0.0]');

      LocalFirestoreDatabase remover = LocalFirestoreDatabase.open(path);
      await remover.collection('items').doc('a').delete();
      remover.close();

      sql.Database rawAfterDelete = sql.sqlite3.open(path);
      sql.ResultSet deletedRows = rawAfterDelete.select(
        'SELECT COUNT(*) AS count FROM document_vectors',
      );
      rawAfterDelete.dispose();
      await directory.delete(recursive: true);

      expect(deletedRows.single['count'], 0);
    });

    test('supports explicit vector score fields and thresholds', () async {
      await db.collection('items').doc('best').set(<String, dynamic>{
        'vector': const VectorValue(vector: <double>[1, 0]),
      });
      await db.collection('items').doc('okay').set(<String, dynamic>{
        'vector': const VectorValue(vector: <double>[0.5, 0]),
      });
      await db.collection('items').doc('low').set(<String, dynamic>{
        'vector': const VectorValue(vector: <double>[0, 1]),
      });

      List<VectorQueryDocumentSnapshot> dotResults = await db
          .collection('items')
          .findNearest(
            vectorField: 'vector',
            queryVector: const VectorValue(vector: <double>[1, 0]),
            limit: 10,
            distanceMeasure: VectorDistanceMeasure.dotProduct,
            distanceResultField: 'score',
            distanceThreshold: 0.5,
          )
          .get();
      List<VectorQueryDocumentSnapshot> cosineResults = await db
          .collection('items')
          .findNearest(
            vectorField: 'vector',
            queryVector: const VectorValue(vector: <double>[1, 0]),
            limit: 10,
            distanceMeasure: VectorDistanceMeasure.cosine,
            distanceThreshold: 0.1,
          )
          .get();

      expect(dotResults.map((document) => document.id), <String>[
        'best',
        'okay',
      ]);
      expect(dotResults.first.score, 1);
      expect(dotResults.first.data?['score'], 1);
      expect(cosineResults.map((document) => document.id), <String>[
        'best',
        'okay',
      ]);
      expect(
        cosineResults.first.data!.containsKey(
          VectorQueryReference.implicitDistanceResultField,
        ),
        isFalse,
      );
    });
  });
}
