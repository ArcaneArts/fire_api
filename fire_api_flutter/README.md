# fire_api_flutter

`fire_api_flutter` is the Flutter implementation for [fire_api](https://pub.dev/packages/fire_api).

It uses `cloud_firestore` and `firebase_storage` for the normal shared API surface.

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

`findNearest(...).get()` is supported in this adapter.

For normal document/query operations this package still uses `cloud_firestore`. For vector queries it sends an authenticated Firestore REST `StructuredQuery.findNearest` request using the current Firebase Auth ID token provider.

```dart
final docs = await FirestoreDatabase.instance
    .collection("items")
    .whereEqual("color", "red")
    .findNearest(
      vectorField: "embedding",
      queryVector: const VectorValue([0.1, 0.2, 0.3]),
      limit: 5,
      distanceMeasure: VectorDistanceMeasure.cosine,
      distanceResultField: "vector_distance",
    )
    .get();
```

### Shared collection deletes

`CollectionReference.deleteAll(...)` is implemented in the shared `fire_api` package, so it works here automatically:

```dart
await FirestoreDatabase.instance.collection("sessions").deleteAll();

await FirestoreDatabase.instance.collection("sessions").deleteAll(
  only: {"a", "b", "c"},
  batchSize: 50,
);
```
