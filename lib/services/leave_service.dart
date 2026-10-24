// Port of services/leaveService.ts

import 'package:hrm_app/api/api_client.dart';

int _int(dynamic v) => v is num ? v.round() : int.tryParse('$v') ?? 0;
int? _intOrNull(dynamic v) => v == null ? null : (v is num ? v.round() : int.tryParse('$v'));
String _str(dynamic v) => v == null ? '' : '$v';
String? _strOrNull(dynamic v) => (v == null || '$v'.isEmpty) ? null : '$v';
bool _bool(dynamic v) => v == true || v == 1 || v == 'true';

/// The endpoints return either a plain list or a paginated {"results": [...]}.
List<Map<String, dynamic>> _rows(dynamic data) {
  final list = data is Map ? data['results'] : data;
  return list is List ? [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)] : const [];
}

class LeaveType {
  const LeaveType({required this.id, required this.name, required this.description, required this.isActive, this.code});

  final int id;
  final String name;
  final String description;
  final bool isActive;
  final String? code;

  factory LeaveType.fromJson(Map<String, dynamic> j) => LeaveType(
        id: _int(j['id']),
        name: _str(j['name']),
        description: _str(j['description']),
        isActive: j['is_active'] == null || _bool(j['is_active']),
        code: _strOrNull(j['code']),
      );
}

class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.employee,
    required this.employeeName,
    this.employeeCode,
    required this.leaveType,
    required this.leaveTypeName,
    this.leaveTypeDisplay,
    required this.startDate,
    required this.endDate,
    this.daysRequested,
    required this.reason,
    required this.status,
    required this.statusDisplay,
    required this.hrComment,
    this.processedBy,
    this.processedAt,
    required this.createdAt,
    this.hasTeamLead = false,
    this.teamLeadName,
    this.tlStatus,
    this.tlComment,
    this.recordedByHr = false,
    this.processedByName,
  });

  final int id;
  final int employee;
  final String employeeName;
  final String? employeeCode;
  final int leaveType;
  final String leaveTypeName;
  final String? leaveTypeDisplay;
  final String startDate; // YYYY-MM-DD
  final String endDate;
  final int? daysRequested;
  final String reason;

  /// PENDING | APPROVED | DECLINED | CANCELLED
  final String status;
  final String statusDisplay;
  final String hrComment;
  final int? processedBy;
  final String? processedAt;
  final String createdAt;
  final bool hasTeamLead;
  final String? teamLeadName;

  /// PENDING | APPROVED | DECLINED
  final String? tlStatus;
  final String? tlComment;

  /// Entered by HR on the employee's behalf.
  final bool recordedByHr;
  final String? processedByName;

  factory LeaveRequest.fromJson(Map<String, dynamic> j) => LeaveRequest(
        id: _int(j['id']),
        employee: _int(j['employee']),
        employeeName: _str(j['employee_name']),
        employeeCode: _strOrNull(j['employee_code']),
        leaveType: _int(j['leave_type']),
        leaveTypeName: _str(j['leave_type_name']),
        leaveTypeDisplay: _strOrNull(j['leave_type_display']),
        startDate: _str(j['start_date']),
        endDate: _str(j['end_date']),
        daysRequested: _intOrNull(j['days_requested']),
        reason: _str(j['reason']),
        status: _str(j['status']),
        statusDisplay: _str(j['status_display']),
        hrComment: _str(j['hr_comment']),
        processedBy: _intOrNull(j['processed_by']),
        processedAt: _strOrNull(j['processed_at']),
        createdAt: _str(j['created_at']),
        hasTeamLead: _bool(j['has_team_lead']),
        teamLeadName: _strOrNull(j['team_lead_name']),
        tlStatus: _strOrNull(j['tl_status']),
        tlComment: _strOrNull(j['tl_comment']),
        recordedByHr: _bool(j['recorded_by_hr']),
        processedByName: _strOrNull(j['processed_by_name']),
      );
}

class LeaveService {
  Future<List<LeaveType>> fetchLeaveTypes() async {
    final res = await api.get('/core/leaves/types/');
    return [for (final r in _rows(res.data)) LeaveType.fromJson(r)];
  }

  Future<List<LeaveRequest>> fetchLeaveRequests({int? page, bool? myOwn, String? status}) async {
    final res = await api.get('/core/leaves/requests/', queryParameters: {
      if (page != null) 'page': page,
      if (myOwn != null) 'my_own': myOwn,
      if (status != null) 'status': status,
    });
    return [for (final r in _rows(res.data)) LeaveRequest.fromJson(r)];
  }

  /// One page of leave requests with the total count (for paging).
  Future<({List<LeaveRequest> results, int count})> fetchLeaveRequestPage({int page = 1, String? status}) async {
    final res = await api.get('/core/leaves/requests/', queryParameters: {
      'page': page,
      if (status != null) 'status': status,
    });
    final data = res.data;
    final count = data is Map ? _int(data['count']) : _rows(data).length;
    return (results: [for (final r in _rows(data)) LeaveRequest.fromJson(r)], count: count);
  }

  /// HR records an already-approved leave for an employee who didn't apply.
  Future<void> recordLeave({
    required int employeeId,
    required int leaveType,
    required String startDate,
    required String endDate,
    required String reason,
  }) async {
    await api.post('/core/leaves/requests/record/', data: {
      'employee_id': employeeId,
      'leave_type': leaveType,
      'start_date': startDate,
      'end_date': endDate,
      'reason': reason,
    });
  }

  Future<LeaveRequest> fetchLeaveRequestDetail(int id) async {
    final res = await api.get('/core/leaves/requests/$id/');
    return LeaveRequest.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<LeaveRequest> createLeaveRequest({
    required int leaveType,
    required String startDate,
    required String endDate,
    required String reason,
  }) async {
    final res = await api.post('/core/leaves/requests/', data: {
      'leave_type': leaveType,
      'start_date': startDate,
      'end_date': endDate,
      'reason': reason,
    });
    return LeaveRequest.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  /// HR decision. [status] is "APPROVED" or "DECLINED".
  Future<LeaveRequest> updateLeaveRequestStatus(int id, String status, String hrComment) async {
    final res = await api.patch('/core/leaves/requests/$id/', data: {'status': status, 'hr_comment': hrComment});
    return LeaveRequest.fromJson(Map<String, dynamic>.from(res.data as Map));
  }
}

final leaveService = LeaveService();