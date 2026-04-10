import 'package:fire_api/fire_api.dart';
import 'package:test/test.dart';

void main() {
  test('convertMapValuesRecursive converts nested maps and lists', () {
    final converted = convertMapValuesRecursive({
      'count': 1,
      'nested': {
        'labels': ['alpha', 'beta'],
      },
      'items': [
        {
          'score': 2,
          'tags': ['cat', 'dog'],
        },
        [
          3,
          {'value': 'zeta'},
        ],
      ],
    }, (value) {
      if (value is int) {
        return value + 1;
      }

      if (value is String) {
        return value.toUpperCase();
      }

      return value;
    });

    expect(converted['count'], 2);
    expect(converted['nested'], {
      'labels': ['ALPHA', 'BETA'],
    });
    expect(converted['items'], [
      {
        'score': 3,
        'tags': ['CAT', 'DOG'],
      },
      [
        4,
        {'value': 'ZETA'},
      ],
    ]);
  });
}
