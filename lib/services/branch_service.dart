// Port of services/branchService.ts

import 'package:hrm_app/api/api_client.dart';

/// Just the id and name, for filters and pickers.
class BranchOption {
  const BranchOption({required this.id, required this.name});

  final int id;
  final String name;
}

class Branch {
  const Branch({
    required this.id,
    required this.name,
    this.location,
    required this.isActive,
    this.employeeCount = 0,
  });

  final int id;
  final String name;
  final String? location;
  final bool isActive;
  final int employeeCount;

  factory Branch.fromJson(Map<String, dynamic> j) => Branch(
        id: (j['id'] as num).toInt(),
        name: '${j['name'] ?? ''}',
        location: (j['location'] == null || '${j['location']}'.isEmpty) ? null : '${j['location']}',
        isActive: j['is_active'] != false,
        employeeCount: j['employee_count'] is num ? (j['employee_count'] as num).toInt() : 0,
      );
}

class BranchService {
  /// Every branch the user can see.
  Future<List<Branch>> fetchBranches() async {
    final res = await api.get('/core/branches/', queryParameters: {'page_size': 1000});
    final data = res.data;
    final list = data is Map ? data['results'] : data;
    return [
      for (final e in (list is List ? list : const []))
        if (e is Map) Branch.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  /// Ids and names only (for filters and pickers).
  Future<List<BranchOption>> fetchBranchOptions() async {
    final list = await fetchBranches();
    return [for (final b in list) BranchOption(id: b.id, name: b.name)];
  }

  Future<void> createBranch({required String name, String location = ''}) async {
    await api.post('/core/branches/admin/', data: {'name': name, 'location': location});
  }

  Future<void> updateBranch(int id, {required String name, String location = ''}) async {
    await api.put('/core/branches/admin/$id/', data: {'name': name, 'location': location});
  }

  Future<void> toggleBranchStatus(int id, bool isActive) async {
    await api.patch('/core/branches/admin/$id/', data: {'is_active': isActive});
  }
}

final branchService = BranchService();