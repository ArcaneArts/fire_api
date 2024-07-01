This is a dart implementation for [fire_api](https://pub.dev/packages/fire_api)

## Usage
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
}

```