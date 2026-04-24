import 'dart:io';
import 'dart:math' as math;

import 'package:fire_api/fire_api.dart';
import 'package:fire_api_local/fire_api_local.dart';

Future<void> main(List<String> args) async {
  List<int> sizes = args.isEmpty
      ? <int>[10000, 100000, 1000000]
      : args.map(int.parse).toList();

  for (int size in sizes) {
    await _LocalBenchmark(size: size).run();
  }
}

class _LocalBenchmark {
  final int size;

  const _LocalBenchmark({required this.size});

  Future<void> run() async {
    Directory directory = await Directory.systemTemp.createTemp(
      'fire_api_local_benchmark_',
    );
    LocalFirestoreDatabase db = LocalFirestoreDatabase.open(
      '${directory.path}/benchmark.sqlite',
      changePollingInterval: null,
    );
    CollectionReference collection = db.collection('items');

    Duration seedDuration = await _time(() => _seed(collection));
    Duration equalityDuration = await _time(
      () => collection.whereEqual('group', 'g-42').get(),
    );
    Duration compositeDuration = await _time(
      () => collection
          .whereEqual('group', 'g-42')
          .whereGreaterThan('score', size ~/ 2)
          .get(),
    );
    Duration orderDuration = await _time(
      () => collection.orderBy('score', descending: true).limit(100).get(),
    );
    Duration countDuration = await _time(
      () => collection.whereEqual('group', 'g-42').count(),
    );
    Duration vectorDuration = await _time(
      () => collection
          .findNearest(
            vectorField: 'vector',
            queryVector: const VectorValue(vector: <double>[1, 0, 0, 0]),
            limit: 10,
            distanceMeasure: VectorDistanceMeasure.cosine,
          )
          .get(),
    );

    stdout.writeln(
      'size=$size '
      'seed=${seedDuration.inMilliseconds}ms '
      'eq=${equalityDuration.inMilliseconds}ms '
      'composite=${compositeDuration.inMilliseconds}ms '
      'order=${orderDuration.inMilliseconds}ms '
      'count=${countDuration.inMilliseconds}ms '
      'vector=${vectorDuration.inMilliseconds}ms',
    );
    db.close();
    await directory.delete(recursive: true);
  }

  Future<void> _seed(CollectionReference collection) async {
    for (int i = 0; i < size; i++) {
      await collection.doc('item-$i').set(<String, dynamic>{
        'group': 'g-${i % 100}',
        'score': i,
        'vector': VectorValue(vector: _vectorFor(i)),
      });
    }
  }

  List<double> _vectorFor(int seed) {
    double angle = seed / math.max(size, 1);
    return <double>[
      math.cos(angle),
      math.sin(angle),
      (seed % 13) / 13,
      (seed % 17) / 17,
    ];
  }

  Future<Duration> _time(Future<dynamic> Function() callback) async {
    Stopwatch stopwatch = Stopwatch()..start();
    await callback();
    stopwatch.stop();
    return stopwatch.elapsed;
  }
}
