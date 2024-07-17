# Firestore API

A stripped down interface for firestore databases which allows both dart servers using `firestore_api_dart` and flutter apps using `firestore_api_flutter` to use the same api. There are more limitations obviously because both backends need to roughly support the same things however it can be useful for basic data model management.

## Firestore Support

| Feature                           | Flutter | Dart |
|-----------------------------------|--|--|
| Get/Set/Add/Del/Upd Documents     | ✅ | ✅ |
| Get/Query Collections             | ✅ | ✅ |
| Agragate Count Queries            | ✅ | ✅ |
| Update Docs with FieldValues      | ✅ | ✅ |
| SetAtomic (txn getThenSet)        | ✅ | ✅ |
| Stream Documents                  | ✅ | ❌ |
| Stream Collection Queries         | ✅ | ❌ |
| Start/End At/After/Before Queries | ✅ | ✅ |
| Limit Queries                     | ✅ | ✅ |
| Order Queries                     | ✅ | ✅ |
| Get Cached                        | ✅ | ❌ |

## Cloud Storage Support (Firebase Storage)
| Feature           | Flutter | Dart |
|-------------------|--|--|
| Upload Files      | ✅ | ✅ |
| Download Files    | ✅ | ✅ |
| Delete Files      | ❌ | ❌ |
| Get File Metadata | ✅ | ✅ |
| Set File Metadata | ✅ | ✅ |
| List Files        | ❌ | ❌ |
| Stream Files      | ❌ | ❌ |
| Generate Download URL | ❌ | ❌ |
| Generate Upload URL   | ❌ | ❌ |

## Flutter Setup

Current Implementation is [fire_api_flutter](https://pub.dev/packages/fire_api_flutter)

All you really need to do is initialize the database with `FirebaseFirestoreDatabase.create();` after you initialize firebase. This will allow you to use the `FirestoreDatabase.instance` to interact with your firestore database.

```dart
import 'package:fire_api_flutter/fire_api_flutter.dart';

void main() {
  // AFTER YOU INITIALIZE FIREBASE
  FirebaseFirestoreDatabase.create();
  FirebaseFireStorage.create();
}
```

## Dart Server Setup

Current Implementation is [fire_api_dart](https://pub.dev/packages/fire_api_dart)

To use Firestore, you need to either make sure you are running in a google cloud environment or provide a service account key file.

If you are not running on google and want to easily test ensure the following environment variables are set when running. (in intellij, you can set them in the run configuration)
1. GCP_PROJECT=<project_id>
2. GOOGLE_APPLICATION_CREDENTIALS=<path_to_service_account_key.json>

If you need a custom database name, other than "(default)", or a custom AuthClient you can use the `GoogleCloudFirestoreDatabase.create(database: "mydbname", auth: AuthClient)` to override.

```dart
import 'package:fire_api_dart/fire_api_dart.dart';

void main() async {
  // You need to await this because using auth credentials requires async
  await GoogleCloudFirestoreDatabase.create();
  await GoogleCloudFireStorage.create();
}

```

# Usage

## Firestore API

The API is designed to be simple and easy to use. It was mostly modeled after the Firebase Firestore API

```dart
// Document references
DocumentReference dan = FirestoreDatabase.instance.collection("user").doc("dan");

// Get!
DocumentSnapshot danDoc = await dan.get();

// Check if exists
if (danDoc.exists) {
  // Get with .data
  Map<String, dynamic> dansData = danDoc.data!;
} else {
  print("Dan doesn't exist!");
}

// Set data
await dan.set({"name": "Dan", "age": 21});

// Update data
await dan.update({
  // add cats and dogs to list of likes, or make new list if the list isnt there
  "likes": FieldValue.arrayUnion(["cats", "dogs"]),
  // increment age by 1
  "age": FieldValue.increment(1)
});

// Atomic set for dan (if tons of devices are setting THIS document with DIFFERENT changes
// Use the setAtomic instead of just set so you dont wipe other peoples recent changes
// Its legit just runTXN -> get -> set -> commit
await dan.setAtomic((danRightNow) {
  // Do operations on this object
  danRightNow!["age"]++;
  return danRightNow;
});

// Delete
await dan.delete(); // ez

// Collection references & queries
CollectionReference users = FirestoreDatabase.instance.collection("user");

// Just get all of em
List<DocumentSnapshot> allUsers = await users.get();

// Get all users with age > 18
users
    .whereGreaterThanOrEqual("age", 18)
    .limit(10)
    .orderBy("name", descending: false)
    .get();

// Simply get the count of users under 18 but only count up to 100 of them but DONT DOWNLOAD THEM
int count = await users.whereLessThan("age", 18).limit(100).count();

// THIS WILL FAIL ON THE SERVER, FLUTTER SIDE ONLY
// Stream dan
Stream<DocumentSnapshot> danStream = dan.stream;

// THIS WILL FAIL ON THE SERVER, FLUTTER SIDE ONLY
// Stream all users with age 25 but only get the first 50
Stream<List<DocumentSnapshot>> usersStream =
    users.whereEqual("age", 25).limit(50).stream;
```

## Firebase Storage API

```dart
FireStorageRef r = FireStorage.instance
    .bucket("my_bucket")
    .ref("some/file");

Future<Uint8List> read = r.read();
Future<void> written = r.write(Uint8List);
```

### Note
Arcane Arts Inc. has no affiliation with Google or Firebase. This is a wrapper project and is not officially supported or endorsed by Google or Firebase. Please test thoroughly before using in a production environment.