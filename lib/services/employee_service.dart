// Port of services/employeeService.ts

import 'package:hrm_app/api/api_client.dart';

int _int(dynamic v) => v is num ? v.round() : int.tryParse('$v') ?? 0;
int? _intOrNull(dynamic v) => v == null ? null : (v is num ? v.round() : int.tryParse('$v'));
String _str(dynamic v) => v == null ? '' : '$v';
String? _strOrNull(dynamic v) => (v == null || '$v'.isEmpty) ? null : '$v';
bool _bool(dynamic v) => v == true || v == 1 || v == 'true';
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : const {};
List<Map<String, dynamic>> _list(dynamic v) =>
    v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];

class Employee {
  const Employee({
    required this.id,
    required this.employeeCode,
    required this.name,
    required this.branchId,
    required this.branchName,
    this.departmentId,
    this.departmentName,
    this.email,
    this.phone,
    required this.isActive,
    required this.hasFingerprint,
    this.portalUserId,
    this.portalUsername,
    this.deviceUid,
    this.isSyncedFromDevice = false,
    this.profileCompleted = false,
    this.portalEnabled = false,
    this.mustChangePassword = false,
    this.lastSyncAt,
    this.photo,
    this.designation,
    this.dateOfJoining,
    this.dateOfBirth,
    this.gender,
    this.employmentType,
    this.nationalId,
    this.isTeamLead = false,
    this.teamName,
    this.teamLead,
    this.teamLeadName,
    this.raw = const {},
  });

  final int id;
  final String employeeCode;
  final String name;
  final int branchId;
  final String branchName;
  final int? departmentId;
  final String? departmentName;
  final String? email;
  final String? phone;
  final bool isActive;
  final bool hasFingerprint;
  final int? portalUserId;
  final String? portalUsername;

  // Device-first onboarding
  final String? deviceUid;
  final bool isSyncedFromDevice;
  final bool profileCompleted;
  final bool portalEnabled;
  final bool mustChangePassword;
  final String? lastSyncAt;

  // Extended profile
  final String? photo;
  final String? designation;
  final String? dateOfJoining;
  final String? dateOfBirth;

  /// "M" | "F" | "O"
  final String? gender;

  /// "FT" | "PT" | "CT"
  final String? employmentType;
  final String? nationalId;
  final bool isTeamLead;
  final String? teamName;
  final int? teamLead;
  final String? teamLeadName;

  /// The full server record, for fields this model doesn't name yet.
  final Map<String, dynamic> raw;

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        id: _int(j['id']),
        employeeCode: _str(j['employee_code']),
        name: _str(j['name']),
        branchId: _int(j['branch_id']),
        branchName: _str(j['branch_name']),
        departmentId: _intOrNull(j['department_id']),
        departmentName: _strOrNull(j['department_name']),
        email: _strOrNull(j['email']),
        phone: _strOrNull(j['phone']),
        isActive: _bool(j['is_active']),
        hasFingerprint: _bool(j['has_fingerprint']),
        portalUserId: _intOrNull(j['portal_user_id']),
        portalUsername: _strOrNull(j['portal_username']),
        deviceUid: _strOrNull(j['device_uid']),
        isSyncedFromDevice: _bool(j['is_synced_from_device']),
        profileCompleted: _bool(j['profile_completed']),
        portalEnabled: _bool(j['portal_enabled']),
        mustChangePassword: _bool(j['must_change_password']),
        lastSyncAt: _strOrNull(j['last_sync_at']),
        photo: _strOrNull(j['photo']),
        designation: _strOrNull(j['designation']),
        dateOfJoining: _strOrNull(j['date_of_joining']),
        dateOfBirth: _strOrNull(j['date_of_birth']),
        gender: _strOrNull(j['gender']),
        employmentType: _strOrNull(j['employment_type']),
        nationalId: _strOrNull(j['national_id']),
        isTeamLead: _bool(j['is_team_lead']),
        teamName: _strOrNull(j['team_name']),
        teamLead: _intOrNull(j['team_lead']),
        teamLeadName: _strOrNull(j['team_lead_name']),
        raw: j,
      );
}

class AttendanceLog {
  const AttendanceLog({
    required this.id,
    required this.employeeName,
    required this.employeeCode,
    required this.branchName,
    required this.timestamp,
    required this.punchType,
    required this.source,
    this.deviceName,
    this.deviceCode,
  });

  final int id;
  final String employeeName;
  final String employeeCode;
  final String branchName;
  final String timestamp; // wall-clock
  final String punchType;
  final String source;
  final String? deviceName;
  final String? deviceCode;

  factory AttendanceLog.fromJson(Map<String, dynamic> j) => AttendanceLog(
        id: _int(j['id']),
        employeeName: _str(j['employee_name']),
        employeeCode: _str(j['employee_code']),
        branchName: _str(j['branch_name']),
        timestamp: _str(j['timestamp']),
        punchType: _str(j['punch_type']),
        source: _str(j['source']),
        deviceName: _strOrNull(j['device_name']),
        deviceCode: _strOrNull(j['device_code']),
      );
}

class EmployeePage {
  const EmployeePage({required this.results, required this.count});

  final List<Employee> results;
  final int count;
}

class EmployeeService {
  /// [profileStatus] is "INCOMPLETE", "COMPLETE" or "EMAIL_SUBMITTED";
  /// [loginStatus] is "SET" or "UNSET" (portal login set up or not).
  Future<EmployeePage> fetchEmployees({
    String? q,
    int? page,
    int? pageSize,
    String? profileStatus,
    String? loginStatus,
    Object? branchId,
  }) async {
    final res = await api.get('/core/employees/', queryParameters: {
      if (q != null && q.isNotEmpty) 'q': q,
      if (page != null) 'page': page,
      if (pageSize != null) 'page_size': pageSize,
      if (profileStatus != null) 'profile_status': profileStatus,
      if (loginStatus != null) 'login_status': loginStatus,
      if (branchId != null && '$branchId'.isNotEmpty) 'branch_id': branchId,
    });
    final j = _map(res.data);
    return EmployeePage(
      results: [for (final e in _list(j['results'])) Employee.fromJson(e)],
      count: _int(j['count']),
    );
  }

  Future<List<Employee>> fetchAllEmployees() async {
    final all = <Employee>[];
    var page = 1;
    while (true) {
      final res = await fetchEmployees(page: page, pageSize: 100);
      all.addAll(res.results);
      if (res.count == 0 || all.length >= res.count || res.results.isEmpty) break;
      page++;
    }
    return all;
  }

  Future<Map<String, dynamic>> createEmployee(Map<String, dynamic> data) async {
    final res = await api.post('/core/employees/admin/', data: data);
    return _map(res.data);
  }

  Future<Employee> fetchEmployeeById(Object id) async {
    final res = await api.get('/core/employees/admin/$id/', queryParameters: {
      't': DateTime.now().millisecondsSinceEpoch,
    });
    return Employee.fromJson(_map(res.data));
  }

  Future<Map<String, dynamic>> updateEmployee(Object id, Map<String, dynamic> data) async {
    final res = await api.put('/core/employees/admin/$id/', data: data);
    return _map(res.data);
  }

  Future<Map<String, dynamic>> patchEmployeeStatus(Object id, bool isActive) async {
    final res = await api.patch('/core/employees/admin/$id/', data: {'is_active': isActive});
    return _map(res.data);
  }

  Future<Map<String, dynamic>> createPortalAccess(Object id, Map<String, dynamic> data) async {
    final res = await api.post('/core/employees/admin/$id/portal-access/', data: data);
    return _map(res.data);
  }

  Future<Map<String, dynamic>> revokePortalAccess(Object id) async {
    final res = await api.delete('/core/employees/admin/$id/portal-access/');
    return _map(res.data);
  }

  Future<({List<AttendanceLog> results, int count})> fetchEmployeeLogs(Object employeeId, {int page = 1}) async {
    final res = await api.get('/core/attendance/logs/', queryParameters: {
      'employee_id': employeeId,
      'page': page,
      't': DateTime.now().millisecondsSinceEpoch,
    });
    final j = _map(res.data);
    return (results: [for (final e in _list(j['results'])) AttendanceLog.fromJson(e)], count: _int(j['count']));
  }

  Future<void> deleteEmployee(Object id) async {
    await api.delete('/core/employees/admin/$id/');
  }
}

final employeeService = EmployeeService();