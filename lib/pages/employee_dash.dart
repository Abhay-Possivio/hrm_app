// Port of features/employee/dashboard/EmployeeDashboard.tsx
// (the home screen for employees, and "My Personal Dashboard" for team leads).
//
// Profile, this month's attendance and violations load once; today's punches
// refresh every 10 s (paused while the app is in the background).
//
// Compact layout:
//   [banners]
//   Header (one line): avatar · greeting · details · live · date
//   KPIs: Check in | Check out | Worked (shift bar) | Status   (equal height)
//   Today's punches (3) | My shift + Month summary (2)
//   Recent attendance   | Compliance alerts

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:hrm_app/auth/auth_store.dart';
import 'package:hrm_app/components/auth/pass_reset.dart';
import 'package:hrm_app/components/dashboard/live_dash.dart';
import 'package:hrm_app/services/empportal_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';

// ── Design tokens ───────────────────────────────────────────────────────────

// Tailwind colors only this screen uses (the rest come from DashK).
class _K {
  static const emerald100 = Color(0xFFD1FAE5);
  static const teal50 = Color(0xFFF0FDFA);
  static const teal200 = Color(0xFF99F6E4);
  static const teal600 = Color(0xFF0D9488);
  static const amber400 = Color(0xFFFBBF24);
  static const red400 = Color(0xFFF87171);
  static const orange50 = Color(0xFFFFF7ED);
  static const orange200 = Color(0xFFFED7AA);
  static const orange600 = Color(0xFFEA580C);
}

/// A tinted color set: soft background, border, and foreground.
class _Tone {
  const _Tone(this.bg, this.border, this.fg);

  final Color bg;
  final Color border;
  final Color fg;
}

const _emerald = _Tone(DashK.emerald50, DashK.emerald200, DashK.emerald600);
const _teal = _Tone(_K.teal50, _K.teal200, _K.teal600);
const _indigo = _Tone(DashK.indigo50, DashK.indigo200, DashK.indigo600);
const _amber = _Tone(DashK.amber50, DashK.amber200, DashK.amber600);
const _red = _Tone(DashK.red50, DashK.red200, DashK.red500);
const _orange = _Tone(_K.orange50, _K.orange200, _K.orange600);
const _gray = _Tone(DashK.gray100, DashK.gray200, DashK.gray500);

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.3, color: DashK.gray900);
  static const subtitle = TextStyle(fontSize: 11.5, height: 1.3, color: DashK.gray500);
  static const label = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, height: 1.2, color: DashK.gray500);
  static const caption = TextStyle(fontSize: 11, height: 1.25, color: DashK.gray400);
  static const body = TextStyle(fontSize: 12.5, height: 1.4, color: DashK.gray600);
  static const value = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    height: 1.2,
    color: DashK.gray900,
    fontFeatures: tabular,
  );
  static const time = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    color: DashK.gray700,
    fontFeatures: tabular,
  );
}

const _cardRadius = 14.0;
const _cardPadding = EdgeInsets.fromLTRB(12, 11, 12, 10);
const _divider = Divider(height: 1, thickness: 1, color: DashK.gray100);

// ── Helpers ─────────────────────────────────────────────────────────────────

const _violationMeta = {
  'DOUBLE_IN': ('Double in', false),
  'DOUBLE_OUT': ('Double out', false),
  'OUT_BEFORE_IN': ('Out before in', true),
  'MISSING_OUT': ('Missing out', true),
  'LATE_IN': ('Late in', false),
  'EARLY_OUT': ('Early out', false),
};

/// 12 → "12", 12.5 → "12.5" (half days).
String _days(num v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

/// "HALF_DAY" → "Half day".
String _sentenceCase(String s) {
  final t = s.replaceAll('_', ' ').trim().toLowerCase();
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

/// "09:30", "09:30:00" or "9:30 PM" → minutes after midnight.
int? _parseHm(Object? raw) {
  final s = raw?.toString().trim();
  if (s == null || s.isEmpty) return null;
  final parts = s.split(':');
  if (parts.length < 2) return null;
  var h = int.tryParse(parts[0].trim());
  final m = int.tryParse(parts[1].trim().split(RegExp(r'\D')).first);
  if (h == null || m == null) return null;
  final upper = s.toUpperCase();
  if (upper.contains('PM') && h < 12) h += 12;
  if (upper.contains('AM') && h == 12) h = 0;
  return h * 60 + m;
}

/// Shift length in minutes (handles shifts that cross midnight).
int? _shiftLength(Object? start, Object? end) {
  final s = _parseHm(start);
  final e = _parseHm(end);
  if (s == null || e == null) return null;
  var diff = e - s;
  if (diff <= 0) diff += 24 * 60;
  return diff;
}

// ── Screen ──────────────────────────────────────────────────────────────────

class EmployeeDashboard extends StatefulWidget {
  const EmployeeDashboard({super.key});

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> with WidgetsBindingObserver {
  EmployeeProfile? _profile;
  List<EmployeeAttendance> _attendance = const [];
  List<EmployeeViolation> _violations = const [];
  List<TodayPunch> _todayPunches = const [];
  EmployeeAttendance? _todayStatus;
  String? _companyDate;
  DateTime? _lastSynced;
  bool _loading = true;
  String? _loadError;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAll();
    _startPolling();

    // Accounts created with a temporary password are asked to change it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<AuthStore>().user?['must_change_password'] == true) {
        showPasswordResetDialog(context);
      }
    });
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
      _loadPunches();
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _loadPunches());
  }

  Future<void> _loadPunches() async {
    try {
      final res = await employeePortalService.fetchTodayPunches();
      if (!mounted) return;
      setState(() {
        _todayPunches = res.punches;
        _todayStatus = res.today;
        if (res.date != null) _companyDate = res.date;
        _lastSynced = DateTime.now();
      });
    } catch (_) {
      // Keep the last data; the next poll retries.
    }
  }

  Future<void> _loadAll() async {
    final now = DateTime.now();
    try {
      final results = await Future.wait([
        employeePortalService.fetchMe(),
        employeePortalService.fetchMonthlyAttendance(month: now.month, year: now.year),
        employeePortalService.fetchViolations(month: now.month, year: now.year),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as EmployeeProfile;
        _attendance = (results[1] as Paged<EmployeeAttendance>).results;
        _violations = (results[2] as Paged<EmployeeViolation>).results;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadError = 'Some attendance data could not be loaded.');
    }
    await _loadPunches();
    if (mounted && _loading) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _DashboardSkeleton();

    // The company's date comes from the server; the phone's date is only a fallback.
    final today = _companyDate ?? toDateKey(DateTime.now());
    EmployeeAttendance? todayLog = _todayStatus;
    if (todayLog == null) {
      for (final a in _attendance) {
        if (a.date == today) {
          todayLog = a;
          break;
        }
      }
    }
    final todayPunchMeta = punchStatusMeta(todayLog?.punchStatus);

    final shift = _profile?.shift;
    final shiftMins = shift == null ? null : _shiftLength(shift.startTime, shift.endTime);

    return RefreshIndicator(
      color: DashK.emerald600,
      onRefresh: _loadAll,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sm = width >= 640;
          final md = width >= 768;
          final lg = width >= 1024;
          final gap = sm ? 14.0 : 12.0;

          final sections = <Widget>[
            if (_loadError != null)
              _Banner(
                style: const StatusStyle(DashK.amber50, Color(0xFF92400E), DashK.amber200),
                icon: Icons.warning_amber_rounded,
                actionLabel: 'Retry',
                onAction: _loadAll,
                child: Text(_loadError!),
              ),
            if (todayPunchMeta != null)
              _Banner(
                style: todayPunchMeta.style,
                icon: Icons.info_outline_rounded,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${todayPunchMeta.label}. ', style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: todayPunchMeta.hint ?? ''),
                  ]),
                ),
              ),
            _Header(profile: _profile, wide: sm),
            _kpiRow(todayLog, md: md, shiftMins: shiftMins),
            _Split(
              wide: lg,
              gap: gap,
              flex: const [3, 2],
              children: [
                _PunchFeedCard(punches: _todayPunches, lastSynced: _lastSynced),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ShiftCard(profile: _profile, shiftMinutes: shiftMins),
                    SizedBox(height: gap),
                    _MonthStatsCard(attendance: _attendance),
                  ],
                ),
              ],
            ),
            _Split(
              wide: lg,
              gap: gap,
              children: [
                _LedgerCard(attendance: _attendance),
                _ViolationsCard(violations: _violations),
              ],
            ),
          ];

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(sm ? 20 : 12),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < sections.length; i++) ...[
                        if (i > 0) SizedBox(height: sections[i - 1] is _Banner ? 8 : gap),
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

  Widget _kpiRow(EmployeeAttendance? log, {required bool md, int? shiftMins}) {
    final last = lastCountedPunch<TodayPunch>(_todayPunches, (p) => p.ignoreReason);
    final lastIsIn = last != null && isInPunch(last.punchType, last.ignoreReason);

    final lastOutValue = log?.lastOut != null
        ? fmtWallTime(log!.lastOut)
        : log?.punchStatus == 'MISSING_OUT'
            ? 'Missing'
            : log?.punchStatus == 'IN_PROGRESS'
                ? 'Working'
                : '--';

    final status = (log != null && log.punchStatus != null && log.punchStatus != 'NO_PUNCH')
        ? attendanceStatus(log.dayType, log.punchStatus, log.leaveName).label
        : 'Not punched';

    final worked = log?.totalWorkMinutes ?? 0;
    final progress =
        (shiftMins != null && shiftMins > 0) ? (worked / shiftMins).clamp(0.0, 1.0).toDouble() : null;

    Widget caption(String text, [Color? color]) => Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: color == null ? _T.caption : _T.caption.copyWith(color: color),
        );

    final checkOutSub = (log?.openIn != null && log?.lastOut == null)
        ? 'In since ${fmtWallTime(log!.openIn)}'
        : 'Last punch out';
    final statusSub = last != null ? 'Last ${fmtWallTime(last.timestamp)}' : 'No punches today';

    return DashGrid(
      // 4 across from tablets up; 2×2 on phones.
      columns: md ? 4 : 2,
      gap: 10,
      children: [
        _KpiCard(
          label: 'Check in',
          value: log?.firstIn != null ? fmtWallTime(log!.firstIn) : '--',
          footer: caption('First punch today'),
          semantics: 'First punch today',
          tone: _emerald,
          icon: Icons.login_rounded,
        ),
        _KpiCard(
          label: 'Check out',
          value: lastOutValue,
          valueColor: log?.punchStatus == 'MISSING_OUT' && log?.lastOut == null ? DashK.red500 : null,
          footer: caption(checkOutSub),
          semantics: checkOutSub,
          tone: _teal,
          icon: Icons.logout_rounded,
        ),
        _KpiCard(
          label: 'Worked',
          value: fmtDuration(worked),
          footer: progress == null
              ? caption('Net working hours')
              : Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor: DashK.indigo50,
                          color: DashK.indigo500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('of ${fmtDuration(shiftMins!)}', style: _T.caption.copyWith(fontFeatures: _T.tabular)),
                  ],
                ),
          semantics: shiftMins != null ? 'of a ${fmtDuration(shiftMins)} shift' : 'Net working hours',
          tone: _indigo,
          icon: Icons.timelapse_rounded,
        ),
        _KpiCard(
          label: 'Status',
          value: status,
          footer: caption(statusSub),
          semantics: statusSub,
          tone: last == null ? _teal : (lastIsIn ? _emerald : _amber),
          icon: (last != null && !lastIsIn) ? Icons.logout_rounded : Icons.login_rounded,
        ),
      ],
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.profile, required this.wide});

  final EmployeeProfile? profile;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final name = (p?.name ?? '').trim();
    final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final firstName = words.isNotEmpty ? words.first : '';
    final initials = words.isEmpty ? '?' : words.take(2).map((w) => w[0].toUpperCase()).join();

    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    final details = [
      if (p != null && p.employeeCode.isNotEmpty) p.employeeCode,
      if (p?.designation != null) p!.designation!,
      if (p?.department != null) p!.department!,
      if (p != null && p.branch.isNotEmpty) p.branch,
    ].join(', ');

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DashK.emerald50,
            shape: BoxShape.circle,
            border: Border.all(color: DashK.emerald200),
          ),
          child: Text(
            initials,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: DashK.emerald600),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Semantics(
                      header: true,
                      child: Text(
                        firstName.isNotEmpty ? '$greeting, $firstName' : 'Dashboard',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: wide ? 19 : 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          height: 1.25,
                          color: DashK.gray900,
                        ),
                      ),
                    ),
                  ),
                  if (p?.isTeamLead == true) ...[
                    const SizedBox(width: 8),
                    const _Tag(text: 'Team lead', tone: _indigo),
                  ],
                ],
              ),
              Text(
                [if (details.isNotEmpty) details, if (!wide) formatEEEMMMd(DateTime.now())].join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, height: 1.3, color: DashK.gray500, fontFeatures: _T.tabular),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const _LiveIndicator(),
        if (wide) ...[
          const SizedBox(width: 12),
          Text(
            formatEEEMMMd(DateTime.now()),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: DashK.gray600),
          ),
        ],
      ],
    );
  }
}

// ── KPI cards ───────────────────────────────────────────────────────────────

/// Icon + label/value on one row, then one footer line (text or bar), so
/// every card in the strip has the same height.
class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.footer,
    required this.semantics,
    required this.tone,
    required this.icon,
    this.valueColor,
  });

  final String label;
  final String value;
  final Widget footer;
  final String semantics;
  final _Tone tone;
  final IconData icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$label: $value. $semantics',
      excludeSemantics: true,
      child: _Surface(
        padding: _cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _IconBox(icon: icon, tone: tone, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.label),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(value, style: _T.value.copyWith(color: valueColor ?? DashK.gray900)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(height: 14, child: Align(alignment: Alignment.centerLeft, child: footer)),
          ],
        ),
      ),
    );
  }
}

// ── Today's punch feed ──────────────────────────────────────────────────────

class _PunchFeedCard extends StatelessWidget {
  const _PunchFeedCard({required this.punches, required this.lastSynced});

  final List<TodayPunch> punches;
  final DateTime? lastSynced;

  @override
  Widget build(BuildContext context) {
    final newestFirst = punches.reversed.toList();
    final count = newestFirst.length;
    final synced = lastSynced != null ? 'updated ${TimeOfDay.fromDateTime(lastSynced!).format(context)}' : null;

    return _Surface(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            icon: Icons.bolt_rounded,
            tone: _indigo,
            title: "Today's punches",
            subtitle: [if (count > 0) '$count', if (synced != null) synced].join(', '),
            trailing: const _LiveIndicator(),
          ),
          const SizedBox(height: 4),
          if (newestFirst.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 8),
              child: _EmptyState(
                icon: Icons.fingerprint_rounded,
                title: 'No punches yet today',
                message: 'They appear a few seconds after you use a device.',
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const ClampingScrollPhysics(),
                itemCount: newestFirst.length,
                separatorBuilder: (_, __) => _divider,
                itemBuilder: (_, i) => _PunchRow(punch: newestFirst[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _PunchRow extends StatelessWidget {
  const _PunchRow({required this.punch});

  final TodayPunch punch;

  @override
  Widget build(BuildContext context) {
    final isIn = isInPunch(punch.punchType, punch.ignoreReason);
    final tone = isIn ? _emerald : _amber;
    final hint = punchLabelHint(punch.ignoreReason);

    Widget label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          punchLabel(punch.punchType, punch.ignoreReason),
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: tone.fg),
        ),
        if (hint != null) ...[
          const SizedBox(width: 3),
          const Icon(Icons.info_outline_rounded, size: 12, color: DashK.gray400),
        ],
      ],
    );
    if (hint != null) label = Tooltip(message: hint, triggerMode: TooltipTriggerMode.tap, child: label);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          _IconBox(icon: isIn ? Icons.login_rounded : Icons.logout_rounded, tone: tone, size: 26),
          const SizedBox(width: 10),
          label,
          if (punch.isManual) ...[
            const SizedBox(width: 6),
            const _MiniChip(text: 'Manual', tone: _gray),
          ],
          const SizedBox(width: 8),
          Icon(
            punch.source == 'RFID' ? Icons.credit_card_rounded : Icons.fingerprint_rounded,
            size: 12,
            color: DashK.gray400,
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              punch.deviceName ?? 'Unknown device',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _T.caption,
            ),
          ),
          const SizedBox(width: 8),
          Text(fmtWallTime(punch.timestamp), style: _T.time),
        ],
      ),
    );
  }
}

// ── My shift ────────────────────────────────────────────────────────────────

class _ShiftCard extends StatelessWidget {
  const _ShiftCard({required this.profile, required this.shiftMinutes});

  final EmployeeProfile? profile;
  final int? shiftMinutes;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final shift = p?.shift;
    final mins = shiftMinutes;

    return _Surface(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            icon: Icons.schedule_rounded,
            tone: _teal,
            title: 'My shift',
            subtitle: shift?.name ?? 'Not assigned',
          ),
          const SizedBox(height: 4),
          if (shift == null)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: _EmptyState(
                icon: Icons.event_busy_outlined,
                title: 'No shift assigned',
                message: 'Ask HR to assign one to see your timings.',
              ),
            )
          else ...[
            for (final (i, row) in <(String, String, Color?)>[
              (
                'Timing',
                '${fmtRawTime(shift.startTime)} – ${fmtRawTime(shift.endTime)}'
                    '${mins != null ? '  (${fmtDuration(mins)})' : ''}',
                null,
              ),
              if (p!.graceMinutes != null) ('Grace', '${p.graceMinutes} min', DashK.emerald600),
              if (p.lunchStart != null && p.lunchEnd != null)
                ('Lunch', '${fmtRawTime(p.lunchStart)} – ${fmtRawTime(p.lunchEnd)}', null),
            ].indexed) ...[
              if (i > 0) _divider,
              _InfoRow(label: row.$1, value: row.$2, valueColor: row.$3),
            ],
            if (shift.workingDays.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final (i, d) in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].indexed) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Expanded(child: _DayChip(day: d, on: shift.workingDays.contains(d))),
                  ],
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: DashK.gray500)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: valueColor ?? DashK.gray900,
                fontFeatures: _T.tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.day, required this.on});

  final String day;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$day ${on ? 'working day' : 'off'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? DashK.indigo50 : DashK.gray50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: on ? DashK.indigo200 : DashK.gray100),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            day,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: on ? DashK.indigo600 : DashK.gray300),
          ),
        ),
      ),
    );
  }
}

// ── This month's summary ────────────────────────────────────────────────────

class _MonthStatsCard extends StatelessWidget {
  const _MonthStatsCard({required this.attendance});

  final List<EmployeeAttendance> attendance;

  @override
  Widget build(BuildContext context) {
    num presentDays = 0;
    var absentDays = 0;
    var lateMins = 0;
    var lateAfterLunchMins = 0;
    var otMins = 0;
    for (final a in attendance) {
      if (a.dayType == 'HALF_DAY') {
        presentDays += 0.5;
      } else if (a.dayType == 'PRESENT' || a.dayType == 'FULL_DAY') {
        presentDays += 1;
      }
      if (a.dayType == 'ABSENT') absentDays++;
      lateMins += a.lateMinutes;
      lateAfterLunchMins += a.lateAfterLunchMinutes;
      otMins += a.overtimeMinutes;
    }

    final tracked = presentDays + absentDays;
    final rate = tracked > 0 ? (presentDays / tracked * 100).round() : null;
    final presentFlex = (presentDays * 2).round();
    final absentFlex = absentDays * 2;

    return _Surface(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            icon: Icons.calendar_month_outlined,
            tone: _indigo,
            title: formatMMMM(DateTime.now()),
            subtitle: rate != null ? '$rate% attendance' : 'Month to date',
          ),
          const SizedBox(height: 8),
          // Present vs absent proportion.
          Semantics(
            label: rate != null ? 'Attendance rate $rate percent' : 'No attendance tracked yet',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 4,
                child: Row(
                  children: [
                    if (presentFlex > 0) Expanded(flex: presentFlex, child: const ColoredBox(color: DashK.emerald500)),
                    if (presentFlex > 0 && absentFlex > 0) const SizedBox(width: 2),
                    if (absentFlex > 0) Expanded(flex: absentFlex, child: const ColoredBox(color: _K.red400)),
                    if (presentFlex == 0 && absentFlex == 0) const Expanded(child: ColoredBox(color: DashK.gray100)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Two stats per row.
          Row(
            children: [
              Expanded(
                child: _StatLine(
                  dot: DashK.emerald500,
                  label: 'Present',
                  value: _days(presentDays),
                  valueColor: DashK.emerald600,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _StatLine(dot: _K.red400, label: 'Absent', value: '$absentDays', valueColor: DashK.red500),
              ),
            ],
          ),
          _divider,
          Row(
            children: [
              Expanded(
                child: _StatLine(
                  dot: _K.amber400,
                  label: lateAfterLunchMins > 0 ? 'Late (+${lateAfterLunchMins}m lunch)' : 'Late in',
                  value: '${lateMins}m',
                  valueColor: DashK.amber600,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _StatLine(
                  dot: DashK.indigo500,
                  label: 'Overtime',
                  value: fmtDuration(otMins),
                  valueColor: DashK.indigo600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.dot, required this.label, required this.value, required this.valueColor});

  final Color dot;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: DashK.gray600),
            ),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: valueColor, fontFeatures: _T.tabular),
          ),
        ],
      ),
    );
  }
}

// ── Recent attendance ───────────────────────────────────────────────────────

class _LedgerCard extends StatelessWidget {
  const _LedgerCard({required this.attendance});

  final List<EmployeeAttendance> attendance;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            icon: Icons.event_note_outlined,
            tone: _emerald,
            title: 'Recent attendance',
            trailing: TextButton(
              onPressed: () => context.go('/portal/attendance'),
              style: TextButton.styleFrom(
                foregroundColor: DashK.emerald600,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: const Text('View all'),
            ),
          ),
          if (attendance.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6, bottom: 8),
              child: _EmptyState(
                icon: Icons.event_available_outlined,
                title: 'No attendance records yet',
                message: 'Days appear once your punches are processed.',
              ),
            )
          else
            for (final (i, day) in attendance.take(7).indexed) ...[
              if (i > 0) _divider,
              _LedgerRow(day: day),
            ],
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.day});

  final EmployeeAttendance day;

  @override
  Widget build(BuildContext context) {
    final date = parseDateOnly(day.date) ?? DateTime.now();
    final tone = isPresentDay(day.dayType)
        ? _emerald
        : day.dayType == 'ABSENT'
            ? _red
            : _gray;
    final statusText = day.statusLabel ?? _sentenceCase(day.dayType);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: tone.bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tone.border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(formatEEE(date), style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, height: 1, color: tone.fg)),
                const SizedBox(height: 2),
                Text(formatDD(date), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1, color: tone.fg)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 5,
              runSpacing: 3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _MiniChip(text: statusText, tone: tone),
                if (day.lateMinutes > 0) _MiniChip(text: '${day.lateMinutes}m late', tone: _red),
                if (day.lateAfterLunchMinutes > 0) _MiniChip(text: '${day.lateAfterLunchMinutes}m after lunch', tone: _orange),
                if (day.overtimeMinutes > 0) _MiniChip(text: '${day.overtimeMinutes}m OT', tone: _indigo),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Check in',
            child: Text(fmtWallTime24(day.firstIn), style: _T.time),
          ),
        ],
      ),
    );
  }
}

// ── Compliance alerts ───────────────────────────────────────────────────────

class _ViolationsCard extends StatelessWidget {
  const _ViolationsCard({required this.violations});

  final List<EmployeeViolation> violations;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            icon: Icons.gpp_maybe_outlined,
            tone: _red,
            title: 'Compliance alerts',
            subtitle: 'This month',
            trailing: violations.isNotEmpty ? _CountBadge(count: violations.length, tone: _red) : null,
          ),
          const SizedBox(height: 8),
          if (violations.isEmpty)
            const _EmptyState(
              icon: Icons.verified_outlined,
              title: 'No violations this month',
              message: 'All your records meet policy.',
              success: true,
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const ClampingScrollPhysics(),
                itemCount: violations.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) => _ViolationRow(v: violations[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _ViolationRow extends StatelessWidget {
  const _ViolationRow({required this.v});

  final EmployeeViolation v;

  @override
  Widget build(BuildContext context) {
    final meta = _violationMeta[v.violationType];
    final isRed = meta == null || meta.$2;
    final base = isRed ? DashK.red500 : DashK.amber500;
    final date = parseDateOnly(v.date);

    // A rounded box can't take a one-sided border, so the accent is its own strip.
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(base.withValues(alpha: 0.04), Colors.white),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: base.withValues(alpha: 0.15)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: isRed ? _K.red400 : _K.amber400,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  meta?.$1 ?? _sentenceCase(v.violationType),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isRed ? DashK.red600 : DashK.amber600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                date != null ? formatMMMddyyyy(date) : v.date,
                style: const TextStyle(fontSize: 11, color: DashK.gray400, fontFeatures: _T.tabular),
              ),
            ],
          ),
                  const SizedBox(height: 2),
                  Text(v.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: _T.body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Loading skeleton ────────────────────────────────────────────────────────

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading your dashboard',
      child: Column(
        children: [
          const LinearProgressIndicator(minHeight: 2, color: DashK.emerald500, backgroundColor: DashK.emerald50),
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
                        _Bone(width: 36, height: 36, radius: 18),
                        SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Bone(width: 170, height: 16),
                            SizedBox(height: 6),
                            _Bone(width: 210, height: 10),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DashGrid(
                      columns: md ? 4 : 2,
                      gap: 10,
                      children: [for (var i = 0; i < 4; i++) const _Bone(height: 76)],
                    ),
                    const SizedBox(height: 12),
                    const _Bone(height: 220),
                    const SizedBox(height: 12),
                    const _Bone(height: 180),
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
      decoration: BoxDecoration(color: DashK.gray100, borderRadius: BorderRadius.circular(radius)),
    );
  }
}

// ── Small shared pieces ─────────────────────────────────────────────────────

/// White card with a hairline border and a barely-there shadow.
class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.padding = const EdgeInsets.all(12)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: DashK.gray100),
        boxShadow: const [BoxShadow(color: Color(0x08101828), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: child,
    );
  }
}

/// Icon · title · subtitle on one line, with an optional trailing widget.
class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.tone,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final _Tone tone;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _IconBox(icon: icon, tone: tone, size: 28),
        const SizedBox(width: 8),
        Flexible(
          child: Semantics(
            header: true,
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.title),
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(width: 6),
          Flexible(child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.subtitle)),
        ],
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

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

/// Single-row empty state: icon, title and a short line.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.success = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return DashedBox(
      background: success ? DashK.emerald50.withValues(alpha: 0.4) : DashK.gray50,
      color: success ? DashK.emerald200 : DashK.gray200,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: success ? _K.emerald100 : DashK.gray100,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: success ? DashK.emerald600 : DashK.gray400),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: DashK.gray700)),
                  if (message != null) Text(message!, style: _T.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.style,
    required this.icon,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final StatusStyle style;
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
        padding: EdgeInsets.fromLTRB(12, 7, hasAction ? 4 : 12, 7),
        decoration: BoxDecoration(
          color: style.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: style.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: style.fg),
            const SizedBox(width: 8),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(fontSize: 12.5, height: 1.35, color: style.fg),
                child: child,
              ),
            ),
            if (hasAction)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: style.fg,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}

class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DashPulse(child: DashDot(color: DashK.emerald400)),
        SizedBox(width: 5),
        Text('Live', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: DashK.emerald600)),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.tone});

  final String text;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tone.border),
      ),
      child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: tone.fg)),
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
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(5)),
      child: Text(
        text,
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
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
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

/// Side by side on wide screens (with optional flex), stacked on narrow ones.
class _Split extends StatelessWidget {
  const _Split({required this.wide, required this.gap, required this.children, this.flex});

  final bool wide;
  final double gap;
  final List<Widget> children;
  final List<int>? flex;

  @override
  Widget build(BuildContext context) {
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(flex: flex?[i] ?? 1, child: children[i]),
        ],
      ],
    );
  }
}