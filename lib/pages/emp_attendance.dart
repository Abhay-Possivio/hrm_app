// Port of features/employee/attendance/EmployeeAttendancePage.tsx
// ("My Attendance": the month's attendance ledger, correction requests,
// and CSV export).
//
// Compact layout:
//   Header (one line): icon · title · month stepper (‹ October 2026 ›) · export
//   [error banner]
//   Stats: Present | Absent | Late in | Missing clock-outs   (equal height)
//   Ledger card: month · day count · All / Needs attention filter
//     wide: table (Date · Status · In · Out · Worked · Deviations · Fix)
//     phones: two-line rows
//   Correction requests (when there are any)

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:hrm_app/components/attendance/correction_req.dart';
import 'package:hrm_app/services/empportal_service.dart';
import 'package:hrm_app/services/hr_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';
import 'package:hrm_app/utils/toast.dart';

/// How far back a correction can be requested (matches the backend limit).
const _correctionMaxAgeDays = 60;

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
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const red50 = Color(0xFFFEF2F2);
  static const red200 = Color(0xFFFECACA);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber200 = Color(0xFFFDE68A);
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);
  static const blue50 = Color(0xFFEFF6FF);
  static const blue200 = Color(0xFFBFDBFE);
  static const blue500 = Color(0xFF3B82F6);
  static const orange50 = Color(0xFFFFF7ED);
  static const orange200 = Color(0xFFFED7AA);
  static const orange500 = Color(0xFFF97316);
  static const orange600 = Color(0xFFEA580C);
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo200 = Color(0xFFC7D2FE);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
}

/// A tinted color set: soft background, border, and foreground.
class _Tone {
  const _Tone(this.bg, this.border, this.fg);

  final Color bg;
  final Color border;
  final Color fg;
}

const _emerald = _Tone(_K.emerald50, _K.emerald200, _K.emerald600);
const _red = _Tone(_K.red50, _K.red200, _K.red600);
const _amber = _Tone(_K.amber50, _K.amber200, _K.amber600);
const _blue = _Tone(_K.blue50, _K.blue200, _K.blue500);
const _orange = _Tone(_K.orange50, _K.orange200, _K.orange600);
const _indigo = _Tone(_K.indigo50, _K.indigo200, _K.indigo600);

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.3, color: _K.gray900);
  static const subtitle = TextStyle(fontSize: 11.5, height: 1.3, color: _K.gray500);
  static const label = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, height: 1.2, color: _K.gray500);
  static const caption = TextStyle(fontSize: 11, height: 1.25, color: _K.gray400);
  static const cell = TextStyle(fontSize: 12.5, color: _K.gray900, fontFeatures: tabular);
  static const columnHead = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.gray500);
}

const _cardRadius = 14.0;
const _divider = Divider(height: 1, thickness: 1, color: _K.gray100);

/// Days that need the employee's attention.
bool _needsAttention(EmployeeAttendance? a) =>
    a != null &&
    (a.dayType == 'ABSENT' ||
        a.punchStatus == 'MISSING_OUT' ||
        a.lateMinutes > 0 ||
        a.lateAfterLunchMinutes > 0 ||
        a.earlyOutMinutes > 0);

// Table column flex: date, status, in, out, worked, deviations.
const _colFlex = [3, 3, 2, 2, 2, 4];

Widget _tableRow(List<Widget> cells, {required Widget trailing}) {
  return Row(
    children: [
      for (var i = 0; i < cells.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(flex: _colFlex[i], child: cells[i]),
      ],
      const SizedBox(width: 8),
      SizedBox(width: 96, child: Align(alignment: Alignment.centerRight, child: trailing)),
    ],
  );
}

// ── Page ────────────────────────────────────────────────────────────────────

class EmployeeAttendancePage extends StatefulWidget {
  const EmployeeAttendancePage({super.key});

  @override
  State<EmployeeAttendancePage> createState() => _EmployeeAttendancePageState();
}

class _EmployeeAttendancePageState extends State<EmployeeAttendancePage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<EmployeeAttendance> _attendance = const [];
  List<CorrectionRequest> _requests = const [];
  bool _loading = true;
  bool _loadedOnce = false;
  bool _issuesOnly = false;
  String? _error;
  int _loadId = 0;

  bool get _isCurrentMonth {
    final n = DateTime.now();
    return _month.year == n.year && _month.month == n.month;
  }

  @override
  void initState() {
    super.initState();
    _loadMonth();
    _loadRequests();
  }

  Future<void> _loadMonth() async {
    final id = ++_loadId; // ignore results from an older month after switching
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await employeePortalService.fetchMonthlyAttendance(month: _month.month, year: _month.year);
      if (!mounted || id != _loadId) return;
      setState(() => _attendance = data.results);
    } catch (_) {
      if (!mounted || id != _loadId) return;
      setState(() {
        _attendance = const [];
        _error = 'Could not load your attendance.';
      });
    } finally {
      if (mounted && id == _loadId) {
        setState(() {
          _loading = false;
          _loadedOnce = true;
        });
      }
    }
  }

  Future<void> _loadRequests() async {
    try {
      final list = await correctionService.list(scope: 'mine', status: 'ALL', pageSize: 20);
      if (mounted) setState(() => _requests = list.results);
    } catch (_) {
      if (mounted) setState(() => _requests = const []);
    }
  }

  Future<void> _cancelRequest(CorrectionRequest r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel this request?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900)),
        content: Text(
          'Your ${r.punchType == 'IN' ? 'clock-in' : 'clock-out'} correction for ${_requestDate(r)} will be withdrawn.',
          style: const TextStyle(fontSize: 13, height: 1.45, color: _K.gray600),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _K.gray600),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _K.red600,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await correctionService.act(r.id, 'cancel');
      if (!mounted) return;
      showToast(context, 'Request cancelled');
      _loadRequests();
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Could not cancel'), error: true);
    }
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _loadMonth();
  }

  void _goToCurrentMonth() {
    final n = DateTime.now();
    setState(() => _month = DateTime(n.year, n.month));
    _loadMonth();
  }

  Future<void> _exportCsv() async {
    String q(Object? v) => '"${'$v'.replaceAll('"', '""')}"';
    final header = [
      'Date', 'Status', 'Shift', 'First In', 'Last Out', 'Worked', 'Late In (min)',
      'Late After Lunch (min)', 'Early Out (min)', 'Overtime (min)',
    ];
    final rows = [..._attendance]..sort((a, b) => a.date.compareTo(b.date));
    final lines = [
      header.join(','),
      for (final a in rows)
        [
          a.date,
          a.statusLabel ?? dayTypeMeta(a.dayType).label,
          (a.shiftStart != null && a.shiftEnd != null) ? '${a.shiftStart}-${a.shiftEnd}' : '',
          fmtWallTime(a.firstIn, fallback: ''),
          fmtWallTime(a.lastOut, fallback: ''),
          fmtMinutes(a.totalWorkMinutes),
          a.lateMinutes,
          a.lateAfterLunchMinutes,
          a.earlyOutMinutes,
          a.overtimeMinutes,
        ].map(q).join(','),
    ];
    final name = 'attendance_${formatYyyyMM(_month)}.csv';
    final bytes = Uint8List.fromList(utf8.encode(lines.join('\n')));
    try {
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: name, mimeType: 'text/csv')],
        fileNameOverrides: [name],
        subject: 'Attendance ${formatMMMMyyyy(_month)}',
      );
    } catch (_) {
      if (mounted) showToast(context, 'Could not export the file', error: true);
    }
  }

  Future<void> _requestFix(String date, EmployeeAttendance? log) async {
    // Suggest the missing direction: a clock-out when they clocked in, else a clock-in.
    final out = log?.punchStatus == 'MISSING_OUT' || log?.firstIn != null;
    final sent = await showCorrectionRequestSheet(
      context,
      date: date,
      suggestedType: out ? 'OUT' : 'IN',
      suggestedTime: out ? log?.shiftEnd : log?.shiftStart,
    );
    if (sent) _loadRequests();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loadedOnce) return const _PageSkeleton();

    final byDate = {for (final a in _attendance) a.date: a};
    final now = DateTime.now();
    final todayKey = toDateKey(now);
    final oldestKey = toDateKey(now.subtract(const Duration(days: _correctionMaxAgeDays)));

    final openByDate = <String, int>{};
    for (final r in _requests) {
      if (r.status == 'PENDING' || r.status == 'TL_APPROVED') {
        openByDate[r.date] = (openByDate[r.date] ?? 0) + 1;
      }
    }

    // Days of the month up to today (plus any later day that has a record), newest first.
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final allDays = [
      for (var d = daysInMonth; d >= 1; d--)
        if (toDateKey(DateTime(_month.year, _month.month, d)).compareTo(todayKey) <= 0 ||
            byDate.containsKey(toDateKey(DateTime(_month.year, _month.month, d))))
          DateTime(_month.year, _month.month, d),
    ];
    final issueCount = allDays.where((d) => _needsAttention(byDate[toDateKey(d)])).length;
    final days = _issuesOnly ? allDays.where((d) => _needsAttention(byDate[toDateKey(d)])).toList() : allDays;

    num presentDays = 0;
    var absent = 0;
    var missingOut = 0;
    var late = 0;
    var lateAfterLunch = 0;
    for (final a in _attendance) {
      if (a.dayType == 'HALF_DAY') {
        presentDays += 0.5;
      } else if (isPresentDay(a.dayType)) {
        presentDays += 1;
      }
      if (a.dayType == 'ABSENT') absent++;
      if (a.punchStatus == 'MISSING_OUT') missingOut++;
      late += a.lateMinutes;
      lateAfterLunch += a.lateAfterLunchMinutes;
    }

    return RefreshIndicator(
      color: _K.emerald600,
      onRefresh: () => Future.wait([_loadMonth(), _loadRequests()]),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sm = width >= 640;
          final md = width >= 768;
          final lg = width >= 1024;
          final gap = sm ? 14.0 : 12.0;

          final sections = <Widget>[
            _header(wide: sm),
            if (_error != null)
              _Banner(message: _error!, onRetry: _loadMonth),
            _Grid(
              columns: md ? 4 : 2,
              gap: 10,
              children: [
                _StatCard(
                  icon: Icons.event_available_outlined,
                  tone: _emerald,
                  label: 'Present',
                  value: presentDays == presentDays.roundToDouble() ? '${presentDays.round()}' : '$presentDays',
                  footer: 'day${presentDays == 1 ? '' : 's'} this month',
                ),
                _StatCard(
                  icon: Icons.event_busy_outlined,
                  tone: _red,
                  label: 'Absent',
                  value: '$absent',
                  footer: absent == 0 ? 'None' : 'day${absent == 1 ? '' : 's'}',
                  highlight: absent > 0,
                  onTap: absent > 0 ? () => setState(() => _issuesOnly = true) : null,
                ),
                _StatCard(
                  icon: Icons.schedule_rounded,
                  tone: _amber,
                  label: 'Late in',
                  value: fmtMinutes(late),
                  footer: '${fmtMinutes(lateAfterLunch)} after lunch',
                  footerColor: lateAfterLunch > 0 ? _K.orange600 : null,
                ),
                _StatCard(
                  icon: Icons.logout_rounded,
                  tone: _blue,
                  label: 'Missing clock-out',
                  value: '$missingOut',
                  footer: missingOut > 0 ? 'Request a fix' : 'All closed',
                  footerColor: missingOut > 0 ? _K.red600 : null,
                  highlight: missingOut > 0,
                  onTap: missingOut > 0 ? () => setState(() => _issuesOnly = true) : null,
                ),
              ],
            ),
            _ledger(days, allDays.length, issueCount, byDate, openByDate, todayKey, oldestKey, wide: lg),
            if (_requests.isNotEmpty) _RequestsCard(requests: _requests, onCancel: _cancelRequest, wide: sm),
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
    final stepper = Container(
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _K.gray200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Previous month',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 34),
            onPressed: () => _changeMonth(-1),
            icon: const Icon(Icons.chevron_left_rounded, size: 18, color: _K.gray500),
          ),
          Semantics(
            label: 'Month: ${formatMMMMyyyy(_month)}',
            excludeSemantics: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 96),
              child: Text(
                formatMMMMyyyy(_month),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _K.gray900),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 34),
            onPressed: _isCurrentMonth ? null : () => _changeMonth(1),
            icon: Icon(Icons.chevron_right_rounded, size: 18, color: _isCurrentMonth ? _K.gray300 : _K.gray500),
          ),
        ],
      ),
    );

    final export = IconButton(
      tooltip: 'Export this month as CSV',
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        side: const BorderSide(color: _K.gray200),
        fixedSize: const Size(36, 36),
        minimumSize: const Size(36, 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      onPressed: _attendance.isEmpty ? null : _exportCsv,
      icon: Icon(Icons.file_download_outlined, size: 18, color: _attendance.isEmpty ? _K.gray300 : _K.gray600),
    );

    final title = Row(
      children: [
        const _IconBox(icon: Icons.calendar_month_outlined, tone: _emerald, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'My attendance',
                  style: TextStyle(
                    fontSize: wide ? 19 : 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    height: 1.25,
                    color: _K.gray900,
                  ),
                ),
              ),
              Row(
                children: [
                  const Flexible(
                    child: Text(
                      'Daily punches, hours and corrections.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _T.subtitle,
                    ),
                  ),
                  if (!_isCurrentMonth) ...[
                    const SizedBox(width: 6),
                    _LinkButton(label: 'This month', onTap: _goToCurrentMonth),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );

    if (wide) {
      return Row(children: [Expanded(child: title), const SizedBox(width: 10), stepper, const SizedBox(width: 6), export]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title,
        const SizedBox(height: 10),
        Row(children: [Expanded(child: Align(alignment: Alignment.centerLeft, child: stepper)), export]),
      ],
    );
  }

  // ── Ledger ──

  Widget _ledger(
    List<DateTime> days,
    int totalDays,
    int issueCount,
    Map<String, EmployeeAttendance> byDate,
    Map<String, int> openByDate,
    String todayKey,
    String oldestKey, {
    required bool wide,
  }) {
    Widget body;
    if (days.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(12),
        child: _issuesOnly
            ? _EmptyState(
                icon: Icons.task_alt_rounded,
                title: 'Nothing needs attention',
                message: 'No absences, late arrivals or missing clock-outs in ${formatMMMMyyyy(_month)}.',
                success: true,
                action: _LinkButton(label: 'Show all days', onTap: () => setState(() => _issuesOnly = false)),
              )
            : _EmptyState(
                icon: Icons.event_note_outlined,
                title: 'No days to show',
                message: _error != null ? 'Pull down or tap Retry above.' : 'This month has no attendance yet.',
              ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < days.length; i++) ...[
            if (i > 0) _divider,
            _DayRow(
              day: days[i],
              log: byDate[toDateKey(days[i])],
              isToday: toDateKey(days[i]) == todayKey,
              canFix: toDateKey(days[i]).compareTo(todayKey) <= 0 && toDateKey(days[i]).compareTo(oldestKey) >= 0,
              hasOpenRequest: (openByDate[toDateKey(days[i])] ?? 0) > 0,
              onRequestFix: () => _requestFix(toDateKey(days[i]), byDate[toDateKey(days[i])]),
              wide: wide,
            ),
          ],
        ],
      );
    }

    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                const _IconBox(icon: Icons.view_list_outlined, tone: _emerald, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: formatMMMMyyyy(_month), style: _T.title),
                        TextSpan(
                          text: '  $totalDays day${totalDays == 1 ? '' : 's'}',
                          style: const TextStyle(fontSize: 11.5, color: _K.gray500, fontFeatures: _T.tabular),
                        ),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                _FilterChip(
                  label: 'All',
                  selected: !_issuesOnly,
                  onTap: () => setState(() => _issuesOnly = false),
                ),
                const SizedBox(width: 5),
                _FilterChip(
                  label: 'Needs attention',
                  count: issueCount,
                  selected: _issuesOnly,
                  tone: issueCount > 0 ? _red : null,
                  onTap: () => setState(() => _issuesOnly = true),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 2,
            child: _loading
                ? const LinearProgressIndicator(minHeight: 2, color: _K.emerald500, backgroundColor: _K.emerald50)
                : const ColoredBox(color: _K.gray100),
          ),
          if (wide && days.isNotEmpty)
            Container(
              color: _K.gray50,
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              child: _tableRow(
                const [
                  Text('Date', style: _T.columnHead),
                  Text('Status', style: _T.columnHead),
                  Text('In', style: _T.columnHead),
                  Text('Out', style: _T.columnHead),
                  Text('Worked', style: _T.columnHead),
                  Text('Deviations', style: _T.columnHead),
                ],
                trailing: const SizedBox.shrink(),
              ),
            ),
          AnimatedOpacity(
            opacity: _loading ? 0.55 : 1,
            duration: const Duration(milliseconds: 150),
            child: body,
          ),
        ],
      ),
    );
  }

  static String _requestDate(CorrectionRequest r) {
    final d = parseDateOnly(r.date);
    return d != null ? formatEEEDDMMM(d) : r.date;
  }
}

// ── One day of the ledger ───────────────────────────────────────────────────

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.log,
    required this.isToday,
    required this.canFix,
    required this.hasOpenRequest,
    required this.onRequestFix,
    required this.wide,
  });

  final DateTime day;
  final EmployeeAttendance? log;
  final bool isToday;
  final bool canFix;
  final bool hasOpenRequest;
  final VoidCallback onRequestFix;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final l = log;
    final offDay = l?.dayType == 'OFF_DAY';
    final status = attendanceStatus(l?.dayType, l?.punchStatus, l?.leaveName);
    final needsFix = l?.punchStatus == 'MISSING_OUT' || l?.dayType == 'ABSENT';
    final shift = (l?.shiftStart != null && l?.shiftEnd != null) ? '${l!.shiftStart}–${l.shiftEnd}' : null;

    final dateBox = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isToday ? _K.emerald50 : (offDay ? _K.orange50 : _K.gray50),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isToday ? _K.emerald200 : (offDay ? _K.orange200 : _K.gray100)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            formatEEE(day),
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              height: 1,
              color: isToday ? _K.emerald600 : (offDay ? _K.orange600 : _K.gray500),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formatDD(day),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              height: 1,
              color: isToday ? _K.emerald600 : (offDay ? _K.orange600 : _K.gray700),
              fontFeatures: _T.tabular,
            ),
          ),
        ],
      ),
    );

    final dateLabel = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                '${formatDD(day)} ${formatMMMM(day)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.25, color: _K.gray900),
              ),
            ),
            if (isToday) ...[const SizedBox(width: 5), const _Chip(text: 'Today', tone: _emerald)],
          ],
        ),
        if (shift != null)
          Text('Shift $shift', style: const TextStyle(fontSize: 10.5, height: 1.25, color: _K.gray500, fontFeatures: _T.tabular)),
      ],
    );

    final badge = l == null
        ? const Text('No record', style: TextStyle(fontSize: 11.5, color: _K.gray400))
        : Tooltip(
            message: status.hint ?? '',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: status.style.bg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: status.style.border),
              ),
              child: Text(
                status.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: status.style.fg),
              ),
            ),
          );

    final inText = l?.firstIn != null ? fmtWallTime(l!.firstIn) : '--';
    final outText = l != null ? lastOutText(lastOut: l.lastOut, punchStatus: l.punchStatus) : '--';
    final outColor = l?.lastOut != null
        ? _K.gray900
        : l?.punchStatus == 'MISSING_OUT'
            ? _K.red600
            : _K.gray400;
    final worked = (l?.totalWorkMinutes ?? 0) > 0 ? fmtMinutes(l!.totalWorkMinutes) : '--';

    final deviations = <Widget>[
      if ((l?.lateMinutes ?? 0) > 0) _Chip(text: '+${l!.lateMinutes}m late', tone: _red),
      if ((l?.lateAfterLunchMinutes ?? 0) > 0) _Chip(text: '+${l!.lateAfterLunchMinutes}m lunch', tone: _orange),
      if ((l?.earlyOutMinutes ?? 0) > 0) _Chip(text: '${l!.earlyOutMinutes}m early', tone: _orange),
      if ((l?.overtimeMinutes ?? 0) > 0) _Chip(text: '+${l!.overtimeMinutes}m OT', tone: _emerald),
    ];

    Widget fix = const SizedBox.shrink();
    if (hasOpenRequest) {
      fix = const Tooltip(
        message: 'A correction request for this day is waiting for approval',
        child: _Chip(text: 'Fix pending', tone: _amber, icon: Icons.hourglass_top_rounded),
      );
    } else if (canFix) {
      fix = Tooltip(
        message: 'Ask HR to add a missing punch',
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: needsFix ? _K.red700 : _K.gray500,
            backgroundColor: needsFix ? _K.red50 : null,
            minimumSize: const Size(0, 28),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
              side: needsFix ? const BorderSide(color: _K.red200) : BorderSide.none,
            ),
            textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
          onPressed: onRequestFix,
          icon: const Icon(Icons.edit_outlined, size: 13),
          label: const Text('Fix'),
        ),
      );
    }

    final bg = isToday ? _K.emerald50.withValues(alpha: 0.45) : Colors.white;

    if (wide) {
      return Container(
        color: bg,
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: _tableRow(
          [
            Row(children: [dateBox, const SizedBox(width: 8), Expanded(child: dateLabel)]),
            Align(alignment: Alignment.centerLeft, child: badge),
            Text(inText, style: _T.cell.copyWith(color: l?.firstIn != null ? _K.gray900 : _K.gray400)),
            Text(
              outText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _T.cell.copyWith(
                color: outColor,
                fontWeight: l?.punchStatus == 'MISSING_OUT' ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            Text(worked, style: _T.cell.copyWith(fontWeight: FontWeight.w600, color: worked == '--' ? _K.gray400 : _K.gray900)),
            deviations.isEmpty
                ? const Text('–', style: TextStyle(fontSize: 12.5, color: _K.gray300))
                : Wrap(spacing: 4, runSpacing: 3, children: deviations),
          ],
          trailing: fix,
        ),
      );
    }

    // Phone: two lines.
    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
      child: Row(
        children: [
          dateBox,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: dateLabel),
                    const SizedBox(width: 6),
                    Flexible(child: Align(alignment: Alignment.centerRight, child: badge)),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 3,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text.rich(
                            TextSpan(children: [
                              const TextSpan(text: 'In ', style: TextStyle(color: _K.gray400)),
                              TextSpan(text: inText),
                              const TextSpan(text: '   Out ', style: TextStyle(color: _K.gray400)),
                              TextSpan(
                                text: outText,
                                style: TextStyle(
                                  color: outColor,
                                  fontWeight: l?.punchStatus == 'MISSING_OUT' ? FontWeight.w600 : FontWeight.w400,
                                ),
                              ),
                              const TextSpan(text: '   ', style: TextStyle(color: _K.gray400)),
                              TextSpan(text: worked, style: const TextStyle(fontWeight: FontWeight.w600)),
                            ]),
                            style: const TextStyle(fontSize: 11.5, color: _K.gray900, fontFeatures: _T.tabular),
                          ),
                          ...deviations,
                        ],
                      ),
                    ),
                    fix,
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── My correction requests ──────────────────────────────────────────────────

class _RequestsCard extends StatelessWidget {
  const _RequestsCard({required this.requests, required this.onCancel, required this.wide});

  final List<CorrectionRequest> requests;
  final void Function(CorrectionRequest r) onCancel;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final open = requests.where((r) => r.status == 'PENDING' || r.status == 'TL_APPROVED').length;
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                const _IconBox(icon: Icons.edit_note_rounded, tone: _indigo, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'Correction requests', style: _T.title),
                        TextSpan(
                          text: open > 0 ? '  $open open' : '  ${requests.length}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: open > 0 ? _K.amber700 : _K.gray500,
                            fontWeight: open > 0 ? FontWeight.w600 : FontWeight.w400,
                            fontFeatures: _T.tabular,
                          ),
                        ),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _divider,
          for (var i = 0; i < requests.length; i++) ...[
            if (i > 0) _divider,
            _RequestRow(request: requests[i], onCancel: () => onCancel(requests[i])),
          ],
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.request, required this.onCancel});

  final CorrectionRequest request;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final d = parseDateOnly(r.date);
    final comment = r.hrComment.isNotEmpty ? r.hrComment : r.tlComment;
    final style = correctionStatusStyle(r.status);
    final isIn = r.punchType == 'IN';
    final note = [
      if (r.reason.isNotEmpty) r.reason,
      if (comment.isNotEmpty) 'Reply: $comment',
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
      child: Row(
        children: [
          _IconBox(icon: isIn ? Icons.login_rounded : Icons.logout_rounded, tone: isIn ? _emerald : _amber, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: '${isIn ? 'Clock-in' : 'Clock-out'} at ${fmtWallTime(r.timestamp)}',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: _K.gray900),
                    ),
                    TextSpan(
                      text: '  ${d != null ? formatEEEDDMMM(d) : r.date}',
                      style: const TextStyle(color: _K.gray500),
                    ),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, height: 1.3, fontFeatures: _T.tabular),
                ),
                if (note.isNotEmpty)
                  Tooltip(
                    message: note,
                    child: Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.caption),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: style.bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: style.border),
            ),
            child: Text(
              correctionStatusLabel(r.status) ?? r.statusDisplay,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: style.fg),
            ),
          ),
          if (r.canCancel)
            IconButton(
              tooltip: 'Cancel request',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded, size: 17, color: _K.gray400),
            )
          else
            const SizedBox(width: 6),
        ],
      ),
    );
  }
}

// ── Stat card ───────────────────────────────────────────────────────────────

/// Icon + label/value on one row, one footer line; equal heights in the grid.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.tone,
    required this.label,
    required this.value,
    required this.footer,
    this.footerColor,
    this.highlight = false,
    this.onTap,
  });

  final IconData icon;
  final _Tone tone;
  final String label;
  final String value;
  final String footer;
  final Color? footerColor;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: onTap != null,
      label: '$label: $value, $footer${onTap != null ? '. Tap to show days that need attention' : ''}',
      excludeSemantics: true,
      child: _Surface(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
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
                        child: Text(
                          value,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            height: 1.2,
                            color: highlight ? tone.fg : _K.gray900,
                            fontFeatures: _T.tabular,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              footer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _T.caption.copyWith(color: footerColor ?? _K.gray400),
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
    Widget bone(double h, {double? w, double r = _cardRadius}) => Container(
          width: w ?? double.infinity,
          height: h,
          decoration: BoxDecoration(color: _K.gray100, borderRadius: BorderRadius.circular(r)),
        );

    return Semantics(
      label: 'Loading your attendance',
      child: Column(
        children: [
          const LinearProgressIndicator(minHeight: 2, color: _K.emerald500, backgroundColor: _K.emerald50),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final sm = c.maxWidth >= 640;
                final md = c.maxWidth >= 768;
                return ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.all(sm ? 20 : 12),
                  children: [
                    Row(children: [bone(36, w: 36, r: 10), const SizedBox(width: 10), bone(16, w: 160, r: 6)]),
                    const SizedBox(height: 14),
                    _Grid(columns: md ? 4 : 2, gap: 10, children: [for (var i = 0; i < 4; i++) bone(68)]),
                    const SizedBox(height: 12),
                    bone(420),
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

// ── Small shared pieces ─────────────────────────────────────────────────────

/// White card with a hairline border; optionally tappable.
class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.padding = EdgeInsets.zero, this.onTap});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

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
      clipBehavior: Clip.antiAlias,
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

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.tone, this.icon});

  final String text;
  final _Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(5)),
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap, this.count, this.tone});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  /// Color for the count when it matters (issues).
  final _Tone? tone;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? _K.emerald600 : _K.gray600;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? _K.emerald50 : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? _K.emerald200 : _K.gray200)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
                if (count != null) ...[
                  const SizedBox(width: 5),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: tone?.fg ?? (selected ? _K.emerald600 : _K.gray400),
                      fontFeatures: _T.tabular,
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

/// Single-row empty state: icon, title, message and an optional action.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, this.message, this.action, this.success = false});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: success ? _K.emerald50.withValues(alpha: 0.5) : _K.gray50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: success ? _K.emerald200 : _K.gray200),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: success ? _K.emerald50 : _K.gray100, shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: success ? _K.emerald600 : _K.gray400),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _K.gray700)),
                if (message != null) Text(message!, style: const TextStyle(fontSize: 11.5, height: 1.35, color: _K.gray500)),
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
  const _Banner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        decoration: BoxDecoration(
          color: _K.red50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _K.red200),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, size: 16, color: _K.red700),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 12.5, height: 1.35, color: _K.red700))),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: _K.red700,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              child: const Text('Retry'),
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
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.emerald600)),
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
      final end = start + columns > children.length ? children.length : start + columns;
      final cells = children.sublist(start, end);
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