# 1.6.0
* Add ranked vector query results with `VectorQueryDocumentSnapshot.rank` and `.score`
* Automatically request and capture vector distance scores without leaking implicit score fields into returned document data
* Finalize the shared vector query surface and collection helpers for the 1.6 release line

# 1.5.9
* Tighten nearest-neighbor vector query support for the official Dart adapter release
* Improve server-side vector query failure messaging for missing Firestore vector indexes

# 1.5.8
* Stabilize nearest-neighbor vector query support across the shared API and official adapters
* Improve missing vector index errors with a clean `gcloud firestore indexes composite create` command

# 1.5.7
* Add `CollectionReference.deleteAll(...)` with batched deletes and optional `only:` filtering
* Add `CollectionReference.listIds(...)` for batched ID streaming
* Add shared `findNearest(...).get()` API surface for nearest-neighbor vector search
* Recursively convert `VectorValue` inside nested maps and lists
* Restore vector query execution in the official Dart and Flutter adapters

# 1.5.4
* Support vector values

# 1.5.2
* Support for rootPrefix

# 1.5.1
* Pagination

# 1.4.0
* Support downloading files

# 1.3.0
* Support update atomics

# 1.2.0
* Storage support for delete

# 1.1.9

* Storage Interface

# 1.1.8

* Stream pooling to reduce opened streams

# 1.1.7

* Fix get cached flag being ignored
* Added getCachedOnly option

# 1.1.6

* Support for startAtValues, startAfterValues, endAtValues, endBeforeValues collection queries
* Support for get(cached: bool) (if available on documents). This will try the cache first then try without cached if not found.

# 1.1.5

* Support document change types on streams

# 1.1.4

* Support for parent getter on references

# 1.1.3

* Support CollectionReference.add(DocumentData) using the same generation method as firestore apis.

# 1.1.2

* Support id and path getters on DocumentSnapshots

# 1.1.1

* Support ID Field in `Document` and `Collection` classes

# 1.1.0

* Support snapshot metadata storage for later usage
* Support for startAt, startAfter, endAt, endBefore collection queries

# 1.0.1

* Fix Meta & Naming

# 1.0.0

* Initial Release
