// Port of services/employeePortalService.ts

import 'package:hrm_app/api/api_client.dart';

int _int(dynamic v) => v is num ? v.round() : int.tryParse('$v') ?? 0;
int? _intOrNull(dynamic v) => v == null ? null : (v is num ? v.round() : int.tryParse('$v'));
String _str(dynamic v) => v == null ? '' : '$v';
String? _strOrNull(dynamic v) => (v == null || '$v'.isEmpty) ? null : '$v';
bool _bool(dynamic v) => v == true || v == 1 || v == 'true';
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : const {};
List<Map<String, dynamic>> _list(dynamic v) =>
    v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];

class EmployeeShiftInfo {
  const EmployeeShiftInfo({
    required this.name,
    required this.isWorkingToday,
    required this.startTime,
    required this.endTime,
    required this.workingDays,
  });

  final String name;
  final bool isWorkingToday;
  final String? startTime; // "HH:MM:SS"
  final String? endTime;
  final List<String> workingDays; // "Mon", "Tue", ...

  factory EmployeeShiftInfo.fromJson(Map<String, dynamic> j) => EmployeeShiftInfo(
        name: _str(j['name']),
        isWorkingToday: _bool(j['is_working_today']),
        startTime: _strOrNull(j['start_time']),
        endTime: _strOrNull(j['end_time']),
        workingDays: [for (final d in (j['working_days'] as List? ?? const [])) '$d'],
      );
}

class EmployeeProfile {
  const EmployeeProfile({
    required this.id,
    required this.name,
    required this.employeeCode,
    required this.designation,
    required this.employmentType,
    required this.branch,
    required this.branchId,
    required this.department,
    required this.isActive,
    required this.isTeamLead,
    required this.teamName,
    required this.dateOfJoining,
    required this.mustChangePassword,
    required this.shift,
    required this.graceMinutes,
    required this.lunchStart,
    required this.lunchEnd,
  });

  final int id;
  final String name;
  final String employeeCode;
  final String? designation;
  final String? employmentType;
  final String branch;
  final int branchId;
  final String? department;
  final bool isActive;
  final bool isTeamLead;
  final String? teamName;
  final String? dateOfJoining;
  final bool mustChangePassword;
  final EmployeeShiftInfo? shift;
  final int? graceMinutes;
  final String? lunchStart;
  final String? lunchEnd;

  factory EmployeeProfile.fromJson(Map<String, dynamic> j) => EmployeeProfile(
        id: _int(j['id']),
        name: _str(j['name']),
        employeeCode: _str(j['employee_code']),
        designation: _strOrNull(j['designation']),
        employmentType: _strOrNull(j['employment_type']),
        branch: _str(j['branch']),
        branchId: _int(j['branch_id']),
        department: _strOrNull(j['department']),
        isActive: _bool(j['is_active']),
        isTeamLead: _bool(j['is_team_lead']),
        teamName: _strOrNull(j['team_name']),
        dateOfJoining: _strOrNull(j['date_of_joining']),
        mustChangePassword: _bool(j['must_change_password']),
        shift: j['shift'] is Map ? EmployeeShiftInfo.fromJson(_map(j['shift'])) : null,
        graceMinutes: _intOrNull(j['grace_minutes']),
        lunchStart: _strOrNull(j['lunch_start']),
        lunchEnd: _strOrNull(j['lunch_end']),
      );
}

class EmployeeAttendance {
  const EmployeeAttendance({
    required this.date,
    required this.dayType,
    this.leaveName,
    this.punchStatus,
    this.statusLabel,
    this.firstIn,
    this.lastOut,
    this.openIn,
    this.lastOutIsEstimated = false,
    this.shiftStart,
    this.shiftEnd,
    this.totalWorkMinutes = 0,
    this.lateMinutes = 0,
    this.lateAfterLunchMinutes = 0,
    this.earlyOutMinutes = 0,
    this.overtimeMinutes = 0,
    this.netLateMinutes = 0,
  });

  final String date; // YYYY-MM-DD
  final String dayType;

  /// Approved leave type when dayType is ON_LEAVE, e.g. "Sick Leave".
  final String? leaveName;
  final String? punchStatus;
  final String? statusLabel;
  final String? firstIn;
  final String? lastOut;
  final String? openIn;
  final bool lastOutIsEstimated;
  final String? shiftStart;
  final String? shiftEnd;
  final int totalWorkMinutes;

  /// Morning late-in minutes.
  final int lateMinutes;

  /// Late return from lunch, kept separate.
  final int lateAfterLunchMinutes;
  final int earlyOutMinutes;
  final int overtimeMinutes;
  final int netLateMinutes;

  factory EmployeeAttendance.fromJson(Map<String, dynamic> j) => EmployeeAttendance(
        date: _str(j['date']),
        dayType: _str(j['day_type']),
        leaveName: _strOrNull(j['leave_name']),
        punchStatus: _strOrNull(j['punch_status']),
        statusLabel: _strOrNull(j['status_label']),
        firstIn: _strOrNull(j['first_in']),
        lastOut: _strOrNull(j['last_out']),
        openIn: _strOrNull(j['open_in']),
        lastOutIsEstimated: _bool(j['last_out_is_estimated']),
        shiftStart: _strOrNull(j['shift_start']),
        shiftEnd: _strOrNull(j['shift_end']),
        totalWorkMinutes: _int(j['total_work_minutes']),
        lateMinutes: _int(j['late_minutes']),
        lateAfterLunchMinutes: _int(j['late_after_lunch_minutes']),
        earlyOutMinutes: _int(j['early_out_minutes']),
        overtimeMinutes: _int(j['overtime_minutes']),
        netLateMinutes: _int(j['net_late_minutes']),
      );
}

class EmployeeViolation {
  const EmployeeViolation({
    required this.id,
    required this.date,
    required this.violationType,
    required this.description,
  });

  final int id;
  final String date;
  final String violationType;
  final String description;

  factory EmployeeViolation.fromJson(Map<String, dynamic> j) => EmployeeViolation(
        id: _int(j['id']),
        date: _str(j['date']),
        violationType: _str(j['violation_type']),
        description: _str(j['description']),
      );
}

class TodayPunch {
  const TodayPunch({
    required this.id,
    required this.timestamp,
    required this.punchType,
    required this.source,
    required this.deviceName,
    required this.ignoreReason,
    required this.isManual,
    required this.counted,
  });

  final int id;
  final String timestamp; // wall-clock
  final String punchType; // "IN" | "OUT"
  final String source; // e.g. "RFID", "FINGERPRINT"
  final String? deviceName;

  /// Set when the punch was not counted: outside_window | unpaired | replaced.
  final String? ignoreReason;
  final bool isManual;

  /// False when the punch fell after the overtime window closed.
  final bool counted;

  factory TodayPunch.fromJson(Map<String, dynamic> j) => TodayPunch(
        id: _int(j['id']),
        timestamp: _str(j['timestamp']),
        punchType: _str(j['punch_type']),
        source: _str(j['source']),
        deviceName: _strOrNull(j['device_name']),
        ignoreReason: _strOrNull(j['ignore_reason']),
        isManual: _bool(j['is_manual']),
        counted: j['counted'] == null || _bool(j['counted']),
      );
}

class TodayPunches {
  const TodayPunches({required this.punches, required this.date, required this.today});

  final List<TodayPunch> punches;

  /// The company's date ("YYYY-MM-DD"), from the server.
  final String? date;

  /// Live status for today, when the server sends it.
  final EmployeeAttendance? today;
}

class Paged<T> {
  const Paged(this.results, this.count);

  final List<T> results;
  final int count;
}

class EmployeePortalService {
  Future<EmployeeProfile> fetchMe() async {
    final res = await api.get('/core/portal/me/');
    return EmployeeProfile.fromJson(_map(res.data));
  }

  Future<Paged<EmployeeAttendance>> fetchMonthlyAttendance({int? month, int? year, int page = 1}) async {
    final res = await api.get('/core/portal/attendance/', queryParameters: {
      if (month != null) 'month': month,
      if (year != null) 'year': year,
      'page': page,
      'page_size': 50,
    });
    final data = _map(res.data);
    return Paged(
      [for (final r in _list(data['results'])) EmployeeAttendance.fromJson(r)],
      _int(data['count']),
    );
  }

  Future<Paged<EmployeeViolation>> fetchViolations({int? month, int? year, int page = 1}) async {
    final res = await api.get('/core/portal/violations/', queryParameters: {
      if (month != null) 'month': month,
      if (year != null) 'year': year,
      'page': page,
    });
    final data = _map(res.data);
    return Paged(
      [for (final r in _list(data['results'])) EmployeeViolation.fromJson(r)],
      _int(data['count']),
    );
  }

  Future<TodayPunches> fetchTodayPunches() async {
    final res = await api.get('/core/portal/punches/today/');
    final data = _map(res.data);
    return TodayPunches(
      punches: [for (final p in _list(data['punches'])) TodayPunch.fromJson(p)],
      date: _strOrNull(data['date']),
      today: data['today'] is Map ? EmployeeAttendance.fromJson(_map(data['today'])) : null,
    );
  }
}

final employeePortalService = EmployeePortalService();