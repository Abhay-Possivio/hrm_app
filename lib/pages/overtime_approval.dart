// Port of features/admin/overtime/OvertimeApprovalPage.tsx.
//
// Overtime days with their approval state. HR and team leads approve (all
// of it or part, in minutes), reject, or reset to pending — one day at a
// time or several selected days at once. Used for both /admin/overtime and
// /team/overtime; the server decides which days each person can decide.
//
// Wide screens get a table with column headers; on phones each day is a
// compact card with labelled Approve / Reject buttons.
//
// Layout (compact):
//   Header: title · how-it-works toggle · refresh
//   [load-error banner] [how auto-approval works]
//   Calculated | Approved | Pending | Pending days   (pending cards jump to the tab)
//   Filters: date range (+ quick ranges) · search
//   Days card: status tabs · selection bar · table / cards · pagination

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hrm_app/components/ui/pagination_bar.dart';
import 'package:hrm_app/services/hr_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';
import 'package:hrm_app/utils/toast.dart';

const _pageSize = 25;
const _tabs = [
  ('PENDING', 'Pending'),
  ('APPROVED', 'Approved'),
  ('REJECTED', 'Rejected'),
  ('AUTO', 'Auto-approved'),
  ('ALL', 'All'),
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
  static const gray900 = Color(0xFF111827);
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo200 = Color(0xFFC7D2FE);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const indigo800 = Color(0xFF3730A3);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber100 = Color(0xFFFEF3C7);
  static const amber600 = Color(0xFFD97706);
  static const red50 = Color(0xFFFEF2F2);
  static const red100 = Color(0xFFFEE2E2);
  static const red200 = Color(0xFFFECACA);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);
  static const orange50 = Color(0xFFFFF7ED);
  static const orange100 = Color(0xFFFFEDD5);
  static const orange600 = Color(0xFFEA580C);
}

/// A tinted color set: soft background, border, and foreground.
class _Tone {
  const _Tone(this.bg, this.border, this.fg);

  final Color bg;
  final Color border;
  final Color fg;
}

const _emerald = _Tone(_K.emerald50, _K.emerald100, _K.emerald600);
const _amber = _Tone(_K.amber50, _K.amber100, _K.amber600);
const _red = _Tone(_K.red50, _K.red100, _K.red600);
const _orange = _Tone(_K.orange50, _K.orange100, _K.orange600);
const _gray = _Tone(_K.gray50, _K.gray200, _K.gray600);

StatusStyle _statusStyle(String s) => switch (s) {
      'PENDING' => StatusStyle.amber,
      'APPROVED' => StatusStyle.emerald,
      'REJECTED' => StatusStyle.red,
      'AUTO' => StatusStyle.sky,
      _ => StatusStyle.gray,
    };

String _statusLabel(String s) => switch (s) {
      'PENDING' => 'Pending',
      'APPROVED' => 'Approved',
      'REJECTED' => 'Rejected',
      'AUTO' => 'Auto-approved',
      _ => s,
    };

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3, color: _K.gray900);
  static const subtitle = TextStyle(fontSize: 12, height: 1.3, color: _K.gray500);
  static const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _K.gray500);
  static const caption = TextStyle(fontSize: 11, height: 1.3, color: _K.gray400);
  static const columnHead = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.gray500);
}

const _cardRadius = 16.0;
const _divider = Divider(height: 1, thickness: 1, color: _K.gray100);

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

/// Quick date ranges for the filter menu.
enum _Preset {
  thisMonth('This month'),
  lastMonth('Last month'),
  last7('Last 7 days'),
  last30('Last 30 days');

  const _Preset(this.label);
  final String label;

  DateTimeRange get range {
    final t = _today();
    return switch (this) {
      _Preset.thisMonth => DateTimeRange(start: DateTime(t.year, t.month, 1), end: t),
      _Preset.lastMonth => DateTimeRange(start: DateTime(t.year, t.month - 1, 1), end: DateTime(t.year, t.month, 0)),
      _Preset.last7 => DateTimeRange(start: DateTime(t.year, t.month, t.day - 6), end: t),
      _Preset.last30 => DateTimeRange(start: DateTime(t.year, t.month, t.day - 29), end: t),
    };
  }
}

// ── Page ────────────────────────────────────────────────────────────────────

class OvertimeApprovalPage extends StatefulWidget {
  const OvertimeApprovalPage({super.key});

  @override
  State<OvertimeApprovalPage> createState() => _OvertimeApprovalPageState();
}

class _OvertimeApprovalPageState extends State<OvertimeApprovalPage> {
  late DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late DateTime _to = _today();
  String _tab = 'PENDING';
  String _query = '';
  int _page = 1;
  OvertimeList? _data;
  bool _loading = true;
  bool _busy = false;
  bool _showHelp = false;
  String? _error;
  Timer? _debounce;
  int _loadId = 0;
  final _searchCtrl = TextEditingController();

  /// Selected rows, by OvertimeDay.key.
  final Set<String> _selected = {};

  /// Minutes typed into the "Approve (min)" boxes, by OvertimeDay.key.
  final Map<String, String> _minutes = {};

  /// Bumped on every load so the minute boxes reset to the server values.
  int _version = 0;

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
    setState(() => _loading = true);
    try {
      final data = await overtimeService.list(
        from: toDateKey(_from),
        to: toDateKey(_to),
        status: _tab,
        q: _query,
        page: _page,
        pageSize: _pageSize,
      );
      if (!mounted || id != _loadId) return;
      setState(() {
        _data = data;
        _error = null;
        _selected.clear();
        _minutes.clear();
        _version++;
      });
    } catch (err) {
      if (mounted && id == _loadId) setState(() => _error = apiError(err, 'Could not load overtime'));
    } finally {
      if (mounted && id == _loadId) setState(() => _loading = false);
    }
  }

  void _reload({String? tab, String? query, DateTime? from, DateTime? to}) {
    setState(() {
      if (tab != null) _tab = tab;
      if (query != null) _query = query;
      if (from != null) _from = from;
      if (to != null) _to = to;
      _page = 1;
    });
    _load();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = value.trim();
      if (q != _query) _reload(query: q);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    if (_query.isNotEmpty) _reload(query: '');
  }

  Future<void> _pickRange() async {
    final today = _today();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: DateTimeRange(start: _from, end: _to.isAfter(today) ? today : _to),
    );
    if (picked != null) _reload(from: picked.start, to: picked.end);
  }

  _Preset? get _activePreset {
    for (final p in _Preset.values) {
      final r = p.range;
      if (r.start == _from && r.end == _to) return p;
    }
    return null;
  }

  bool _editable(OvertimeDay r) => r.canDecide && r.status != 'AUTO';

  Future<void> _decide(List<OvertimeDay> items, String action) async {
    if (items.isEmpty) return;
    setState(() => _busy = true);
    try {
      final decisions = [
        for (final r in items)
          OvertimeDecision(
            employeeId: r.employeeId,
            date: r.date,
            action: action,
            minutes: action == 'approve' ? _typedMinutes(r) : null,
          ),
      ];
      final res = await overtimeService.decide(decisions);
      if (!mounted) return;
      final verb = switch (action) {
        'approve' => 'approved',
        'reject' => 'rejected',
        _ => 'moved back to pending',
      };
      showToast(context, '${res.updated} day${res.updated == 1 ? '' : 's'} $verb');
      if (res.errors > 0) {
        showToast(context, '${res.errors} day${res.errors == 1 ? '' : 's'} could not be updated', error: true);
      }
      _load();
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Update failed'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmBulkReject(List<OvertimeDay> items) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Reject ${items.length} overtime day${items.length == 1 ? '' : 's'}?',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900),
        ),
        content: const Text(
          "Rejected overtime isn't payable. You can move a day back to pending later.",
          style: TextStyle(fontSize: 13, height: 1.45, color: _K.gray600),
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
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok == true) _decide(items, 'reject');
  }

  /// Minutes typed for this row, or null to approve the whole calculated overtime.
  int? _typedMinutes(OvertimeDay r) {
    final raw = _minutes[r.key];
    if (raw == null || raw.trim().isEmpty) return null;
    final value = num.tryParse(raw.trim());
    if (value == null) return null;
    final rounded = value.round();
    return rounded < 0 ? 0 : rounded;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null && _error == null) return const _PageSkeleton();

    final rows = _data?.results ?? const <OvertimeDay>[];
    final decidable = rows.where(_editable).toList();
    final allSelected = decidable.isNotEmpty && decidable.every((r) => _selected.contains(r.key));
    final someSelected = decidable.any((r) => _selected.contains(r.key));
    final selectedRows = rows.where((r) => _selected.contains(r.key)).toList();
    final s = _data?.summary;

    void toggleAll() => setState(() {
          if (allSelected) {
            _selected.clear();
          } else {
            _selected
              ..clear()
              ..addAll(decidable.map((r) => r.key));
          }
        });

    return RefreshIndicator(
      color: _K.indigo600,
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sm = width >= 640;
          final md = width >= 768;
          final lg = width >= 1024;
          final gap = sm ? 20.0 : 16.0;

          final sections = <Widget>[
            _Header(
              wide: sm,
              loading: _loading,
              showHelp: _showHelp,
              onToggleHelp: () => setState(() => _showHelp = !_showHelp),
              onRefresh: _load,
            ),
            if (_showHelp)
              const _Banner(
                tone: _Tone(_K.indigo50, _K.indigo200, _K.indigo800),
                icon: Icons.info_outline_rounded,
                child: Text(
                  'Overtime counts as payable once approved. Turn on "Require overtime approval" in '
                  'Configuration → Overtime. While it is off, or when a day is under the auto-approve '
                  'limit, overtime is approved automatically.',
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
            _Grid(
              columns: lg ? 4 : 2,
              gap: 12,
              children: [
                _Stat(
                  label: 'Calculated',
                  value: fmtMinutes(s?.calculated),
                  icon: Icons.functions_rounded,
                  tone: _gray,
                ),
                _Stat(
                  label: 'Approved',
                  value: fmtMinutes(s?.approved),
                  icon: Icons.check_circle_outline_rounded,
                  tone: _emerald,
                  onTap: _tab == 'APPROVED' ? null : () => _reload(tab: 'APPROVED'),
                ),
                _Stat(
                  label: 'Pending',
                  value: fmtMinutes(s?.pending),
                  icon: Icons.hourglass_top_rounded,
                  tone: _amber,
                  onTap: _tab == 'PENDING' ? null : () => _reload(tab: 'PENDING'),
                ),
                _Stat(
                  label: 'Pending days',
                  value: '${s?.pendingDays ?? 0}',
                  icon: Icons.event_note_outlined,
                  tone: _amber,
                  onTap: _tab == 'PENDING' ? null : () => _reload(tab: 'PENDING'),
                ),
              ],
            ),
            _filterBar(sm: sm),
            _daysCard(
              rows: rows,
              decidable: decidable,
              selectedRows: selectedRows,
              allSelected: allSelected,
              someSelected: someSelected,
              onToggleAll: toggleAll,
              md: md,
              pendingDays: s?.pendingDays ?? 0,
            ),
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

  // ── Filters ──

  Widget _filterBar({required bool sm}) {
    final preset = _activePreset;
    final rangeText = '${formatDDMMMYYYY(_from)} – ${formatDDMMMYYYY(_to)}';

    final range = Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'Date range, $rangeText',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _pickRange,
              child: InputDecorator(
                decoration: _inputDecoration(icon: Icons.date_range_outlined),
                child: Text(
                  rangeText,
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
          onSelected: (p) => _reload(from: p.range.start, to: p.range.end),
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

  // ── Days ──

  Widget _daysCard({
    required List<OvertimeDay> rows,
    required List<OvertimeDay> decidable,
    required List<OvertimeDay> selectedRows,
    required bool allSelected,
    required bool someSelected,
    required VoidCallback onToggleAll,
    required bool md,
    required int pendingDays,
  }) {
    final count = _data?.count ?? 0;

    final tabs = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, (id, label)) in _tabs.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            _TabChip(
              label: label,
              count: id == 'PENDING' && pendingDays > 0 ? pendingDays : null,
              selected: _tab == id,
              onTap: () {
                if (_tab != id) _reload(tab: id);
              },
            ),
          ],
        ],
      ),
    );

    final selectAll = decidable.isEmpty
        ? null
        : Semantics(
            label: allSelected ? 'Clear selection' : 'Select all on this page',
            child: Checkbox(
              value: allSelected ? true : (someSelected ? null : false),
              tristate: true,
              activeColor: _K.indigo600,
              visualDensity: VisualDensity.compact,
              onChanged: (_) => onToggleAll(),
            ),
          );

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
                  icon: Icons.timer_outlined,
                  tone: _emerald,
                  title: 'Overtime days',
                  subtitle: _loading && _data == null
                      ? 'Loading…'
                      : '$count day${count == 1 ? '' : 's'}, ${formatDDMMMYYYY(_from)} – ${formatDDMMMYYYY(_to)}',
                ),
                const SizedBox(height: 12),
                tabs,
              ],
            ),
          ),

          // Selection bar
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.topCenter,
            child: selectedRows.isEmpty
                ? const SizedBox(width: double.infinity)
                : _SelectionBar(
                    count: selectedRows.length,
                    busy: _busy,
                    onApprove: () => _decide(selectedRows, 'approve'),
                    onReject: () => _confirmBulkReject(selectedRows),
                    onClear: () => setState(_selected.clear),
                  ),
          ),

          SizedBox(
            height: 2,
            child: (_loading || _busy)
                ? const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50)
                : const ColoredBox(color: _K.gray100),
          ),

          // Column headers (wide) / select-all strip (phones)
          if (rows.isNotEmpty)
            Container(
              color: _K.gray50,
              padding: EdgeInsets.fromLTRB(4, md ? 4 : 2, 16, md ? 4 : 2),
              child: md
                  ? _tableRow(
                      checkbox: SizedBox(width: 40, child: selectAll),
                      employee: const Text('Employee', style: _T.columnHead),
                      date: const Text('Date', style: _T.columnHead),
                      inOut: const Text('In – out', style: _T.columnHead),
                      overtime: const Text('Overtime', textAlign: TextAlign.right, style: _T.columnHead),
                      minutes: const Text('Approve', style: _T.columnHead),
                      status: const Text('Status', style: _T.columnHead),
                      actions: const SizedBox.shrink(),
                    )
                  : Row(
                      children: [
                        SizedBox(width: 40, child: selectAll),
                        Text(
                          decidable.isEmpty ? 'Nothing to decide on this page' : 'Select all on this page',
                          style: _T.columnHead,
                        ),
                      ],
                    ),
            ),

          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Loading overtime…', textAlign: TextAlign.center, style: _T.subtitle),
                    )
                  : _tab == 'PENDING' && _query.isEmpty
                      ? const _EmptyState(
                          icon: Icons.task_alt_rounded,
                          success: true,
                          title: 'Nothing waiting for approval',
                          message: 'Pending overtime for this period will appear here.',
                        )
                      : _EmptyState(
                          icon: Icons.timer_off_outlined,
                          title: 'No overtime days here',
                          message: _query.isNotEmpty
                              ? 'No matches for "$_query" in this period.'
                              : 'Try another status or a wider date range.',
                          action: _query.isNotEmpty ? _LinkButton(label: 'Clear search', onTap: _clearSearch) : null,
                        ),
            )
          else
            AnimatedOpacity(
              opacity: _loading ? 0.55 : 1,
              duration: const Duration(milliseconds: 150),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) _divider,
                    _DayRow(
                      key: ValueKey('${rows[i].key}#$_version'),
                      day: rows[i],
                      editable: _editable(rows[i]),
                      selected: _selected.contains(rows[i].key),
                      busy: _busy,
                      wide: md,
                      onSelect: (v) => setState(() => v ? _selected.add(rows[i].key) : _selected.remove(rows[i].key)),
                      onMinutes: (v) => _minutes[rows[i].key] = v,
                      onApprove: () => _decide([rows[i]], 'approve'),
                      onReject: () => _decide([rows[i]], 'reject'),
                      onReset: () => _decide([rows[i]], 'reset'),
                    ),
                  ],
                ],
              ),
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
}

// ── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.wide,
    required this.loading,
    required this.showHelp,
    required this.onToggleHelp,
    required this.onRefresh,
  });

  final bool wide;
  final bool loading;
  final bool showHelp;
  final VoidCallback onToggleHelp;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _IconBox(icon: Icons.timer_outlined, tone: _emerald, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Overtime approval',
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
                  const Text('Approved overtime counts as payable.', style: _T.subtitle),
                  _LinkButton(label: showHelp ? 'Hide details' : 'How auto-approval works', onTap: onToggleHelp),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        wide
            ? OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _K.gray700,
                  side: const BorderSide(color: _K.gray200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                onPressed: loading ? null : onRefresh,
                icon: loading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Refresh'),
              )
            : IconButton(
                tooltip: 'Refresh',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: _K.gray200),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: loading ? null : onRefresh,
                icon: loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, size: 18, color: _K.gray600),
              ),
      ],
    );
  }
}

// ── One overtime day ────────────────────────────────────────────────────────

Widget _tableRow({
  required Widget checkbox,
  required Widget employee,
  required Widget date,
  required Widget inOut,
  required Widget overtime,
  required Widget minutes,
  required Widget status,
  required Widget actions,
}) {
  return Row(
    children: [
      checkbox,
      Expanded(flex: 3, child: employee),
      const SizedBox(width: 12),
      Expanded(flex: 2, child: date),
      const SizedBox(width: 12),
      Expanded(flex: 3, child: inOut),
      const SizedBox(width: 12),
      SizedBox(width: 80, child: overtime),
      const SizedBox(width: 16),
      SizedBox(width: 96, child: minutes),
      const SizedBox(width: 16),
      Expanded(flex: 2, child: status),
      SizedBox(width: 116, child: Align(alignment: Alignment.centerRight, child: actions)),
    ],
  );
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    super.key,
    required this.day,
    required this.editable,
    required this.selected,
    required this.busy,
    required this.wide,
    required this.onSelect,
    required this.onMinutes,
    required this.onApprove,
    required this.onReject,
    required this.onReset,
  });

  final OvertimeDay day;
  final bool editable;
  final bool selected;
  final bool busy;
  final bool wide;
  final ValueChanged<bool> onSelect;
  final ValueChanged<String> onMinutes;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final r = day;
    final d = parseDateOnly(r.date);
    final offDay = r.dayType == 'OFF_DAY';
    final dateText = d != null ? formatEEEDDMMM(d) : r.date;

    final employee = Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: _K.indigo50, shape: BoxShape.circle),
          child: Text(
            _initials(r.employeeName),
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _K.indigo600),
          ),
        ),
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
                [r.employeeCode, if (r.branchName.isNotEmpty) r.branchName].join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: _K.gray500, fontFeatures: _T.tabular),
              ),
            ],
          ),
        ),
      ],
    );

    final dateCell = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(dateText, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray900)),
        if (offDay) ...[const SizedBox(height: 2), const _MiniChip(text: 'Off day / holiday', tone: _orange)],
      ],
    );

    final inOut = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${fmtWallTime(r.firstIn)} – ${fmtWallTime(r.lastOut)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: _K.gray700, fontFeatures: _T.tabular),
        ),
        if (r.shiftEnd != null) Text('Shift ends ${r.shiftEnd}', style: _T.caption),
      ],
    );

    final changed = r.changed
        ? const Tooltip(
            message: 'The day was recalculated after the decision',
            triggerMode: TooltipTriggerMode.tap,
            child: _MiniChip(text: 'Changed', tone: _amber, icon: Icons.warning_amber_rounded),
          )
        : null;

    final overtime = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          fmtMinutes(r.calculatedMinutes),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _K.gray900, fontFeatures: _T.tabular),
        ),
        if (changed != null) ...[const SizedBox(height: 2), changed],
      ],
    );

    final minutes = editable
        ? TextFormField(
            initialValue: '${r.status == 'APPROVED' ? r.approvedMinutes : r.calculatedMinutes}',
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            enabled: !busy,
            onChanged: onMinutes,
            style: const TextStyle(fontSize: 14, color: _K.gray900, fontFeatures: _T.tabular),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              suffixText: 'min',
              suffixStyle: _T.caption,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _K.gray200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _K.gray200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _K.indigo500, width: 1.5),
              ),
            ),
          )
        : Text(
            '${r.approvedMinutes} min',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray700, fontFeatures: _T.tabular),
          );

    final status = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusBadge(status: r.status),
        if (r.decidedBy != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('By ${r.decidedBy}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.caption),
          ),
      ],
    );

    final checkbox = SizedBox(
      width: 40,
      child: editable
          ? Checkbox(
              value: selected,
              activeColor: _K.indigo600,
              visualDensity: VisualDensity.compact,
              onChanged: busy ? null : (v) => onSelect(v ?? false),
            )
          : null,
    );

    if (wide) {
      return Material(
        color: selected ? _K.indigo50.withValues(alpha: 0.5) : Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 16, 10),
          child: _tableRow(
            checkbox: checkbox,
            employee: employee,
            date: dateCell,
            inOut: inOut,
            overtime: overtime,
            minutes: minutes,
            status: status,
            actions: editable
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ActionIcon(icon: Icons.check_rounded, tone: _emerald, tooltip: 'Approve', onTap: busy ? null : onApprove),
                      const SizedBox(width: 4),
                      _ActionIcon(icon: Icons.close_rounded, tone: _red, tooltip: 'Reject', onTap: busy ? null : onReject),
                      if (r.status != 'PENDING') ...[
                        const SizedBox(width: 4),
                        _ActionIcon(
                          icon: Icons.undo_rounded,
                          tone: _gray,
                          tooltip: 'Back to pending',
                          onTap: busy ? null : onReset,
                        ),
                      ],
                    ],
                  )
                : const Text('—', style: TextStyle(fontSize: 13, color: _K.gray300)),
          ),
        ),
      );
    }

    // Phone card
    return Material(
      color: selected ? _K.indigo50.withValues(alpha: 0.5) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            checkbox,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Expanded(child: employee), const SizedBox(width: 8), status],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 12, color: _K.gray400),
                          const SizedBox(width: 4),
                          Text(dateText, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.gray700)),
                        ],
                      ),
                      if (offDay) const _MiniChip(text: 'Off day / holiday', tone: _orange),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule_rounded, size: 12, color: _K.gray400),
                          const SizedBox(width: 4),
                          Text(
                            '${fmtWallTime(r.firstIn)} – ${fmtWallTime(r.lastOut)}',
                            style: const TextStyle(fontSize: 12, color: _K.gray700, fontFeatures: _T.tabular),
                          ),
                        ],
                      ),
                      if (r.shiftEnd != null) Text('Shift ends ${r.shiftEnd}', style: _T.caption),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    decoration: BoxDecoration(
                      color: _K.gray50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _K.gray100),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Overtime', style: _T.caption),
                              Row(
                                children: [
                                  Text(
                                    fmtMinutes(r.calculatedMinutes),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: _K.gray900,
                                      fontFeatures: _T.tabular,
                                    ),
                                  ),
                                  if (changed != null) ...[const SizedBox(width: 6), changed],
                                ],
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(editable ? 'Approve' : 'Approved', style: _T.caption),
                            const SizedBox(height: 2),
                            editable ? SizedBox(width: 100, child: minutes) : minutes,
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (editable) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: _K.red50,
                              foregroundColor: _K.red600,
                              side: const BorderSide(color: _K.red100),
                              minimumSize: const Size.fromHeight(38),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            onPressed: busy ? null : onReject,
                            icon: const Icon(Icons.close_rounded, size: 16),
                            label: const Text('Reject'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _K.emerald600,
                              minimumSize: const Size.fromHeight(38),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            onPressed: busy ? null : onApprove,
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: const Text('Approve'),
                          ),
                        ),
                        if (r.status != 'PENDING') ...[
                          const SizedBox(width: 6),
                          _ActionIcon(
                            icon: Icons.undo_rounded,
                            tone: _gray,
                            tooltip: 'Back to pending',
                            size: 38,
                            onTap: busy ? null : onReset,
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.icon, required this.tone, required this.tooltip, required this.onTap, this.size = 32});

  final IconData icon;
  final _Tone tone;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: tone.border));
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Material(
          color: tone.bg,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: SizedBox(width: size, height: size, child: Icon(icon, size: 16, color: tone.fg)),
          ),
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onClear,
  });

  final int count;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    ButtonStyle filled(Color c) => FilledButton.styleFrom(
          backgroundColor: c,
          disabledBackgroundColor: c.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white70,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 34),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        );

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: _K.gray900,
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '$count day${count == 1 ? '' : 's'} selected',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: _K.gray300,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  onPressed: onClear,
                  child: const Text('Clear'),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  style: filled(_K.red500),
                  onPressed: busy ? null : onReject,
                  icon: const Icon(Icons.close_rounded, size: 14),
                  label: const Text('Reject'),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  style: filled(_K.emerald500),
                  onPressed: busy ? null : onApprove,
                  icon: busy
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 14),
                  label: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final style = _statusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: style.border),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: style.fg),
      ),
    );
  }
}

// ── Stats ───────────────────────────────────────────────────────────────────

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon, required this.tone, this.onTap});

  final String label;
  final String value;
  final IconData icon;
  final _Tone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: '$label: $value',
      excludeSemantics: true,
      child: _Surface(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _IconBox(icon: icon, tone: tone, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.label),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        color: tone == _gray ? _K.gray900 : tone.fg,
                        fontFeatures: _T.tabular,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.selected, required this.onTap, this.count});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(side: BorderSide(color: selected ? _K.gray900 : _K.gray200));
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? _K.gray900 : Colors.white,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : _K.gray600),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white.withValues(alpha: 0.2) : _K.amber100,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : _K.amber600,
                        fontFeatures: _T.tabular,
                      ),
                    ),
                  ),
                ],
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
      label: 'Loading overtime',
      child: Column(
        children: [
          const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final sm = c.maxWidth >= 640;
                final lg = c.maxWidth >= 1024;
                return ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.all(sm ? 24 : 16),
                  children: [
                    const Row(
                      children: [
                        _Bone(width: 44, height: 44, radius: 13),
                        SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Bone(width: 190, height: 18),
                            SizedBox(height: 8),
                            _Bone(width: 240, height: 12),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _Grid(
                      columns: lg ? 4 : 2,
                      gap: 12,
                      children: [for (var i = 0; i < 4; i++) const _Bone(height: 66)],
                    ),
                    const SizedBox(height: 16),
                    const _Bone(height: 80),
                    const SizedBox(height: 16),
                    const _Bone(height: 360),
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

/// White card with a hairline border; optionally tappable.
class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.clip = false});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool clip;

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
        color: Colors.white,
        borderRadius: radius,
        border: Border.all(color: _K.gray100),
        boxShadow: const [BoxShadow(color: Color(0x08101828), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: content,
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
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: _K.gray500, fontFeatures: _T.tabular),
                ),
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

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.text, required this.tone, this.icon});

  final String text;
  final _Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: tone.fg), const SizedBox(width: 3)],
          Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: tone.fg)),
        ],
      ),
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
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 18, color: tone.fg),
            ),
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