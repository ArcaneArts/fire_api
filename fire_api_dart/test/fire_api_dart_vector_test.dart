import 'dart:convert';

import 'package:fire_api/fire_api.dart';
import 'package:fire_api_dart/fire_api_dart.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('GoogleCloudFirestoreDatabase vector support', () {
    test('getDocument decodes sentinel vector values recursively', () async {
      MockClient client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'https://firestore.googleapis.com/v1/projects/demo-project/databases/(default)/documents/users/alice',
        );

        return http.Response(
          jsonEncode({
            'name':
                'projects/demo-project/databases/(default)/documents/users/alice',
            'fields': {
              'embedding': _vectorJson([1, 2.5]),
              'nested': {
                'mapValue': {
                  'fields': {
                    'history': {
                      'arrayValue': {
                        'values': [
                          _vectorJson([3, 4]),
                        ],
                      },
                    },
                  },
                },
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      GoogleCloudFirestoreDatabase db = GoogleCloudFirestoreDatabase(
        FirestoreApi(client),
        'demo-project',
        client: client,
      );
      DocumentReference ref = db.collection('users').doc('alice');
      DocumentSnapshot snapshot = await db.getDocument(ref);

      expect(snapshot.exists, isTrue);
      expect(
        (snapshot.data!['embedding'] as VectorValue).toArray(),
        [1.0, 2.5],
      );
      expect(
        ((snapshot.data!['nested'] as Map<String, dynamic>)['history'] as List)
            .single,
        isA<VectorValue>(),
      );
      expect(
        ((((snapshot.data!['nested'] as Map<String, dynamic>)['history']
                    as List)
                .single) as VectorValue)
            .toArray(),
        [3.0, 4.0],
      );
    });

    test('getDocument decodes legacy vectorValue payloads recursively',
        () async {
      MockClient client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'name':
                'projects/demo-project/databases/(default)/documents/users/alice',
            'fields': {
              'embedding': {
                'vectorValue': {
                  'values': [1, 2.5],
                },
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      GoogleCloudFirestoreDatabase db = GoogleCloudFirestoreDatabase(
        FirestoreApi(client),
        'demo-project',
        client: client,
      );

      DocumentSnapshot snapshot =
          await db.getDocument(db.collection('users').doc('alice'));
      expect(
          (snapshot.data!['embedding'] as VectorValue).toArray(), [1.0, 2.5]);
    });

    test('setDocument encodes nested vector values for commit writes',
        () async {
      late Map<String, dynamic> body;
      MockClient client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://firestore.googleapis.com/v1/projects/demo-project/databases/(default)/documents:commit',
        );

        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      GoogleCloudFirestoreDatabase db = GoogleCloudFirestoreDatabase(
        FirestoreApi(client),
        'demo-project',
        client: client,
      );

      await db.setDocument(db.collection('users').doc('alice'), {
        'embedding': const VectorValue(vector: [9, 8, 7]),
        'nested': {
          'items': [
            const VectorValue(vector: [1, 2]),
          ],
        },
      });

      Map<String, dynamic> fields = (body['writes'] as List).single['update']
          ['fields'] as Map<String, dynamic>;
      expect(fields['embedding'], _vectorJson([9, 8, 7]));
      expect(
        (((fields['nested'] as Map<String, dynamic>)['mapValue']
                as Map<String, dynamic>)['fields']
            as Map<String, dynamic>)['items'],
        {
          'arrayValue': {
            'values': [
              _vectorJson([1, 2]),
            ],
          },
        },
      );
    });

    test('setDocument accepts serialized vector sentinel maps', () async {
      late Map<String, dynamic> body;
      MockClient client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      GoogleCloudFirestoreDatabase db = GoogleCloudFirestoreDatabase(
        FirestoreApi(client),
        'demo-project',
        client: client,
      );

      await db.setDocument(db.collection('users').doc('alice'), {
        'embedding': const VectorValue(vector: [6, 7]).toMap(),
      });

      Map<String, dynamic> fields = (body['writes'] as List).single['update']
          ['fields'] as Map<String, dynamic>;
      expect(fields['embedding'], _vectorJson([6, 7]));
    });

    test('updateDocument encodes vector values inside array transforms',
        () async {
      late Map<String, dynamic> body;
      MockClient client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      GoogleCloudFirestoreDatabase db = GoogleCloudFirestoreDatabase(
        FirestoreApi(client),
        'demo-project',
        client: client,
      );

      await db.updateDocument(db.collection('users').doc('alice'), {
        'history': FieldValue.arrayUnion([
          const VectorValue(vector: [4, 5])
        ]),
      });

      List writes = body['writes'] as List;
      Map<String, dynamic> transforms =
          (writes.single['transform']['fieldTransforms'] as List).single;
      expect(transforms['fieldPath'], 'history');
      expect(transforms['appendMissingElements'], {
        'values': [
          _vectorJson([4, 5]),
        ],
      });
    });

    test('updateDocumentAtomic decodes vectors before txn callback', () async {
      late Map<String, dynamic> commitBody;
      MockClient client = MockClient((request) async {
        String path = request.url.path;

        if (path.endsWith('documents:beginTransaction')) {
          return http.Response(
            jsonEncode({'transaction': 'txn-123'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.method == 'GET' &&
            path.endsWith('/documents/users/alice') &&
            request.url.queryParameters['transaction'] == 'txn-123') {
          return http.Response(
            jsonEncode({
              'name':
                  'projects/demo-project/databases/(default)/documents/users/alice',
              'fields': {
                'embedding': _vectorJson([1, 2]),
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (path.endsWith('documents:commit')) {
          commitBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        fail('Unexpected request: ${request.method} ${request.url}');
      });

      GoogleCloudFirestoreDatabase db = GoogleCloudFirestoreDatabase(
        FirestoreApi(client),
        'demo-project',
        client: client,
      );

      await db.updateDocumentAtomic(db.collection('users').doc('alice'),
          (data) {
        expect((data!['embedding'] as VectorValue).toArray(), [1.0, 2.0]);
        return {
          'embedding': const VectorValue(vector: [3, 4]),
        };
      });

      Map<String, dynamic> updateFields =
          ((commitBody['writes'] as List).single['update']
              as Map<String, dynamic>)['fields'] as Map<String, dynamic>;
      expect(updateFields['embedding'], _vectorJson([3, 4]));
      expect(commitBody['transaction'], 'txn-123');
    });

    test('findNearest encodes structuredQuery.findNearest', () async {
      MockClient client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://firestore.googleapis.com/v1/projects/demo-project/databases/(default)/documents:runQuery',
        );

        Map<String, dynamic> body =
            jsonDecode(request.body) as Map<String, dynamic>;
        Map<String, dynamic> query =
            body['structuredQuery'] as Map<String, dynamic>;
        expect(
          query['where'],
          {
            'fieldFilter': {
              'field': {'fieldPath': 'color'},
              'op': 'EQUAL',
              'value': {'stringValue': 'red'},
            },
          },
        );
        expect(
          query['findNearest'],
          {
            'vectorField': {'fieldPath': 'embedding_field'},
            'queryVector': _vectorJson([3, 1, 2]),
            'limit': 5,
            'distanceMeasure': 'EUCLIDEAN',
            'distanceResultField': 'vector_distance',
            'distanceThreshold': 4.5,
          },
        );

        return http.Response(
          jsonEncode([
            {
              'document': {
                'name':
                    'projects/demo-project/databases/(default)/documents/items/item-1',
                'fields': {
                  'color': {'stringValue': 'red'},
                  'vector_distance': {'doubleValue': 0.25},
                },
              },
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      GoogleCloudFirestoreDatabase db = GoogleCloudFirestoreDatabase(
        FirestoreApi(client),
        'demo-project',
        client: client,
      );

      List<VectorQueryDocumentSnapshot> results = await db
          .collection('items')
          .whereEqual('color', 'red')
          .findNearest(
            vectorField: 'embedding_field',
            queryVector: const VectorValue(vector: [3, 1, 2]),
            limit: 5,
            distanceMeasure: VectorDistanceMeasure.euclidean,
            distanceResultField: 'vector_distance',
            distanceThreshold: 4.5,
          )
          .get();

      expect(results, hasLength(1));
      expect(results.single.id, 'item-1');
      expect(results.single.data!['vector_distance'], 0.25);
    });

    test('findNearest injects an implicit distance result field', () async {
      MockClient client = MockClient((request) async {
        Map<String, dynamic> body =
            jsonDecode(request.body) as Map<String, dynamic>;
        Map<String, dynamic> query =
            body['structuredQuery'] as Map<String, dynamic>;
        expect(
          (query['findNearest'] as Map<String, dynamic>)['distanceResultField'],
          VectorQueryReference.implicitDistanceResultField,
        );

        return http.Response(
          jsonEncode([
            {
              'document': {
                'name':
                    'projects/demo-project/databases/(default)/documents/items/item-1',
                'fields': {
                  VectorQueryReference.implicitDistanceResultField: {
                    'doubleValue': 0.25,
                  },
                },
              },
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      GoogleCloudFirestoreDatabase db = GoogleCloudFirestoreDatabase(
        FirestoreApi(client),
        'demo-project',
        client: client,
      );

      List<VectorQueryDocumentSnapshot> results = await db
          .collection('items')
          .findNearest(
            vectorField: 'embedding_field',
            queryVector: const VectorValue(vector: [3, 1, 2]),
            limit: 5,
            distanceMeasure: VectorDistanceMeasure.euclidean,
          )
          .get();

      expect(results, hasLength(1));
      expect(results.single.score, 0.25);
      expect(
        results.single.data!.containsKey(
          VectorQueryReference.implicitDistanceResultField,
        ),
        isFalse,
      );
    });

    test('findNearest surfaces a clean vector index create command', () async {
      MockClient client = MockClient((request) async {
        return http.Response(
          jsonEncode([
            {
              'error': {
                'code': 400,
                'message':
                    'Missing vector index configuration. Please create the required index with the following gcloud command: gcloud firestore indexes composite create --project=demo-project --collection-group=vectors --query-scope=COLLECTION --field-config=vector-config=\'{\\"dimension\\":\\"768\\",\\"flat\\": \\"{}\\"}\',field-path=vector',
                'status': 'FAILED_PRECONDITION',
              },
            },
          ]),
          400,
          headers: {'content-type': 'application/json'},
        );
      });

      GoogleCloudFirestoreDatabase db = GoogleCloudFirestoreDatabase(
        FirestoreApi(client),
        'demo-project',
        client: client,
      );

      try {
        await db
            .collection('vectors')
            .whereEqual('lod', 1)
            .findNearest(
              vectorField: 'vector',
              queryVector: VectorValue(vector: List<double>.filled(768, 0.0)),
              limit: 5,
              distanceMeasure: VectorDistanceMeasure.cosine,
            )
            .get();
        fail('Expected get() to throw');
      } catch (error) {
        String message = error.toString();
        expect(
          message,
          contains(
            '--field-config=\'order=ASCENDING,field-path=lod\'',
          ),
        );
        expect(
          message,
          contains(
            '--field-config=\'field-path=vector,vector-config={"dimension":768,"flat":{}}\'',
          ),
        );
        expect(
          message,
          contains(
            'Create it with: gcloud firestore indexes composite create --project=\'demo-project\' --collection-group=\'vectors\' --query-scope=collection',
          ),
        );
      }
    });
  });
}

Map<String, dynamic> _vectorJson(List<num> values) => {
      'mapValue': {
        'fields': {
          '__type__': {'stringValue': '__vector__'},
          'value': {
            'arrayValue': {
              'values': [
                for (final value in values)
                  {
                    'doubleValue': value.toDouble(),
                  },
              ],
            },
          },
        },
      },
    };
