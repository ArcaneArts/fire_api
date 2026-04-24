## 1.0.0

- Initial local Firestore-compatible `fire_api` adapter.
- Added pure Dart SQLite storage through `package:sqlite3`.
- Added document CRUD, collection queries, streams, atomic updates, field
  transforms, vector value persistence, and exact nearest-vector queries.
- Added local parity coverage for query operators, cursors, root prefixes,
  subcollections, batched deletes, stream change types, and vector thresholds.
- Added persisted scalar field index rows for equality-style query candidate
  narrowing.
- Added indexed candidate narrowing for numeric/string range filters and
  indexed candidate ordering for scalar `orderBy` queries.
- Split the local backend into focused storage, query, index, vector, stream,
  cursor, codec, and aggregation implementation files.
- Added exact indexed `count()` and `sum(field)` aggregation paths for simple
  query shapes, with separate scalar and array index rows to preserve Firestore
  query semantics.
- Added local collection stream `removed` change events with the last known
  document payload.
- Added composite index planning that intersects multiple equality, array, and
  range index candidates before loading and validating documents.
- Added persisted snapshot change-log rows for local document writes and
  deletes.
- Updated collection streams to suppress no-op query snapshot emissions when
  unrelated writes do not affect the result set.
- Added resumable local snapshot change replay through `changesSince(...)` and
  `streamChangesSince(...)`.
- Added cross-handle snapshot notifications for file-backed databases using the
  persisted change log.
- Added local value encoding for `DateTime`, bytes, `LocalGeoPoint`, and
  `DocumentReference`, including nested map/list values.
- Fixed byte blob equality indexing so `Uint8List` fields can be queried
  without being mistaken for array fields.
- Added a persisted vector side table with dimension and magnitude metadata for
  exact vector query candidate acceleration.
- Added Firestore-like query validation for inequality/order and unsupported
  mixed operators.
- Added a local filesystem `FireStorage` adapter.
- Added benchmark harness coverage for large document and vector workloads.
- Split local adapter tests into focused core, query, index, stream, vector,
  and storage suites with additional edge-case coverage.
