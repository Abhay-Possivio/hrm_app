// Port of features/admin/attendance/AttendancePage.tsx ("Attendance
// Records") with RealtimePunches.tsx and the "Manage Attendance Punches"
// dialog (add a manual punch, delete a punch).
//
// Wide screens get a table with column headers; on phones each record is a
// compact card. Tap any record to manage its punches.
//
// Compact layout:
//   Header (one line)
//   [error banner] [missing clock-out banner → Review]
//   Live punches | Stat cards (tap to filter)
//   Filter bar (one row on tablets): Day/Range · ‹ date › · search · status
//     active filter chips · Clear all
//   Records: table (wide) / two-line rows (phones) + pagination

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hrm_app/components/ui/pagination_bar.dart';
import 'package:hrm_app/services/attendadmin_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';
import 'package:hrm_app/utils/toast.dart';

const _pageSize = 10;

const _statusOptions = [
  ('ALL', 'All statuses'),
  ('PRESENT', 'Present (any)'),
  ('FULL_DAY', 'Full day'),
  ('HALF_DAY', 'Half day'),
  ('LATE', 'Late in (morning)'),
  ('LATE_AFTER_LUNCH', 'Late after lunch'),
  ('ABSENT', 'Absent'),
  ('IN_PROGRESS', 'Working now'),
  ('STEPPED_OUT', 'Out now'),
  ('MISSING_OUT', 'Missing clock-out'),
  ('ON_LEAVE', 'On leave'),
  ('OFF_DAY', 'Off day / holiday'),
];

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
  static const gray800 = Color(0xFF1F2937);
  static const gray900 = Color(0xFF111827);
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo200 = Color(0xFFC7D2FE);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber200 = Color(0xFFFDE68A);
  static const amber600 = Color(0xFFD97706);
  static const amber800 = Color(0xFF92400E);
  static const orange50 = Color(0xFFFFF7ED);
  static const orange200 = Color(0xFFFED7AA);
  static const orange600 = Color(0xFFEA580C);
  static const red50 = Color(0xFFFEF2F2);
  static const red200 = Color(0xFFFECACA);
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);
  static const yellow50 = Color(0xFFFEFCE8);
  static const yellow200 = Color(0xFFFEF08A);
  static const yellow600 = Color(0xFFCA8A04);
}

/// A tinted color set: soft background, border, and foreground.
class _Tone {
  const _Tone(this.bg, this.border, this.fg);

  final Color bg;
  final Color border;
  final Color fg;
}

const _indigo = _Tone(_K.indigo50, _K.indigo200, _K.indigo600);
const _emerald = _Tone(_K.emerald50, _K.emerald200, _K.emerald600);
const _amber = _Tone(_K.amber50, _K.amber200, _K.amber600);
const _yellow = _Tone(_K.yellow50, _K.yellow200, _K.yellow600);
const _red = _Tone(_K.red50, _K.red200, _K.red600);
const _orange = _Tone(_K.orange50, _K.orange200, _K.orange600);
const _gray = _Tone(_K.gray100, _K.gray200, _K.gray500);

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.3, color: _K.gray900);
  static const subtitle = TextStyle(fontSize: 11.5, height: 1.3, color: _K.gray500);
  static const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _K.gray500);
  static const caption = TextStyle(fontSize: 11, height: 1.3, color: _K.gray400);
  static const cell = TextStyle(fontSize: 13, color: _K.gray900, fontFeatures: tabular);
  static const columnHead = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.gray500);
}

const _cardRadius = 14.0;
const _divider = Divider(height: 1, thickness: 1, color: _K.gray100);

// ── Helpers ─────────────────────────────────────────────────────────────────

/// "7h 5m" (the web table's format).
String _hm(int minutes) => '${minutes ~/ 60}h ${minutes % 60}m';

/// "09:05:30 AM" from a wall-clock timestamp.
String _wallTimeSeconds(String ts) {
  final m = RegExp(r'T(\d{2}):(\d{2})(?::(\d{2}))?').firstMatch(ts);
  if (m == null) return fmtWallTime(ts);
  final h = int.parse(m.group(1)!);
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '${h12.toString().padLeft(2, '0')}:${m.group(2)}:${m.group(3) ?? '00'} ${h >= 12 ? 'PM' : 'AM'}';
}

/// "FINGERPRINT" → "Fingerprint".
String _sentenceCase(String s) {
  final t = s.replaceAll('_', ' ').trim().toLowerCase();
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

String _statusLabel(String value) => _statusOptions.firstWhere((o) => o.$1 == value, orElse: () => (value, value)).$2;

// Table column flex values: employee, branch, first in, last out, worked,
// late in, late after lunch, status.
const _colFlex = [3, 2, 2, 2, 2, 2, 2, 2];

Widget _tableRow(List<Widget> cells, {required Widget trailing}) {
  return Row(
    children: [
      for (var i = 0; i < cells.length; i++) ...[
        if (i > 0) const SizedBox(width: 12),
        Expanded(flex: _colFlex[i], child: cells[i]),
      ],
      const SizedBox(width: 8),
      SizedBox(width: 36, child: trailing),
    ],
  );
}

// ── Page ────────────────────────────────────────────────────────────────────

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  List<AttendanceSummary> _records = const [];
  AttendanceStats _stats = const AttendanceStats();
  int _total = 0;
  int _page = 1;
  bool _loading = true;
  bool _firstLoadDone = false;
  String? _error;
  int _loadId = 0;

  bool _rangeMode = false;
  DateTime _date = _today();
  DateTime _start = _today();
  DateTime _end = _today();
  String _query = '';
  String _status = 'ALL';
  Timer? _debounce;
  final _searchCtrl = TextEditingController();

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool get _hasFilters => _status != 'ALL' || _query.isNotEmpty;

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
      final res = await attendanceAdminService.fetchSummaries(
        page: _page,
        date: _rangeMode ? null : toDateKey(_date),
        startDate: _rangeMode ? toDateKey(_start) : null,
        endDate: _rangeMode ? toDateKey(_end) : null,
        status: _status == 'ALL' ? null : _status,
        q: _query,
      );
      if (!mounted || id != _loadId) return;
      setState(() {
        _records = res.results;
        _total = res.count;
        if (res.stats != null) _stats = res.stats!;
      });
    } catch (_) {
      if (mounted && id == _loadId) {
        setState(() => _error = 'Could not load attendance records. Check your connection and retry.');
      }
    } finally {
      if (mounted && id == _loadId) {
        setState(() {
          _loading = false;
          _firstLoadDone = true;
        });
      }
    }
  }

  /// Applies a filter change and goes back to page 1.
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
      _status = 'ALL';
      _query = '';
    });
  }

  /// Tapping a stat card filters by it; tapping it again clears the filter.
  void _toggleStatus(String s) => _filter(() => _status = (_status == s) ? 'ALL' : s);

  void _shiftDay(int delta) => _filter(() => _date = DateTime(_date.year, _date.month, _date.day + delta));

  Future<void> _pickSingle() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) _filter(() => _date = d);
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _start, end: _end),
    );
    if (r != null) {
      _filter(() {
        _start = r.start;
        _end = r.end;
      });
    }
  }

  Future<void> _openLogs(AttendanceSummary record) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => _ManagePunchesDialog(record: record));
    if (changed == true) _load();
  }

  String get _periodLabel => _rangeMode
      ? '${formatDDMMMYYYY(_start)} – ${formatDDMMMYYYY(_end)}'
      : formatDDMMMYYYY(_date);

  @override
  Widget build(BuildContext context) {
    if (!_firstLoadDone) return const _PageSkeleton();

    return RefreshIndicator(
      color: _K.indigo600,
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sm = width >= 640;
          final md = width >= 768;
          final lg = width >= 1024;
          final gap = sm ? 14.0 : 12.0;

          final sections = <Widget>[
            _PageHeader(wide: sm),
            if (_error != null)
              _Banner(
                tone: const _Tone(_K.red50, _K.red200, _K.red700),
                icon: Icons.error_outline_rounded,
                actionLabel: 'Retry',
                onAction: _load,
                child: Text(_error!),
              ),
            if (_stats.missingOut > 0 && _status != 'MISSING_OUT')
              _Banner(
                tone: const _Tone(_K.amber50, _K.amber200, _K.amber800),
                icon: Icons.warning_amber_rounded,
                actionLabel: 'Review',
                onAction: () => _filter(() => _status = 'MISSING_OUT'),
                child: Tooltip(
                  message: 'They clocked in but did not clock out before the overtime window closed.',
                  child: Text(
                    '${_stats.missingOut} employee${_stats.missingOut == 1 ? ' has' : 's have'} a missing clock-out.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            if (lg)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(child: _RealtimePunches()),
                  SizedBox(width: gap),
                  Expanded(child: _statsGrid(2)),
                ],
              )
            else ...[
              _statsGrid(md ? 4 : 2),
              const _RealtimePunches(),
            ],
            _filterBar(md: md),
            _recordsCard(wide: lg),
          ];

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(sm ? 20 : 12),
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

  Widget _statsGrid(int columns) {
    return _Grid(
      columns: columns,
      gap: 10,
      children: [
        _StatCard(
          label: 'Employees',
          value: _stats.total,
          icon: Icons.groups_outlined,
          tone: _indigo,
          onTap: _status == 'ALL' ? null : () => _filter(() => _status = 'ALL'),
        ),
        _StatCard(
          label: 'Present',
          value: _stats.present,
          icon: Icons.check_circle_outline_rounded,
          tone: _emerald,
          selected: _status == 'PRESENT',
          onTap: () => _toggleStatus('PRESENT'),
        ),
        _StatCard(
          label: 'Absent',
          value: _stats.absent,
          icon: Icons.cancel_outlined,
          tone: _red,
          selected: _status == 'ABSENT',
          onTap: () => _toggleStatus('ABSENT'),
        ),
        _StatCard(
          label: 'Late arrivals',
          value: _stats.late,
          icon: Icons.schedule_rounded,
          tone: _yellow,
          selected: _status == 'LATE',
          onTap: () => _toggleStatus('LATE'),
        ),
      ],
    );
  }

  // ── Filters ──

  Widget _filterBar({required bool md}) {
    final isToday = _date == _today();

    final mode = _Segmented<bool>(
      value: _rangeMode,
      height: 40,
      options: const [
        (false, 'Day', Icons.today_outlined),
        (true, 'Range', Icons.date_range_outlined),
      ],
      onChanged: (v) {
        if (v != _rangeMode) _filter(() => _rangeMode = v);
      },
    );

    final date = _rangeMode
        ? _DateButton(
            text: _periodLabel,
            icon: Icons.date_range_outlined,
            semanticLabel: 'Date range, $_periodLabel',
            onTap: _pickRange,
          )
        : SizedBox(
            height: 40,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _NavButton(icon: Icons.chevron_left_rounded, tooltip: 'Previous day', onTap: () => _shiftDay(-1)),
                const SizedBox(width: 4),
                Expanded(
                  child: _DateButton(
                    text: formatDDMMMYYYY(_date),
                    icon: Icons.calendar_today_outlined,
                    semanticLabel: 'Date, ${formatDDMMMYYYY(_date)}',
                    onTap: _pickSingle,
                    trailing: isToday
                        ? null
                        : _LinkButton(label: 'Today', onTap: () => _filter(() => _date = _today())),
                  ),
                ),
                const SizedBox(width: 4),
                _NavButton(icon: Icons.chevron_right_rounded, tooltip: 'Next day', onTap: () => _shiftDay(1)),
              ],
            ),
          );

    final search = Semantics(
      label: 'Search',
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _searchCtrl,
        builder: (context, value, _) => TextField(
          controller: _searchCtrl,
          onChanged: _onSearch,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 13, color: _K.gray900),
          decoration: _inputDecoration(
            hint: 'Name or code',
            icon: Icons.search_rounded,
            suffix: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: _clearSearch,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                    icon: const Icon(Icons.close_rounded, size: 16, color: _K.gray400),
                  ),
          ),
        ),
      ),
    );

    final status = Semantics(
      label: 'Status',
      child: DropdownButtonFormField<String>(
        key: ValueKey(_status),
        value: _status,
        isExpanded: true,
        isDense: true,
        borderRadius: BorderRadius.circular(10),
        icon: const Icon(Icons.expand_more_rounded, size: 18, color: _K.gray500),
        decoration: _inputDecoration(),
        items: [
          for (final (v, label) in _statusOptions)
            DropdownMenuItem(
              value: v,
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            ),
        ],
        onChanged: (v) {
          if (v != null && v != _status) _filter(() => _status = v);
        },
      ),
    );

    return _Surface(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (md)
            Row(
              children: [
                SizedBox(width: 170, child: mode),
                const SizedBox(width: 8),
                Expanded(flex: 3, child: date),
                const SizedBox(width: 8),
                Expanded(flex: 3, child: search),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: status),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(width: 132, child: mode),
                    const SizedBox(width: 8),
                    Expanded(child: date),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: 8),
                    Expanded(child: status),
                  ],
                ),
              ],
            ),
          if (_hasFilters) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Filtered by', style: _T.caption),
                if (_status != 'ALL')
                  _RemovableChip(label: _statusLabel(_status), onRemove: () => _filter(() => _status = 'ALL')),
                if (_query.isNotEmpty) _RemovableChip(label: '"$_query"', onRemove: _clearSearch),
                _LinkButton(label: 'Clear all', onTap: _clearFilters),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Records ──

  Widget _recordsCard({required bool wide}) {
    return _Surface(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: _CardHeader(
              icon: Icons.fact_check_outlined,
              tone: _indigo,
              title: 'Records',
              subtitle: '$_total, $_periodLabel',
              inline: true,
            ),
          ),
          SizedBox(
            height: 2,
            child: _loading
                ? const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50)
                : const ColoredBox(color: _K.gray100),
          ),
          if (wide && _records.isNotEmpty)
            Container(
              color: _K.gray50,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: _tableRow(
                const [
                  Text('Employee', style: _T.columnHead),
                  Text('Branch', style: _T.columnHead),
                  Text('First in', style: _T.columnHead),
                  Text('Last out', style: _T.columnHead),
                  Text('Worked', style: _T.columnHead),
                  Text('Late in', style: _T.columnHead),
                  Text('After lunch', style: _T.columnHead),
                  Text('Status', style: _T.columnHead),
                ],
                trailing: const SizedBox.shrink(),
              ),
            ),
          if (_records.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Loading records…', textAlign: TextAlign.center, style: _T.subtitle),
                    )
                  : _EmptyState(
                      icon: Icons.event_busy_outlined,
                      title: _hasFilters ? 'No records match these filters' : 'No attendance records for this period',
                      message: _hasFilters
                          ? 'Try another status or search term.'
                          : 'Pick another date, or switch to a date range.',
                      action: _hasFilters ? _LinkButton(label: 'Clear filters', onTap: _clearFilters) : null,
                    ),
            )
          else
            AnimatedOpacity(
              opacity: _loading ? 0.55 : 1,
              duration: const Duration(milliseconds: 150),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _records.length; i++) ...[
                    if (i > 0 || wide) _divider,
                    _RecordRow(
                      record: _records[i],
                      showDate: _rangeMode,
                      wide: wide,
                      onManage: () => _openLogs(_records[i]),
                    ),
                  ],
                ],
              ),
            ),
          if (_total > _pageSize)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.gray100))),
              child: PaginationBar(
                page: _page,
                total: _total,
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
}

// ── Header ──────────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _IconBox(icon: Icons.event_available_outlined, tone: _indigo, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Attendance records',
                  style: TextStyle(
                    fontSize: wide ? 19 : 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    height: 1.25,
                    color: _K.gray900,
                  ),
                ),
              ),
              const Text(
                'Daily attendance and work hours. Tap a record to manage its punches.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _T.subtitle,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Stat cards ──────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final int value;
  final IconData icon;
  final _Tone tone;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '$label: $value${onTap != null ? (selected ? ', filter on' : ', tap to filter') : ''}',
      excludeSemantics: true,
      child: _Surface(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        color: selected ? tone.bg : Colors.white,
        borderColor: selected ? tone.border : _K.gray100,
        child: Row(
          children: [
            _IconBox(icon: icon, tone: tone, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.label),
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      height: 1.2,
                      color: _K.gray900,
                      fontFeatures: _T.tabular,
                    ),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.filter_alt_rounded, size: 16, color: tone.fg),
          ],
        ),
      ),
    );
  }
}

// ── One attendance record ───────────────────────────────────────────────────

class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.record,
    required this.showDate,
    required this.wide,
    required this.onManage,
  });

  final AttendanceSummary record;
  final bool showDate;
  final bool wide;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final status = attendanceStatus(r.dayType, r.punchStatus, r.leaveName);
    final day = parseDateOnly(r.date);
    final dateText = showDate && day != null ? formatEEEDDMMM(day) : null;

    final badge = Tooltip(
      message: status.hint ?? '',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: status.style.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: status.style.border),
        ),
        child: Text(
          status.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: status.style.fg),
        ),
      ),
    );

    final lastOutColor = r.lastOut != null
        ? _K.gray900
        : r.punchStatus == 'MISSING_OUT'
            ? _K.red600
            : _K.gray400;
    final lastOut = Tooltip(
      message: r.lastPunch != null ? 'Last punch: ${fmtWallTime(r.lastPunch)}' : '',
      child: Text(
        lastOutText(lastOut: r.lastOut, punchStatus: r.punchStatus),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _T.cell.copyWith(
          color: lastOutColor,
          fontWeight: r.punchStatus == 'MISSING_OUT' ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
    final firstIn = Text(fmtWallTime(r.firstIn), maxLines: 1, style: _T.cell);
    final work = Text(_hm(r.totalWorkMinutes), maxLines: 1, style: _T.cell.copyWith(fontWeight: FontWeight.w600));
    Widget late(int m, Color c) => m > 0
        ? Text(_hm(m), maxLines: 1, style: _T.cell.copyWith(fontWeight: FontWeight.w600, color: c))
        : const Text('–', style: TextStyle(fontSize: 13, color: _K.gray300));

    if (wide) {
      return Material(
        color: Colors.white,
        child: InkWell(
          onTap: onManage,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: _tableRow(
              [
                Row(
                  children: [
                    _Avatar(name: r.employeeName),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.employeeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray900),
                          ),
                          Text(
                            dateText != null ? '${r.employeeCode}, $dateText' : r.employeeCode,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: _K.gray500, fontFeatures: _T.tabular),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Text(
                  r.branchName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: _K.gray500),
                ),
                firstIn,
                lastOut,
                work,
                late(r.lateMinutes, _K.red600),
                late(r.lateAfterLunchMinutes, _K.orange600),
                Align(alignment: Alignment.centerLeft, child: badge),
              ],
              trailing: IconButton(
                tooltip: 'Manage punches',
                onPressed: onManage,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                icon: const Icon(Icons.history_rounded, size: 17, color: _K.gray500),
              ),
            ),
          ),
        ),
      );
    }

    final sub = [
      r.employeeCode,
      if (dateText != null) dateText,
      if (r.branchName.isNotEmpty) r.branchName,
    ].join(', ');

    final outText = lastOutText(lastOut: r.lastOut, punchStatus: r.punchStatus);
    final metrics = Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'In ', style: TextStyle(color: _K.gray400)),
        TextSpan(text: fmtWallTime(r.firstIn)),
        const TextSpan(text: '   Out ', style: TextStyle(color: _K.gray400)),
        TextSpan(
          text: outText,
          style: TextStyle(
            color: lastOutColor,
            fontWeight: r.punchStatus == 'MISSING_OUT' ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        const TextSpan(text: '   Worked ', style: TextStyle(color: _K.gray400)),
        TextSpan(text: _hm(r.totalWorkMinutes), style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: _K.gray900, fontFeatures: _T.tabular),
    );

    return Semantics(
      button: true,
      hint: 'Manage punches',
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: onManage,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            child: Row(
              children: [
                _Avatar(name: r.employeeName),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                  text: r.employeeName,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray900),
                                ),
                                TextSpan(
                                  text: '  $sub',
                                  style: const TextStyle(fontSize: 11, color: _K.gray500, fontFeatures: _T.tabular),
                                ),
                              ]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(child: badge),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(child: metrics),
                          if (r.lateMinutes > 0) ...[
                            const SizedBox(width: 4),
                            _MiniChip(text: 'Late ${_hm(r.lateMinutes)}', tone: _red),
                          ],
                          if (r.lateAfterLunchMinutes > 0) ...[
                            const SizedBox(width: 4),
                            _MiniChip(text: 'Lunch ${_hm(r.lateAfterLunchMinutes)}', tone: _orange),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18, color: _K.gray300),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Live punch feed (RealtimePunches.tsx) ───────────────────────────────────

class _RealtimePunches extends StatefulWidget {
  const _RealtimePunches();

  @override
  State<_RealtimePunches> createState() => _RealtimePunchesState();
}

class _RealtimePunchesState extends State<_RealtimePunches> with WidgetsBindingObserver {
  List<PunchLog> _logs = const [];
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
      _start();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  Future<void> _load() async {
    try {
      final res = await attendanceAdminService.fetchRecords();
      if (mounted) setState(() => _logs = res.results);
    } catch (_) {
      // Keep the last feed; the next poll retries.
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Surface(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardHeader(
            icon: Icons.monitor_heart_outlined,
            tone: _indigo,
            title: 'Live punches',
            subtitle: 'every 10 s',
            trailing: _LiveDot(),
            inline: true,
          ),
          const SizedBox(height: 2),
          if (_loading)
            for (var i = 0; i < 2; i++) ...[
              if (i > 0) _divider,
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    _Bone(width: 26, height: 26, radius: 8),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(widthFactor: 0.5, child: _Bone(height: 12, radius: 4)),
                          SizedBox(height: 6),
                          FractionallySizedBox(widthFactor: 0.75, child: _Bone(height: 10, radius: 4)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ]
          else if (_logs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 8),
              child: _EmptyState(
                icon: Icons.schedule_rounded,
                title: 'No recent punches',
                message: 'New punches from any device appear here within 10 seconds.',
              ),
            )
          else
            // Only the latest two, as on the web.
            for (final (i, log) in _logs.take(2).indexed) ...[
              if (i > 0) _divider,
              _FeedRow(log: log),
            ],
        ],
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({required this.log});

  final PunchLog log;

  @override
  Widget build(BuildContext context) {
    final isIn = isInPunch(log.punchType, log.ignoreReason);
    final tone = isIn ? _emerald : _orange;
    final device = log.deviceName != null
        ? '${log.deviceName}${log.deviceCode != null ? ' (${log.deviceCode})' : ''}'
        : null;
    final details = [
      log.employeeCode,
      log.branchName,
      if (log.departmentName.isNotEmpty) log.departmentName,
      if (device != null) device,
    ].join(', ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          _IconBox(icon: isIn ? Icons.login_rounded : Icons.logout_rounded, tone: tone, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.employeeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.25, color: _K.gray900),
                ),
                Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _MiniChip(text: punchLabel(log.punchType, log.ignoreReason), tone: tone),
              const SizedBox(height: 2),
              Text(
                _wallTimeSeconds(log.timestamp),
                style: const TextStyle(fontSize: 11, color: _K.gray500, fontFeatures: _T.tabular),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Manage punches for one record ───────────────────────────────────────────

class _ManagePunchesDialog extends StatefulWidget {
  const _ManagePunchesDialog({required this.record});

  final AttendanceSummary record;

  @override
  State<_ManagePunchesDialog> createState() => _ManagePunchesDialogState();
}

class _ManagePunchesDialogState extends State<_ManagePunchesDialog> {
  List<PunchLog> _logs = const [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _adding = false;
  bool _submitting = false;
  bool _changed = false;
  String _punchType = 'IN';
  TimeOfDay? _time;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final res = await attendanceAdminService.fetchRecords(
        employeeId: widget.record.employeeId,
        date: widget.record.date,
        page: 1,
      );
      if (mounted) setState(() => _logs = res.results);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final t = _time;
    if (t == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      String two(int n) => n.toString().padLeft(2, '0');
      await attendanceAdminService.createManualPunch(
        employeeId: widget.record.employeeId,
        timestamp: '${widget.record.date}T${two(t.hour)}:${two(t.minute)}:00',
        punchType: _punchType,
      );
      _changed = true;
      if (!mounted) return;
      showToast(context, 'Manual punch added');
      setState(() {
        _adding = false;
        _time = null;
      });
      await _load();
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to create manual punch'), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _delete(PunchLog log) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete this punch?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900),
        ),
        content: Text(
          'The ${punchLabel(log.punchType, log.ignoreReason)} punch at ${fmtWallTime(log.timestamp)} '
          'will be permanently removed.',
          style: const TextStyle(fontSize: 13, height: 1.45, color: _K.gray600),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _K.gray600),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _K.red600,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete punch'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await attendanceAdminService.deletePunch(log.id);
      _changed = true;
      if (mounted) showToast(context, 'Punch deleted');
      await _load();
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to delete punch'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final d = parseDateOnly(r.date);
    final size = MediaQuery.sizeOf(context);
    final dateText = d != null ? '${formatMMMM(d)} ${formatDD(d)}, ${d.year}' : r.date;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 560, maxHeight: size.height * 0.9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _IconBox(icon: Icons.history_rounded, tone: _indigo, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Manage punches',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900),
                          ),
                          const SizedBox(height: 2),
                          Text.rich(
                            TextSpan(
                              style: const TextStyle(fontSize: 12, color: _K.gray500),
                              children: [
                                TextSpan(
                                  text: r.employeeName,
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: _K.gray800),
                                ),
                                TextSpan(
                                  text: '  #${r.employeeCode}',
                                  style: const TextStyle(fontFeatures: _T.tabular),
                                ),
                                TextSpan(text: '\n$dateText'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(_changed),
                      icon: const Icon(Icons.close_rounded, size: 20, color: _K.gray400),
                    ),
                  ],
                ),
              ),
              _divider,
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _body(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && _logs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: _K.indigo600)),
            SizedBox(height: 10),
            Text('Loading punches…', style: _T.subtitle),
          ],
        ),
      );
    }
    if (_loadFailed && _logs.isEmpty) {
      return _EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load punches',
        message: 'Check your connection and try again.',
        action: _LinkButton(label: 'Retry', onTap: _load),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _adding
              ? _addForm()
              : OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _K.indigo600,
                    backgroundColor: _K.indigo50.withValues(alpha: 0.5),
                    side: const BorderSide(color: _K.indigo200),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => setState(() => _adding = true),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add manual punch'),
                ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Text('Recorded punches', style: _T.title),
            const SizedBox(width: 8),
            _CountBadge(count: _logs.length, tone: _gray),
            const Spacer(),
            if (_loading)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _K.indigo500)),
          ],
        ),
        const SizedBox(height: 10),
        if (_logs.isEmpty)
          const _EmptyState(
            icon: Icons.schedule_rounded,
            title: 'No punches recorded for this date',
            message: 'Add a manual punch above if one is missing.',
          )
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _K.gray200),
            ),
            child: Column(
              children: [
                for (final (i, log) in _logs.indexed) ...[
                  if (i > 0) _divider,
                  _PunchRow(log: log, onDelete: () => _delete(log)),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _addForm() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _K.indigo50.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _K.indigo100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Expanded(child: Text('New manual punch', style: _T.title)),
              Icon(Icons.verified_user_outlined, size: 13, color: _K.indigo600),
              SizedBox(width: 4),
              Text('Audit logged', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _K.indigo600)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _LabeledField(
                  label: 'Direction',
                  child: _Segmented<String>(
                    value: _punchType,
                    height: 44,
                    options: const [
                      ('IN', 'In', Icons.login_rounded),
                      ('OUT', 'Out', Icons.logout_rounded),
                    ],
                    onChanged: (v) => setState(() => _punchType = v),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LabeledField(
                  label: 'Time',
                  child: _DateButton(
                    text: _time == null ? 'Pick time' : _time!.format(context),
                    placeholder: _time == null,
                    icon: Icons.schedule_rounded,
                    fill: Colors.white,
                    semanticLabel: _time == null ? 'Pick time' : 'Time, ${_time!.format(context)}',
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: _time ?? TimeOfDay.now());
                      if (picked != null) setState(() => _time = picked);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: _K.gray600,
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                onPressed: _submitting
                    ? null
                    : () => setState(() {
                          _adding = false;
                          _time = null;
                        }),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _K.indigo600,
                  disabledBackgroundColor: _K.indigo200,
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                onPressed: (_submitting || _time == null) ? null : _save,
                icon: _submitting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded, size: 16),
                label: Text(_submitting ? 'Saving…' : 'Save punch'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PunchRow extends StatelessWidget {
  const _PunchRow({required this.log, required this.onDelete});

  final PunchLog log;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isIn = isInPunch(log.punchType, log.ignoreReason);
    final tone = isIn ? _emerald : _amber;
    final label = punchLabel(log.punchType, log.ignoreReason);
    final hint = punchLabelHint(log.ignoreReason);
    final source = log.source ?? 'FINGERPRINT';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(
        children: [
          Tooltip(
            message: hint ?? '',
            child: _IconBox(icon: isIn ? Icons.login_rounded : Icons.logout_rounded, tone: tone, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      fmtWallTime(log.timestamp),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _K.gray900,
                        fontFeatures: _T.tabular,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(child: _MiniChip(text: label, tone: tone)),
                  ],
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          source == 'RFID' ? Icons.credit_card_rounded : Icons.fingerprint_rounded,
                          size: 12,
                          color: _K.gray400,
                        ),
                        const SizedBox(width: 4),
                        Text(_sentenceCase(source), style: const TextStyle(fontSize: 11, color: _K.gray500)),
                      ],
                    ),
                    if (log.deviceName != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.router_outlined, size: 12, color: _K.gray400),
                          const SizedBox(width: 4),
                          Text(
                            '${log.deviceName}${log.deviceCode != null ? ' (${log.deviceCode})' : ''}',
                            style: const TextStyle(fontSize: 11, color: _K.gray500),
                          ),
                        ],
                      ),
                    if (log.isManual) const _MiniChip(text: 'Manual', tone: _indigo),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete punch',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 20, color: _K.gray400),
          ),
        ],
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
      label: 'Loading attendance records',
      child: Column(
        children: [
          const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final sm = c.maxWidth >= 640;
                final md = c.maxWidth >= 768;
                return ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.all(sm ? 20 : 12),
                  children: [
                    const Row(
                      children: [
                        _Bone(width: 36, height: 36, radius: 10),
                        SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Bone(width: 190, height: 18),
                            SizedBox(height: 8),
                            _Bone(width: 230, height: 12),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _Grid(
                      columns: md ? 4 : 2,
                      gap: 12,
                      children: [for (var i = 0; i < 4; i++) const _Bone(height: 52)],
                    ),
                    const SizedBox(height: 12),
                    const _Bone(height: 110),
                    const SizedBox(height: 12),
                    const _Bone(height: 60),
                    const SizedBox(height: 12),
                    const _Bone(height: 300),
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
  const _Bone({this.width, required this.height, this.radius = _cardRadius});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(color: _K.gray100, borderRadius: BorderRadius.circular(radius)),
    );
  }
}

// ── Form pieces ─────────────────────────────────────────────────────────────

InputDecoration _inputDecoration({String? hint, IconData? icon, Color fill = _K.gray50, Widget? suffix}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: _K.gray400),
    prefixIcon: icon == null ? null : Icon(icon, size: 15, color: _K.gray500),
    prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 20),
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 20),
    filled: true,
    fillColor: fill,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    border: border(_K.gray200),
    enabledBorder: border(_K.gray200),
    focusedBorder: border(_K.indigo500, 1.5),
  );
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child, this.trailing});

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: _T.label)),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// Field-styled button (date, date range, time).
class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.text,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.placeholder = false,
    this.fill = _K.gray50,
    this.trailing,
  });

  final String text;
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool placeholder;
  final Color fill;

  /// Small action inside the field (the "Today" link).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: trailing == null,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: InputDecorator(
          decoration: _inputDecoration(icon: icon, fill: fill),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: placeholder ? _K.gray400 : _K.gray900,
                    fontFeatures: _T.tabular,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _K.gray200),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onTap: onTap,
          child: SizedBox(width: 32, child: Icon(icon, size: 18, color: _K.gray600)),
        ),
      ),
    );
  }
}

/// Two-or-more option toggle (Single day / Date range, In / Out).
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.options,
    required this.onChanged,
    this.height = 40,
  });

  final T value;
  final List<(T, String, IconData?)> options;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _K.gray100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _K.gray200),
      ),
      child: Row(
        children: [
          for (final (v, label, icon) in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: v == value,
                child: Material(
                  color: v == value ? Colors.white : Colors.transparent,
                  elevation: v == value ? 1 : 0,
                  shadowColor: const Color(0x33000000),
                  borderRadius: BorderRadius.circular(7),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(7),
                    onTap: () => onChanged(v),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 14, color: v == value ? _K.indigo600 : _K.gray500),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: v == value ? FontWeight.w600 : FontWeight.w500,
                                color: v == value ? _K.indigo600 : _K.gray500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RemovableChip extends StatelessWidget {
  const _RemovableChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 3, 3, 3),
      decoration: BoxDecoration(
        color: _K.indigo50,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: _K.indigo200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _K.indigo600)),
          const SizedBox(width: 2),
          Semantics(
            button: true,
            label: 'Remove filter $label',
            excludeSemantics: true,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(Icons.close_rounded, size: 14, color: _K.indigo600),
              ),
            ),
          ),
        ],
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

// ── Small shared pieces ─────────────────────────────────────────────────────

/// White card with a hairline border; optionally tappable.
class _Surface extends StatelessWidget {
  const _Surface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.clip = false,
    this.color = Colors.white,
    this.borderColor = _K.gray100,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool clip;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(_cardRadius);
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(borderRadius: radius, onTap: onTap, child: content),
      );
    }
    return Container(
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius,
        border: Border.all(color: borderColor),
        boxShadow: const [BoxShadow(color: Color(0x08101828), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: content,
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.tone,
    required this.title,
    this.subtitle,
    this.trailing,
    this.inline = false,
  });

  final IconData icon;
  final _Tone tone;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Title and subtitle on one line.
  final bool inline;

  @override
  Widget build(BuildContext context) {
    if (inline) {
      return Row(
        children: [
          _IconBox(icon: icon, tone: tone, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              header: true,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: title, style: _T.title),
                  if (subtitle != null)
                    TextSpan(
                      text: '  $subtitle',
                      style: const TextStyle(fontSize: 11.5, color: _K.gray500, fontFeatures: _T.tabular),
                    ),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      );
    }
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
                Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.subtitle),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: _K.indigo50, shape: BoxShape.circle),
      child: Text(
        _initials(name),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _K.indigo600),
      ),
    );
  }
}

/// Single-row empty state: icon, title, message and an optional action.
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
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: _K.gray50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _K.gray200),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(color: _K.gray100, shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: _K.gray400),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _K.gray700)),
                if (message != null) Text(message!, style: _T.caption),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
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
        padding: EdgeInsets.fromLTRB(12, 6, hasAction ? 4 : 12, 6),
        decoration: BoxDecoration(
          color: tone.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tone.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: tone.fg),
            const SizedBox(width: 8),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(fontSize: 12.5, height: 1.35, color: tone.fg),
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

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: const BoxDecoration(color: _K.emerald500, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        const Text('Live', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.emerald600)),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.text, required this.tone});

  final String text;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: tone.fg, fontFeatures: _T.tabular),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.tone});

  final int count;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: tone.border),
      ),
      child: Text(
        '$count',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tone.fg, fontFeatures: _T.tabular),
      ),
    );
  }
}

/// Equal-width grid built from rows, so every card in a row is the same height.
class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.gap, required this.children});

  final int columns;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var start = 0; start < children.length; start += columns) {
      final cells = children.sublist(start, (start + columns).clamp(0, children.length));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < columns; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(child: i < cells.length ? cells[i] : const SizedBox.shrink()),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          rows[i],
        ],
      ],
    );
  }
}