# 1.7.4
* Fix implicit vector score field naming for nearest-neighbor queries on the Dart server adapter
* Improve missing vector index hints so prefiltered vector queries emit accurate `gcloud firestore indexes composite create` commands
* Align with `fire_api` 1.7.4 for the shared vector normalization and query-index helpers

# 1.7.0
* Accept artifact-style serialized `VectorValue` sentinel maps in Firestore write and query payloads
* Keep Dart server vector reads decoding back into the shared `VectorValue` model while preserving native Firestore vector storage
* Align with `fire_api` 1.7.0's artifact-backed vector serialization flow

# 1.6.0
* Support ranked vector query results with automatic score capture from Firestore nearest-neighbor queries
* Keep implicit vector score fields out of returned document data while exposing them through the shared API
* Ship the stable Firestore server adapter for the 1.6 release line

# 1.5.9
* Fix server-side vector query error handling so missing index failures are caught and rewritten correctly
* Emit a single-line copy-pasteable `gcloud firestore indexes composite create` command for missing vector indexes

# 1.5.8
* Stabilize Firestore vector query execution through `StructuredQuery.findNearest`
* Improve missing vector index failures with a copy-pasteable `gcloud` command

# 1.5.7
* Support recursive `VectorValue` conversion in both read and write paths
* Support shared collection helpers such as `deleteAll(...)` and `listIds(...)`
* Support nearest-neighbor vector query execution through `StructuredQuery.findNearest`
* Encode vectors using Firestore's sentinel map value shape on both reads and writes

# 1.4.0
* Support downloads

# 1.3.0
* Support fire_api 1.3.0
* Update now works with FieldValue.delete()

# 1.2.0
* Support fire_api 1.2.0

## 1.1.6
* Fix subcollection queries not working

## 1.1.5
* Support FireAPI 1.1.9+ with firebase storage support

## 1.1.4

* Support cache only getting (but not actually supporting)
* Brings support up to fire_api 1.1.7+

## 1.1.3

* Support startAtValues, startAfterValues, endAtValues, endBeforeValues collection queries
* Ignore get(cached: bool) as its not supported by Firestore over REST
* Support fire_api 1.1.6+

## 1.1.2

* Support new metadata parameter access (supports fire_api 1.1.5+)

## 1.1.1

* Fixed collection queries referencing the wrong collection id (used path)
* Fixed atomic sets not specifying the db correctly
* Fixed updates not correctly applying when mixing field values and non field values

## 1.1.0

* Support snapshot metadata storage for later usage
* Support for startAt, startAfter, endAt, endBefore collection queries

## 1.0.0

* Initial Release
