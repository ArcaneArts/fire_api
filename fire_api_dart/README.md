# fire_api_dart

`fire_api_dart` is the Dart server implementation for [fire_api](https://pub.dev/packages/fire_api).

It provides the shared `FirestoreDatabase` and `FireStorage` API on top of Google Cloud Firestore and Storage.

## Setup

Run on Google Cloud or provide service-account credentials.

Useful environment variables for local development:

1. `GCP_PROJECT=<project_id>`
2. `GOOGLE_APPLICATION_CREDENTIALS=<path_to_service_account_key.json>`

If you need a custom database name or authenticated client, use `GoogleCloudFirestoreDatabase.create(...)`.

```dart
import 'package:fire_api_dart/fire_api_dart.dart';

void main() async {
  await GoogleCloudFirestoreDatabase.create();
  await GoogleCloudFireStorage.create();
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
    .whereEqual("color", "red")
    .findNearest(
      vectorField: "embedding_field",
      queryVector: const VectorValue([3, 1, 2]),
      limit: 5,
      distanceMeasure: VectorDistanceMeasure.euclidean,
      distanceResultField: "vector_distance",
    )
    .get();
```

Important:

- Vector queries require `GoogleCloudFirestoreDatabase.create()` or a constructor call that includes `client:`
- The legacy two-argument constructor still works for non-vector reads and writes

### Shared collection deletes

`CollectionReference.deleteAll(...)` is implemented in the shared `fire_api` package, so it works here automatically:

```dart
await FirestoreDatabase.instance.collection("sessions").deleteAll();

await FirestoreDatabase.instance.collection("sessions").deleteAll(
  only: {"a", "b", "c"},
  batchSize: 50,
);
```
