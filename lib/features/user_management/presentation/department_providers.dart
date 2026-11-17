import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/utils/result.dart';
import '../data/models/department.dart';

/// The departments on the list now, read once when a form opens
/// (2026-11-17): the Create Account form, signed out, and the console's
/// account dialog. Read again each time a form opens.
final activeDepartmentsProvider =
    FutureProvider.autoDispose<Result<List<Department>>>(
      (ref) => ref.watch(departmentRepositoryProvider).getActive(),
    );

/// The whole list, retired ones too, live: Settings → Departments.
final allDepartmentsProvider =
    StreamProvider.autoDispose<Result<List<Department>>>(
      (ref) => ref.watch(departmentRepositoryProvider).watchAll(),
    );
