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
