# fire_api_local Checklist

## Query Indexes And Performance

- [x] Add persisted scalar field indexes for equality filters.
- [x] Use scalar indexes to narrow range filters.
- [x] Use scalar indexes to accelerate `orderBy`.
- [x] Use scalar indexes to accelerate `count()`.
- [x] Use scalar indexes to accelerate `sum(field)`.
- [x] Add composite index planning for multi-clause queries.
- [x] Add query planner diagnostics for indexed vs scanned execution.
- [x] Add benchmarks for 10k, 100k, and 1m document query workloads.

## Vector Search

- [x] Keep exact brute-force vector search as the correctness fallback.
- [x] Persist vector metadata separately from document JSON.
- [x] Add exact vector search pruning after scalar prefilters.
- [x] Add optional vector index acceleration.
- [x] Add vector benchmark coverage across dimensions and collection sizes.

## Realtime And Change Tracking

- [x] Add removed document change events for collection streams.
- [x] Add persisted change log entries for writes and deletes.
- [x] Support resumable local snapshots from the persisted change log.
- [x] Support cross-process notifications for multiple local database handles.

## Firestore Type Coverage

- [x] Add local encoding for `DateTime` / timestamp values.
- [x] Add local encoding for bytes/blob values.
- [x] Add local encoding for geo points.
- [x] Add local encoding for document references.
- [x] Add tests for nested and array-contained special values.

## Transaction Semantics

- [x] Keep single-document atomic set/update backed by SQLite transactions.
- [x] Add multi-document transaction API if the shared wrapper exposes one. Not exposed by the shared wrapper.
- [x] Add retry/conflict semantics if concurrent local access requires it.

## Query Semantics

- [x] Add validation for Firestore-like inequality/order combinations.
- [x] Add validation for unsupported mixed query operators.
- [x] Expand cursor tests for descending order and multiple values.
- [x] Add pagination tests via `DocumentPage`.
- [x] Add collection group queries if the shared wrapper exposes them. Not exposed by the shared wrapper.

## Storage

- [x] Decide whether `FireStorage` needs a local filesystem adapter.
- [x] Add local storage adapter if shared local deployments need it.

## Packaging

- [x] Keep `fire_api_local` pure Dart.
- [x] Document SQLite platform requirements.
- [x] Add release notes as feature milestones land.
