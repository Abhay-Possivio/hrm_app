// Port of services/adminDashboardService.ts

import 'package:hrm_app/api/api_client.dart';

int _int(dynamic v) => v is num ? v.round() : int.tryParse('$v') ?? 0;
double _double(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String _str(dynamic v) => v == null ? '' : '$v';
String? _strOrNull(dynamic v) => (v == null || '$v'.isEmpty) ? null : '$v';
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : const {};
List<Map<String, dynamic>> _list(dynamic v) =>
    v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];

class DashboardKpis {
  const DashboardKpis({
    required this.totalEmployees,
    required this.presentToday,
    required this.lateToday,
    required this.lateAfterLunchToday,
    required this.activeViolations,
    required this.attendanceRate,
  });

  final int totalEmployees;
  final int presentToday;

  /// Employees late in the morning (arrival).
  final int lateToday;

  /// Employees who came back late from lunch.
  final int lateAfterLunchToday;
  final int activeViolations;
  final double attendanceRate;

  factory DashboardKpis.fromJson(Map<String, dynamic> j) => DashboardKpis(
        totalEmployees: _int(j['total_employees']),
        presentToday: _int(j['present_today']),
        lateToday: _int(j['late_today']),
        lateAfterLunchToday: _int(j['late_after_lunch_today']),
        activeViolations: _int(j['active_violations']),
        attendanceRate: _double(j['attendance_rate']),
      );
}

class LivePunch {
  const LivePunch({
    required this.id,
    required this.employeeName,
    required this.timestamp,
    required this.punchType,
    required this.ignoreReason,
    required this.deviceName,
  });

  final int id;
  final String employeeName;
  final String timestamp; // wall-clock time
  final String punchType;
  final String? ignoreReason;
  final String deviceName;

  factory LivePunch.fromJson(Map<String, dynamic> j) => LivePunch(
        id: _int(j['id']),
        employeeName: _str(j['employee_name']),
        timestamp: _str(j['timestamp']),
        punchType: _str(j['punch_type']),
        ignoreReason: _strOrNull(j['ignore_reason']),
        deviceName: _str(j['device_name']),
      );
}

class RecentViolation {
  const RecentViolation({
    required this.id,
    required this.employeeCode,
    required this.employeeName,
    required this.violationType,
    required this.description,
    required this.branchName,
    required this.createdAt,
    required this.date,
    required this.occurredAt,
    required this.violationLabel,
  });

  final int id;
  final String? employeeCode;
  final String employeeName;
  final String violationType;
  final String? description;
  final String branchName;
  final String createdAt;

  /// The attendance day the violation belongs to.
  final String? date;

  /// The punch time it refers to (wall-clock).
  final String? occurredAt;
  final String? violationLabel;

  factory RecentViolation.fromJson(Map<String, dynamic> j) => RecentViolation(
        id: _int(j['id']),
        employeeCode: _strOrNull(j['employee_code']),
        employeeName: _str(j['employee_name']),
        violationType: _str(j['violation_type']),
        description: _strOrNull(j['description']),
        branchName: _str(j['branch_name']),
        createdAt: _str(j['created_at']),
        date: _strOrNull(j['date']),
        occurredAt: _strOrNull(j['occurred_at']),
        violationLabel: _strOrNull(j['violation_label']),
      );
}

class BranchStat {
  const BranchStat({
    required this.branchId,
    required this.branchName,
    required this.employeeCount,
    required this.presentToday,
    required this.attendanceRate,
  });

  final int branchId;
  final String branchName;
  final int employeeCount;
  final int presentToday;
  final double attendanceRate;

  factory BranchStat.fromJson(Map<String, dynamic> j) => BranchStat(
        branchId: _int(j['branch_id']),
        branchName: _str(j['branch_name']),
        employeeCount: _int(j['employee_count']),
        presentToday: _int(j['present_today']),
        attendanceRate: _double(j['attendance_rate']),
      );
}

class FleetStats {
  const FleetStats({required this.totalDevices, required this.onlineDevices, required this.offlineDevices});

  final int totalDevices;
  final int onlineDevices;
  final int offlineDevices;

  factory FleetStats.fromJson(Map<String, dynamic> j) => FleetStats(
        totalDevices: _int(j['total_devices']),
        onlineDevices: _int(j['online_devices']),
        offlineDevices: _int(j['offline_devices']),
      );
}

/// The /core/dashboard/company-stats/ response. (`attendance_trends` is also
/// returned, but the dashboards use the separate trends endpoint instead.)
class AdminDashboardData {
  const AdminDashboardData({
    required this.kpis,
    required this.fleet,
    required this.recentPunches,
    required this.recentViolations,
    required this.branchStats,
  });

  final DashboardKpis kpis;
  final FleetStats fleet;
  final List<LivePunch> recentPunches;
  final List<RecentViolation> recentViolations;
  final List<BranchStat> branchStats;

  AdminDashboardData copyWith({List<LivePunch>? recentPunches}) => AdminDashboardData(
        kpis: kpis,
        fleet: fleet,
        recentPunches: recentPunches ?? this.recentPunches,
        recentViolations: recentViolations,
        branchStats: branchStats,
      );

  factory AdminDashboardData.fromJson(Map<String, dynamic> j) => AdminDashboardData(
        kpis: DashboardKpis.fromJson(_map(j['kpis'])),
        fleet: FleetStats.fromJson(_map(j['fleet'])),
        recentPunches: [for (final p in _list(j['recent_punches'])) LivePunch.fromJson(p)],
        recentViolations: [for (final v in _list(j['recent_violations'])) RecentViolation.fromJson(v)],
        branchStats: [for (final b in _list(j['branch_stats'])) BranchStat.fromJson(b)],
      );
}

class AdminDashboardService {
  Future<AdminDashboardData> fetchStats() async {
    final res = await api.get('/core/dashboard/company-stats/');
    return AdminDashboardData.fromJson(_map(res.data));
  }

  Future<List<LivePunch>> fetchLivePunches() async {
    final res = await api.get('/core/punches/live/');
    return [for (final p in _list(_map(res.data)['punches'])) LivePunch.fromJson(p)];
  }
}

final adminDashboardService = AdminDashboardService();