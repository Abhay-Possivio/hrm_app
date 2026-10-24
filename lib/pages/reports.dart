// Port of features/admin/reports/ReportsPage.tsx with ReportLayout,
// ReportFilters, ExportToolbar and ReportTable.
//
// Pick a category and report, set filters, and the results reload. Columns
// come from the rows the server returns. Export as Excel, CSV or PDF opens
// the phone's share sheet (print from there, or from the PDF viewer, in
// place of the web's Print button).
//
// Layout (compact):
//   Header: title · refresh · Export menu
//   Report picker: category tabs · report chips
//   Filters card: collapsible on phones, with an active-filter count and Reset
//   Results card: report name · row count · table/cards toggle · columns
//                 table (wide) or one card per row (phones) · pagination

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hrm_app/components/ui/pagination_bar.dart';
import 'package:hrm_app/services/branch_service.dart';
import 'package:hrm_app/services/dept_service.dart';
import 'package:hrm_app/services/employee_service.dart';
import 'package:hrm_app/services/reports_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';
import 'package:hrm_app/utils/toast.dart';

const _pageSize = 25;

enum _Category {
  daily('Daily', Icons.today_outlined),
  weekly('Weekly', Icons.date_range_outlined),
  monthly('Monthly', Icons.calendar_month_outlined),
  summary('Summary', Icons.bar_chart_rounded);

  const _Category(this.label, this.icon);

  final String label;
  final IconData icon;
}

const _reports = [
  ('daily_total_time_card', 'Total time card', _Category.daily),
  ('daily_all_punches', 'All punches log', _Category.daily),
  ('daily_worked_hours', 'Worked hours', _Category.daily),
  ('daily_overtime', 'Overtime', _Category.daily),
  ('daily_late_in', 'Late in', _Category.daily),
  ('daily_early_out', 'Early out', _Category.daily),
  ('daily_absent', 'Absent', _Category.daily),
  ('daily_break_time', 'Break time', _Category.daily),
  ('daily_violations', 'Violations', _Category.daily),
  ('weekly_worked_hours', 'Weekly worked hours', _Category.weekly),
  ('weekly_overtime', 'Weekly overtime', _Category.weekly),
  ('monthly_status', 'Monthly status', _Category.monthly),
  ('monthly_check_in_out', 'Monthly check-in & out', _Category.monthly),
  ('monthly_worked_hours', 'Monthly worked hours', _Category.monthly),
  ('monthly_overtime', 'Monthly overtime', _Category.monthly),
  ('monthly_absence', 'Monthly absence', _Category.monthly),
  ('monthly_payroll', 'Payroll export', _Category.monthly),
  ('summary_employee_attendance', 'Employee attendance', _Category.summary),
  ('summary_department_attendance', 'Department attendance', _Category.summary),
  ('summary_team_attendance', 'Team attendance', _Category.summary),
];

const _periods = [
  ('today', 'Today'),
  ('yesterday', 'Yesterday'),
  ('this_week', 'This week'),
  ('last_week', 'Last week'),
  ('this_month', 'This month'),
  ('last_month', 'Last month'),
  ('this_year', 'This year'),
  ('last_year', 'Previous year'),
  ('user_defined', 'Custom range…'),
];

const _exports = [
  ('xlsx', 'Excel (.xlsx)', Icons.table_chart_outlined, Color(0xFF059669)),
  ('csv', 'CSV (.csv)', Icons.description_outlined, Color(0xFF2563EB)),
  ('pdf', 'PDF (.pdf)', Icons.picture_as_pdf_outlined, Color(0xFFDC2626)),
];

// ── Design tokens ───────────────────────────────────────────────────────────

class _K {
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo200 = Color(0xFFC7D2FE);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const indigo700 = Color(0xFF4338CA);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald500 = Color(0xFF10B981);
  static const emerald700 = Color(0xFF047857);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber200 = Color(0xFFFDE68A);
  static const amber500 = Color(0xFFF59E0B);
  static const amber700 = Color(0xFFB45309);
  static const red50 = Color(0xFFFEF2F2);
  static const red200 = Color(0xFFFECACA);
  static const red500 = Color(0xFFEF4444);
  static const red700 = Color(0xFFB91C1C);
}

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3, color: _K.slate900);
  static const subtitle = TextStyle(fontSize: 12, height: 1.3, color: _K.slate500);
  static const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _K.slate500);
  static const columnHead = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.slate500);
  static const cell = TextStyle(fontSize: 13, color: _K.slate700, fontFeatures: tabular);
}

const _cardRadius = 16.0;
const _divider = Divider(height: 1, thickness: 1, color: _K.slate100);

/// "check_in_time" → "Check in time".
String _label(String key) {
  final t = key.replaceAll('_', ' ').trim();
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

// ── Page ────────────────────────────────────────────────────────────────────

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  _Category _category = _Category.daily;
  String _reportType = 'daily_total_time_card';

  List<BranchOption> _branches = const [];
  List<Department> _departments = const [];
  List<Employee> _employees = const [];
  bool _optionsFailed = false;

  // Filters
  String _period = 'this_month';
  DateTime _from = _today();
  DateTime _to = _today();
  String _branchId = '';
  String _departmentId = '';
  List<int> _employeeIds = const [];
  String _searchQ = '';
  final _search = TextEditingController();
  Timer? _debounce;

  /// Null = follow the screen width (open on tablets, closed on phones).
  bool? _filtersOpen;

  /// Null = follow the screen width (cards on phones, table on tablets).
  bool? _cardView;

  // Results
  List<Map<String, dynamic>> _rows = const [];
  List<String> _columns = const [];
  final Set<String> _hidden = {};
  int _total = 0;
  int _page = 1;
  bool _loading = false;
  bool _searched = false;
  String? _error;
  String? _exporting;
  int _loadId = 0;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String get _reportName => _reports.firstWhere((r) => r.$1 == _reportType, orElse: () => (_reportType, _reportType, _category)).$2;

  int get _activeFilters =>
      (_period != 'this_month' ? 1 : 0) +
      (_branchId.isNotEmpty ? 1 : 0) +
      (_departmentId.isNotEmpty ? 1 : 0) +
      (_employeeIds.isNotEmpty ? 1 : 0) +
      (_searchQ.isNotEmpty ? 1 : 0);

  @override
  void initState() {
    super.initState();
    _loadOptions();
    _run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final results = await Future.wait([
        branchService.fetchBranchOptions(),
        departmentService.fetchDepartments(),
        employeeService.fetchAllEmployees(),
      ]);
      if (!mounted) return;
      setState(() {
        _branches = results[0] as List<BranchOption>;
        _departments = results[1] as List<Department>;
        _employees = results[2] as List<Employee>;
        _optionsFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _optionsFailed = true);
    }
  }

  ReportQuery get _query => ReportQuery(
        reportType: _reportType,
        period: _period,
        fromDate: toDateKey(_from),
        toDate: toDateKey(_to),
        branchId: _branchId,
        departmentId: _departmentId,
        employeeIds: _employeeIds,
        searchQ: _searchQ,
      );

  Future<void> _run({int page = 1}) async {
    final id = ++_loadId;
    setState(() {
      _loading = true;
      _searched = true;
      _page = page;
      _error = null;
    });
    try {
      final res = await reportService.run(_query, page: page, pageSize: _pageSize);
      if (!mounted || id != _loadId) return;
      setState(() {
        _rows = res.results;
        _total = res.count;
        // Columns from the first row; none for an empty result.
        final cols = res.results.isEmpty ? <String>[] : res.results.first.keys.toList();
        if (cols.join('|') != _columns.join('|')) _hidden.clear();
        _columns = cols;
      });
    } catch (err) {
      if (!mounted || id != _loadId) return;
      setState(() {
        _rows = const [];
        _total = 0;
        _error = apiError(err, 'Failed to fetch report data.');
      });
    } finally {
      if (mounted && id == _loadId) setState(() => _loading = false);
    }
  }

  /// Applies a filter change and reloads (the web reloads on every change).
  void _set(VoidCallback change) {
    setState(change);
    _run();
  }

  void _onSearch(String value) {
    // Wait for typing to pause (the web requests on every keystroke).
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final q = value.trim();
      if (q != _searchQ) _set(() => _searchQ = q);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    if (_searchQ.isNotEmpty) _set(() => _searchQ = '');
  }

  void _reset() {
    _debounce?.cancel();
    _search.clear();
    _set(() {
      _period = 'this_month';
      _from = _today();
      _to = _today();
      _branchId = '';
      _departmentId = '';
      _employeeIds = const [];
      _searchQ = '';
    });
  }

  Future<void> _export(String format) async {
    if (!_searched || _rows.isEmpty) {
      showToast(context, 'Generate a report with results before exporting.', error: true);
      return;
    }
    setState(() => _exporting = format);
    try {
      await reportService.export(_query, format, fileName: '${_reportType}_${toDateKey(_from)}.$format');
    } catch (_) {
      if (mounted) showToast(context, 'Failed to export ${format.toUpperCase()} report.', error: true);
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _from, end: _to.isBefore(_from) ? _from : _to),
    );
    if (picked == null) return;
    _set(() {
      _from = picked.start;
      _to = picked.end;
      _period = 'user_defined';
    });
  }

  Future<void> _onPeriod(String v) async {
    if (v == 'user_defined') {
      await _pickRange();
      return;
    }
    if (v != _period) _set(() => _period = v);
  }

  Future<void> _pickEmployees() async {
    final ids = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EmployeePicker(employees: _employees, selected: _employeeIds),
    );
    if (ids != null) _set(() => _employeeIds = ids);
  }

  Future<void> _pickColumns() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxWidth: 480),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) {
          void update(VoidCallback f) {
            setState(f);
            setSheet(() {});
          }

          final shown = _columns.length - _hidden.length;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Columns', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.slate900)),
                            Text('$shown of ${_columns.length} shown', style: _T.subtitle),
                          ],
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: _K.indigo600),
                        onPressed: _hidden.isEmpty ? null : () => update(_hidden.clear),
                        child: const Text('Show all'),
                      ),
                    ],
                  ),
                ),
                _divider,
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      for (final c in _columns)
                        CheckboxListTile(
                          value: !_hidden.contains(c),
                          dense: true,
                          activeColor: _K.indigo600,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(_label(c), style: const TextStyle(fontSize: 13.5, color: _K.slate800)),
                          // Keep at least one column visible.
                          onChanged: (!_hidden.contains(c) && shown == 1)
                              ? null
                              : (v) => update(() => v == true ? _hidden.remove(c) : _hidden.add(c)),
                        ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _K.indigo600,
                        minimumSize: const Size.fromHeight(42),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: _K.indigo600,
      onRefresh: () => _run(page: _page),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sm = width >= 640;
          final gap = sm ? 20.0 : 16.0;

          final sections = <Widget>[
            _header(wide: sm),
            _reportPicker(),
            if (_optionsFailed)
              _Banner(
                tone: const (_K.amber50, _K.amber200, _K.amber700),
                icon: Icons.warning_amber_rounded,
                actionLabel: 'Retry',
                onAction: _loadOptions,
                child: const Text('Branch, department and employee lists could not be loaded.'),
              ),
            _filters(open: _filtersOpen ?? sm),
            _results(cards: _cardView ?? !sm),
          ];

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(sm ? 24 : 16),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < sections.length; i++) ...[
                        if (i > 0) SizedBox(height: i == 1 ? gap : 12),
                        sections[i],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Header ──

  Widget _header({required bool wide}) {
    final canExport = _searched && _rows.isNotEmpty && _exporting == null;

    final export = PopupMenuButton<String>(
      tooltip: canExport ? 'Export this report' : 'Generate a report with results first',
      enabled: canExport,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: _export,
      itemBuilder: (_) => [
        for (final (format, label, icon, color) in _exports)
          PopupMenuItem(
            value: format,
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 10),
                Text(label, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
      ],
      child: Opacity(
        opacity: canExport || _exporting != null ? 1 : 0.5,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: _K.indigo600, borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_exporting != null)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              else
                const Icon(Icons.file_download_outlined, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                _exporting != null ? 'Exporting ${_exporting!.toUpperCase()}…' : 'Export',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
              ),
              if (_exporting == null) ...[
                const SizedBox(width: 2),
                const Icon(Icons.expand_more_rounded, size: 18, color: Colors.white),
              ],
            ],
          ),
        ),
      ),
    );

    final refresh = IconButton(
      tooltip: 'Refresh',
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        side: const BorderSide(color: _K.slate200),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: _loading ? null : () => _run(page: _page),
      icon: _loading
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.refresh_rounded, size: 18, color: _K.slate600),
    );

    final title = Row(
      children: [
        const _IconBox(icon: Icons.insert_chart_outlined_rounded, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Reports',
                  style: TextStyle(
                    fontSize: wide ? 22 : 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.25,
                    color: _K.slate900,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              const Text('Choose a report, set filters, then export or share it.', style: _T.subtitle),
            ],
          ),
        ),
      ],
    );

    if (wide) {
      return Row(children: [Expanded(child: title), const SizedBox(width: 12), refresh, const SizedBox(width: 8), export]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [title, const SizedBox(height: 12), Row(children: [refresh, const SizedBox(width: 8), export])],
    );
  }

  // ── Report picker ──

  Widget _reportPicker() {
    final reports = _reports.where((r) => r.$3 == _category).toList();

    return _Surface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Row(
              children: [
                for (final c in _Category.values)
                  _CategoryTab(
                    category: c,
                    count: _reports.where((r) => r.$3 == c).length,
                    selected: _category == c,
                    onTap: () {
                      if (c == _category) return;
                      _set(() {
                        _category = c;
                        _reportType = _reports.firstWhere((r) => r.$3 == c).$1;
                      });
                    },
                  ),
              ],
            ),
          ),
          _divider,
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                for (final (i, (id, name, _)) in reports.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  _ReportChip(
                    label: name,
                    selected: _reportType == id,
                    onTap: () {
                      if (id != _reportType) _set(() => _reportType = id);
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Filters ──

  Widget _filters({required bool open}) {
    final periodLabel = _period == 'user_defined'
        ? '${formatDDMMMYYYY(_from)} – ${formatDDMMMYYYY(_to)}'
        : _periods.firstWhere((p) => p.$1 == _period, orElse: () => (_period, _period)).$2;
    var branchLabel = 'All branches';
    for (final b in _branches) {
      if ('${b.id}' == _branchId) branchLabel = b.name;
    }
    final summary = [
      periodLabel,
      if (_branchId.isNotEmpty) branchLabel,
      if (_employeeIds.isNotEmpty) '${_employeeIds.length} employee${_employeeIds.length == 1 ? '' : 's'}',
      if (_searchQ.isNotEmpty) '"$_searchQ"',
    ].join(', ');
    final active = _activeFilters;

    final fields = <Widget>[
      _Field(
        label: 'Period',
        child: _Dropdown(
          value: _period,
          options: _periods,
          onChanged: _onPeriod,
        ),
      ),
      if (_period == 'user_defined')
        _Field(
          label: 'Dates',
          child: Semantics(
            button: true,
            label: 'Dates, $periodLabel',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _pickRange,
              child: InputDecorator(
                decoration: _inputDecoration(icon: Icons.date_range_outlined),
                child: Text(periodLabel,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: _K.slate800)),
              ),
            ),
          ),
        ),
      _Field(
        label: 'Branch',
        child: _Dropdown(
          value: _branchId,
          options: [('', 'All branches'), for (final b in _branches) ('${b.id}', b.name)],
          onChanged: (v) {
            if (v != _branchId) _set(() => _branchId = v);
          },
        ),
      ),
      _Field(
        label: 'Department',
        child: _Dropdown(
          value: _departmentId,
          options: [('', 'All departments'), for (final d in _departments) ('${d.id}', d.name)],
          onChanged: (v) {
            if (v != _departmentId) _set(() => _departmentId = v);
          },
        ),
      ),
      _Field(
        label: 'Employees',
        child: Semantics(
          button: true,
          label: _employeeIds.isEmpty ? 'Employees, all' : 'Employees, ${_employeeIds.length} selected',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _employees.isEmpty ? null : _pickEmployees,
            child: InputDecorator(
              decoration: _inputDecoration(icon: Icons.people_outline_rounded).copyWith(
                suffixIcon: const Icon(Icons.expand_more_rounded, size: 18, color: _K.slate400),
              ),
              child: Text(
                _employees.isEmpty && !_optionsFailed
                    ? 'Loading…'
                    : _employeeIds.isEmpty
                        ? 'All employees'
                        : '${_employeeIds.length} selected',
                style: TextStyle(fontSize: 13, color: _employeeIds.isEmpty ? _K.slate500 : _K.slate800),
              ),
            ),
          ),
        ),
      ),
      _Field(
        label: 'Search',
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _search,
          builder: (context, value, _) => TextField(
            controller: _search,
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 13, color: _K.slate800),
            decoration: _inputDecoration(icon: Icons.search_rounded).copyWith(
              hintText: 'Name or code',
              hintStyle: const TextStyle(fontSize: 13, color: _K.slate400),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                      onPressed: _clearSearch,
                      icon: const Icon(Icons.close_rounded, size: 16, color: _K.slate400),
                    ),
            ),
          ),
        ),
      ),
    ];

    return _Surface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(_cardRadius),
                bottom: Radius.circular(open ? 0 : _cardRadius),
              ),
              onTap: () => setState(() => _filtersOpen = !open),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    const Icon(Icons.tune_rounded, size: 18, color: _K.slate500),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('Filters', style: _T.title),
                              if (active > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(color: _K.indigo50, borderRadius: BorderRadius.circular(99)),
                                  child: Text('$active',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _K.indigo600)),
                                ),
                              ],
                            ],
                          ),
                          if (!open) ...[
                            const SizedBox(height: 1),
                            Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.subtitle),
                          ],
                        ],
                      ),
                    ),
                    if (active > 0)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: _K.indigo600,
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        onPressed: _reset,
                        child: const Text('Reset'),
                      ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(Icons.expand_more_rounded, size: 20, color: _K.slate400),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: open
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _divider,
                      Padding(padding: const EdgeInsets.all(14), child: _FilterGrid(children: fields)),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  // ── Results ──

  Widget _results({required bool cards}) {
    final visible = _columns.where((c) => !_hidden.contains(c)).toList();
    final from = _total == 0 ? 0 : (_page - 1) * _pageSize + 1;
    final to = (_page - 1) * _pageSize + _rows.length;

    Widget body;
    if (_error != null && _rows.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: _EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load this report',
          message: _error,
          action: _LinkButton(label: 'Try again', onTap: () => _run(page: _page)),
        ),
      );
    } else if (_loading && _rows.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: _K.indigo500)),
            SizedBox(height: 10),
            Text('Generating report…', style: _T.subtitle),
          ],
        ),
      );
    } else if (!_searched) {
      body = const Padding(
        padding: EdgeInsets.all(16),
        child: _EmptyState(
          icon: Icons.insert_chart_outlined_rounded,
          title: 'No report yet',
          message: 'Choose a report and filters to generate it.',
        ),
      );
    } else if (_rows.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: _EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No records found',
          message: 'Try a wider period or fewer filters.',
          action: _activeFilters > 0 ? _LinkButton(label: 'Reset filters', onTap: _reset) : null,
        ),
      );
    } else if (cards) {
      body = Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _RowCard(row: _rows[i], columns: visible, value: _value),
            ],
          ],
        ),
      );
    } else {
      body = LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(flex: 1),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: const BoxDecoration(
                    color: _K.slate50,
                    border: Border(bottom: BorderSide(color: _K.slate200)),
                  ),
                  children: [for (final c in visible) _cell(Text(_label(c), style: _T.columnHead))],
                ),
                for (var i = 0; i < _rows.length; i++)
                  TableRow(
                    decoration: BoxDecoration(
                      color: i.isOdd ? _K.slate50.withValues(alpha: 0.6) : Colors.white,
                      border: i < _rows.length - 1 ? const Border(bottom: BorderSide(color: _K.slate100)) : null,
                    ),
                    children: [for (final c in visible) _cell(_value(c, _rows[i][c]))],
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return _Surface(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(_reportName, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.title),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _rows.isEmpty
                            ? (_loading ? 'Loading…' : 'No rows')
                            : 'Rows $from–$to of $_total'
                                '${_hidden.isNotEmpty ? ', ${visible.length} of ${_columns.length} columns' : ''}',
                        style: const TextStyle(fontSize: 12, color: _K.slate500, fontFeatures: _T.tabular),
                      ),
                    ],
                  ),
                ),
                if (_rows.isNotEmpty) ...[
                  _ViewToggle(cards: cards, onChanged: (v) => setState(() => _cardView = v)),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Choose columns',
                    visualDensity: VisualDensity.compact,
                    onPressed: _columns.isEmpty ? null : _pickColumns,
                    icon: Badge(
                      isLabelVisible: _hidden.isNotEmpty,
                      backgroundColor: _K.indigo600,
                      smallSize: 7,
                      child: const Icon(Icons.view_column_outlined, size: 20, color: _K.slate600),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            height: 2,
            child: _loading
                ? const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50)
                : const ColoredBox(color: _K.slate100),
          ),
          AnimatedOpacity(
            opacity: _loading && _rows.isNotEmpty ? 0.55 : 1,
            duration: const Duration(milliseconds: 150),
            child: body,
          ),
          if (_rows.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.slate100))),
              child: PaginationBar(page: _page, total: _total, pageSize: _pageSize, onPage: (p) => _run(page: p)),
            ),
        ],
      ),
    );
  }

  static Widget _cell(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: child,
      );

  /// Same special cells as the web table; everything else is plain text.
  Widget _value(String key, dynamic value) {
    final text = value == null ? '' : '$value';
    switch (key) {
      case 'all_punches':
        if (text.isEmpty || text == 'No Punches') {
          return const Text('No punches', style: TextStyle(fontSize: 12, color: _K.slate400));
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final p in text.split(', '))
                _PunchTag(time: p.replaceAll(RegExp(r'\s*\((IN|OUT)\)'), ''), isOut: p.contains('(OUT)')),
            ],
          ),
        );
      case 'total_punches':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(
            color: _K.indigo50,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: _K.indigo200),
          ),
          child: Text(text,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _K.indigo700, fontFeatures: _T.tabular)),
        );
      case 'violation_type':
        final upper = text.toUpperCase();
        final red = upper.contains('DOUBLE IN') || upper.contains('MISSING');
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: red ? _K.red50 : _K.amber50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: red ? _K.red200 : _K.amber200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: red ? _K.red500 : _K.amber500, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(
                _label(text.toLowerCase()),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: red ? _K.red700 : _K.amber700),
              ),
            ],
          ),
        );
      case 'time':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: _K.slate100,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _K.slate200),
          ),
          child: Text(text,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.slate700, fontFeatures: _T.tabular)),
        );
      default:
        return Text(text, style: _T.cell);
    }
  }
}

// ── Row card (phones) ───────────────────────────────────────────────────────

class _RowCard extends StatelessWidget {
  const _RowCard({required this.row, required this.columns, required this.value});

  final Map<String, dynamic> row;
  final List<String> columns;
  final Widget Function(String key, dynamic value) value;

  @override
  Widget build(BuildContext context) {
    if (columns.isEmpty) return const SizedBox.shrink();
    final head = columns.first;
    final rest = columns.skip(1).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _K.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            row[head] == null ? '' : '${row[head]}',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _K.slate900),
          ),
          if (rest.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final c in rest)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(_label(c), style: const TextStyle(fontSize: 11.5, height: 1.5, color: _K.slate500)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Align(alignment: Alignment.centerLeft, child: value(c, row[c]))),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.cards, required this.onChanged});

  final bool cards;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(bool value, IconData icon, String tip) {
      final selected = cards == value;
      return Tooltip(
        message: tip,
        child: Semantics(
          button: true,
          selected: selected,
          label: tip,
          child: Material(
            color: selected ? Colors.white : Colors.transparent,
            elevation: selected ? 1 : 0,
            shadowColor: const Color(0x33000000),
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onChanged(value),
              child: SizedBox(
                width: 32,
                height: 28,
                child: Icon(icon, size: 16, color: selected ? _K.indigo600 : _K.slate500),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: _K.slate100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _K.slate200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          option(false, Icons.table_rows_outlined, 'Table view'),
          option(true, Icons.view_agenda_outlined, 'Card view'),
        ],
      ),
    );
  }
}

// ── Employee multi-select ───────────────────────────────────────────────────

class _EmployeePicker extends StatefulWidget {
  const _EmployeePicker({required this.employees, required this.selected});

  final List<Employee> employees;
  final List<int> selected;

  @override
  State<_EmployeePicker> createState() => _EmployeePickerState();
}

class _EmployeePickerState extends State<_EmployeePicker> {
  late final Set<int> _ids = {...widget.selected};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = widget.employees
        .where((e) => q.isEmpty || e.name.toLowerCase().contains(q) || e.employeeCode.toLowerCase().contains(q))
        .toList();
    final allShownSelected = shown.isNotEmpty && shown.every((e) => _ids.contains(e.id));
    final height = MediaQuery.sizeOf(context).height * 0.8;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Employees', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.slate900)),
                        Text(
                          _ids.isEmpty ? 'None selected means all employees' : '${_ids.length} selected',
                          style: _T.subtitle,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: _K.indigo600),
                    onPressed: _ids.isEmpty ? null : () => setState(_ids.clear),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 14),
                decoration: _inputDecoration(icon: Icons.search_rounded).copyWith(
                  hintText: 'Search name or code',
                  hintStyle: const TextStyle(fontSize: 14, color: _K.slate400),
                ),
              ),
            ),
            if (shown.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 16, 0),
                child: CheckboxListTile(
                  value: allShownSelected,
                  dense: true,
                  activeColor: _K.indigo600,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    q.isEmpty ? 'Select all (${shown.length})' : 'Select all matches (${shown.length})',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.slate700),
                  ),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _ids.addAll(shown.map((e) => e.id));
                    } else {
                      _ids.removeAll(shown.map((e) => e.id));
                    }
                  }),
                ),
              ),
            _divider,
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('No matching employees.', style: _T.subtitle))
                  : ListView.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, __) => const Padding(padding: EdgeInsets.only(left: 64), child: _divider),
                      itemBuilder: (_, i) {
                        final e = shown[i];
                        final sub = [e.employeeCode, e.departmentName, e.branchName]
                            .whereType<String>()
                            .where((s) => s.isNotEmpty)
                            .join(', ');
                        return CheckboxListTile(
                          value: _ids.contains(e.id),
                          dense: true,
                          activeColor: _K.indigo600,
                          secondary: Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(color: _K.indigo50, shape: BoxShape.circle),
                            child: Text(_initials(e.name),
                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _K.indigo600)),
                          ),
                          title: Text(e.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          subtitle: Text(sub, style: const TextStyle(fontSize: 11.5, color: _K.slate500)),
                          onChanged: (v) => setState(() => v == true ? _ids.add(e.id) : _ids.remove(e.id)),
                        );
                      },
                    ),
            ),
            Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.slate100))),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _K.slate600,
                            side: const BorderSide(color: _K.slate200),
                            minimumSize: const Size.fromHeight(42),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _K.indigo600,
                            minimumSize: const Size.fromHeight(42),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          onPressed: () => Navigator.of(context).pop(_ids.toList()),
                          child: Text(_ids.isEmpty ? 'Use all employees' : 'Apply (${_ids.length})'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small pieces ────────────────────────────────────────────────────────────

InputDecoration _inputDecoration({IconData? icon}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    prefixIcon: icon == null ? null : Icon(icon, size: 16, color: _K.slate400),
    prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 20),
    suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 20),
    filled: true,
    fillColor: _K.slate50,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: border(_K.slate200),
    enabledBorder: border(_K.slate200),
    focusedBorder: border(_K.indigo500, 1.5),
  );
}

/// Filters in 1 column on phones, 2 on small tablets, 3–4 on wide screens.
class _FilterGrid extends StatelessWidget {
  const _FilterGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 1100 ? (children.length > 6 ? 6 : children.length) : (w >= 860 ? 3 : (w >= 480 ? 2 : 1));
        const gap = 12.0;
        final itemW = ((w - gap * (cols - 1)) / cols).floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [for (final c in children) SizedBox(width: itemW, child: c)],
        );
      },
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(label, style: _T.label)),
        child,
      ],
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({required this.value, required this.options, required this.onChanged});

  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = options.any((o) => o.$1 == value) ? value : options.first.$1;
    return DropdownButtonFormField<String>(
      key: ValueKey('${options.length}:$current'),
      value: current,
      isExpanded: true,
      isDense: true,
      borderRadius: BorderRadius.circular(10),
      icon: const Icon(Icons.expand_more_rounded, size: 18, color: _K.slate400),
      decoration: _inputDecoration(),
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _K.slate800),
      items: [
        for (final (v, label) in options)
          DropdownMenuItem(value: v, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({required this.category, required this.count, required this.selected, required this.onTap});

  final _Category category;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? _K.indigo600 : _K.slate500;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: selected ? _K.indigo600 : Colors.transparent, width: 2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(category.icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(category.label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: fg)),
              const SizedBox(width: 6),
              Text('$count', style: TextStyle(fontSize: 11, color: selected ? _K.indigo500 : _K.slate400, fontFeatures: _T.tabular)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportChip extends StatelessWidget {
  const _ReportChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(side: BorderSide(color: selected ? _K.slate900 : _K.slate200));
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? _K.slate900 : Colors.white,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? Colors.white : _K.slate700),
            ),
          ),
        ),
      ),
    );
  }
}

class _PunchTag extends StatelessWidget {
  const _PunchTag({required this.time, required this.isOut});

  final String time;
  final bool isOut;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border, dot) = isOut
        ? (_K.amber50, _K.amber700, _K.amber200, _K.amber500)
        : (_K.emerald50, _K.emerald700, _K.emerald200, _K.emerald500);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(time, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg, fontFeatures: _T.tabular)),
          const SizedBox(width: 3),
          Text(isOut ? 'Out' : 'In', style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.8))),
        ],
      ),
    );
  }
}

/// White card with a hairline border.
class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.padding = const EdgeInsets.all(16), this.clip = false});

  final Widget child;
  final EdgeInsets padding;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: _K.slate200),
        boxShadow: const [BoxShadow(color: Color(0x08101828), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: child,
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, this.size = 32});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _K.indigo50,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: _K.indigo100),
      ),
      child: Icon(icon, size: size * 0.5, color: _K.indigo600),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: _K.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _K.slate200),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: _K.slate100, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: _K.slate400),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _K.slate700),
          ),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, height: 1.4, color: _K.slate500),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.tone,
    required this.icon,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  /// (bg, border, fg)
  final (Color, Color, Color) tone;
  final IconData icon;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg) = tone;
    final hasAction = actionLabel != null && onAction != null;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(12, 10, hasAction ? 4 : 12, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(fontSize: 13, height: 1.4, color: fg),
                child: child,
              ),
            ),
            if (hasAction)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: fg,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.indigo600)),
        ),
      ),
    );
  }
}