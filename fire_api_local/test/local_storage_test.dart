import 'dart:io';
import 'dart:typed_data';

import 'package:fire_api/fire_api.dart';
import 'package:fire_api_local/fire_api_local.dart';
import 'package:test/test.dart';

void main() {
  group('LocalFireStorage', () {
    test('stores local files and metadata through FireStorage API', () async {
      Directory directory = await Directory.systemTemp.createTemp(
        'fire_api_local_storage_test_',
      );
      LocalFireStorage storage = LocalFireStorage(directory.path);
      FireStorageRef ref = storage.bucket('bucket-a').ref('folder/object.bin');

      await ref.write(Uint8List.fromList(<int>[1, 2, 3]));
      await ref.setMetadata(<String, String>{'content-type': 'test/binary'});

      expect(await ref.read(), orderedEquals(<int>[1, 2, 3]));
      expect(await ref.getMetadata(), <String, String>{
        'content-type': 'test/binary',
      });
      await ref.delete();
      expect(
        File('${directory.path}/bucket-a/folder/object.bin').existsSync(),
        isFalse,
      );
      await directory.delete(recursive: true);
    });

    test('rejects unsafe bucket and object paths', () async {
      Directory directory = await Directory.systemTemp.createTemp(
        'fire_api_local_storage_safety_test_',
      );
      LocalFireStorage storage = LocalFireStorage(directory.path);

      await expectLater(
        storage
            .bucket('safe')
            .ref('../evil.bin')
            .write(Uint8List.fromList(<int>[1])),
        throwsArgumentError,
      );
      await expectLater(
        storage
            .bucket('safe')
            .ref('folder/..')
            .write(Uint8List.fromList(<int>[1])),
        throwsArgumentError,
      );
      await expectLater(
        storage
            .bucket('unsafe/bucket')
            .ref('object.bin')
            .write(Uint8List.fromList(<int>[1])),
        throwsArgumentError,
      );
      await directory.delete(recursive: true);
    });
  });
}
