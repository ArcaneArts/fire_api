# fire_api_flutter

`fire_api_flutter` is the Flutter implementation for [fire_api](https://pub.dev/packages/fire_api).

It uses `cloud_firestore` and `firebase_storage` for the normal shared API surface, and uses Firestore REST for vector search while still authenticating as the current Firebase user.

## Setup

Initialize after Firebase:

```dart
import 'package:fire_api_flutter/fire_api_flutter.dart';

void main() {
  FirebaseFirestoreDatabase.create();
  FirebaseFireStorage.create();
}
```

## Notes

### Vector values

`VectorValue` is translated automatically in both directions, including nested maps and lists.

```dart
await FirestoreDatabase.instance.collection("items").doc("one").set({
  "embedding": const VectorValue([0.1, 0.2, 0.3]),
});
```

### Vector search

Vector queries are supported through the shared API:

```dart
final docs = await FirestoreDatabase.instance
    .collection("items")
    .findNearest(
      vectorField: "embedding_field",
      queryVector: const VectorValue([3, 1, 2]),
      limit: 10,
      distanceMeasure: VectorDistanceMeasure.euclidean,
      distanceResultField: "vector_distance",
    )
    .get();
```

Implementation details:

- vector queries use Firestore REST `runQuery`
- authentication is done with the current Firebase Auth ID token
- this keeps the request in the normal client-auth / Firestore-rules model
- vector queries are `get()` only and do not support realtime listeners

If you need custom auth behavior, `FirebaseFirestoreDatabase.create(...)` also accepts a custom `idTokenProvider`.

### Shared collection deletes

`CollectionReference.deleteAll(...)` is implemented in the shared `fire_api` package, so it works here automatically:

```dart
await FirestoreDatabase.instance.collection("sessions").deleteAll();

await FirestoreDatabase.instance.collection("sessions").deleteAll(
  only: {"a", "b", "c"},
  batchSize: 50,
);
```
