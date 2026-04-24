# fire_api_local

A pure Dart local implementation of the `fire_api` Firestore wrapper.

This package is intended for local apps, tests, tools, and embedded server
use cases where you want the same `fire_api` surface without talking to
Firestore.

## Storage

`fire_api_local` uses `package:sqlite3` directly, so it does not require
Flutter or `sqflite`.

Documents are stored as JSON blobs in SQLite. Query behavior is currently
evaluated in Dart for correctness, with a simple collection/document-id SQLite
index underneath. Equality-style filters, numeric/string range filters, and
scalar `orderBy` queries also maintain/use persisted scalar field index rows to
narrow candidate documents before Dart-side query validation. Exact vector
nearest-neighbor search is supported by scanning the matching collection query
and ranking vectors in memory.
Exact `count()` and `sum(field)` aggregations use the persisted index rows for
simple non-paginated query shapes and fall back to the normal query engine for
more complex shapes.
Multi-clause queries intersect the available scalar/array/range index rows
before loading candidate documents, then still run the shared Dart matcher as a
correctness backstop. Vector fields are also mirrored into a side table with
dimension and magnitude metadata so nearest-neighbor queries can use indexed
vector candidates while preserving exact ranking.

## Usage

```dart
import 'package:fire_api/fire_api.dart';
import 'package:fire_api_local/fire_api_local.dart';

Future<void> main() async {
  LocalFirestoreDatabase db = LocalFirestoreDatabase.open('local.db');

  await db.collection('chunks').doc('a').set({
    'content': 'Hello world',
    'vector': const VectorValue(vector: [1, 0, 0]),
  });

  List<VectorQueryDocumentSnapshot> results = await db
      .collection('chunks')
      .findNearest(
        vectorField: 'vector',
        queryVector: const VectorValue(vector: [1, 0, 0]),
        limit: 10,
        distanceMeasure: VectorDistanceMeasure.cosine,
      )
      .get();

  db.close();
}
```

For tests, use an in-memory database:

```dart
LocalFirestoreDatabase db = LocalFirestoreDatabase.memory();
```

Use local filesystem storage when the shared `FireStorage` API is needed:

```dart
LocalFireStorage storage = LocalFireStorage('local_storage');
await storage.bucket('files').ref('hello.txt').write(Uint8List.fromList([1]));
```

Replay local snapshot changes from the persisted change log:

```dart
List<LocalDocumentChange> changes = db.changesSince(lastSeenVersion);
```

## Current Status

Supported now:

- document `set`, `get`, `update`, `delete`
- collection `get`, `count`, `sum`, `listIds`, `deleteAll`
- dotted update paths
- `FieldValue` transforms for array union/remove, increment/decrement, delete,
  and local server timestamps
- document and collection streams, including `added`, `modified`, and `removed`
  collection document change types
- persisted snapshot change log rows for local writes and deletes
- resumable local snapshot changes with `changesSince(...)` and
  `streamChangesSince(...)`
- cross-handle snapshot notifications for file-backed databases
- query snapshot streams suppress no-op emissions when unrelated writes do not
  affect the result set
- atomic set/update using SQLite transactions
- `VectorValue` persistence and exact vector nearest queries with distance
  result fields and distance thresholds
- vector side-table metadata and exact vector candidate acceleration
- local encoding for `DateTime`, bytes, `LocalGeoPoint`, and
  `DocumentReference` values
- persisted scalar indexes for equality, `in`, `array-contains`, and
  `array-contains-any` candidate narrowing
- persisted scalar indexes for numeric/string range filter narrowing and
  scalar `orderBy` candidate ordering
- exact indexed `count()` and `sum(field)` aggregations for simple query shapes
- composite index planning for multi-clause equality, array, and range filters
- local filesystem `FireStorage` adapter
- benchmark harness for 10k, 100k, and 1m document workloads
