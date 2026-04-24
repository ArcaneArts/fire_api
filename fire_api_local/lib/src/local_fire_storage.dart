part of 'fire_api_local_base.dart';

class LocalFireStorage extends FireStorage {
  final Directory root;

  LocalFireStorage(String path) : root = Directory(path) {
    root.createSync(recursive: true);
  }

  @override
  Future<void> delete(String bucket, String path) async {
    File file = _file(bucket, path);
    File metadata = _metadataFile(bucket, path);
    if (await file.exists()) {
      await file.delete();
    }
    if (await metadata.exists()) {
      await metadata.delete();
    }
  }

  @override
  Future<void> download(String bucket, String path, String file) =>
      _file(bucket, path).copy(file).then((_) {});

  @override
  Future<Map<String, String>> getMetadata(String bucket, String path) async {
    File file = _metadataFile(bucket, path);
    if (!await file.exists()) return <String, String>{};

    Map<String, dynamic> metadata = Map<String, dynamic>.from(
      convert.jsonDecode(await file.readAsString()) as Map,
    );
    return metadata.map((key, value) => MapEntry(key, value.toString()));
  }

  @override
  Future<Uint8List> read(String bucket, String path) =>
      _file(bucket, path).readAsBytes();

  @override
  Future<void> setMetadata(
    String bucket,
    String path,
    Map<String, String> metadata,
  ) async {
    File file = _metadataFile(bucket, path);
    await file.parent.create(recursive: true);
    await file.writeAsString(convert.jsonEncode(metadata));
  }

  @override
  Future<void> upload(String bucket, String path, String file) =>
      File(file).readAsBytes().then((bytes) => write(bucket, path, bytes));

  @override
  Future<void> write(String bucket, String path, Uint8List data) async {
    File file = _file(bucket, path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data);
  }

  File _file(String bucket, String path) =>
      File(_join(<String>[root.path, _sanitize(bucket), ..._segments(path)]));

  File _metadataFile(String bucket, String path) =>
      File('${_file(bucket, path).path}.metadata.json');

  List<String> _segments(String path) => path
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .map(_sanitize)
      .toList();

  String _sanitize(String value) {
    if (value == '..' || value.contains(Platform.pathSeparator)) {
      throw ArgumentError.value(value, 'path', 'Unsafe local storage path.');
    }
    return value;
  }

  String _join(List<String> segments) => segments.join(Platform.pathSeparator);
}
