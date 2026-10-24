// Port of features/admin/violations/ViolationsPage.tsx: punch anomalies by
// the attendance day they happened on, with date range, search, type filter
// (with counts) and Excel export. Tapping a violation opens that employee.
//
// Wide screens get a table with column headers; on phones violations are
// compact rows grouped under their day.
//
// Layout (compact):
//   Header: title · how-to-fix toggle · refresh · export
//   [how to fix] [load-error banner]
//   Filters: period (+ quick ranges) · search
//   Violations card: type chips with counts · table / grouped rows · pagination

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hrm_app/components/ui/pagination_bar.dart';
import 'package:hrm_app/services/violation_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';
import 'package:hrm_app/utils/toast.dart';

const _pageSize = 20;

// ── Design tokens ───────────────────────────────────────────────────────────

class _K {
  static const gray50 = Color(0xFFF9FAFB);
  static const gray100 = Color(0xFFF3F4F6);
  static const gray200 = Color(0xFFE5E7EB);
  static const gray300 = Color(0xFFD1D5DB);
  static const gray400 = Color(0xFF9CA3AF);
  static const gray500 = Color(0xFF6B7280);
  static const gray600 = Color(0xFF4B5563);
  static const gray700 = Color(0xFF374151);
  static const gray900 = Color(0xFF111827);
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo200 = Color(0xFFC7D2FE);
  static const indigo400 = Color(0xFF818CF8);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const indigo800 = Color(0xFF3730A3);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald600 = Color(0xFF059669);
  static const red50 = Color(0xFFFEF2F2);
  static const red100 = Color(0xFFFEE2E2);
  static const red200 = Color(0xFFFECACA);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);
}

/// A tinted color set: soft background, border, and foreground.
class _Tone {
  const _Tone(this.bg, this.border, this.fg);

  final Color bg;
  final Color border;
  final Color fg;
}

const _red = _Tone(_K.red50, _K.red100, _K.red600);

/// Severity colours per type (unknown types are neutral).
StatusStyle _typeStyle(String type) => switch (type) {
      'MISSING_OUT' => StatusStyle.red,
      'PUNCH_OUTSIDE_WINDOW' => const StatusStyle(Color(0xFFFFF7ED), Color(0xFFC2410C), Color(0xFFFED7AA)),
      'DOUBLE_IN' || 'DOUBLE_OUT' || 'OUT_BEFORE_IN' => StatusStyle.amber,
      'LAST_IN_AS_OUT' || 'MISSED_BREAK_PUNCH' => StatusStyle.sky,
      _ => StatusStyle.gray,
    };

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3, color: _K.gray900);
  static const subtitle = TextStyle(fontSize: 12, height: 1.3, color: _K.gray500);
  static const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _K.gray500);
  static const columnHead = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.gray500);
}

const _cardRadius = 16.0;
const _divider = Divider(height: 1, thickness: 1, color: _K.gray100);

DateTime _daysAgo(int n) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - n);
}

String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

String _dayText(String raw) {
  final d = parseDateOnly(raw);
  return d != null ? '${formatEEE(d)}, ${formatDDMMMYYYY(d)}' : raw;
}

/// Quick date ranges for the filter menu.
enum _Preset {
  today('Today'),
  yesterday('Yesterday'),
  last7('Last 7 days'),
  thisMonth('This month'),
  last30('Last 30 days');

  const _Preset(this.label);
  final String label;

  DateTimeRange get range {
    final t = _daysAgo(0);
    return switch (this) {
      _Preset.today => DateTimeRange(start: t, end: t),
      _Preset.yesterday => DateTimeRange(start: _daysAgo(1), end: _daysAgo(1)),
      _Preset.last7 => DateTimeRange(start: _daysAgo(6), end: t),
      _Preset.thisMonth => DateTimeRange(start: DateTime(t.year, t.month, 1), end: t),
      _Preset.last30 => DateTimeRange(start: _daysAgo(29), end: t),
    };
  }
}

// ── Page ────────────────────────────────────────────────────────────────────

class ViolationsPage extends StatefulWidget {
  const ViolationsPage({super.key});

  @override
  State<ViolationsPage> createState() => _ViolationsPageState();
}

class _ViolationsPageState extends State<ViolationsPage> {
  DateTime _start = _daysAgo(6);
  DateTime _end = _daysAgo(0);
  String _type = '';
  String _query = '';
  int _page = 1;
  ViolationList? _data;
  bool _loading = true;
  bool _exporting = false;
  bool _showHelp = false;
  String? _error;
  Timer? _debounce;
  int _loadId = 0;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await violationService.list(
        startDate: toDateKey(_start),
        endDate: toDateKey(_end),
        violationType: _type,
        q: _query,
        page: _page,
        pageSize: _pageSize,
      );
      if (mounted && id == _loadId) setState(() => _data = data);
    } catch (err) {
      if (mounted && id == _loadId) setState(() => _error = apiError(err, 'Could not load violations.'));
    } finally {
      if (mounted && id == _loadId) setState(() => _loading = false);
    }
  }

  void _filter(VoidCallback change) {
    setState(() {
      change();
      _page = 1;
    });
    _load();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = value.trim();
      if (q != _query) _filter(() => _query = q);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    if (_query.isNotEmpty) _filter(() => _query = '');
  }

  void _clearFilters() {
    _debounce?.cancel();
    _searchCtrl.clear();
    _filter(() {
      _query = '';
      _type = '';
    });
  }

  Future<void> _pickRange() async {
    final today = _daysAgo(0);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: DateTimeRange(
        start: _start.isAfter(today) ? today : _start,
        end: _end.isAfter(today) ? today : _end,
      ),
    );
    if (picked != null) {
      _filter(() {
        _start = picked.start;
        _end = picked.end;
      });
    }
  }

  _Preset? get _activePreset {
    for (final p in _Preset.values) {
      final r = p.range;
      if (r.start == _start && r.end == _end) return p;
    }
    return null;
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      await violationService.exportXlsx(
        startDate: toDateKey(_start),
        endDate: toDateKey(_end),
        violationType: _type,
        q: _query,
      );
    } catch (_) {
      if (mounted) showToast(context, 'Export failed. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String get _periodText => _start == _end
      ? formatDDMMMYYYY(_start)
      : '${formatDDMMMYYYY(_start)} – ${formatDDMMMYYYY(_end)}';

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null && _error == null) return const _PageSkeleton();

    return RefreshIndicator(
      color: _K.indigo600,
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sm = width >= 640;
          final lg = width >= 1024;
          final gap = sm ? 20.0 : 16.0;

          final sections = <Widget>[
            _header(wide: sm),
            if (_showHelp)
              const _Banner(
                tone: _Tone(_K.indigo50, _K.indigo200, _K.indigo800),
                icon: Icons.build_circle_outlined,
                child: Text(
                  'Violations are listed by the attendance day they happened on. To fix one, open the employee '
                  '(tap the row) or go to the Attendance page and add the missing punch for that day.',
                ),
              ),
            if (_error != null)
              _Banner(
                tone: const _Tone(_K.red50, _K.red200, _K.red700),
                icon: Icons.error_outline_rounded,
                actionLabel: 'Retry',
                onAction: _load,
                child: Text(_error!),
              ),
            _filterBar(sm: sm),
            _violationsCard(wide: lg),
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
                        if (i > 0) SizedBox(height: gap),
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
    final export = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: _K.indigo600,
        disabledBackgroundColor: _K.indigo200,
        disabledForegroundColor: Colors.white,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      onPressed: _exporting ? null : _export,
      icon: _exporting
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.file_download_outlined, size: 18),
      label: Text(_exporting ? 'Exporting…' : 'Export Excel'),
    );

    final refresh = IconButton(
      tooltip: 'Refresh',
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        side: const BorderSide(color: _K.gray200),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: _loading ? null : _load,
      icon: _loading
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.refresh_rounded, size: 18, color: _K.gray600),
    );

    final title = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _IconBox(icon: Icons.gpp_maybe_outlined, tone: _red, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Violations',
                  style: TextStyle(
                    fontSize: wide ? 22 : 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.25,
                    color: _K.gray900,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Punch anomalies by attendance day.', style: _T.subtitle),
                  _LinkButton(
                    label: _showHelp ? 'Hide' : 'How to fix one',
                    onTap: () => setState(() => _showHelp = !_showHelp),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    if (wide) {
      return Row(
        children: [Expanded(child: title), const SizedBox(width: 12), refresh, const SizedBox(width: 8), export],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        const SizedBox(height: 12),
        Row(children: [refresh, const SizedBox(width: 8), Expanded(child: export)]),
      ],
    );
  }

  // ── Filters ──

  Widget _filterBar({required bool sm}) {
    final preset = _activePreset;

    final range = Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'Period, $_periodText',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _pickRange,
              child: InputDecorator(
                decoration: _inputDecoration(icon: Icons.date_range_outlined),
                child: Text(
                  _periodText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: _K.gray900, fontFeatures: _T.tabular),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<_Preset>(
          tooltip: 'Quick ranges',
          position: PopupMenuPosition.under,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onSelected: (p) => _filter(() {
            _start = p.range.start;
            _end = p.range.end;
          }),
          itemBuilder: (_) => [
            for (final p in _Preset.values)
              PopupMenuItem(
                value: p,
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: p == preset ? const Icon(Icons.check_rounded, size: 16, color: _K.indigo600) : null,
                    ),
                    const SizedBox(width: 6),
                    Text(p.label, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
          ],
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _K.gray200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  preset?.label ?? 'Custom',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _K.gray700),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.expand_more_rounded, size: 16, color: _K.gray400),
              ],
            ),
          ),
        ),
      ],
    );

    final search = ValueListenableBuilder<TextEditingValue>(
      valueListenable: _searchCtrl,
      builder: (context, value, _) => TextField(
        controller: _searchCtrl,
        onChanged: _onSearch,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14, color: _K.gray900),
        decoration: _inputDecoration(
          hint: 'Search employee name or code',
          icon: Icons.search_rounded,
          suffix: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                  onPressed: _clearSearch,
                  icon: const Icon(Icons.close_rounded, size: 16, color: _K.gray400),
                ),
        ),
      ),
    );

    return _Surface(
      padding: const EdgeInsets.all(14),
      child: sm
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(flex: 5, child: _LabeledField(label: 'Period', child: range)),
                const SizedBox(width: 12),
                Expanded(flex: 4, child: _LabeledField(label: 'Employee', child: search)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LabeledField(label: 'Period', child: range),
                const SizedBox(height: 12),
                search,
              ],
            ),
    );
  }

  // ── Violations ──

  Widget _violationsCard({required bool wide}) {
    final data = _data;
    final chips = (data?.byType ?? const <ViolationTypeCount>[]).where((t) => t.count > 0).toList();
    final rows = data?.results ?? const <Violation>[];
    final count = data?.count ?? 0;
    final total = data?.total ?? 0;
    final filtered = _type.isNotEmpty || _query.isNotEmpty;

    // Keep the selected type visible even if its count dropped to zero.
    final selectedMissing = _type.isNotEmpty && !chips.any((t) => t.violationType == _type);

    final body = <Widget>[];
    if (rows.isEmpty) {
      body.add(
        Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Loading violations…', textAlign: TextAlign.center, style: _T.subtitle),
                )
              : filtered
                  ? _EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No matching violations',
                      message: 'Nothing matches these filters in $_periodText.',
                      action: _LinkButton(label: 'Clear filters', onTap: _clearFilters),
                    )
                  : _EmptyState(
                      icon: Icons.verified_outlined,
                      success: true,
                      title: 'No violations in this period',
                      message: 'All punches between ${formatDDMMMYYYY(_start)} and ${formatDDMMMYYYY(_end)} look clean.',
                    ),
        ),
      );
    } else if (wide) {
      for (var i = 0; i < rows.length; i++) {
        if (i > 0) body.add(_divider);
        body.add(_ViolationRow(violation: rows[i], wide: true, onTap: () => _open(rows[i])));
      }
    } else {
      // Phones: group under the attendance day.
      String? day;
      for (final v in rows) {
        if (v.date != day) {
          day = v.date;
          final n = rows.where((r) => r.date == day).length;
          body.add(_DayLabel(text: _dayText(v.date), count: n));
        } else {
          body.add(const Padding(padding: EdgeInsets.only(left: 58), child: _divider));
        }
        body.add(_ViolationRow(violation: v, wide: false, onTap: () => _open(v)));
      }
    }

    return _Surface(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CardHeader(
                  icon: Icons.list_alt_rounded,
                  tone: _red,
                  title: 'Violations',
                  subtitle: _type.isEmpty && _query.isEmpty
                      ? '$total in $_periodText'
                      : '$count of $total in $_periodText',
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _TypeChip(
                        label: 'All',
                        count: total,
                        style: null,
                        selected: _type.isEmpty,
                        onTap: () {
                          if (_type.isNotEmpty) _filter(() => _type = '');
                        },
                      ),
                      for (final t in chips) ...[
                        const SizedBox(width: 6),
                        _TypeChip(
                          label: t.label,
                          count: t.count,
                          style: _typeStyle(t.violationType),
                          selected: _type == t.violationType,
                          onTap: () => _filter(() => _type = _type == t.violationType ? '' : t.violationType),
                        ),
                      ],
                      if (selectedMissing) ...[
                        const SizedBox(width: 6),
                        _TypeChip(
                          label: _type.replaceAll('_', ' ').toLowerCase(),
                          count: 0,
                          style: _typeStyle(_type),
                          selected: true,
                          onTap: () => _filter(() => _type = ''),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 2,
            child: _loading
                ? const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50)
                : const ColoredBox(color: _K.gray100),
          ),
          if (wide && rows.isNotEmpty)
            Container(
              color: _K.gray50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: _tableRow(
                date: const Text('Day', style: _T.columnHead),
                time: const Text('Time', style: _T.columnHead),
                employee: const Text('Employee', style: _T.columnHead),
                type: const Text('Type', style: _T.columnHead),
                details: const Text('Details', style: _T.columnHead),
                trailing: const SizedBox.shrink(),
              ),
            ),
          AnimatedOpacity(
            opacity: _loading && rows.isNotEmpty ? 0.55 : 1,
            duration: const Duration(milliseconds: 150),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
          ),
          if (count > _pageSize)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.gray100))),
              child: PaginationBar(
                page: _page,
                total: count,
                pageSize: _pageSize,
                onPage: (p) {
                  setState(() => _page = p);
                  _load();
                },
              ),
            ),
        ],
      ),
    );
  }

  void _open(Violation v) => context.go('/admin/employees/${v.employeeId}');
}

// ── One violation ───────────────────────────────────────────────────────────

Widget _tableRow({
  required Widget date,
  required Widget time,
  required Widget employee,
  required Widget type,
  required Widget details,
  required Widget trailing,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(flex: 3, child: date),
      const SizedBox(width: 12),
      Expanded(flex: 2, child: time),
      const SizedBox(width: 12),
      Expanded(flex: 4, child: employee),
      const SizedBox(width: 12),
      Expanded(flex: 3, child: type),
      const SizedBox(width: 12),
      Expanded(flex: 6, child: details),
      SizedBox(width: 28, child: trailing),
    ],
  );
}

class _ViolationRow extends StatelessWidget {
  const _ViolationRow({required this.violation, required this.wide, required this.onTap});

  final Violation violation;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v = violation;
    final style = _typeStyle(v.violationType);
    final label = v.violationLabel.isNotEmpty ? v.violationLabel : v.violationType;
    final time = v.occurredAt != null ? fmtWallTime(v.occurredAt) : '—';

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: style.border),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: style.fg)),
    );

    final avatar = Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: _K.gray100, shape: BoxShape.circle),
      child: Text(
        _initials(v.employeeName),
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _K.gray600),
      ),
    );

    final who = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(v.employeeName, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray900)),
        Text(
          [v.employeeCode, if (v.branchName.isNotEmpty) v.branchName].join(', '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: _K.gray500, fontFeatures: _T.tabular),
        ),
      ],
    );

    final row = wide
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _tableRow(
              date: Text(_dayText(v.date),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray900)),
              time: Text(time, style: const TextStyle(fontSize: 13, color: _K.gray600, fontFeatures: _T.tabular)),
              employee: Row(children: [avatar, const SizedBox(width: 10), Expanded(child: who)]),
              type: Align(alignment: Alignment.centerLeft, child: badge),
              details: Text(v.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.4, color: _K.gray600)),
              trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: _K.gray300),
            ),
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: who),
                          const SizedBox(width: 8),
                          Text(time, style: const TextStyle(fontSize: 12, color: _K.gray500, fontFeatures: _T.tabular)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(alignment: Alignment.centerLeft, child: badge),
                      if (v.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(v.description, maxLines: 3, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, height: 1.4, color: _K.gray600)),
                      ],
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 6, left: 2),
                  child: Icon(Icons.chevron_right_rounded, size: 18, color: _K.gray300),
                ),
              ],
            ),
          );

    return Semantics(
      button: true,
      label: '$label, ${v.employeeName}, ${_dayText(v.date)}${v.occurredAt != null ? ' at $time' : ''}',
      hint: "Opens this employee's attendance",
      child: Material(
        color: Colors.white,
        child: InkWell(onTap: onTap, child: row),
      ),
    );
  }
}

class _DayLabel extends StatelessWidget {
  const _DayLabel({required this.text, required this.count});

  final String text;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _K.gray50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _K.gray600)),
            ),
          ),
          Text('$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.gray400, fontFeatures: _T.tabular)),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.count,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;

  /// Null = the neutral "All" chip.
  final StatusStyle? style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = style;
    final (bg, fg, border) = s == null
        ? (selected ? _K.gray900 : Colors.white, selected ? Colors.white : _K.gray600, selected ? _K.gray900 : _K.gray200)
        : (selected ? s.bg : Colors.white, s.fg, selected ? s.border : _K.gray200);
    final shape = StadiumBorder(
      side: BorderSide(color: s != null && selected ? _K.indigo400 : border, width: s != null && selected ? 1.5 : 1),
    );

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: bg,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s != null) ...[
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: s.fg, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                ],
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: s == null ? fg : _K.gray700)),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: s == null ? (selected ? Colors.white70 : _K.gray400) : fg,
                    fontFeatures: _T.tabular,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Loading skeleton ────────────────────────────────────────────────────────

class _PageSkeleton extends StatelessWidget {
  const _PageSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading violations',
      child: Column(
        children: [
          const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final sm = c.maxWidth >= 640;
                return ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.all(sm ? 24 : 16),
                  children: const [
                    _Bone(height: 48),
                    SizedBox(height: 20),
                    _Bone(height: 80),
                    SizedBox(height: 16),
                    _Bone(height: 420),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Bone extends StatelessWidget {
  const _Bone({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(color: _K.gray100, borderRadius: BorderRadius.circular(_cardRadius)),
    );
  }
}

// ── Small shared pieces ─────────────────────────────────────────────────────

InputDecoration _inputDecoration({String? hint, IconData? icon, Widget? suffix}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 14, color: _K.gray400),
    prefixIcon: icon == null ? null : Icon(icon, size: 16, color: _K.gray500),
    prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 20),
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 20),
    filled: true,
    fillColor: _K.gray50,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: border(_K.gray200),
    enabledBorder: border(_K.gray200),
    focusedBorder: border(_K.indigo500, 1.5),
  );
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [Text(label, style: _T.label), const SizedBox(height: 6), child],
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
        border: Border.all(color: _K.gray100),
        boxShadow: const [BoxShadow(color: Color(0x08101828), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: child,
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.icon, required this.tone, required this.title, this.subtitle});

  final IconData icon;
  final _Tone tone;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _IconBox(icon: icon, tone: tone, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.title),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 1),
                Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _K.gray500, fontFeatures: _T.tabular)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, required this.tone, this.size = 32});

  final IconData icon;
  final _Tone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: tone.border),
      ),
      child: Icon(icon, size: size * 0.5, color: tone.fg),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.success = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: success ? _K.emerald50.withValues(alpha: 0.5) : _K.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: success ? _K.emerald200 : _K.gray200),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: success ? _K.emerald100 : _K.gray100, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: success ? _K.emerald600 : _K.gray400),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _K.gray700),
          ),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, height: 1.4, color: _K.gray500),
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

  final _Tone tone;
  final IconData icon;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final hasAction = actionLabel != null && onAction != null;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(12, 10, hasAction ? 4 : 12, 10),
        decoration: BoxDecoration(
          color: tone.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tone.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: tone.fg)),
            const SizedBox(width: 10),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(fontSize: 13, height: 1.45, color: tone.fg),
                child: child,
              ),
            ),
            if (hasAction)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: tone.fg,
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
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.indigo600)),
        ),
      ),
    );
  }
}