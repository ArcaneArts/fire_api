This is a flutter implementation for [fire_api](https://pub.dev/packages/fire_api)

## Usage
All you really need to do is initialize the database with `FirebaseFirestoreDatabase.create();` after you initialize firebase. This will allow you to use the `FirestoreDatabase.instance` to interact with your firestore database.

```dart
import 'package:fire_api_flutter/fire_api_flutter.dart';

void main() {
  // AFTER YOU INITIALIZE FIREBASE
  FirebaseFirestoreDatabase.create();
}
```