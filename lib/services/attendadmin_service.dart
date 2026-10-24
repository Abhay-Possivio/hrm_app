// Ports of services/attendanceAdminService.ts and attendanceLogService.ts,
// plus the attendance summaries call from AttendancePage.tsx.

import 'package:hrm_app/api/api_client.dart';

int _int(dynamic v) => v is num ? v.round() : int.tryParse('$v') ?? 0;
int? _intOrNull(dynamic v) => v == null ? null : (v is num ? v.round() : int.tryParse('$v'));
String _str(dynamic v) => v == null ? '' : '$v';
String? _strOrNull(dynamic v) => (v == null || '$v'.isEmpty) ? null : '$v';
bool _bool(dynamic v) => v == true || v == 1 || v == 'true';
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : const {};
List<Map<String, dynamic>> _list(dynamic v) =>
    v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];

/// One employee's attendance for one day (/core/attendance/summaries/).
class AttendanceSummary {
  const AttendanceSummary({
    required this.id,
    required this.date,
    this.leaveName,
    required this.employeeId,
    required this.employeeCode,
    required this.employeeName,
    required this.branchName,
    this.firstIn,
    this.lastOut,
    this.lastOutIsEstimated = false,
    this.totalWorkMinutes = 0,
    this.movementMinutes = 0,
    this.lateMinutes = 0,
    this.lateAfterLunchMinutes = 0,
    this.overtimeMinutes = 0,
    this.netLateMinutes = 0,
    this.earlyOutMinutes = 0,
    required this.dayType,
    this.punchStatus,
    this.openIn,
    this.lastPunch,
    this.shiftStart,
    this.shiftEnd,
  });

  final int? id;
  final String date; // YYYY-MM-DD

  /// Approved leave type when dayType is ON_LEAVE.
  final String? leaveName;
  final int employeeId;
  final String employeeCode;
  final String employeeName;
  final String branchName;
  final String? firstIn;
  final String? lastOut;
  final bool lastOutIsEstimated;
  final int totalWorkMinutes;
  final int movementMinutes;
  final int lateMinutes;
  final int lateAfterLunchMinutes;
  final int overtimeMinutes;
  final int netLateMinutes;
  final int earlyOutMinutes;
  final String dayType;
  final String? punchStatus;
  final String? openIn;
  final String? lastPunch;
  final String? shiftStart;
  final String? shiftEnd;

  factory AttendanceSummary.fromJson(Map<String, dynamic> j) => AttendanceSummary(
        id: _intOrNull(j['id']),
        date: _str(j['date']),
        leaveName: _strOrNull(j['leave_name']),
        employeeId: _int(j['employee_id']),
        employeeCode: _str(j['employee_code']),
        employeeName: _str(j['employee_name']),
        branchName: _str(j['branch_name']),
        firstIn: _strOrNull(j['first_in']),
        lastOut: _strOrNull(j['last_out']),
        lastOutIsEstimated: _bool(j['last_out_is_estimated']),
        totalWorkMinutes: _int(j['total_work_minutes']),
        movementMinutes: _int(j['movement_minutes']),
        lateMinutes: _int(j['late_minutes']),
        lateAfterLunchMinutes: _int(j['late_after_lunch_minutes']),
        overtimeMinutes: _int(j['overtime_minutes']),
        netLateMinutes: _int(j['net_late_minutes']),
        earlyOutMinutes: _int(j['early_out_minutes']),
        dayType: _str(j['day_type']),
        punchStatus: _strOrNull(j['punch_status']),
        openIn: _strOrNull(j['open_in']),
        lastPunch: _strOrNull(j['last_punch']),
        shiftStart: _strOrNull(j['shift_start']),
        shiftEnd: _strOrNull(j['shift_end']),
      );
}

class AttendanceStats {
  const AttendanceStats({
    this.total = 0,
    this.present = 0,
    this.absent = 0,
    this.late = 0,
    this.missingOut = 0,
    this.inProgress = 0,
  });

  final int total;
  final int present;
  final int absent;
  final int late;
  final int missingOut;
  final int inProgress;

  factory AttendanceStats.fromJson(Map<String, dynamic> j) => AttendanceStats(
        total: _int(j['total']),
        present: _int(j['present']),
        absent: _int(j['absent']),
        late: _int(j['late']),
        missingOut: _int(j['missing_out']),
        inProgress: _int(j['in_progress']),
      );
}

class SummaryPage {
  const SummaryPage({required this.results, required this.count, required this.stats});

  final List<AttendanceSummary> results;
  final int count;
  final AttendanceStats? stats;
}

/// One raw punch (/core/attendance/logs/). Named PunchLog so it doesn't
/// clash with AttendanceLog in employee_service.dart.
class PunchLog {
  const PunchLog({
    required this.id,
    required this.employeeName,
    required this.employeeCode,
    required this.branchName,
    required this.departmentName,
    this.deviceName,
    this.deviceCode,
    required this.timestamp,
    required this.punchType,
    this.recordedPunchType,
    this.ignoreReason,
    this.source,
    this.isManual = false,
  });

  final int id;
  final String employeeName;
  final String employeeCode;
  final String branchName;
  final String departmentName;
  final String? deviceName;
  final String? deviceCode;
  final String timestamp; // wall-clock

  /// Direction used by the attendance calculation.
  final String punchType;

  /// What the device recorded.
  final String? recordedPunchType;

  /// Set when the punch was not counted: outside_window | unpaired | replaced.
  final String? ignoreReason;
  final String? source;
  final bool isManual;

  factory PunchLog.fromJson(Map<String, dynamic> j) => PunchLog(
        id: _int(j['id']),
        employeeName: _str(j['employee_name']),
        employeeCode: _str(j['employee_code']),
        branchName: _str(j['branch_name']),
        departmentName: _str(j['department_name']),
        deviceName: _strOrNull(j['device_name']),
        deviceCode: _strOrNull(j['device_code']),
        timestamp: _str(j['timestamp']),
        punchType: _str(j['punch_type']),
        recordedPunchType: _strOrNull(j['recorded_punch_type']),
        ignoreReason: _strOrNull(j['ignore_reason']),
        source: _strOrNull(j['source']),
        isManual: _bool(j['is_manual']),
      );
}

class AttendanceAdminService {
  /// [status] filters by ATTENDANCE status (PRESENT, LATE, MISSING_OUT, ...).
  Future<SummaryPage> fetchSummaries({
    int page = 1,
    String? date,
    String? startDate,
    String? endDate,
    String? status,
    String? q,
  }) async {
    final res = await api.get('/core/attendance/summaries/', queryParameters: {
      'page': page,
      if (date != null) 'date': date,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (status != null) 'status': status,
      if (q != null && q.isNotEmpty) 'q': q,
    });
    final j = _map(res.data);
    return SummaryPage(
      results: [for (final r in _list(j['results'])) AttendanceSummary.fromJson(r)],
      count: _int(j['count']),
      stats: j['stats'] is Map ? AttendanceStats.fromJson(_map(j['stats'])) : null,
    );
  }

  Future<({List<PunchLog> results, int count})> fetchRecords({
    int? days,
    int? employeeId,
    String? date,
    String? startDate,
    String? endDate,
    int? page,
    int? pageSize,
  }) async {
    final res = await api.get('/core/attendance/logs/', queryParameters: {
      if (days != null) 'days': days,
      if (employeeId != null) 'employee_id': employeeId,
      if (date != null) 'date': date,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (page != null) 'page': page,
      if (pageSize != null) 'page_size': pageSize,
    });
    final j = _map(res.data);
    return (results: [for (final r in _list(j['results'])) PunchLog.fromJson(r)], count: _int(j['count']));
  }

  /// [timestamp] is wall-clock "YYYY-MM-DDTHH:MM:SS"; [punchType] "IN" or "OUT".
  Future<void> createManualPunch({required int employeeId, required String timestamp, required String punchType}) async {
    await api.post('/core/attendance/logs/admin/', data: {
      'employee_id': employeeId,
      'timestamp': timestamp,
      'punch_type': punchType,
    });
  }

  Future<void> updatePunch(int id, Map<String, dynamic> data) async {
    await api.patch('/core/attendance/logs/admin/$id/', data: data);
  }

  Future<void> deletePunch(int id) async {
    await api.delete('/core/attendance/logs/admin/$id/');
  }

  /// Company audit log (used by the Audit Trail screen).
  Future<({List<Map<String, dynamic>> results, int count})> fetchAuditLogs({String? actionType, String? date, int? page}) async {
    final res = await api.get('/core/audit/logs/', queryParameters: {
      if (actionType != null) 'action_type': actionType,
      if (date != null) 'date': date,
      if (page != null) 'page': page,
    });
    final j = _map(res.data);
    return (results: _list(j['results']), count: _int(j['count']));
  }
}

final attendanceAdminService = AttendanceAdminService();