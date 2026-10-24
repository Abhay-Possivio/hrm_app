// Port of services/tenantUserService.ts (staff accounts of the company:
// HR, team leads, branch managers, viewers, company admins).

import 'package:hrm_app/api/api_client.dart';

class TenantUserBranch {
  const TenantUserBranch({required this.id, required this.name});

  final int id;
  final String name;
}

class TenantUser {
  const TenantUser({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    required this.isCompanyAdmin,
    required this.isSuspended,
    required this.branches,
  });

  final int id;
  final String username;
  final String email;
  final String role;
  final bool isCompanyAdmin;
  final bool isSuspended;
  final List<TenantUserBranch> branches;

  TenantUser copyWith({bool? isSuspended, List<TenantUserBranch>? branches}) => TenantUser(
        id: id,
        username: username,
        email: email,
        role: role,
        isCompanyAdmin: isCompanyAdmin,
        isSuspended: isSuspended ?? this.isSuspended,
        branches: branches ?? this.branches,
      );

  factory TenantUser.fromJson(Map<String, dynamic> j) => TenantUser(
        id: (j['id'] as num).toInt(),
        username: '${j['username'] ?? ''}',
        email: '${j['email'] ?? ''}',
        role: '${j['role'] ?? ''}',
        isCompanyAdmin: j['is_company_admin'] == true,
        isSuspended: j['is_suspended'] == true,
        branches: [
          for (final b in (j['branches'] as List? ?? const []))
            if (b is Map) TenantUserBranch(id: (b['id'] as num).toInt(), name: '${b['name'] ?? ''}'),
        ],
      );
}

class TenantUserService {
  Future<List<TenantUser>> fetchUsers() async {
    final res = await api.get('/accounts/users/');
    final data = res.data;
    final list = data is Map ? data['results'] : data;
    return [
      for (final e in (list is List ? list : const []))
        if (e is Map) TenantUser.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  /// [role] is HR, TEAM_LEAD, BRANCH_MANAGER or VIEWER; company admins get COMPANY_ADMIN.
  Future<void> createUser({
    required String username,
    required String email,
    required String password,
    required String role,
    required bool isCompanyAdmin,
    required List<int> branches,
  }) async {
    await api.post('/accounts/create-user/', data: {
      'username': username,
      'email': email,
      'password': password,
      'password_confirm': password,
      'role': isCompanyAdmin ? 'COMPANY_ADMIN' : role,
      'is_company_admin': isCompanyAdmin,
      'branches': branches,
    });
  }

  Future<void> toggleSuspension(int userId) async {
    await api.patch('/accounts/users/$userId/toggle-suspension/');
  }

  Future<void> assignBranches(int userId, List<int> branchIds) async {
    await api.put('/accounts/users/$userId/branches/', data: {'branch_ids': branchIds});
  }
}

final tenantUserService = TenantUserService();