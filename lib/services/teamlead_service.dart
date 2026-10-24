// Port of services/teamLeadService.ts

import 'package:hrm_app/api/api_client.dart';

int _int(dynamic v) => v is num ? v.round() : int.tryParse('$v') ?? 0;
String _str(dynamic v) => v == null ? '' : '$v';
String? _strOrNull(dynamic v) => (v == null || '$v'.isEmpty) ? null : '$v';
bool _bool(dynamic v) => v == true || v == 1 || v == 'true';
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : const {};
List<Map<String, dynamic>> _list(dynamic v) =>
    v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];

class TeamMember {
  const TeamMember({
    required this.id,
    required this.employeeCode,
    required this.name,
    required this.designation,
    required this.branchName,
    required this.departmentName,
    required this.status,
    this.dayType,
    this.leaveName,
    this.punchStatus,
    this.statusLabel,
    this.isLate = false,
    this.inOffice = false,
    this.firstIn,
    this.lastOut,
    this.lateMinutes = 0,
    this.lateAfterLunchMinutes = 0,
    this.totalWorkMinutes = 0,
  });

  final int id;
  final String employeeCode;
  final String name;
  final String designation;
  final String branchName;
  final String departmentName;

  /// Present | Half Day | Absent | On Leave | Off Day | Awaiting Punch
  final String status;
  final String? dayType;

  /// Approved leave type when dayType is ON_LEAVE.
  final String? leaveName;
  final String? punchStatus;
  final String? statusLabel;
  final bool isLate;
  final bool inOffice;

  /// Already formatted by the server, e.g. "09:05 AM".
  final String? firstIn;
  final String? lastOut;

  /// Morning late-in minutes.
  final int lateMinutes;

  /// Late return from lunch, kept separate.
  final int lateAfterLunchMinutes;
  final int totalWorkMinutes;

  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
        id: _int(j['id']),
        employeeCode: _str(j['employee_code']),
        name: _str(j['name']),
        designation: _str(j['designation']),
        branchName: _str(j['branch_name']),
        departmentName: _str(j['department_name']),
        status: _str(j['status']),
        dayType: _strOrNull(j['day_type']),
        leaveName: _strOrNull(j['leave_name']),
        punchStatus: _strOrNull(j['punch_status']),
        statusLabel: _strOrNull(j['status_label']),
        isLate: _bool(j['is_late']),
        inOffice: _bool(j['in_office']),
        firstIn: _strOrNull(j['first_in']),
        lastOut: _strOrNull(j['last_out']),
        lateMinutes: _int(j['late_minutes']),
        lateAfterLunchMinutes: _int(j['late_after_lunch_minutes']),
        totalWorkMinutes: _int(j['total_work_minutes']),
      );
}

class TeamPunch {
  const TeamPunch({
    required this.id,
    required this.employeeName,
    required this.employeeCode,
    required this.timestamp,
    required this.punchType,
    required this.ignoreReason,
    required this.source,
    required this.deviceName,
  });

  final int id;
  final String employeeName;
  final String employeeCode;
  final String timestamp; // wall-clock
  final String punchType; // "IN" | "OUT"

  /// Set when the punch was not counted: outside_window | unpaired | replaced.
  final String? ignoreReason;
  final String source;
  final String? deviceName;

  factory TeamPunch.fromJson(Map<String, dynamic> j) => TeamPunch(
        id: _int(j['id']),
        employeeName: _str(j['employee_name']),
        employeeCode: _str(j['employee_code']),
        timestamp: _str(j['timestamp']),
        punchType: _str(j['punch_type']),
        ignoreReason: _strOrNull(j['ignore_reason']),
        source: _str(j['source']),
        deviceName: _strOrNull(j['device_name']),
      );
}

class TeamLeadKpis {
  const TeamLeadKpis({
    required this.totalEmployees,
    required this.presentToday,
    required this.lateToday,
    required this.lateAfterLunchToday,
    required this.absentToday,
    required this.onLeaveToday,
    required this.notStartedToday,
    required this.inOfficeNow,
    required this.pendingLeaves,
  });

  final int totalEmployees;
  final int presentToday;
  final int lateToday;
  final int lateAfterLunchToday;
  final int absentToday;
  final int onLeaveToday;
  final int notStartedToday;
  final int inOfficeNow;
  final int pendingLeaves;

  factory TeamLeadKpis.fromJson(Map<String, dynamic> j) => TeamLeadKpis(
        totalEmployees: _int(j['total_employees']),
        presentToday: _int(j['present_today']),
        lateToday: _int(j['late_today']),
        lateAfterLunchToday: _int(j['late_after_lunch_today']),
        absentToday: _int(j['absent_today']),
        onLeaveToday: _int(j['on_leave_today']),
        notStartedToday: _int(j['not_started_today']),
        inOfficeNow: _int(j['in_office_now']),
        pendingLeaves: _int(j['pending_leaves']),
      );
}

class TeamLeadDashboardData {
  const TeamLeadDashboardData({
    required this.date,
    required this.kpis,
    required this.recentPunches,
    required this.teamMembers,
  });

  /// Company-local date the figures are for.
  final String? date;
  final TeamLeadKpis kpis;
  final List<TeamPunch> recentPunches;
  final List<TeamMember> teamMembers;

  factory TeamLeadDashboardData.fromJson(Map<String, dynamic> j) => TeamLeadDashboardData(
        date: _strOrNull(j['date']),
        kpis: TeamLeadKpis.fromJson(_map(j['kpis'])),
        recentPunches: [for (final p in _list(j['recent_punches'])) TeamPunch.fromJson(p)],
        teamMembers: [for (final m in _list(j['team_members'])) TeamMember.fromJson(m)],
      );
}

/// A leave request as the team lead sees it (/core/leaves/requests/).
class TeamLeaveRequest {
  const TeamLeaveRequest({
    required this.id,
    required this.employeeName,
    required this.leaveTypeName,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.tlStatus,
    required this.tlComment,
    required this.tlProcessedAt,
  });

  final int id;
  final String employeeName;
  final String leaveTypeName;
  final String startDate; // YYYY-MM-DD
  final String endDate;
  final String reason;

  /// PENDING | APPROVED | DECLINED
  final String tlStatus;
  final String tlComment;
  final String? tlProcessedAt;

  factory TeamLeaveRequest.fromJson(Map<String, dynamic> j) => TeamLeaveRequest(
        id: _int(j['id']),
        employeeName: _str(j['employee_name']),
        leaveTypeName: _str(j['leave_type_name']),
        startDate: _str(j['start_date']),
        endDate: _str(j['end_date']),
        reason: _str(j['reason']),
        tlStatus: _str(j['tl_status']),
        tlComment: _str(j['tl_comment']),
        tlProcessedAt: _strOrNull(j['tl_processed_at']),
      );
}

class TeamLeadService {
  Future<TeamLeadDashboardData> fetchStats() async {
    final res = await api.get('/core/dashboard/team-stats/');
    return TeamLeadDashboardData.fromJson(_map(res.data));
  }

  Future<List<TeamLeaveRequest>> fetchTeamLeaves() async {
    final res = await api.get('/core/leaves/requests/');
    final data = res.data;
    final list = data is Map ? data['results'] : data;
    return [
      for (final e in (list is List ? list : const []))
        if (e is Map) TeamLeaveRequest.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  Future<void> approveLeave(int id, String comment) async {
    await api.patch('/core/leaves/requests/$id/', data: {'status': 'APPROVED', 'tl_comment': comment});
  }

  Future<void> declineLeave(int id, String comment) async {
    await api.patch('/core/leaves/requests/$id/', data: {'status': 'DECLINED', 'tl_comment': comment});
  }
}

final teamLeadService = TeamLeadService();