part of 'fire_api_local_base.dart';

extension _LocalDatabaseQueryValidation on LocalFirestoreDatabase {
  void _validateQuery(CollectionReference reference) {
    List<Clause> arrayContainsClauses = reference.clauses
        .where((clause) => clause.operator == ClauseOperator.arrayContains)
        .toList();
    List<Clause> disjunctiveClauses = reference.clauses
        .where((clause) => clause.operator.isLocalDisjunctive)
        .toList();
    List<Clause> notInClauses = reference.clauses
        .where((clause) => clause.operator == ClauseOperator.notIn)
        .toList();
    List<Clause> notEqualClauses = reference.clauses
        .where((clause) => clause.operator == ClauseOperator.notEqual)
        .toList();
    Set<String> inequalityFields = reference.clauses
        .where((clause) => clause.operator.isLocalInequality)
        .map((clause) => clause.field)
        .toSet();

    if (arrayContainsClauses.length > 1) {
      throw StateError(
        'LocalFirestoreDatabase supports only one arrayContains filter per query.',
      );
    }

    if (disjunctiveClauses.length > 1) {
      throw StateError(
        'LocalFirestoreDatabase supports only one in/arrayContainsAny/notIn filter per query.',
      );
    }

    if (notInClauses.isNotEmpty &&
        (notEqualClauses.isNotEmpty || disjunctiveClauses.length > 1)) {
      throw StateError(
        'LocalFirestoreDatabase cannot combine notIn with notEqual or another disjunctive filter.',
      );
    }

    for (Clause clause in reference.clauses) {
      if (clause.operator.usesListQueryValue &&
          (clause.value is! List || (clause.value as List).isEmpty)) {
        throw StateError(
          'LocalFirestoreDatabase ${clause.operator.name} filters require a non-empty List value.',
        );
      }
    }

    if (reference.qOrderBy != null &&
        inequalityFields.isNotEmpty &&
        !inequalityFields.contains(reference.qOrderBy)) {
      throw StateError(
        'LocalFirestoreDatabase requires orderBy to match an inequality field before ordering by another field.',
      );
    }
  }
}

extension _XClauseOperatorLocalValidation on ClauseOperator {
  bool get isLocalDisjunctive =>
      this == ClauseOperator.isIn ||
      this == ClauseOperator.arrayContainsAny ||
      this == ClauseOperator.notIn;

  bool get isLocalInequality =>
      this == ClauseOperator.lessThan ||
      this == ClauseOperator.lessThanOrEqual ||
      this == ClauseOperator.greaterThan ||
      this == ClauseOperator.greaterThanOrEqual ||
      this == ClauseOperator.notEqual ||
      this == ClauseOperator.notIn;
}
