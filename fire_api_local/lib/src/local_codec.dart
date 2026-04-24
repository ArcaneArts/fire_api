part of 'fire_api_local_base.dart';

class _LocalDocumentCodec {
  static const String _typeKey = 'magic\$type';
  static const String _timestampType = 'fire_api_local_timestamp';
  static const String _blobType = 'fire_api_local_blob';
  static const String _geoPointType = 'fire_api_local_geo_point';
  static const String _documentReferenceType =
      'fire_api_local_document_reference';

  const _LocalDocumentCodec._();

  static String encode(DocumentData data) => convert.jsonEncode(
    _toJsonValue(convertRuntimeVectorMapToSerialized(data)),
  );

  static DocumentData decode(String json, {FirestoreDatabase? db}) =>
      Map<String, dynamic>.from(
        convertSerializedVectorValuesToRuntime(
              _fromJsonValue(convert.jsonDecode(json), db: db),
            )
            as Map,
      );

  static DocumentData clone(DocumentData data, {FirestoreDatabase? db}) =>
      decode(encode(data), db: db);

  static dynamic cloneValue(dynamic value, {FirestoreDatabase? db}) =>
      convertSerializedVectorValuesToRuntime(
        _fromJsonValue(
          convert.jsonDecode(
            convert.jsonEncode(
              _toJsonValue(convertRuntimeVectorValuesToSerialized(value)),
            ),
          ),
          db: db ?? (value is DocumentReference ? value.db : null),
        ),
      );

  static dynamic _toJsonValue(dynamic value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }

    if (value is DateTime) {
      return <String, dynamic>{
        _typeKey: _timestampType,
        'microsecondsSinceEpoch': value.toUtc().microsecondsSinceEpoch,
      };
    }

    if (value is Uint8List) {
      return <String, dynamic>{
        _typeKey: _blobType,
        'base64': convert.base64Encode(value),
      };
    }

    if (value is LocalGeoPoint) {
      return <String, dynamic>{
        _typeKey: _geoPointType,
        'latitude': value.latitude,
        'longitude': value.longitude,
      };
    }

    if (value is DocumentReference) {
      return <String, dynamic>{
        _typeKey: _documentReferenceType,
        'path': value.path,
      };
    }

    if (value is List) {
      return value.map(_toJsonValue).toList();
    }

    if (value is Map) {
      return Map<String, dynamic>.fromEntries(
        value.entries.map(
          (entry) => MapEntry(entry.key.toString(), _toJsonValue(entry.value)),
        ),
      );
    }

    throw UnsupportedError(
      'Unsupported local Firestore value: '
      '${value.runtimeType}',
    );
  }

  static dynamic _fromJsonValue(dynamic value, {FirestoreDatabase? db}) {
    if (value is List) {
      return value.map((item) => _fromJsonValue(item, db: db)).toList();
    }

    if (value is Map) {
      Map<String, dynamic> map = Map<String, dynamic>.from(value);
      dynamic type = map[_typeKey];
      if (type == _timestampType) {
        return DateTime.fromMicrosecondsSinceEpoch(
          (map['microsecondsSinceEpoch'] as num).toInt(),
          isUtc: true,
        );
      }

      if (type == _blobType) {
        return Uint8List.fromList(
          convert.base64Decode(map['base64'] as String),
        );
      }

      if (type == _geoPointType) {
        return LocalGeoPoint(
          latitude: (map['latitude'] as num).toDouble(),
          longitude: (map['longitude'] as num).toDouble(),
        );
      }

      if (type == _documentReferenceType && db != null) {
        return db.document(map['path'] as String);
      }

      return Map<String, dynamic>.fromEntries(
        map.entries.map(
          (entry) => MapEntry(entry.key, _fromJsonValue(entry.value, db: db)),
        ),
      );
    }

    return value;
  }
}
