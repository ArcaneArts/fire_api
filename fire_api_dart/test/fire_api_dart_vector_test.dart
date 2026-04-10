import 'dart:convert';

import 'package:fire_api/fire_api.dart';
import 'package:fire_api_dart/fire_api_dart.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('GoogleCloudFirestoreDatabase vector support', () {
    test('getDocument decodes vector values recursively', () async {
      final client = MockClient((request) async {
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
              'embedding': {
                'vectorValue': {
                  'values': [1, 2.5],
                },
              },
              'nested': {
                'mapValue': {
                  'fields': {
                    'history': {
                      'arrayValue': {
                        'values': [
                          {
                            'vectorValue': {
                              'values': [3, 4],
                            },
                          },
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

      final db = GoogleCloudFirestoreDatabase(
        FirestoreApi(client),
        'demo-project',
        client: client,
      );
      final ref = db.collection('users').doc('alice');
      final snapshot = await db.getDocument(ref);

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

    test('setDocument encodes nested vector values for commit writes',
        () async {
      late Map<String, dynamic> body;
      final client = MockClient((request) async {
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

      final db = GoogleCloudFirestoreDatabase(
        FirestoreApi(client),
        'demo-project',
        client: client,
      );

      await db.setDocument(db.collection('users').doc('alice'), {
        'embedding': const VectorValue([9, 8, 7]),
        'nested': {
          'items': [
            const VectorValue([1, 2]),
          ],
        },
      });

      final fields = (body['writes'] as List).single['update']['fields']
          as Map<String, dynamic>;
      expect(fields['embedding'], {
        'vectorValue': {
          'values': [9.0, 8.0, 7.0],
        },
      });
      expect(
        (((fields['nested'] as Map<String, dynamic>)['mapValue']
                as Map<String, dynamic>)['fields']
            as Map<String, dynamic>)['items'],
        {
          'arrayValue': {
            'values': [
              {
                'vectorValue': {
                  'values': [1.0, 2.0],
                },
              },
            ],
          },
        },
      );
    });

    test('updateDocument encodes vector values inside array transforms',
        () async {
      late Map<String, dynamic> body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final db = GoogleCloudFirestoreDatabase(
        FirestoreApi(client),
        'demo-project',
        client: client,
      );

      await db.updateDocument(db.collection('users').doc('alice'), {
        'history': FieldValue.arrayUnion([
          const VectorValue([4, 5])
        ]),
      });

      final writes = body['writes'] as List;
      final transforms =
          (writes.single['transform']['fieldTransforms'] as List).single;
      expect(transforms['fieldPath'], 'history');
      expect(transforms['appendMissingElements'], {
        'values': [
          {
            'vectorValue': {
              'values': [4.0, 5.0],
            },
          },
        ],
      });
    });

    test('updateDocumentAtomic decodes vectors before txn callback', () async {
      late Map<String, dynamic> commitBody;
      final client = MockClient((request) async {
        final path = request.url.path;

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
                'embedding': {
                  'vectorValue': {
                    'values': [1, 2],
                  },
                },
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

      final db = GoogleCloudFirestoreDatabase(
        FirestoreApi(client),
        'demo-project',
        client: client,
      );

      await db.updateDocumentAtomic(db.collection('users').doc('alice'),
          (data) {
        expect((data!['embedding'] as VectorValue).toArray(), [1.0, 2.0]);
        return {
          'embedding': const VectorValue([3, 4]),
        };
      });

      final updateFields = ((commitBody['writes'] as List).single['update']
          as Map<String, dynamic>)['fields'] as Map<String, dynamic>;
      expect(updateFields['embedding'], {
        'vectorValue': {
          'values': [3.0, 4.0],
        },
      });
      expect(commitBody['transaction'], 'txn-123');
    });

    test('findNearest executes runQuery with vector search config', () async {
      late Map<String, dynamic> body;
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://firestore.googleapis.com/v1/projects/demo-project/databases/(default)/documents:runQuery',
        );

        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode([
            {
              'document': {
                'name':
                    'projects/demo-project/databases/(default)/documents/items/item-1',
                'fields': {
                  'color': {
                    'stringValue': 'red',
                  },
                  'vector_distance': {
                    'doubleValue': 0.42,
                  },
                },
              },
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final db = GoogleCloudFirestoreDatabase(
        FirestoreApi(client),
        'demo-project',
        client: client,
      );

      final results = await db
          .collection('items')
          .whereEqual('color', 'red')
          .findNearest(
            vectorField: 'embedding_field',
            queryVector: const VectorValue([3, 1, 2]),
            limit: 5,
            distanceMeasure: VectorDistanceMeasure.euclidean,
            distanceResultField: 'vector_distance',
            distanceThreshold: 4.5,
          )
          .get();

      final structuredQuery = body['structuredQuery'] as Map<String, dynamic>;
      expect(structuredQuery['where'], {
        'fieldFilter': {
          'field': {'fieldPath': 'color'},
          'op': 'EQUAL',
          'value': {
            'stringValue': 'red',
          },
        },
      });
      expect(structuredQuery['findNearest'], {
        'vectorField': {
          'fieldPath': 'embedding_field',
        },
        'queryVector': {
          'vectorValue': {
            'values': [3.0, 1.0, 2.0],
          },
        },
        'limit': 5,
        'distanceMeasure': 'EUCLIDEAN',
        'distanceResultField': 'vector_distance',
        'distanceThreshold': 4.5,
      });

      expect(results, hasLength(1));
      expect(results.single.id, 'item-1');
      expect(results.single.data!['color'], 'red');
      expect(results.single.data!['vector_distance'], 0.42);
    });
  });
}
