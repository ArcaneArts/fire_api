## 1.2.0
* Storage support for delete

## 1.1.9

* Storage Interface

## 1.1.8

* Stream pooling to reduce opened streams

## 1.1.7

* Fix get cached flag being ignored
* Added getCachedOnly option

## 1.1.6

* Support for startAtValues, startAfterValues, endAtValues, endBeforeValues collection queries
* Support for get(cached: bool) (if available on documents). This will try the cache first then try without cached if not found.

## 1.1.5

* Support document change types on streams

## 1.1.4

* Support for parent getter on references

## 1.1.3

* Support CollectionReference.add(DocumentData) using the same generation method as firestore apis.

## 1.1.2

* Support id and path getters on DocumentSnapshots

## 1.1.1

* Support ID Field in `Document` and `Collection` classes

## 1.1.0

* Support snapshot metadata storage for later usage
* Support for startAt, startAfter, endAt, endBefore collection queries

## 1.0.1

* Fix Meta & Naming

## 1.0.0

* Initial Release