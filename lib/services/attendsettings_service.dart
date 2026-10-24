// Port of services/attendanceSettingsService.ts
//
// Rules and the weekly schedule are kept as plain maps (field name → value)
// so every field the server sends is sent back unchanged on save, including
// ones a form doesn't show.

import 'package:hrm_app/api/api_client.dart';

int _int(dynamic v) => v is num ? v.round() : int.tryParse('$v') ?? 0;
int? _intOrNull(dynamic v) => v == null ? null : (v is num ? v.round() : int.tryParse('$v'));
String _str(dynamic v) => v == null ? '' : '$v';
String? _strOrNull(dynamic v) => (v == null || '$v'.isEmpty) ? null : '$v';
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

Map<String, dynamic> _branch(int? branchId) => branchId == null ? const {} : {'branch_id': branchId};

/// A one-day override of the schedule (holiday, special working day).
class ScheduledException {
  const ScheduledException({
    required this.id,
    this.branch,
    required this.date,
    required this.isWorkingDay,
    this.startTime,
    this.endTime,
    required this.reason,
  });

  final int id;
  final int? branch;
  final String date; // YYYY-MM-DD
  final bool isWorkingDay;
  final String? startTime; // "HH:MM[:SS]"
  final String? endTime;
  final String reason;

  factory ScheduledException.fromJson(Map<String, dynamic> j) => ScheduledException(
        id: _int(j['id']),
        branch: _intOrNull(j['branch']),
        date: _str(j['date']),
        isWorkingDay: j['is_working_day'] == true,
        startTime: _strOrNull(j['start_time']),
        endTime: _strOrNull(j['end_time']),
        reason: _str(j['reason']),
      );
}

class AttendanceSettingsService {
  // ── Rules (late policy, breaks, overtime settings) ────────────────────────

  Future<Map<String, dynamic>> getRules({int? branchId}) async {
    final res = await api.get('/core/attendance/rules/', queryParameters: _branch(branchId));
    return _map(res.data);
  }

  Future<Map<String, dynamic>> updateRules(Map<String, dynamic> data, {int? branchId}) async {
    final res = await api.put('/core/attendance/rules/', data: data, queryParameters: _branch(branchId));
    return _map(res.data);
  }

  /// Removes a branch's own rules so it uses the company defaults again.
  Future<void> resetRules(int branchId) async {
    await api.delete('/core/attendance/rules/', queryParameters: {'branch_id': branchId});
  }

  // ── Weekly schedule ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getSchedule({int? branchId}) async {
    final res = await api.get('/core/attendance/schedule/', queryParameters: _branch(branchId));
    return _map(res.data);
  }

  Future<Map<String, dynamic>> updateSchedule(Map<String, dynamic> data, {int? branchId}) async {
    final res = await api.put('/core/attendance/schedule/', data: data, queryParameters: _branch(branchId));
    return _map(res.data);
  }

  Future<void> resetSchedule(int branchId) async {
    await api.delete('/core/attendance/schedule/', queryParameters: {'branch_id': branchId});
  }

  // ── Date exceptions ───────────────────────────────────────────────────────

  Future<List<ScheduledException>> getExceptions({int? branchId, int? year, int? month}) async {
    final res = await api.get('/core/attendance/exceptions/', queryParameters: {
      ..._branch(branchId),
      if (year != null) 'year': year,
      if (month != null) 'month': month,
    });
    final data = res.data;
    final list = data is Map ? data['results'] : data;
    return [
      for (final e in (list is List ? list : const []))
        if (e is Map) ScheduledException.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  Future<void> createException({
    required String date,
    required bool isWorkingDay,
    String? startTime,
    String? endTime,
    required String reason,
    int? branchId,
  }) async {
    await api.post(
      '/core/attendance/exceptions/',
      data: {
        'date': date,
        'is_working_day': isWorkingDay,
        'start_time': startTime,
        'end_time': endTime,
        'reason': reason,
      },
      queryParameters: _branch(branchId),
    );
  }

  Future<void> deleteException(int id) async {
    await api.delete('/core/attendance/exceptions/', queryParameters: {'id': id});
  }
}

final attendanceSettingsService = AttendanceSettingsService();