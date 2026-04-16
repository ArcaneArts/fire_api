import 'package:fire_api/fire_api.dart';
import 'package:test/test.dart';

void main() {
  test('VectorValue serializes to a sentinel map', () {
    VectorValue value = const VectorValue(vector: [1, 2, 3]);

    expect(value.toMap(), <String, dynamic>{
      'magic\$type': 'vector',
      'vector': <double>[1, 2, 3],
    });
  });

  test('VectorValue round-trips through artifact json helpers', () {
    VectorValue original = const VectorValue(vector: [1, 2, 3]);
    String json = original.to.json;
    VectorValue restored = $VectorValue.from.json(json);

    expect(json, contains(r'magic$type'));
    expect(restored, original);
  });

  test('convertSerializedVectorValuesToRuntime decodes nested vectors', () {
    dynamic converted =
        convertSerializedVectorValuesToRuntime(<String, dynamic>{
      'embedding': <String, dynamic>{
        'magic\$type': 'vector',
        'vector': <num>[1, 2, 3],
      },
      'items': <dynamic>[
        <String, dynamic>{
          'magic\$type': 'vector',
          'vector': <num>[4, 5],
        },
      ],
    });

    Map<String, dynamic> map = Map<String, dynamic>.from(converted as Map);
    expect(map['embedding'], const VectorValue(vector: [1, 2, 3]));
    expect(map['items'], <dynamic>[
      const VectorValue(vector: [4, 5])
    ]);
  });

  test('convertRuntimeVectorValuesToSerialized encodes nested vectors', () {
    dynamic converted =
        convertRuntimeVectorValuesToSerialized(<String, dynamic>{
      'embedding': const VectorValue(vector: [1, 2, 3]),
      'items': <dynamic>[
        const VectorValue(vector: [4, 5]),
      ],
    });

    expect(converted, <String, dynamic>{
      'embedding': <String, dynamic>{
        'magic\$type': 'vector',
        'vector': <double>[1, 2, 3],
      },
      'items': <dynamic>[
        <String, dynamic>{
          'magic\$type': 'vector',
          'vector': <double>[4, 5],
        },
      ],
    });
  });

  test('VectorValue tolerates cast numeric lists when exporting', () {
    dynamic raw = <int>[1, 2, 3];
    List<double> casted = (raw as List).cast<double>();
    VectorValue value = VectorValue(vector: casted);

    expect(value.toArray(), <double>[1, 2, 3]);
    expect(value.toMap(), <String, dynamic>{
      'magic\$type': 'vector',
      'vector': <double>[1, 2, 3],
    });
    expect(value, const VectorValue(vector: [1, 2, 3]));
  });
}
