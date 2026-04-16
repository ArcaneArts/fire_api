# 1.7.4
* Fix implicit vector score field naming for nearest-neighbor queries on the Flutter adapter
* Improve missing vector index hints so prefiltered vector queries emit accurate `gcloud firestore indexes composite create` commands
* Align with `fire_api` 1.7.4 for the shared vector normalization and query-index helpers

# 1.7.0
* Accept artifact-style serialized `VectorValue` sentinel maps in Flutter Firestore write and query payloads
* Keep Flutter vector reads decoding back into the shared `VectorValue` model while preserving native Firestore vector storage
* Align with `fire_api` 1.7.0's artifact-backed vector serialization flow

# 1.6.0
* Support ranked vector query results with automatic score capture from Firestore nearest-neighbor queries
* Keep implicit vector score fields out of returned document data while exposing them through the shared API
* Ship the stable Flutter vector query adapter for the 1.6 release line

# 1.5.8
* Stabilize Firestore nearest-neighbor vector queries through authenticated REST `StructuredQuery.findNearest`
* Improve missing vector index failures with a copy-pasteable `gcloud` command

# 1.5.7
* Support recursive `VectorValue` conversion in both read and write paths
* Support shared collection helpers such as `deleteAll(...)` and `listIds(...)`
* Support nearest-neighbor vector query execution through Firestore REST `StructuredQuery.findNearest`
* Authenticate vector queries with the current Firebase Auth ID token provider

# 1.5.2
* Support fire_api 1.5.2 and rootPrefix

# 1.5.0
* Support fire_api 1.4.0

# 1.4.0
* Support fire_api 1.3.0 for Update Atomic

# 1.3.0
* Support fire_api 1.2.0

## 1.2.0

* **SEMI BREAKING** Allow the use of setAtomic while using windows by simply not actually doing it atomically. Yes this breaks atomicity, but it allows for the same code to be used on all platforms without crashing windows. You can disable this with `(FirestoreDatabase.instance as FirebaseFirestoreDatabase).useWindowsAtomicPatch = false`. However, this only happens on windows specifically if enabled.
* Adjusted dependency constraints to allow for newer versions of fire_api, and cloud_storage
* setAtomic actually sets now instead of calling update inside txn, shouldnt affect anything but prevents weird update bugs when you actually intended for a set.

## 1.1.6

* Support firebase storage
* Brings support up to fire_api 1.1.9+

## 1.1.4

* Support cache only getting
* Brings support up to fire_api 1.1.7+

## 1.1.3

* Support cache getting
* Support for startAtValues, startAfterValues, endAtValues, endBeforeValues collection queries
* Brings support up to fire_api 1.1.6+

## 1.1.2

* Support new metadata parameter access (supports fire_api 1.1.5+)
* Supports docChanges added,removed,modified in collection streams

## 1.1.1

* Fix transactions

## 1.1.0

* Support snapshot metadata storage for later usage
* Support for startAt, startAfter, endAt, endBefore collection queries

## 1.0.0

* Initial Release
