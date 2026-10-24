// The report engine calls from ReportsPage.tsx (/core/reports/engine/).
// Every report returns rows as plain maps; the columns are whatever keys the
// rows have, exactly as on the web.

import 'package:hrm_app/api/api_client.dart';
import 'package:hrm_app/utils/file_share.dart';

class ReportQuery {
  const ReportQuery({
    required this.reportType,
    required this.period,
    this.fromDate,
    this.toDate,
    this.branchId = '',
    this.departmentId = '',
    this.employeeIds = const [],
    this.searchQ = '',
  });

  final String reportType;

  /// today | yesterday | this_week | last_week | this_month | last_month |
  /// this_year | last_year | user_defined
  final String period;
  final String? fromDate; // YYYY-MM-DD, used when period is user_defined
  final String? toDate;
  final String branchId;
  final String departmentId;
  final List<int> employeeIds;
  final String searchQ;

  Map<String, dynamic> toParams() => {
        'report_type': reportType,
        'period': period,
        'branch_id': branchId,
        'department_id': departmentId,
        'team_id': '',
        'search_q': searchQ,
        if (period == 'user_defined') 'from_date': fromDate,
        if (period == 'user_defined') 'to_date': toDate,
        if (employeeIds.isNotEmpty) 'employee_ids': employeeIds.join(','),
      };
}

class ReportService {
  Future<({List<Map<String, dynamic>> results, int count})> run(ReportQuery q, {int page = 1, int pageSize = 25}) async {
    final res = await api.get('/core/reports/engine/', queryParameters: {...q.toParams(), 'page': page, 'page_size': pageSize});
    final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const <String, dynamic>{};
    final rows = data['results'];
    return (
      results: [
        for (final r in (rows is List ? rows : const []))
          if (r is Map) Map<String, dynamic>.from(r),
      ],
      count: data['count'] is num ? (data['count'] as num).toInt() : 0,
    );
  }

  /// [format] is "xlsx", "csv" or "pdf". Downloads and opens the share sheet.
  Future<void> export(ReportQuery q, String format, {required String fileName}) {
    return downloadAndShare(
      '/core/reports/engine/',
      queryParameters: {...q.toParams(), 'export': format},
      fileName: fileName,
      mimeType: switch (format) { 'pdf' => pdfMime, 'csv' => csvMime, _ => xlsxMime },
    );
  }
}

final reportService = ReportService();