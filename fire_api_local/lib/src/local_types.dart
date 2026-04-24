part of 'fire_api_local_base.dart';

class LocalGeoPoint {
  final double latitude;
  final double longitude;

  const LocalGeoPoint({required this.latitude, required this.longitude});

  @override
  bool operator ==(Object other) =>
      other is LocalGeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() =>
      'LocalGeoPoint(latitude: $latitude, longitude: $longitude)';
}

class LocalDocumentChange {
  final int version;
  final DocumentReference reference;
  final String path;
  final String collectionPath;
  final String documentId;
  final DocumentChangeType changeType;
  final DocumentData? data;
  final DateTime createdAt;

  const LocalDocumentChange({
    required this.version,
    required this.reference,
    required this.path,
    required this.collectionPath,
    required this.documentId,
    required this.changeType,
    required this.data,
    required this.createdAt,
  });

  factory LocalDocumentChange.fromRow(
    sql.Row row, {
    required FirestoreDatabase db,
  }) {
    String path = row['path'] as String;
    String changeType = row['change_type'] as String;
    String? dataJson = row['data_json'] as String?;
    String visiblePath =
        db.rootPrefix.isNotEmpty && path.startsWith('${db.rootPrefix}/')
        ? path.substring(db.rootPrefix.length + 1)
        : path;
    return LocalDocumentChange(
      version: row['version'] as int,
      reference: db.document(visiblePath),
      path: path,
      collectionPath: row['collection_path'] as String,
      documentId: row['document_id'] as String,
      changeType: DocumentChangeType.values.firstWhere(
        (type) => type.name == changeType,
      ),
      data: dataJson == null
          ? null
          : _LocalDocumentCodec.decode(dataJson, db: db),
      createdAt: DateTime.fromMicrosecondsSinceEpoch(
        row['created_at'] as int,
        isUtc: true,
      ),
    );
  }
}
