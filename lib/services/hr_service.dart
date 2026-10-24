// Port of services/hrService.ts (the parts used so far; more is added as
// screens are ported).

import 'package:hrm_app/api/api_client.dart';

int _int(dynamic v) => v is num ? v.round() : int.tryParse('$v') ?? 0;
double? _doubleOrNull(dynamic v) => v is num ? v.toDouble() : (v == null ? null : double.tryParse('$v'));
bool _bool(dynamic v) => v == true || v == 1 || v == 'true';
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : const {};

// ── Attendance trends ───────────────────────────────────────────────────────

class TrendPoint {
  const TrendPoint({
    required this.date,
    required this.present,
    required this.onTime,
    required this.late,
    required this.halfDay,
    required this.absent,
    required this.onLeave,
    required this.offDay,
    required this.missingOut,
    required this.expected,
    required this.attendanceRate,
    required this.punctualityRate,
    required this.isToday,
    required this.isOffDay,
  });

  final String date; // YYYY-MM-DD
  final int present;
  final int onTime;
  final int late;
  final int halfDay;
  final int absent;
  final int onLeave;
  final int offDay;
  final int missingOut;
  final int expected;
  final double? attendanceRate;
  final double? punctualityRate;
  final bool isToday;
  final bool isOffDay;

  factory TrendPoint.fromJson(Map<String, dynamic> j) => TrendPoint(
        date: '${j['date'] ?? ''}',
        present: _int(j['present']),
        onTime: _int(j['on_time']),
        late: _int(j['late']),
        halfDay: _int(j['half_day']),
        absent: _int(j['absent']),
        onLeave: _int(j['on_leave']),
        offDay: _int(j['off_day']),
        missingOut: _int(j['missing_out']),
        expected: _int(j['expected']),
        attendanceRate: _doubleOrNull(j['attendance_rate']),
        punctualityRate: _doubleOrNull(j['punctuality_rate']),
        isToday: _bool(j['is_today']),
        isOffDay: _bool(j['is_off_day']),
      );
}

class TrendSummary {
  const TrendSummary({
    this.attendanceRate,
    this.punctualityRate,
    this.previousAttendanceRate,
    this.previousPunctualityRate,
    this.present = 0,
    this.late = 0,
    this.absent = 0,
    this.onLeave = 0,
    this.missingOut = 0,
  });

  final double? attendanceRate;
  final double? punctualityRate;
  final double? previousAttendanceRate;
  final double? previousPunctualityRate;
  final int present;
  final int late;
  final int absent;
  final int onLeave;
  final int missingOut;

  factory TrendSummary.fromJson(Map<String, dynamic> j) => TrendSummary(
        attendanceRate: _doubleOrNull(j['attendance_rate']),
        punctualityRate: _doubleOrNull(j['punctuality_rate']),
        previousAttendanceRate: _doubleOrNull(j['previous_attendance_rate']),
        previousPunctualityRate: _doubleOrNull(j['previous_punctuality_rate']),
        present: _int(j['present']),
        late: _int(j['late']),
        absent: _int(j['absent']),
        onLeave: _int(j['on_leave']),
        missingOut: _int(j['missing_out']),
      );
}

class TrendData {
  const TrendData({
    required this.days,
    required this.from,
    required this.to,
    required this.series,
    required this.summary,
  });

  final int days;
  final String from; // YYYY-MM-DD
  final String to;
  final List<TrendPoint> series;
  final TrendSummary summary;

  factory TrendData.fromJson(Map<String, dynamic> j) => TrendData(
        days: _int(j['days']),
        from: '${j['from'] ?? ''}',
        to: '${j['to'] ?? ''}',
        series: [
          for (final e in (j['series'] as List? ?? const []))
            if (e is Map) TrendPoint.fromJson(Map<String, dynamic>.from(e)),
        ],
        summary: TrendSummary.fromJson(_map(j['summary'])),
      );
}

class TrendService {
  Future<TrendData> get(int days, [Object? branchId]) async {
    final res = await api.get(
      '/core/dashboard/attendance-trends/',
      queryParameters: {
        'days': days,
        if (branchId != null && '$branchId'.isNotEmpty) 'branch_id': branchId,
      },
    );
    return TrendData.fromJson(_map(res.data));
  }
}

final trendService = TrendService();

// ── Attendance corrections ──────────────────────────────────────────────────

String _str(dynamic v) => v == null ? '' : '$v';
String? _strOrNull(dynamic v) => (v == null || '$v'.isEmpty) ? null : '$v';

/// Drops empty values, like clean() in hrService.ts.
Map<String, dynamic> _clean(Map<String, dynamic> params) => {
      for (final e in params.entries)
        if (e.value != null && e.value != '') e.key: e.value,
    };

class CorrectionRequest {
  const CorrectionRequest({
    required this.id,
    required this.employeeId,
    required this.employeeCode,
    required this.employeeName,
    required this.branchName,
    required this.departmentName,
    required this.teamLeadName,
    required this.date,
    required this.punchType,
    required this.timestamp,
    required this.reason,
    required this.status,
    required this.statusDisplay,
    required this.tlStatus,
    required this.tlComment,
    required this.tlProcessedBy,
    required this.tlProcessedAt,
    required this.hrComment,
    required this.processedBy,
    required this.processedAt,
    required this.createdAt,
    required this.canCancel,
    required this.canApproveTl,
    required this.canApproveHr,
  });

  final int id;
  final int employeeId;
  final String employeeCode;
  final String employeeName;
  final String branchName;
  final String departmentName;
  final String? teamLeadName;

  /// Attendance day (YYYY-MM-DD).
  final String date;
  final String punchType; // "IN" | "OUT"

  /// Requested punch, wall clock.
  final String timestamp;
  final String reason;

  /// PENDING | TL_APPROVED | APPROVED | DECLINED | CANCELLED
  final String status;
  final String statusDisplay;

  /// PENDING | APPROVED | DECLINED | NOT_REQUIRED
  final String tlStatus;
  final String tlComment;
  final String? tlProcessedBy;
  final String? tlProcessedAt;
  final String hrComment;
  final String? processedBy;
  final String? processedAt;
  final String createdAt;
  final bool canCancel;
  final bool canApproveTl;
  final bool canApproveHr;

  factory CorrectionRequest.fromJson(Map<String, dynamic> j) => CorrectionRequest(
        id: _int(j['id']),
        employeeId: _int(j['employee_id']),
        employeeCode: _str(j['employee_code']),
        employeeName: _str(j['employee_name']),
        branchName: _str(j['branch_name']),
        departmentName: _str(j['department_name']),
        teamLeadName: _strOrNull(j['team_lead_name']),
        date: _str(j['date']),
        punchType: _str(j['punch_type']),
        timestamp: _str(j['timestamp']),
        reason: _str(j['reason']),
        status: _str(j['status']),
        statusDisplay: _str(j['status_display']),
        tlStatus: _str(j['tl_status']),
        tlComment: _str(j['tl_comment']),
        tlProcessedBy: _strOrNull(j['tl_processed_by']),
        tlProcessedAt: _strOrNull(j['tl_processed_at']),
        hrComment: _str(j['hr_comment']),
        processedBy: _strOrNull(j['processed_by']),
        processedAt: _strOrNull(j['processed_at']),
        createdAt: _str(j['created_at']),
        canCancel: _bool(j['can_cancel']),
        canApproveTl: _bool(j['can_approve_tl']),
        canApproveHr: _bool(j['can_approve_hr']),
      );
}

class CorrectionList {
  const CorrectionList({required this.results, required this.count, required this.openCount});

  final List<CorrectionRequest> results;
  final int count;
  final int openCount;
}

class CorrectionService {
  Future<CorrectionList> list({
    String? scope, // "mine" | "team" | "all"
    String? status,
    String? from,
    String? to,
    String? q,
    int? page,
    int? pageSize,
  }) async {
    final res = await api.get(
      '/core/attendance/corrections/',
      queryParameters: _clean({
        'scope': scope,
        'status': status,
        'from': from,
        'to': to,
        'q': q,
        'page': page,
        'page_size': pageSize,
      }),
    );
    final j = _map(res.data);
    return CorrectionList(
      results: [
        for (final e in (j['results'] as List? ?? const []))
          if (e is Map) CorrectionRequest.fromJson(Map<String, dynamic>.from(e)),
      ],
      count: _int(j['count']),
      openCount: _int(j['open_count']),
    );
  }

  /// [time] is "HH:MM"; [nextDay] when the punch was after midnight.
  Future<CorrectionRequest> create({
    required String date,
    required String punchType,
    required String time,
    bool nextDay = false,
    required String reason,
  }) async {
    final res = await api.post('/core/attendance/corrections/', data: {
      'date': date,
      'punch_type': punchType,
      'time': time,
      'next_day': nextDay,
      'reason': reason,
    });
    return CorrectionRequest.fromJson(_map(res.data));
  }

  /// [action] is "approve", "decline" or "cancel".
  Future<CorrectionRequest> act(int id, String action, {String comment = ''}) async {
    final res = await api.patch('/core/attendance/corrections/$id/', data: {'action': action, 'comment': comment});
    return CorrectionRequest.fromJson(_map(res.data));
  }
}

final correctionService = CorrectionService();

// ── Overtime approval ───────────────────────────────────────────────────────

class OvertimeDay {
  const OvertimeDay({
    required this.employeeId,
    required this.employeeCode,
    required this.employeeName,
    required this.branchName,
    required this.departmentName,
    required this.date,
    required this.dayType,
    required this.shiftEnd,
    required this.firstIn,
    required this.lastOut,
    required this.workedMinutes,
    required this.calculatedMinutes,
    required this.approvedMinutes,
    required this.status,
    required this.changed,
    required this.comment,
    required this.decidedBy,
    required this.decidedAt,
    required this.canDecide,
  });

  final int employeeId;
  final String employeeCode;
  final String employeeName;
  final String branchName;
  final String departmentName;
  final String date; // YYYY-MM-DD
  final String dayType;
  final String? shiftEnd;
  final String? firstIn;
  final String? lastOut;
  final int workedMinutes;
  final int calculatedMinutes;
  final int approvedMinutes;

  /// PENDING | APPROVED | REJECTED | AUTO
  final String status;

  /// The day was recalculated after the decision.
  final bool changed;
  final String comment;
  final String? decidedBy;
  final String? decidedAt;
  final bool canDecide;

  /// Unique per row: one employee, one day.
  String get key => '$employeeId|$date';

  factory OvertimeDay.fromJson(Map<String, dynamic> j) => OvertimeDay(
        employeeId: _int(j['employee_id']),
        employeeCode: _str(j['employee_code']),
        employeeName: _str(j['employee_name']),
        branchName: _str(j['branch_name']),
        departmentName: _str(j['department_name']),
        date: _str(j['date']),
        dayType: _str(j['day_type']),
        shiftEnd: _strOrNull(j['shift_end']),
        firstIn: _strOrNull(j['first_in']),
        lastOut: _strOrNull(j['last_out']),
        workedMinutes: _int(j['worked_minutes']),
        calculatedMinutes: _int(j['calculated_minutes']),
        approvedMinutes: _int(j['approved_minutes']),
        status: _str(j['status']),
        changed: _bool(j['changed']),
        comment: _str(j['comment']),
        decidedBy: _strOrNull(j['decided_by']),
        decidedAt: _strOrNull(j['decided_at']),
        canDecide: _bool(j['can_decide']),
      );
}

class OvertimeSummary {
  const OvertimeSummary({
    this.calculated = 0,
    this.approved = 0,
    this.pending = 0,
    this.rejected = 0,
    this.pendingDays = 0,
  });

  final int calculated;
  final int approved;
  final int pending;
  final int rejected;
  final int pendingDays;

  factory OvertimeSummary.fromJson(Map<String, dynamic> j) => OvertimeSummary(
        calculated: _int(j['calculated']),
        approved: _int(j['approved']),
        pending: _int(j['pending']),
        rejected: _int(j['rejected']),
        pendingDays: _int(j['pending_days']),
      );
}

class OvertimeList {
  const OvertimeList({required this.results, required this.count, required this.summary});

  final List<OvertimeDay> results;
  final int count;
  final OvertimeSummary summary;
}

class OvertimeDecision {
  const OvertimeDecision({required this.employeeId, required this.date, required this.action, this.minutes});

  final int employeeId;
  final String date;

  /// "approve" | "reject" | "reset"
  final String action;

  /// Minutes to approve (part of the overtime); null approves all of it.
  final int? minutes;

  Map<String, dynamic> toJson() => {
        'employee_id': employeeId,
        'date': date,
        'action': action,
        if (minutes != null) 'minutes': minutes,
      };
}

class OvertimeService {
  Future<OvertimeList> list({
    String? from,
    String? to,
    String? status,
    Object? branchId,
    String? q,
    int? page,
    int? pageSize,
  }) async {
    final res = await api.get(
      '/core/attendance/overtime-approvals/',
      queryParameters: _clean({
        'from': from,
        'to': to,
        'status': status,
        'branch_id': branchId,
        'q': q,
        'page': page,
        'page_size': pageSize,
      }),
    );
    final j = _map(res.data);
    return OvertimeList(
      results: [
        for (final e in (j['results'] as List? ?? const []))
          if (e is Map) OvertimeDay.fromJson(Map<String, dynamic>.from(e)),
      ],
      count: _int(j['count']),
      summary: OvertimeSummary.fromJson(_map(j['summary'])),
    );
  }

  /// Returns how many days were updated and how many failed.
  Future<({int updated, int errors})> decide(List<OvertimeDecision> items, {String comment = ''}) async {
    final res = await api.post('/core/attendance/overtime-approvals/decide/', data: {
      'items': [for (final i in items) i.toJson()],
      'comment': comment,
    });
    final j = _map(res.data);
    return (updated: _int(j['updated']), errors: (j['errors'] as List? ?? const []).length);
  }
}

final overtimeService = OvertimeService();

// ── Holidays ────────────────────────────────────────────────────────────────

/// A schedule exception: a holiday, or a special working day.
class Holiday {
  const Holiday({
    required this.id,
    required this.branch,
    required this.date,
    required this.isWorkingDay,
    required this.startTime,
    required this.endTime,
    required this.reason,
    required this.repeatsYearly,
  });

  final int id;
  final int? branch;
  final String date; // YYYY-MM-DD
  final bool isWorkingDay;
  final String? startTime;
  final String? endTime;
  final String reason;
  final bool repeatsYearly;

  factory Holiday.fromJson(Map<String, dynamic> j) => Holiday(
        id: _int(j['id']),
        branch: j['branch'] == null ? null : _int(j['branch']),
        date: _str(j['date']),
        isWorkingDay: _bool(j['is_working_day']),
        startTime: _strOrNull(j['start_time']),
        endTime: _strOrNull(j['end_time']),
        reason: _str(j['reason']),
        repeatsYearly: _bool(j['repeats_yearly']),
      );
}

class HolidayService {
  /// All schedule exceptions of a year (holidays and special working days).
  Future<List<Holiday>> list(int year, {int? branchId}) async {
    final res = await api.get('/core/attendance/exceptions/', queryParameters: _clean({'year': year, 'branch_id': branchId}));
    final data = res.data;
    final list = data is Map ? data['results'] : data;
    return [
      for (final e in (list is List ? list : const []))
        if (e is Map) Holiday.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  /// Adds a holiday for every day from [startDate] to [endDate]; returns how many were created.
  Future<int> addRange({
    required String startDate,
    required String endDate,
    required String reason,
    required bool repeatsYearly,
    int? branchId,
  }) async {
    final res = await api.post(
      '/core/attendance/holidays/bulk/',
      data: {'start_date': startDate, 'end_date': endDate, 'reason': reason, 'repeats_yearly': repeatsYearly},
      queryParameters: _clean({'branch_id': branchId}),
    );
    return _int(_map(res.data)['created']);
  }

  Future<void> remove(int id, {int? branchId}) async {
    await api.delete('/core/attendance/exceptions/', queryParameters: _clean({'id': id, 'branch_id': branchId}));
  }

  /// Copies the "repeats yearly" holidays to another year.
  Future<({int created, int skipped})> copyYear(int fromYear, int toYear, {int? branchId}) async {
    final res = await api.post(
      '/core/attendance/holidays/copy-year/',
      data: {'from_year': fromYear, 'to_year': toYear},
      queryParameters: _clean({'branch_id': branchId}),
    );
    final j = _map(res.data);
    return (created: _int(j['created']), skipped: _int(j['skipped']));
  }
}

final holidayService = HolidayService();