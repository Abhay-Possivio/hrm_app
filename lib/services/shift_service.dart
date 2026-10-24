// Port of services/shiftService.ts

import 'package:hrm_app/api/api_client.dart';

int _int(dynamic v) => v is num ? v.round() : int.tryParse('$v') ?? 0;
String _str(dynamic v) => v == null ? '' : '$v';
String? _strOrNull(dynamic v) => (v == null || '$v'.isEmpty) ? null : '$v';

const shiftDays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

/// One day of a shift template.
class ShiftDay {
  const ShiftDay({required this.working, this.start, this.end});

  final bool working;
  final String? start; // "HH:MM:SS"
  final String? end;
}

class ShiftTemplate {
  const ShiftTemplate({required this.id, required this.name, required this.isActive, required this.days, this.raw = const {}});

  final int id;
  final String name;
  final bool isActive;

  /// Keyed by "mon" ... "sun".
  final Map<String, ShiftDay> days;
  final Map<String, dynamic> raw;

  factory ShiftTemplate.fromJson(Map<String, dynamic> j) => ShiftTemplate(
        id: _int(j['id']),
        name: _str(j['name']),
        isActive: j['is_active'] != false,
        days: {
          for (final d in shiftDays)
            d: ShiftDay(
              working: j['${d}_working'] == true,
              start: _strOrNull(j['${d}_start']),
              end: _strOrNull(j['${d}_end']),
            ),
        },
        raw: j,
      );
}

class EmployeeShift {
  const EmployeeShift({
    required this.id,
    required this.employee,
    required this.employeeName,
    required this.shift,
    required this.shiftName,
    required this.effectiveFrom,
    required this.effectiveTo,
    required this.createdAt,
  });

  final int id;
  final int employee;
  final String employeeName;
  final int shift; // template id
  final String shiftName;
  final String effectiveFrom; // YYYY-MM-DD
  final String? effectiveTo;
  final String createdAt;

  factory EmployeeShift.fromJson(Map<String, dynamic> j) => EmployeeShift(
        id: _int(j['id']),
        employee: _int(j['employee']),
        employeeName: _str(j['employee_name']),
        shift: _int(j['shift']),
        shiftName: _str(j['shift_name']),
        effectiveFrom: _str(j['effective_from']),
        effectiveTo: _strOrNull(j['effective_to']),
        createdAt: _str(j['created_at']),
      );
}

List<Map<String, dynamic>> _rows(dynamic data) {
  final list = data is Map ? data['results'] : data;
  return list is List ? [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)] : const [];
}

class ShiftService {
  // ── Shift templates ───────────────────────────────────────────────────────

  Future<List<ShiftTemplate>> getTemplates({int? branchId}) async {
    final res = await api.get('/core/attendance/shifts/', queryParameters: {
      't': DateTime.now().millisecondsSinceEpoch,
      if (branchId != null) 'branch_id': branchId,
    });
    return [for (final r in _rows(res.data)) ShiftTemplate.fromJson(r)];
  }

  Future<ShiftTemplate> createTemplate(Map<String, dynamic> data, {int? branchId}) async {
    final res = await api.post('/core/attendance/shifts/', data: {...data, 'branch_id': branchId});
    return ShiftTemplate.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ShiftTemplate> updateTemplate(int id, Map<String, dynamic> data) async {
    final res = await api.put('/core/attendance/shifts/$id/', data: data);
    return ShiftTemplate.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<void> deleteTemplate(int id) async {
    await api.delete('/core/attendance/shifts/$id/');
  }

  // ── Employee shift assignments ────────────────────────────────────────────

  Future<List<EmployeeShift>> getEmployeeShifts(int employeeId) async {
    final res = await api.get('/core/employees/admin/$employeeId/shifts/', queryParameters: {
      't': DateTime.now().millisecondsSinceEpoch,
    });
    return [for (final r in _rows(res.data)) EmployeeShift.fromJson(r)];
  }

  Future<void> assignShift(int employeeId, {required int shift, required String effectiveFrom, String? effectiveTo}) async {
    await api.post('/core/employees/admin/$employeeId/shifts/', data: {
      'shift': shift,
      'effective_from': effectiveFrom,
      'effective_to': effectiveTo,
    });
  }

  Future<void> updateShift(
    int employeeId,
    int assignmentId, {
    required int shift,
    required String effectiveFrom,
    String? effectiveTo,
  }) async {
    await api.put('/core/employees/admin/$employeeId/shifts/$assignmentId/', data: {
      'shift': shift,
      'effective_from': effectiveFrom,
      'effective_to': effectiveTo,
    });
  }

  Future<void> removeShift(int employeeId, int assignmentId) async {
    await api.delete('/core/employees/admin/$employeeId/shifts/$assignmentId/');
  }
}

final shiftService = ShiftService();