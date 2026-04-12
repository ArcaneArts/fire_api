# Fire API

`fire_api` is a shared Firestore and Firebase Storage wrapper that lets Flutter apps and Dart servers use the same API surface.

The shared package models a smaller common subset of Firestore so the same document, query, aggregate, atomic-update, and storage code can run against:

- `fire_api_flutter` for Flutter via `cloud_firestore` and `firebase_storage`
- `fire_api_dart` for Dart servers via Google Cloud Firestore and Storage APIs

## Firestore Support

| Feature | Flutter | Dart |
| -- | -- | -- |
| Get / Set / Add / Delete / Update documents | ✅ | ✅ |
| Query collections | ✅ | ✅ |
| Aggregate count queries | ✅ | ✅ |
| Aggregate sum queries | ✅ | ✅ |
| `FieldValue` updates | ✅ | ✅ |
| Atomic get-then-set / get-then-update | ✅ | ✅ |
| Start / end at / after / before queries | ✅ | ✅ |
| Limit queries | ✅ | ✅ |
| Order queries | ✅ | ✅ |
| Recursive `VectorValue` read / write conversion | ✅ | ✅ |
| Nearest-neighbor vector query API surface | ✅ | ✅ |
| Nearest-neighbor vector query execution in official adapters | ✅ | ✅ |
| `CollectionReference.deleteAll()` | ✅ | ✅ |
| Realtime document streams | ✅ | ❌ |
| Realtime collection streams | ✅ | ❌ |
| Cached document reads | ✅ | ❌ |

## Cloud Storage Support

| Feature | Flutter | Dart |
| -- | -- | -- |
| Upload files | ✅ | ✅ |
| Download files | ✅ | ✅ |
| Delete files | ❌ | ❌ |
| Get file metadata | ✅ | ✅ |
| Set file metadata | ✅ | ✅ |
| List files | ❌ | ❌ |
| Stream files | ❌ | ❌ |
| Generate download URLs | ❌ | ❌ |
| Generate upload URLs | ❌ | ❌ |

## Setup

### Flutter

Current implementation: [fire_api_flutter](https://pub.dev/packages/fire_api_flutter)

Initialize after Firebase:

```dart
import 'package:fire_api_flutter/fire_api_flutter.dart';

void main() {
  FirebaseFirestoreDatabase.create();
  FirebaseFireStorage.create();
}
```

### Dart Server

Current implementation: [fire_api_dart](https://pub.dev/packages/fire_api_dart)

To use Firestore, run on Google Cloud or provide service-account credentials.

Useful environment variables for local development:

1. `GCP_PROJECT=<project_id>`
2. `GOOGLE_APPLICATION_CREDENTIALS=<path_to_service_account_key.json>`

If you need a custom database name or custom authenticated client, use `GoogleCloudFirestoreDatabase.create(...)`.

```dart
import 'package:fire_api_dart/fire_api_dart.dart';

void main() async {
  await GoogleCloudFirestoreDatabase.create();
  await GoogleCloudFireStorage.create();
}
```

## Usage

### Documents

```dart
final dan = FirestoreDatabase.instance.collection("user").doc("dan");

final danDoc = await dan.get();

if (danDoc.exists) {
  final data = danDoc.data!;
  print(data["name"]);
}

await dan.set({
  "name": "Dan",
  "age": 21,
});

await dan.update({
  "likes": FieldValue.arrayUnion(["cats", "dogs"]),
  "age": FieldValue.increment(1),
});

await dan.setAtomic((current) {
  current!["age"]++;
  return current;
});

await dan.delete();
```

### Queries

```dart
final users = FirestoreDatabase.instance.collection("user");

final allUsers = await users.get();

final adults = await users
    .whereGreaterThanOrEqual("age", 18)
    .orderBy("name")
    .limit(10)
    .get();

final under18Count = await users
    .whereLessThan("age", 18)
    .limit(100)
    .count();
```

### Listing IDs

`listIds()` streams document IDs by paging through the current query in batches.

```dart
final ids = await FirestoreDatabase.instance
    .collection("items")
    .whereEqual("enabled", true)
    .listIds(batchSize: 100)
    .toList();
```

### Vector Values

`VectorValue` is the shared vector type for both adapters. Reads and writes convert recursively through nested maps and lists.

```dart
await FirestoreDatabase.instance.collection("items").doc("one").set({
  "title": "Example",
  "embedding": const VectorValue([0.2, 0.4, 0.6]),
  "nested": {
    "history": [
      const VectorValue([1, 2, 3]),
    ],
  },
});

final doc = await FirestoreDatabase.instance.collection("items").doc("one").get();
final embedding = doc.data!["embedding"] as VectorValue;
```

### Vector Search

The shared package exposes `findNearest(...).get()` as a request/response-only vector search API.

```dart
final docs = await FirestoreDatabase.instance
    .collection("items")
    .whereEqual("color", "red")
    .findNearest(
      vectorField: "embedding",
      queryVector: const VectorValue([0.2, 0.4, 0.6]),
      limit: 5,
      distanceMeasure: VectorDistanceMeasure.cosine,
      distanceResultField: "vector_distance",
      distanceThreshold: 0.5,
    )
    .get();
```

Notes:

- vector queries are `get()` only and do not expose realtime streams
- `fire_api_dart` executes vector queries through Firestore `StructuredQuery.findNearest`
- `fire_api_flutter` executes vector queries through authenticated Firestore REST requests

### Collection Deletes

`deleteAll()` is implemented in the shared package and works by:

1. Counting the remaining documents
2. Fetching and deleting up to `batchSize` documents at a time
3. Repeating until the collection is empty

```dart
await FirestoreDatabase.instance
    .collection("users")
    .doc("dan")
    .collection("sessions")
    .deleteAll();

await FirestoreDatabase.instance
    .collection("items")
    .deleteAll(
      only: {"a", "b", "c"},
      batchSize: 50,
    );
```

Notes:

- `batchSize` defaults to `100`
- `only:` lets you target a known set of document IDs
- if every ID in `only:` is already gone, the operation finishes early

### Streams

Realtime streams are Flutter-only:

```dart
final danStream = FirestoreDatabase.instance
    .collection("user")
    .doc("dan")
    .stream;

final usersStream = FirestoreDatabase.instance
    .collection("user")
    .whereEqual("age", 25)
    .limit(50)
    .stream;
```

### Firebase Storage

```dart
final ref = FireStorage.instance
    .bucket("my_bucket")
    .ref("some/file");

final bytes = await ref.read();
await ref.write(bytes);
```

## Notes

- This is an unofficial wrapper around Firebase / Google Cloud APIs.
- Test carefully before using in production.
