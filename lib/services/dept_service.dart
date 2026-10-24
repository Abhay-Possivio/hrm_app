// Port of services/departmentService.ts

import 'package:hrm_app/api/api_client.dart';

class Department {
  const Department({required this.id, required this.name, this.isActive = true});

  final int id;
  final String name;
  final bool isActive;
}

class DepartmentService {
  Future<List<Department>> fetchDepartments() async {
    final res = await api.get('/core/departments/', queryParameters: {'page_size': 1000});
    final data = res.data;
    final list = data is Map ? data['results'] : data;
    return [
      for (final e in (list is List ? list : const []))
        if (e is Map)
          Department(
            id: (e['id'] as num).toInt(),
            name: '${e['name'] ?? ''}',
            isActive: e['is_active'] != false,
          ),
    ];
  }

  /// Creates a department (or returns the existing one with that name).
  Future<Department> createDepartment(String name) async {
    final res = await api.post('/core/departments/admin/', data: {'name': name});
    final j = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const <String, dynamic>{};
    final id = j['department_id'] ?? j['id'];
    return Department(id: id is num ? id.toInt() : int.parse('$id'), name: '${j['name'] ?? name}');
  }
}

final departmentService = DepartmentService();