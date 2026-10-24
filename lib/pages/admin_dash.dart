// Port of features/admin/dashboard/AdminDashboard.tsx
// (the "/" screen for HR / branch staff).
//
// LiveDashboardView handles loading, polling and spacing; this file supplies
// the sections. The live feed, trends and violations cards are the shared
// ones from live_dash.dart.
//
// Compact layout:
//   Header: icon · title · date · live (one line)
//   KPIs: 5 equal-height cards (icon + label/value on one row, one footer line)
//         tablet and wide: 5 across · phones: attendance rate full width, then 2×2
//         Tap a card for the people (or violations) behind its number
//   Live feed · Trends · Violations (shared cards)
//   Branches: one row per branch (name · bar · rate), 2 columns on wide
//   screens, the 6 that need attention first, "Show all" for the rest

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hrm_app/api/api_client.dart';
import 'package:hrm_app/components/dashboard/live_dash.dart';
import 'package:hrm_app/components/ui/app_card.dart';
import 'package:hrm_app/services/admindash_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';

// ── Design tokens ───────────────────────────────────────────────────────────

/// A tinted color set: soft background, border, and foreground.
class _Tone {
  const _Tone(this.bg, this.border, this.fg);

  final Color bg;
  final Color border;
  final Color fg;
}

const _indigo = _Tone(Color(0xFFEEF2FF), Color(0xFFC7D2FE), Color(0xFF6366F1));
const _emerald = _Tone(Color(0xFFECFDF5), Color(0xFFA7F3D0), Color(0xFF10B981));
const _teal = _Tone(Color(0xFFF0FDFA), Color(0xFF99F6E4), Color(0xFF14B8A6));
const _yellow = _Tone(Color(0xFFFEFCE8), Color(0xFFFEF08A), Color(0xFFCA8A04));
const _red = _Tone(Color(0xFFFEF2F2), Color(0xFFFECACA), Color(0xFFEF4444));
const _purple = _Tone(Color(0xFFFAF5FF), Color(0xFFE9D5FF), DashK.purple500);

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const label = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, height: 1.2, color: DashK.gray500);
  static const caption = TextStyle(fontSize: 11, height: 1.25, color: DashK.gray400);
  static const value = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    height: 1.2,
    color: DashK.gray900,
    fontFeatures: tabular,
  );
}

const _cardPadding = EdgeInsets.fromLTRB(12, 11, 12, 10);

/// How many branches show before "Show all".
const _branchPreview = 6;

/// Attendance-rate thresholds used across the page.
({Color text, Color bar, String label, IconData icon}) _rateLevel(double rate) {
  if (rate >= 90) return (text: DashK.emerald600, bar: DashK.emerald500, label: 'On track', icon: Icons.trending_up_rounded);
  if (rate >= 75) return (text: DashK.yellow600, bar: DashK.yellow500, label: 'Fair', icon: Icons.trending_flat_rounded);
  return (text: DashK.red600, bar: DashK.red500, label: 'Low', icon: Icons.trending_down_rounded);
}

// ── Dashboard ───────────────────────────────────────────────────────────────

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return LiveDashboardView(
      sections: (context, data, width, openPunchLog) {
        final sm = width >= 640;
        final md = width >= 768;
        final lg = width >= 1024;
        return [
          _Header(wide: sm),
          _kpis(context, data.kpis, md: md),
          LiveFeedCard(
            punches: data.recentPunches,
            columns: lg ? 3 : (md ? 2 : 1),
            onViewAll: openPunchLog,
          ),
          const TrendsCard(),
          ViolationsCard(violations: data.recentViolations, wide: sm),
          if (data.branchStats.isNotEmpty) _BranchCard(branches: data.branchStats, columns: lg ? 2 : 1),
        ];
      },
    );
  }

  Widget _kpis(BuildContext context, DashboardKpis k, {required bool md}) {
    void open(_Detail kind) => _showKpiDetails(context, kind);

    final others = [
      _KpiCard(
        label: 'Employees',
        value: '${k.totalEmployees}',
        footer: const Text('Active staff', maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.caption),
        icon: Icons.groups_outlined,
        tone: _indigo,
        semantics: 'Active staff',
        onTap: () => open(_Detail.workforce),
      ),
      _KpiCard(
        label: 'Present now',
        value: '${k.presentToday}',
        footer: const Text('On site today', maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.caption),
        icon: Icons.how_to_reg_outlined,
        tone: _teal,
        semantics: 'On site today',
        onTap: () => open(_Detail.present),
      ),
      _KpiCard(
        label: 'Late in',
        value: '${k.lateToday}',
        footer: Text(
          '${k.lateAfterLunchToday} after lunch',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _T.caption,
        ),
        icon: Icons.schedule_rounded,
        tone: _yellow,
        semantics: '${k.lateAfterLunchToday} late after lunch',
        onTap: () => open(_Detail.punctuality),
      ),
      _KpiCard(
        label: 'Violations',
        value: '${k.activeViolations}',
        footer: Text(
          k.activeViolations > 0 ? 'Need action' : 'None open',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _T.caption.copyWith(color: k.activeViolations > 0 ? DashK.red600 : DashK.gray400),
        ),
        icon: Icons.gpp_maybe_outlined,
        tone: _red,
        highlight: k.activeViolations > 0,
        semantics: k.activeViolations > 0 ? 'Need action' : 'None open',
        onTap: () => open(_Detail.violations),
      ),
    ];
    final rate = _rateCard(k, onTap: () => open(_Detail.rate));

    if (md) {
      return DashGrid(columns: 5, gap: 10, children: [others[0], others[1], rate, others[2], others[3]]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        rate,
        const SizedBox(height: 10),
        DashGrid(columns: 2, gap: 10, children: others),
      ],
    );
  }

  /// Attendance rate as a KPI card: trend icon next to the value, bar as the footer.
  Widget _rateCard(DashboardKpis k, {required VoidCallback onTap}) {
    final level = _rateLevel(k.attendanceRate);
    return _KpiCard(
      label: 'Attendance',
      value: '${k.attendanceRate.toStringAsFixed(1)}%',
      valueColor: level.text,
      badge: Tooltip(message: level.label, child: Icon(level.icon, size: 15, color: level.text)),
      footer: Row(
        children: [
          Expanded(child: _RateBar(rate: k.attendanceRate, color: level.bar, height: 4)),
          const SizedBox(width: 8),
          Text(
            '${k.presentToday}/${k.totalEmployees}',
            style: _T.caption.copyWith(fontFeatures: _T.tabular),
          ),
        ],
      ),
      icon: Icons.check_circle_outline_rounded,
      tone: _emerald,
      semantics: '${level.label}, ${k.presentToday} of ${k.totalEmployees} present',
      onTap: onTap,
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.wide});

  final bool wide;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final date = '${_weekdays[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}';

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: DashK.indigo50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DashK.indigo200),
          ),
          child: const Icon(Icons.space_dashboard_outlined, size: 18, color: DashK.indigo600),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Workforce overview',
                  style: TextStyle(
                    fontSize: wide ? 19 : 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    height: 1.3,
                    color: DashK.gray900,
                  ),
                ),
              ),
              Text(date, style: const TextStyle(fontSize: 12, height: 1.3, color: DashK.gray500)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: DashK.emerald50,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: DashK.emerald200),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DashPulse(child: DashDot(color: DashK.emerald500)),
              SizedBox(width: 5),
              Text('Live', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: DashK.emerald600)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── KPI cards ───────────────────────────────────────────────────────────────

/// Icon + label/value on one row, then a single footer line (text or bar),
/// so every card in the strip has the same height. Tapping opens the details.
class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.footer,
    required this.icon,
    required this.tone,
    required this.semantics,
    required this.onTap,
    this.valueColor,
    this.badge,
    this.highlight = false,
  });

  final String label;
  final String value;
  final Widget footer;
  final IconData icon;
  final _Tone tone;

  /// Spoken after the label and value.
  final String semantics;
  final VoidCallback onTap;
  final Color? valueColor;

  /// Shown right after the value (the rate trend icon).
  final Widget? badge;

  /// Colors the number (used for open violations).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = valueColor ?? (highlight ? tone.fg : DashK.gray900);

    return Semantics(
      container: true,
      button: true,
      label: '$label: $value. $semantics',
      hint: 'Show details',
      excludeSemantics: true,
      onTap: onTap,
      child: Stack(
        children: [
          AppCard(
            padding: _cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _IconBox(icon: icon, tone: tone),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.label),
                          Row(
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(value, style: _T.value.copyWith(color: color)),
                                ),
                              ),
                              if (badge != null) ...[const SizedBox(width: 4), badge!],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // The web's ↗ "open details" marker.
                    const Icon(Icons.arrow_outward_rounded, size: 14, color: DashK.gray400),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(height: 14, child: Align(alignment: Alignment.centerLeft, child: footer)),
              ],
            ),
          ),
          // Ripple on top of the card.
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RateBar extends StatelessWidget {
  const _RateBar({required this.rate, required this.color, this.height = 4});

  final double rate;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: DashK.gray100)),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (rate / 100).clamp(0.0, 1.0).toDouble()),
              duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, f, __) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: f,
                heightFactor: 1,
                child: ColoredBox(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── KPI details (the web's KpiDetailModal) ──────────────────────────────────

enum _Detail {
  workforce('Active workforce', 'Every active employee and their status today', Icons.groups_outlined, _indigo),
  present('Present staff', 'Employees who have attended today', Icons.how_to_reg_outlined, _teal),
  rate('Attendance rate', 'Who is present and who is absent today', Icons.check_circle_outline_rounded, _emerald),
  punctuality('Late arrivals', 'Late in the morning or back late from lunch today', Icons.schedule_rounded, _yellow),
  violations('Violations', 'Punch issues recorded for today', Icons.gpp_maybe_outlined, _red);

  const _Detail(this.title, this.subtitle, this.icon, this.tone);

  final String title;
  final String subtitle;
  final IconData icon;
  final _Tone tone;
}

const _presentTypes = ['PRESENT', 'FULL_DAY', 'HALF_DAY'];

/// One employee's day, as the details list needs it.
class _DayRow {
  const _DayRow(this.j);

  final Map<String, dynamic> j;

  int get employeeId => (j['employee_id'] as num?)?.toInt() ?? 0;
  String get code => '${j['employee_code'] ?? ''}';
  String get name => '${j['employee_name'] ?? ''}';
  String get branch => '${j['branch_name'] ?? ''}';
  String get department => '${j['department_name'] ?? ''}';
  String get dayType => '${j['day_type'] ?? ''}';
  String? get leaveName => j['leave_name'] as String?;
  String? get punchStatus => j['punch_status'] as String?;
  String? get firstIn => j['first_in'] as String?;
  String? get lastOut => j['last_out'] as String?;
  int get lateMinutes => (j['late_minutes'] as num?)?.toInt() ?? 0;
  int get lateAfterLunch => (j['late_after_lunch_minutes'] as num?)?.toInt() ?? 0;
  bool get isPresent => _presentTypes.contains(dayType);
}

/// One of today's violations, as the details list needs it.
class _ViolationRow {
  const _ViolationRow(this.j);

  final Map<String, dynamic> j;

  int get employeeId => (j['employee_id'] as num?)?.toInt() ?? 0;
  String get code => '${j['employee_code'] ?? ''}';
  String get name => '${j['employee_name'] ?? ''}';
  String get label {
    final l = '${j['violation_label'] ?? ''}';
    return l.isNotEmpty ? l : '${j['violation_type'] ?? ''}';
  }

  String get description => '${j['description'] ?? ''}';
  String? get occurredAt => j['occurred_at'] as String?;
}

void _showKpiDetails(BuildContext context, _Detail kind) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    constraints: const BoxConstraints(maxWidth: 768),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _KpiDetailSheet(kind: kind, date: toDateKey(DateTime.now())),
  );
}

class _KpiDetailSheet extends StatefulWidget {
  const _KpiDetailSheet({required this.kind, required this.date});

  final _Detail kind;

  /// YYYY-MM-DD (today on the phone).
  final String date;

  @override
  State<_KpiDetailSheet> createState() => _KpiDetailSheetState();
}

class _KpiDetailSheetState extends State<_KpiDetailSheet> {
  List<_DayRow> _rows = const [];
  List<_ViolationRow> _violations = const [];
  bool _loading = true;
  String? _error;
  String _search = '';
  String _rateFilter = 'ALL'; // ALL | PRESENT | ABSENT

  _Detail get _kind => widget.kind;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _results(dynamic data) {
    final list = data is Map ? data['results'] : data;
    return list is List ? [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)] : const [];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_kind == _Detail.violations) {
        final res = await api.get('/core/attendance/violations/', queryParameters: {
          'start_date': widget.date,
          'end_date': widget.date,
          'page_size': 500,
        });
        if (mounted) setState(() => _violations = [for (final r in _results(res.data)) _ViolationRow(r)]);
      } else {
        final res = await api.get('/core/attendance/summaries/', queryParameters: {
          'date': widget.date,
          'status': _kind == _Detail.present ? 'PRESENT' : 'ALL',
          'page_size': 1000,
        });
        if (mounted) setState(() => _rows = [for (final r in _results(res.data)) _DayRow(r)]);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the details. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _matches(String name, String code) {
    final q = _search.trim().toLowerCase();
    return q.isEmpty || name.toLowerCase().contains(q) || code.toLowerCase().contains(q);
  }

  void _openEmployee(int id) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go('/admin/employees/$id');
  }

  @override
  Widget build(BuildContext context) {
    // Filter the list the same way as the web pop-up.
    var list = _rows;
    if (_kind == _Detail.punctuality) {
      list = list.where((r) => r.isPresent && (r.lateMinutes > 0 || r.lateAfterLunch > 0)).toList();
    } else if (_kind == _Detail.rate) {
      list = list.where((r) => r.isPresent || r.dayType == 'ABSENT').toList();
      if (_rateFilter == 'PRESENT') list = list.where((r) => r.isPresent).toList();
      if (_rateFilter == 'ABSENT') list = list.where((r) => r.dayType == 'ABSENT').toList();
    }
    list = list.where((r) => _matches(r.name, r.code)).toList();
    final shownViolations = _violations.where((v) => _matches(v.name, v.code)).toList();
    final count = _kind == _Detail.violations ? shownViolations.length : list.length;

    final presentN = _rows.where((r) => r.isPresent).length;
    final absentN = _rows.where((r) => r.dayType == 'ABSENT').length;
    final expected = presentN + absentN;
    final rate = expected > 0 ? (1000 * presentN / expected).round() / 10 : 0.0;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
              child: Row(
                children: [
                  _IconBox(icon: _kind.icon, tone: _kind.tone, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: _kind.title,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: DashK.gray900),
                            ),
                            if (!_loading)
                              TextSpan(
                                text: '  $count',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: DashK.gray400),
                              ),
                          ]),
                        ),
                        Text(_kind.subtitle, style: const TextStyle(fontSize: 12, color: DashK.gray500)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: DashK.gray400),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: DashK.gray100),

            // Search + rate filter
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search name or employee code',
                  hintStyle: const TextStyle(fontSize: 14, color: DashK.gray400),
                  prefixIcon: const Icon(Icons.search, size: 18, color: DashK.gray400),
                  filled: true,
                  fillColor: DashK.gray50,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: DashK.gray200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: DashK.indigo600),
                  ),
                ),
              ),
            ),
            if (_kind == _Detail.rate) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (key, text) in [
                      ('ALL', 'All ($expected)'),
                      ('PRESENT', 'Present ($presentN)'),
                      ('ABSENT', 'Absent ($absentN)'),
                    ])
                      _FilterChip(label: text, selected: _rateFilter == key, onTap: () => setState(() => _rateFilter = key)),
                  ],
                ),
              ),
              if (!_loading && _error == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('$presentN present of $expected expected',
                                style: const TextStyle(fontSize: 12, color: DashK.gray500)),
                          ),
                          Text('$rate%',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: DashK.emerald600)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: (rate / 100).clamp(0.0, 1.0).toDouble(),
                          minHeight: 8,
                          color: DashK.emerald500,
                          backgroundColor: const Color(0xFFFEE2E2),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),

            // List
            Expanded(child: _list(list, shownViolations, count)),

            // Footer
            const Divider(height: 1, color: DashK.gray100),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Text(
                  'Tap a row to open the employee. Showing ${widget.date}.',
                  style: const TextStyle(fontSize: 11, color: DashK.gray400),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<_DayRow> rows, List<_ViolationRow> violations, int count) {
    if (_loading) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, __) => Container(
          height: 48,
          decoration: BoxDecoration(color: DashK.gray100, borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
    if (_error != null) {
      return Center(child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: DashK.red600)));
    }
    if (count == 0) {
      return Center(
        child: Text(
          _search.trim().isNotEmpty ? 'No matches.' : 'Nothing to show for today.',
          style: const TextStyle(fontSize: 14, color: DashK.gray400),
        ),
      );
    }

    if (_kind == _Detail.violations) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: violations.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: DashK.gray50),
        itemBuilder: (_, i) {
          final v = violations[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openEmployee(v.employeeId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: DashK.red50,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: _red.border),
                    ),
                    child: Text(v.label,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFB91C1C))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(TextSpan(
                          text: v.name,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: DashK.gray900),
                          children: [
                            TextSpan(
                              text: '  ${v.code}',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                color: DashK.gray400,
                              ),
                            ),
                          ],
                        )),
                        if (v.description.isNotEmpty)
                          Text(v.description, style: const TextStyle(fontSize: 12, color: DashK.gray500)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    v.occurredAt != null ? fmtWallTime(v.occurredAt) : '',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: DashK.gray500),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: DashK.gray50),
      itemBuilder: (_, i) => _personRow(rows[i]),
    );
  }

  Widget _personRow(_DayRow r) {
    final status = attendanceStatus(r.dayType, r.punchStatus, r.leaveName);
    final initials = r.name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.characters.first)
        .join()
        .toUpperCase();
    final where = r.department.isNotEmpty && r.department != '—' ? r.department : r.branch;

    Widget? trailing;
    if (_kind == _Detail.punctuality) {
      trailing = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (r.lateMinutes > 0)
            Text('${fmtMinutes(r.lateMinutes)} late in · ${fmtWallTime(r.firstIn)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: DashK.red600)),
          if (r.lateAfterLunch > 0)
            Text('${fmtMinutes(r.lateAfterLunch)} late after lunch',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFEA580C))),
        ],
      );
    } else if (r.firstIn != null && r.firstIn!.isNotEmpty) {
      trailing = Text(
        '${fmtWallTime(r.firstIn)} – ${lastOutText(lastOut: r.lastOut, punchStatus: r.punchStatus)}',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: DashK.gray600),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openEmployee(r.employeeId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: DashK.indigo50, shape: BoxShape.circle),
              child: Text(initials, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: DashK.indigo600)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: DashK.gray900)),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: r.code, style: const TextStyle(fontFamily: 'monospace')),
                      TextSpan(text: ' · $where'),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: DashK.gray500),
                  ),
                  if (trailing != null) ...[const SizedBox(height: 2), trailing],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: status.hint ?? '',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: status.style.bg,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: status.style.border),
                ),
                child: Text(status.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: status.style.fg)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(side: BorderSide(color: selected ? DashK.gray900 : DashK.gray200));
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? DashK.gray900 : Colors.white,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : DashK.gray600),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Branch performance ──────────────────────────────────────────────────────

class _BranchCard extends StatefulWidget {
  const _BranchCard({required this.branches, required this.columns});

  final List<BranchStat> branches;
  final int columns;

  @override
  State<_BranchCard> createState() => _BranchCardState();
}

class _BranchCardState extends State<_BranchCard> {
  /// Lowest attendance first, so the branches that need attention lead.
  bool _lowestFirst = true;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.branches]
      ..sort((a, b) => _lowestFirst
          ? a.attendanceRate.compareTo(b.attendanceRate)
          : a.branchName.toLowerCase().compareTo(b.branchName.toLowerCase()));
    final shown = _showAll ? sorted : sorted.take(_branchPreview).toList();
    final hidden = sorted.length - shown.length;
    final canCollapse = _showAll && sorted.length > _branchPreview;
    final low = widget.branches.where((b) => b.attendanceRate < 75).length;

    // Split into columns, filling top to bottom.
    final perColumn = (shown.length / widget.columns).ceil();
    final columns = [
      for (var c = 0; c < widget.columns; c++) shown.skip(c * perColumn).take(perColumn).toList(),
    ];

    return AppCard(
      padding: _cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _IconBox(icon: Icons.apartment_rounded, tone: _purple),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(
                      text: 'Branches',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: DashK.gray900),
                    ),
                    TextSpan(
                      text: '  ${widget.branches.length}${low > 0 ? ', $low below 75%' : ''}',
                      style: TextStyle(fontSize: 12, color: low > 0 ? DashK.red600 : DashK.gray500),
                    ),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PopupMenuButton<bool>(
                tooltip: 'Sort branches',
                initialValue: _lowestFirst,
                position: PopupMenuPosition.under,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                onSelected: (v) => setState(() => _lowestFirst = v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: true, child: Text('Lowest attendance first', style: TextStyle(fontSize: 13))),
                  PopupMenuItem(value: false, child: Text('Name (A–Z)', style: TextStyle(fontSize: 13))),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sort_rounded, size: 15, color: DashK.gray500),
                      const SizedBox(width: 4),
                      Text(
                        _lowestFirst ? 'Lowest first' : 'A–Z',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: DashK.gray600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < columns.length; c++) ...[
                if (c > 0) const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [
                      for (var i = 0; i < columns[c].length; i++) ...[
                        if (i > 0) const Divider(height: 1, thickness: 1, color: DashK.gray100),
                        _BranchRow(key: ValueKey(columns[c][i].branchName), branch: columns[c][i]),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (hidden > 0 || canCollapse)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: DashK.indigo600,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                onPressed: () => setState(() => _showAll = !_showAll),
                child: Text(_showAll ? 'Show fewer' : 'Show all ($hidden more)'),
              ),
            ),
        ],
      ),
    );
  }
}

/// One branch on one line: name and headcount · bar · rate.
class _BranchRow extends StatelessWidget {
  const _BranchRow({super.key, required this.branch});

  final BranchStat branch;

  @override
  Widget build(BuildContext context) {
    final rate = branch.attendanceRate;
    final level = _rateLevel(rate);

    return Semantics(
      label: '${branch.branchName}: ${rate.toStringAsFixed(0)} percent attendance, '
          '${branch.presentToday} of ${branch.employeeCount} present',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    branch.branchName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.25, color: DashK.gray900),
                  ),
                  Text(
                    '${branch.presentToday}/${branch.employeeCount} present',
                    style: const TextStyle(fontSize: 11, height: 1.25, color: DashK.gray500, fontFeatures: _T.tabular),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(flex: 4, child: _RateBar(rate: rate, color: level.bar, height: 5)),
            SizedBox(
              width: 44,
              child: Text(
                '${rate.toStringAsFixed(0)}%',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: level.text, fontFeatures: _T.tabular),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small pieces ────────────────────────────────────────────────────────────

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, required this.tone, this.size = 30});

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
      child: Icon(icon, size: size * 0.52, color: tone.fg),
    );
  }
}