import 'dart:async';

import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/user_management/data/models/department.dart';
import 'package:gsuhub/features/user_management/data/repositories/department_repository.dart';

/// The departments list in memory (2026-11-17), with the database's
/// rules that matter on screen: a name only once, whatever the case.
class FakeDepartmentRepository implements DepartmentRepository {
  FakeDepartmentRepository([List<Department>? departments])
    : _departments = [...?departments];

  /// The list DOrSU-shaped test data starts from.
  static List<Department> sample() => const [
    Department(
      id: 'dep-fcet',
      name: 'Faculty of Computing, Engineering and Technology',
    ),
    Department(id: 'dep-fbm', name: 'Faculty of Business and Management'),
    Department(id: 'dep-gsu', name: 'General Services Unit'),
    Department(id: 'dep-old', name: 'Old Office', isActive: false),
  ];

  final List<Department> _departments;
  final _changes = StreamController<void>.broadcast();

  /// When set, reading the list fails with it.
  Failure? readFailure;

  int _next = 0;

  List<Department> get all => List.unmodifiable(_departments);

  @override
  Future<Result<List<Department>>> getActive() async {
    if (readFailure case final failure?) return Result.failure(failure);
    return Result.success(
      [
        for (final d in _departments)
          if (d.isActive) d,
      ]..sort((a, b) => a.name.compareTo(b.name)),
    );
  }

  @override
  Stream<Result<List<Department>>> watchAll() async* {
    yield _sorted();
    yield* _changes.stream.map((_) => _sorted());
  }

  Result<List<Department>> _sorted() => Result.success(
    [..._departments]..sort((a, b) => a.name.compareTo(b.name)),
  );

  @override
  Future<Result<String>> create(String name) async {
    final clean = name.trim();
    final existing = _departments.where(
      (d) => d.name.toLowerCase() == clean.toLowerCase(),
    );
    if (existing.isNotEmpty) {
      return Result.failure(
        ValidationFailure('${existing.first.name} is already on the list.'),
      );
    }
    final id = 'dep-new-${_next++}';
    _departments.add(Department(id: id, name: clean));
    _changes.add(null);
    return Result.success(id);
  }

  @override
  Future<Result<void>> rename(String id, String name) async {
    final index = _departments.indexWhere((d) => d.id == id);
    final old = _departments[index];
    _departments[index] = Department(
      id: id,
      name: name.trim(),
      isActive: old.isActive,
    );
    _changes.add(null);
    return const Result.success(null);
  }

  @override
  Future<Result<void>> setActive(String id, {required bool active}) async {
    final index = _departments.indexWhere((d) => d.id == id);
    final old = _departments[index];
    _departments[index] = Department(id: id, name: old.name, isActive: active);
    _changes.add(null);
    return const Result.success(null);
  }
}
