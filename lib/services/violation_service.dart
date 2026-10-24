// Port of services/violationService.ts

import 'package:hrm_app/api/api_client.dart';
import 'package:hrm_app/utils/file_share.dart';

int _int(dynamic v) => v is num ? v.round() : int.tryParse('$v') ?? 0;
String _str(dynamic v) => v == null ? '' : '$v';
String? _strOrNull(dynamic v) => (v == null || '$v'.isEmpty) ? null : '$v';
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : const {};
List<Map<String, dynamic>> _list(dynamic v) =>
    v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];

class Violation {
  const Violation({
    required this.id,
    required this.date,
    required this.occurredAt,
    required this.employeeId,
    required this.employeeCode,
    required this.employeeName,
    required this.branchName,
    required this.violationType,
    required this.violationLabel,
    required this.description,
    required this.createdAt,
  });

  final int id;

  /// Attendance day the violation belongs to (YYYY-MM-DD).
  final String date;

  /// Wall-clock time of the punch involved, when there is one.
  final String? occurredAt;
  final int employeeId;
  final String employeeCode;
  final String employeeName;
  final String branchName;
  final String violationType;
  final String violationLabel;
  final String description;

  /// When the system first detected it (server time).
  final String createdAt;

  factory Violation.fromJson(Map<String, dynamic> j) => Violation(
        id: _int(j['id']),
        date: _str(j['date']),
        occurredAt: _strOrNull(j['occurred_at']),
        employeeId: _int(j['employee_id']),
        employeeCode: _str(j['employee_code']),
        employeeName: _str(j['employee_name']),
        branchName: _str(j['branch_name']),
        violationType: _str(j['violation_type']),
        violationLabel: _str(j['violation_label']),
        description: _str(j['description']),
        createdAt: _str(j['created_at']),
      );
}

class ViolationTypeCount {
  const ViolationTypeCount({required this.violationType, required this.label, required this.count});

  final String violationType;
  final String label;
  final int count;
}

class ViolationList {
  const ViolationList({required this.count, required this.results, required this.total, required this.byType});

  final int count;
  final List<Violation> results;
  final int total;
  final List<ViolationTypeCount> byType;
}

Map<String, dynamic> _filters({String? startDate, String? endDate, String? violationType, String? q}) => {
      if (startDate != null && startDate.isNotEmpty) 'start_date': startDate,
      if (endDate != null && endDate.isNotEmpty) 'end_date': endDate,
      if (violationType != null && violationType.isNotEmpty) 'violation_type': violationType,
      if (q != null && q.isNotEmpty) 'q': q,
    };

class ViolationService {
  Future<ViolationList> list({
    String? startDate,
    String? endDate,
    String? violationType,
    String? q,
    int? page,
    int? pageSize,
  }) async {
    final res = await api.get('/core/attendance/violations/', queryParameters: {
      ..._filters(startDate: startDate, endDate: endDate, violationType: violationType, q: q),
      if (page != null) 'page': page,
      if (pageSize != null) 'page_size': pageSize,
    });
    final j = _map(res.data);
    final summary = _map(j['summary']);
    return ViolationList(
      count: _int(j['count']),
      results: [for (final r in _list(j['results'])) Violation.fromJson(r)],
      total: _int(summary['total']),
      byType: [
        for (final t in _list(summary['by_type']))
          ViolationTypeCount(violationType: _str(t['violation_type']), label: _str(t['label']), count: _int(t['count'])),
      ],
    );
  }

  /// Downloads the Excel export and opens the share sheet.
  Future<void> exportXlsx({String? startDate, String? endDate, String? violationType, String? q}) {
    return downloadAndShare(
      '/core/attendance/violations/export/xlsx/',
      queryParameters: _filters(startDate: startDate, endDate: endDate, violationType: violationType, q: q),
      fileName: 'violations_${startDate ?? ''}_${endDate ?? ''}.xlsx',
      mimeType: xlsxMime,
    );
  }
}

final violationService = ViolationService();