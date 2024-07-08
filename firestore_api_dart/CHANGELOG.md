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
