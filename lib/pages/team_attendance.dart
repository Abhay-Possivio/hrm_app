// Port of features/team-lead/attendance/TeamAttendancePage.tsx
// (today's status for each member of the team lead's team).
//
// Wide screens get a table with column headers; on phones each member is a
// compact row with the same details.
//
// Layout (compact):
//   Header: title · company date · refresh
//   [refresh-error banner]
//   Total | Present | Late | Absent   (tap to filter)
//   Toolbar: search · status chips with counts · sort
//   Members (table / rows) · "Showing x of y"

import 'package:flutter/material.dart';

import 'package:hrm_app/services/teamlead_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';

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
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber100 = Color(0xFFFEF3C7);
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  static const rose50 = Color(0xFFFFF1F2);
  static const rose100 = Color(0xFFFFE4E6);
  static const rose200 = Color(0xFFFECDD3);
  static const rose600 = Color(0xFFE11D48);
  static const rose700 = Color(0xFFBE123C);
  static const orange50 = Color(0xFFFFF7ED);
  static const orange100 = Color(0xFFFFEDD5);
  static const orange600 = Color(0xFFEA580C);
  static const blue50 = Color(0xFFEFF6FF);
  static const blue100 = Color(0xFFDBEAFE);
  static const blue600 = Color(0xFF2563EB);
  static const purple50 = Color(0xFFFAF5FF);
  static const purple100 = Color(0xFFF3E8FF);
  static const purple600 = Color(0xFF9333EA);
  static const teal50 = Color(0xFFF0FDFA);
  static const teal100 = Color(0xFFCCFBF1);
  static const teal600 = Color(0xFF0D9488);
}

/// A tinted color set: soft background, border, and foreground.
class _Tone {
  const _Tone(this.bg, this.border, this.fg);

  final Color bg;
  final Color border;
  final Color fg;
}

const _indigo = _Tone(_K.indigo50, _K.indigo100, _K.indigo600);
const _emerald = _Tone(_K.emerald50, _K.emerald100, _K.emerald600);
const _amber = _Tone(_K.amber50, _K.amber100, _K.amber600);
const _rose = _Tone(_K.rose50, _K.rose100, _K.rose600);
const _orange = _Tone(_K.orange50, _K.orange100, _K.orange600);
const _blue = _Tone(_K.blue50, _K.blue100, _K.blue600);
const _purple = _Tone(_K.purple50, _K.purple100, _K.purple600);
const _teal = _Tone(_K.teal50, _K.teal100, _K.teal600);
const _gray = _Tone(_K.gray50, _K.gray200, _K.gray500);

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3, color: _K.gray900);
  static const subtitle = TextStyle(fontSize: 12, height: 1.3, color: _K.gray500);
  static const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _K.gray500);
  static const columnHead = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.gray500);
}

const _cardRadius = 16.0;
const _divider = Divider(height: 1, thickness: 1, color: _K.gray100);

// ── Status presentation ─────────────────────────────────────────────────────

class _Status {
  const _Status(this.label, this.tone, this.icon);

  final String label;
  final _Tone tone;
  final IconData icon;
}

const _onLeave = _Status('On leave', _blue, Icons.coffee_outlined);
const _unknown = _Status('Unknown', _gray, Icons.help_outline_rounded);

const _statusConfig = {
  'Present': _Status('Present', _emerald, Icons.check_circle_outline_rounded),
  'Late': _Status('Late', _amber, Icons.schedule_rounded),
  'Absent': _Status('Absent', _rose, Icons.cancel_outlined),
  'Awaiting Punch': _Status('Not punched', _gray, Icons.hourglass_empty_rounded),
  'Half Day': _Status('Half day', _amber, Icons.schedule_rounded),
  'On Leave': _onLeave,
  'Off Day': _Status('Off day', _purple, Icons.calendar_month_outlined),
  'Leave': _onLeave,
  'Weekend': _Status('Weekend', _purple, Icons.calendar_month_outlined),
  'Holiday': _Status('Holiday', _teal, Icons.calendar_month_outlined),
};

_Status _statusOf(TeamMember m) {
  if (m.dayType == 'ON_LEAVE') {
    return _Status(m.status.isNotEmpty && m.status != 'On Leave' ? m.status : 'On leave', _blue, Icons.coffee_outlined);
  }
  return _statusConfig[m.status] ?? _unknown;
}

/// Lower sorts first: the people a lead needs to look at come to the top.
int _statusPriority(TeamMember m) {
  if (m.status == 'Absent') return 0;
  if (m.status == 'Awaiting Punch') return 1;
  if (m.isLate || m.lateAfterLunchMinutes > 0) return 2;
  if (m.status == 'Half Day') return 3;
  if (m.status == 'Present') return 4;
  if (m.dayType == 'ON_LEAVE') return 5;
  return 6;
}

const _avatarGradients = [
  [Color(0xFF818CF8), Color(0xFF8B5CF6)],
  [Color(0xFF34D399), Color(0xFF14B8A6)],
  [Color(0xFFFB7185), Color(0xFFEC4899)],
  [Color(0xFFFBBF24), Color(0xFFF97316)],
  [Color(0xFF38BDF8), Color(0xFF06B6D4)],
  [Color(0xFFC084FC), Color(0xFFD946EF)],
];

String _initials(String name) => name
    .split(' ')
    .where((p) => p.isNotEmpty)
    .take(2)
    .map((p) => p.characters.first)
    .join()
    .toUpperCase();

/// Filter value and chip label.
const _filters = [
  ('ALL', 'All'),
  ('Present', 'Present'),
  ('Late', 'Late'),
  ('Absent', 'Absent'),
  ('Awaiting Punch', 'Not punched'),
  ('Leave', 'On leave'),
];

bool _matchesStatus(TeamMember m, String filter) =>
    filter == 'ALL' ||
    (filter == 'Present' && (m.status == 'Present' || m.status == 'Half Day')) ||
    (filter == 'Late' && m.isLate) ||
    (filter == 'Leave' && m.dayType == 'ON_LEAVE') ||
    m.status == filter;

// ── Page ────────────────────────────────────────────────────────────────────

class TeamAttendancePage extends StatefulWidget {
  const TeamAttendancePage({super.key});

  @override
  State<TeamAttendancePage> createState() => _TeamAttendancePageState();
}

class _TeamAttendancePageState extends State<TeamAttendancePage> {
  List<TeamMember> _members = const [];
  int _totalEmployees = 0;
  String? _companyDate;
  String? _loadError;
  DateTime? _updatedAt;
  bool _loading = true;
  bool _loadedOnce = false;
  bool _refreshing = false;
  String _search = '';
  String _filter = 'ALL';
  bool _sortByStatus = false;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      if (refresh) _refreshing = true;
      _loadError = null;
    });
    try {
      final data = await teamLeadService.fetchStats();
      if (!mounted) return;
      setState(() {
        _members = data.teamMembers;
        _totalEmployees = data.kpis.totalEmployees;
        if (data.date != null) _companyDate = data.date;
        _updatedAt = DateTime.now();
        _loadedOnce = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loadError = 'Could not load team attendance.');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  void _retryFromScratch() {
    setState(() => _loading = true);
    _load();
  }

  bool _matchesSearch(TeamMember m) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;
    return m.name.toLowerCase().contains(q) ||
        m.employeeCode.toLowerCase().contains(q) ||
        m.designation.toLowerCase().contains(q);
  }

  void _toggleFilter(String f) => setState(() => _filter = _filter == f ? 'ALL' : f);

  void _clearAll() {
    _searchCtrl.clear();
    setState(() {
      _search = '';
      _filter = 'ALL';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _PageSkeleton();
    if (!_loadedOnce) {
      return _ErrorState(onRetry: _retryFromScratch, onRefresh: () => _load(refresh: true));
    }

    // Keep each member's original index so avatar colors stay stable.
    final filtered = [
      for (final (i, m) in _members.indexed)
        if (_matchesSearch(m) && _matchesStatus(m, _filter)) (i, m),
    ];
    if (_sortByStatus) {
      filtered.sort((a, b) {
        final p = _statusPriority(a.$2).compareTo(_statusPriority(b.$2));
        return p != 0 ? p : a.$2.name.toLowerCase().compareTo(b.$2.name.toLowerCase());
      });
    }

    final searched = _members.where(_matchesSearch).toList();
    final counts = {for (final (v, _) in _filters) v: searched.where((m) => _matchesStatus(m, v)).length};

    final present = _members.where((m) => m.status == 'Present' || m.status == 'Half Day').length;
    final late = _members.where((m) => m.isLate).length;
    final absent = _members.where((m) => m.status == 'Absent').length;
    final notPunched = _members.where((m) => m.status == 'Awaiting Punch').length;
    final day = parseDateOnly(_companyDate) ?? DateTime.now();

    return RefreshIndicator(
      color: _K.indigo600,
      onRefresh: () => _load(refresh: true),
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
              dateText: '${formatEEEE(day)}, ${formatMMMM(day)} ${formatDD(day)}, ${day.year}',
              notPunched: notPunched,
              updatedAt: _updatedAt,
              refreshing: _refreshing,
              onRefresh: () => _load(refresh: true),
            ),
            if (_loadError != null)
              _Banner(
                tone: const _Tone(_K.rose50, _K.rose200, _K.rose700),
                icon: Icons.error_outline_rounded,
                actionLabel: 'Retry',
                onAction: () => _load(refresh: true),
                child: Text('${_loadError!} Showing the last update.'),
              ),
            _Grid(
              columns: lg ? 4 : 2,
              gap: 12,
              children: [
                _KpiCard(
                  label: 'Team members',
                  value: _totalEmployees,
                  icon: Icons.groups_outlined,
                  tone: _indigo,
                  onTap: _filter == 'ALL' ? null : () => setState(() => _filter = 'ALL'),
                ),
                _KpiCard(
                  label: 'Present',
                  value: present,
                  icon: Icons.how_to_reg_outlined,
                  tone: _emerald,
                  active: _filter == 'Present',
                  onTap: () => _toggleFilter('Present'),
                ),
                _KpiCard(
                  label: 'Late',
                  value: late,
                  icon: Icons.schedule_rounded,
                  tone: _amber,
                  active: _filter == 'Late',
                  onTap: () => _toggleFilter('Late'),
                ),
                _KpiCard(
                  label: 'Absent',
                  value: absent,
                  icon: Icons.person_off_outlined,
                  tone: _rose,
                  active: _filter == 'Absent',
                  onTap: () => _toggleFilter('Absent'),
                ),
              ],
            ),
            _membersCard(filtered: filtered, counts: counts, sm: sm, md: md, lg: lg),
          ];

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(sm ? 24 : 16),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
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

  Widget _membersCard({
    required List<(int, TeamMember)> filtered,
    required Map<String, int> counts,
    required bool sm,
    required bool md,
    required bool lg,
  }) {
    final search = ValueListenableBuilder<TextEditingValue>(
      valueListenable: _searchCtrl,
      builder: (context, value, _) => TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _search = v),
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14, color: _K.gray900),
        decoration: InputDecoration(
          hintText: 'Search name, code or designation',
          hintStyle: const TextStyle(fontSize: 14, color: _K.gray400),
          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: _K.gray400),
          prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 20),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _search = '');
                  },
                  icon: const Icon(Icons.close_rounded, size: 16, color: _K.gray400),
                ),
          filled: true,
          fillColor: _K.gray50,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _K.gray200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _K.gray200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _K.indigo500, width: 1.5),
          ),
        ),
      ),
    );

    final sort = PopupMenuButton<bool>(
      tooltip: 'Sort members',
      initialValue: _sortByStatus,
      onSelected: (v) => setState(() => _sortByStatus = v),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      itemBuilder: (_) => const [
        PopupMenuItem(value: false, child: Text('Sort by name', style: TextStyle(fontSize: 13))),
        PopupMenuItem(value: true, child: Text('Needs attention first', style: TextStyle(fontSize: 13))),
      ],
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _K.gray200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, size: 16, color: _K.gray500),
            const SizedBox(width: 6),
            Text(
              _sortByStatus ? 'Attention first' : 'Name',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _K.gray700),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded, size: 16, color: _K.gray400),
          ],
        ),
      ),
    );

    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, (value, label)) in _filters.indexed)
            if (i == 0 || (counts[value] ?? 0) > 0 || _filter == value) ...[
              if (i > 0) const SizedBox(width: 6),
              _FilterChip(
                label: label,
                count: counts[value] ?? 0,
                selected: _filter == value,
                onTap: () => setState(() => _filter = value),
              ),
            ],
        ],
      ),
    );

    final hasQuery = _search.trim().isNotEmpty || _filter != 'ALL';

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
                if (sm)
                  Row(
                    children: [
                      Expanded(child: search),
                      const SizedBox(width: 10),
                      sort,
                    ],
                  )
                else ...[
                  search,
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerLeft, child: sort),
                ],
                const SizedBox(height: 10),
                chips,
              ],
            ),
          ),
          SizedBox(
            height: 2,
            child: _refreshing
                ? const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50)
                : const ColoredBox(color: _K.gray100),
          ),
          if (md && filtered.isNotEmpty)
            Container(
              color: _K.gray50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: _tableRow(
                lg: lg,
                cells: const [
                  Text('Member', style: _T.columnHead),
                  Text('Department', style: _T.columnHead),
                  Text('Status', style: _T.columnHead),
                  Text('First in', style: _T.columnHead),
                  Text('Last out', style: _T.columnHead),
                  Text('Late', style: _T.columnHead),
                ],
              ),
            ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: _members.isEmpty
                  ? const _EmptyState(
                      icon: Icons.group_off_outlined,
                      title: 'No team members assigned',
                      message: 'Members appear here once HR assigns them to you.',
                    )
                  : _EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No members match',
                      message: 'Try another name or status.',
                      action: hasQuery ? _LinkButton(label: 'Clear search and filters', onTap: _clearAll) : null,
                    ),
            )
          else
            AnimatedOpacity(
              opacity: _refreshing ? 0.6 : 1,
              duration: const Duration(milliseconds: 150),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < filtered.length; i++) ...[
                    if (i > 0) _divider,
                    md
                        ? _MemberTableRow(member: filtered[i].$2, colorIndex: filtered[i].$1, lg: lg)
                        : _MemberRow(member: filtered[i].$2, colorIndex: filtered[i].$1),
                  ],
                ],
              ),
            ),
          if (_members.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.gray100))),
              child: Text(
                'Showing ${filtered.length} of ${_members.length} team member${_members.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, color: _K.gray500, fontFeatures: _T.tabular),
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
    required this.dateText,
    required this.notPunched,
    required this.updatedAt,
    required this.refreshing,
    required this.onRefresh,
  });

  final bool wide;
  final String dateText;
  final int notPunched;
  final DateTime? updatedAt;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final updated = updatedAt != null ? 'Updated ${TimeOfDay.fromDateTime(updatedAt!).format(context)}' : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _IconBox(icon: Icons.fact_check_outlined, tone: _indigo, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Team attendance',
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
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Today, $dateText', style: _T.subtitle),
                  if (notPunched > 0)
                    _MiniChip(text: '$notPunched not punched in yet', tone: _gray, icon: Icons.hourglass_empty_rounded),
                  if (updated != null) Text(updated, style: const TextStyle(fontSize: 11, color: _K.gray400)),
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
                onPressed: refreshing ? null : onRefresh,
                icon: refreshing
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
                onPressed: refreshing ? null : onRefresh,
                icon: refreshing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, size: 18, color: _K.gray600),
              ),
      ],
    );
  }
}

// ── KPI cards ───────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    this.onTap,
    this.active = false,
  });

  final String label;
  final int value;
  final IconData icon;
  final _Tone tone;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      selected: active,
      label: '$label: $value${onTap != null ? (active ? ', filter on' : ', tap to filter') : ''}',
      excludeSemantics: true,
      child: _Surface(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        color: active ? tone.bg : Colors.white,
        borderColor: active ? tone.border : _K.gray100,
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
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      height: 1.15,
                      color: _K.gray900,
                      fontFeatures: _T.tabular,
                    ),
                  ),
                ],
              ),
            ),
            if (active) Icon(Icons.filter_alt_rounded, size: 16, color: tone.fg),
          ],
        ),
      ),
    );
  }
}

// ── Members ─────────────────────────────────────────────────────────────────

/// Table column flex values: member, department, status, first in,
/// last out (lg), late (lg).
Widget _tableRow({required bool lg, required List<Widget> cells}) {
  const flex = [4, 3, 3, 2, 2, 2];
  final count = lg ? 6 : 4;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      for (var i = 0; i < count; i++) ...[
        if (i > 0) const SizedBox(width: 12),
        Expanded(flex: flex[i], child: cells[i]),
      ],
    ],
  );
}

class _MemberTableRow extends StatelessWidget {
  const _MemberTableRow({required this.member, required this.colorIndex, required this.lg});

  final TeamMember member;
  final int colorIndex;
  final bool lg;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final where = [
      if (m.departmentName.isNotEmpty) m.departmentName,
      if (lg && m.branchName.isNotEmpty) m.branchName,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: _tableRow(
        lg: lg,
        cells: [
          _MemberIdentity(member: m, colorIndex: colorIndex),
          where.isEmpty
              ? const Text('—', style: TextStyle(fontSize: 13, color: _K.gray300))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(where.first, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: _K.gray700)),
                    if (where.length > 1)
                      Text(where[1], maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: _K.gray400)),
                  ],
                ),
          _StatusCell(member: m),
          _TimeText(m.firstIn, icon: Icons.login_rounded, iconColor: _K.emerald500),
          _TimeText(m.lastOut, icon: Icons.logout_rounded, iconColor: _K.amber500),
          _LateCell(member: m),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.colorIndex});

  final TeamMember member;
  final int colorIndex;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final cfg = _statusOf(m);
    final punch = punchStatusMeta(m.punchStatus);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _MemberIdentity(member: m, colorIndex: colorIndex, showDepartment: true)),
              const SizedBox(width: 8),
              _StatusBadge(status: cfg),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 42),
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _TimeText(m.firstIn, icon: Icons.login_rounded, iconColor: _K.emerald500, label: 'In'),
                _TimeText(m.lastOut, icon: Icons.logout_rounded, iconColor: _K.amber500, label: 'Out'),
                if (m.isLate) _MiniChip(text: 'Late in ${m.lateMinutes}m', tone: _amber),
                if (m.lateAfterLunchMinutes > 0) _MiniChip(text: 'After lunch ${m.lateAfterLunchMinutes}m', tone: _orange),
                if (punch != null)
                  Tooltip(
                    message: punch.hint ?? '',
                    triggerMode: TooltipTriggerMode.tap,
                    child: _MiniChip(
                      text: punch.label,
                      tone: _Tone(punch.style.bg, punch.style.border, punch.style.fg),
                      icon: Icons.info_outline_rounded,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberIdentity extends StatelessWidget {
  const _MemberIdentity({required this.member, required this.colorIndex, this.showDepartment = false});

  final TeamMember member;
  final int colorIndex;
  final bool showDepartment;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final sub = [
      if (m.employeeCode.isNotEmpty) '#${m.employeeCode}',
      if (m.designation.isNotEmpty) m.designation,
      if (showDepartment && m.departmentName.isNotEmpty) m.departmentName,
    ].join(', ');

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _avatarGradients[colorIndex % _avatarGradients.length],
            ),
          ),
          child: Text(
            _initials(m.name),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray900),
              ),
              if (sub.isNotEmpty)
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _K.gray500, fontFeatures: _T.tabular),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusCell extends StatelessWidget {
  const _StatusCell({required this.member});

  final TeamMember member;

  @override
  Widget build(BuildContext context) {
    final punch = punchStatusMeta(member.punchStatus);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        _StatusBadge(status: _statusOf(member)),
        if (punch != null)
          Tooltip(
            message: punch.hint ?? '',
            child: _MiniChip(
              text: punch.label,
              tone: _Tone(punch.style.bg, punch.style.border, punch.style.fg),
            ),
          ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final _Status status;

  @override
  Widget build(BuildContext context) {
    final t = status.tone;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 12, color: t.fg),
          const SizedBox(width: 4),
          Text(status.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.fg)),
        ],
      ),
    );
  }
}

class _TimeText extends StatelessWidget {
  const _TimeText(this.value, {required this.icon, required this.iconColor, this.label});

  final String? value;
  final IconData icon;
  final Color iconColor;

  /// Shown before the time on phones ("In 09:02 AM").
  final String? label;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final empty = v == null || v.isEmpty;
    return Semantics(
      label: '${label ?? ''} ${empty ? 'no punch' : v}'.trim(),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: empty ? _K.gray300 : iconColor),
          const SizedBox(width: 4),
          if (label != null) ...[
            Text(label!, style: const TextStyle(fontSize: 12, color: _K.gray400)),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                empty ? '--' : v,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: empty ? FontWeight.w400 : FontWeight.w600,
                  color: empty ? _K.gray300 : _K.gray700,
                  fontFeatures: _T.tabular,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LateCell extends StatelessWidget {
  const _LateCell({required this.member});

  final TeamMember member;

  @override
  Widget build(BuildContext context) {
    final m = member;
    if (!m.isLate && m.lateAfterLunchMinutes <= 0) {
      return const Text('—', style: TextStyle(fontSize: 13, color: _K.gray300));
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (m.isLate) _MiniChip(text: '+${m.lateMinutes}m in', tone: _amber),
        if (m.lateAfterLunchMinutes > 0) _MiniChip(text: '+${m.lateAfterLunchMinutes}m lunch', tone: _orange),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.count, required this.selected, required this.onTap});

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? _K.indigo600 : _K.gray600;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? _K.indigo50 : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? _K.indigo200 : _K.gray200)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: selected ? _K.indigo500 : _K.gray400,
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

// ── First-load failure ──────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry, required this.onRefresh});

  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: _K.indigo600,
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, c) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: _EmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Could not load team attendance',
                      message: 'Check your connection, then retry or pull down to refresh.',
                      action: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _K.indigo600,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry'),
                      ),
                    ),
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

// ── Loading skeleton ────────────────────────────────────────────────────────

class _PageSkeleton extends StatelessWidget {
  const _PageSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading team attendance',
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
                            _Bone(width: 180, height: 18),
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
                    const _Bone(height: 380),
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
          Text(
            text,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: tone.fg, fontFeatures: _T.tabular),
          ),
        ],
      ),
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
        color: _K.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _K.gray200),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: _K.gray100, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: _K.gray400),
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
          if (action != null) ...[const SizedBox(height: 10), action!],
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
          children: [
            Icon(icon, size: 18, color: tone.fg),
            const SizedBox(width: 10),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(fontSize: 13, height: 1.4, color: tone.fg),
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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