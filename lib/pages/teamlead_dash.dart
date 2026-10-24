// Port of features/team-lead/dashboard/TeamLeadDashboard.tsx
// (the home screen for team leads: "Team Overview").
//
// Team stats refresh every 30 s and the lead's own punches every 10 s
// (paused while the app is in the background); pull down to refresh.
//
// Compact layout:
//   [refresh-error banner]
//   Header (one line): icon · title · pending tag · date / updated · live · Broadcast
//   My day strip (one line): first in · last out · status · My dashboard
//   KPIs: My team | Present (rate bar) | Late | Pending leaves   (equal height;
//         tap one for the members or leave requests behind its number)
//   Team punches (2) | Pending approvals + Quick links (1)
//   Team roster with status filters

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:hrm_app/api/api_client.dart';
import 'package:hrm_app/auth/auth_store.dart';
import 'package:hrm_app/components/dashboard/live_dash.dart';
import 'package:hrm_app/services/empportal_service.dart';
import 'package:hrm_app/services/notification_service.dart';
import 'package:hrm_app/services/teamlead_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';

// ── Design tokens ───────────────────────────────────────────────────────────

// Tailwind colors only this screen uses (the rest come from DashK).
class _K {
  static const indigo400 = Color(0xFF818CF8);
  static const indigo700 = Color(0xFF4338CA);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald700 = Color(0xFF047857);
  static const teal50 = Color(0xFFF0FDFA);
  static const teal200 = Color(0xFF99F6E4);
  static const teal600 = Color(0xFF0D9488);
  static const amber100 = Color(0xFFFEF3C7);
  static const amber400 = Color(0xFFFBBF24);
  static const amber900 = Color(0xFF78350F);
  static const red100 = Color(0xFFFEE2E2);
  static const blue50 = Color(0xFFEFF6FF);
  static const blue200 = Color(0xFFBFDBFE);
  static const blue700 = Color(0xFF1D4ED8);
  static const rose50 = Color(0xFFFFF1F2);
  static const rose100 = Color(0xFFFFE4E6);
  static const rose700 = Color(0xFFBE123C);
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
const _red = _Tone(DashK.red50, DashK.red200, DashK.red600);
const _orange = _Tone(_K.orange50, _K.orange200, _K.orange600);
const _gray = _Tone(DashK.gray100, DashK.gray200, DashK.gray500);

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.3, color: DashK.gray900);
  static const subtitle = TextStyle(fontSize: 11.5, height: 1.3, color: DashK.gray500);
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
  static const time = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    color: DashK.gray700,
    fontFeatures: tabular,
  );
  static const columnHead = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: DashK.gray500);
}

const _cardRadius = 14.0;
const _cardPadding = EdgeInsets.fromLTRB(12, 11, 12, 10);
const _divider = Divider(height: 1, thickness: 1, color: DashK.gray100);

String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

/// Team attendance thresholds (same as before: 80% / 60%).
({Color text, Color bar}) _rateColors(int rate) => rate >= 80
    ? (text: DashK.emerald600, bar: DashK.emerald500)
    : rate >= 60
        ? (text: DashK.amber600, bar: _K.amber400)
        : (text: DashK.red600, bar: DashK.red500);

// ── Screen ──────────────────────────────────────────────────────────────────

class TeamLeadDashboard extends StatefulWidget {
  const TeamLeadDashboard({super.key});

  @override
  State<TeamLeadDashboard> createState() => _TeamLeadDashboardState();
}

class _TeamLeadDashboardState extends State<TeamLeadDashboard> with WidgetsBindingObserver {
  TeamLeadDashboardData? _data;
  EmployeeAttendance? _personal;
  List<TodayPunch> _todayPunches = const [];
  DateTime? _statsUpdated;
  bool _loading = true;
  String? _loadError;
  Timer? _statsTimer;
  Timer? _punchTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _stopPolling();
    }
  }

  void _startPolling() {
    _stopPolling();
    _statsTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
    _punchTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadPunches());
  }

  void _stopPolling() {
    _statsTimer?.cancel();
    _punchTimer?.cancel();
  }

  Future<void> _loadPunches() async {
    try {
      final res = await employeePortalService.fetchTodayPunches();
      if (!mounted) return;
      setState(() {
        _todayPunches = res.punches;
        _personal = res.today; // the lead's own status today (company date)
      });
    } catch (_) {
      // Keep the last data; the next poll retries.
    }
  }

  Future<void> _load() async {
    try {
      final stats = await teamLeadService.fetchStats();
      if (!mounted) return;
      setState(() {
        _data = stats;
        _loadError = null;
        _statsUpdated = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadError = 'Could not load your team dashboard.');
    }
    await _loadPunches();
    if (mounted && _loading) setState(() => _loading = false);
  }

  void _retryFromScratch() {
    setState(() => _loading = true);
    _load();
  }

  void _openBroadcast() {
    final user = context.read<AuthStore>().user;
    final firstName = '${user?['first_name'] ?? ''}'.trim();
    showDialog<void>(
      context: context,
      builder: (_) => _BroadcastDialog(senderName: firstName.isNotEmpty ? firstName : '${user?['username'] ?? ''}'),
    );
  }

  /// The web's TeamDetailModal, as a bottom sheet.
  void _openDetails(_Detail kind, List<TeamMember> members) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 672),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _TeamDetailSheet(kind: kind, members: members),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _DashboardSkeleton();

    final data = _data;
    if (data == null) return _ErrorState(message: _loadError, onRetry: _retryFromScratch, onRefresh: _load);

    final k = data.kpis;
    final rate = k.totalEmployees > 0 ? (k.presentToday / k.totalEmployees * 100).round() : 0;
    final rateColors = _rateColors(rate);
    final lastPunch = lastCountedPunch<TodayPunch>(_todayPunches, (p) => p.ignoreReason);

    return RefreshIndicator(
      color: DashK.indigo600,
      onRefresh: _load,
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
                tone: const _Tone(DashK.amber50, DashK.amber200, _K.amber900),
                icon: Icons.warning_amber_rounded,
                actionLabel: 'Retry',
                onAction: _load,
                child: const Text("Couldn't refresh team data. Showing the last update."),
              ),
            _Header(
              pendingLeaves: k.pendingLeaves,
              updatedAt: _statsUpdated,
              wide: sm,
              onBroadcast: _openBroadcast,
            ),
            _MyDayStrip(personal: _personal, hasPunch: lastPunch != null, wide: sm),
            DashGrid(
              columns: md ? 4 : 2,
              gap: 10,
              children: [
                _KpiCard(
                  label: 'My team',
                  value: '${k.totalEmployees}',
                  footer: Text(
                    '${k.absentToday} absent today',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _T.caption.copyWith(color: k.absentToday > 0 ? DashK.red600 : DashK.gray400),
                  ),
                  semantics: '${k.absentToday} absent today',
                  tone: _indigo,
                  icon: Icons.groups_outlined,
                  onTap: () => _openDetails(_Detail.team, data.teamMembers),
                ),
                _KpiCard(
                  label: 'Present',
                  value: '${k.presentToday}',
                  badge: Text(
                    '$rate%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: rateColors.text,
                      fontFeatures: _T.tabular,
                    ),
                  ),
                  footer: _RateBar(rate: rate, color: rateColors.bar),
                  semantics: '$rate percent of the team present',
                  tone: _emerald,
                  icon: Icons.how_to_reg_outlined,
                  onTap: () => _openDetails(_Detail.present, data.teamMembers),
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
                  semantics: '${k.lateAfterLunchToday} late after lunch',
                  tone: _amber,
                  icon: Icons.schedule_rounded,
                  onTap: () => _openDetails(_Detail.lateIn, data.teamMembers),
                ),
                _KpiCard(
                  label: 'Pending leaves',
                  value: '${k.pendingLeaves}',
                  highlight: k.pendingLeaves > 0,
                  footer: Text(
                    k.pendingLeaves > 0 ? 'Needs your review' : 'All caught up',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _T.caption.copyWith(color: k.pendingLeaves > 0 ? DashK.red600 : DashK.gray400),
                  ),
                  semantics: k.pendingLeaves > 0 ? 'Needs your review' : 'All caught up',
                  tone: k.pendingLeaves > 0 ? _red : _teal,
                  icon: Icons.description_outlined,
                  onTap: () => _openDetails(_Detail.leaves, data.teamMembers),
                ),
              ],
            ),
            _Split(
              wide: lg,
              gap: gap,
              flex: const [2, 1],
              children: [
                _TeamPunchFeed(punches: data.recentPunches),
                _QuickActions(pendingLeaves: k.pendingLeaves),
              ],
            ),
            _Roster(
              members: data.teamMembers,
              total: k.totalEmployees,
              showLastOut: sm,
              showDepartment: md,
              showLate: lg,
              hPad: 12,
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
}

// ── First-load failure ──────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry, required this.onRefresh});

  final String? message;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: DashK.indigo600,
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(color: DashK.red50, shape: BoxShape.circle),
                        child: const Icon(Icons.cloud_off_outlined, size: 20, color: DashK.red500),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        message ?? 'Dashboard data is unavailable.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: DashK.gray900),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Check your connection, then retry or pull down to refresh.',
                        textAlign: TextAlign.center,
                        style: _T.subtitle,
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: DashK.indigo600,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry'),
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

// ── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.pendingLeaves,
    required this.updatedAt,
    required this.wide,
    required this.onBroadcast,
  });

  final int pendingLeaves;
  final DateTime? updatedAt;
  final bool wide;
  final VoidCallback onBroadcast;

  @override
  Widget build(BuildContext context) {
    final meta = [
      formatEEEMMMd(DateTime.now()),
      if (updatedAt != null) 'updated ${TimeOfDay.fromDateTime(updatedAt!).format(context)}',
    ].join(', ');

    final broadcast = wide
        ? _GradientButton(
            onTap: onBroadcast,
            radius: 9,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.campaign_outlined, size: 15, color: Colors.white),
                SizedBox(width: 6),
                Text('Broadcast', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white)),
              ],
            ),
          )
        : Tooltip(
            message: 'Broadcast alert to your team',
            child: _GradientButton(
              onTap: onBroadcast,
              radius: 9,
              padding: const EdgeInsets.all(8),
              child: const Icon(Icons.campaign_outlined, size: 18, color: Colors.white),
            ),
          );

    return Row(
      children: [
        const _IconBox(icon: Icons.groups_rounded, tone: _indigo, size: 36),
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
                        'Team overview',
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
                  if (pendingLeaves > 0) ...[
                    const SizedBox(width: 8),
                    _Tag(text: '$pendingLeaves pending', tone: _amber),
                  ],
                ],
              ),
              Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.subtitle),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const _LiveIndicator(dot: _K.indigo400, fg: DashK.indigo600),
        const SizedBox(width: 10),
        broadcast,
      ],
    );
  }
}

// ── The lead's own day ──────────────────────────────────────────────────────

/// One-line strip: first in · last out · status · link to the personal dashboard.
class _MyDayStrip extends StatelessWidget {
  const _MyDayStrip({required this.personal, required this.hasPunch, required this.wide});

  final EmployeeAttendance? personal;
  final bool hasPunch;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final p = personal;
    final hasStatus = p != null && p.punchStatus != null && p.punchStatus != 'NO_PUNCH';
    final (statusText, statusColor) = hasStatus
        ? (
            attendanceStatus(p!.dayType, p.punchStatus, p.leaveName).label,
            p.punchStatus == 'IN_PROGRESS' ? DashK.emerald600 : DashK.amber600,
          )
        : (hasPunch ? 'Punched' : 'Not punched', DashK.gray700);
    final firstIn = p?.firstIn != null ? fmtWallTime(p!.firstIn) : '--';
    final lastOut = p?.lastOut != null ? fmtWallTime(p!.lastOut) : '--';

    Widget item(String label, String value, [Color color = DashK.gray900]) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label.isNotEmpty) Text('$label ', style: const TextStyle(fontSize: 11.5, color: DashK.indigo500)),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color, fontFeatures: _T.tabular),
              ),
            ),
          ],
        );

    return Semantics(
      container: true,
      label: 'My day: first in $firstIn, last out $lastOut, status $statusText',
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_cardRadius),
          border: Border.all(color: DashK.indigo100),
          gradient: LinearGradient(
            colors: [
              Color.alphaBlend(DashK.indigo500.withValues(alpha: 0.05), Colors.white),
              Color.alphaBlend(DashK.purple500.withValues(alpha: 0.04), Colors.white),
            ],
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_outline_rounded, size: 16, color: DashK.indigo600),
            const SizedBox(width: 6),
            const Text('My day', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: DashK.gray900)),
            const SizedBox(width: 12),
            Expanded(
              child: ExcludeSemantics(
                child: Wrap(
                  spacing: wide ? 18 : 12,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    item('In', firstIn),
                    item('Out', lastOut),
                    item(wide ? 'Status' : '', statusText, statusColor),
                  ],
                ),
              ),
            ),
            TextButton(
              // The web button opens /portal, which shows this team dashboard
              // again; "My Personal Dashboard" is what it's meant to open.
              onPressed: () => context.go('/portal/dashboard'),
              style: TextButton.styleFrom(
                foregroundColor: DashK.indigo600,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: Text(wide ? 'My dashboard' : 'Open'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── KPI cards ───────────────────────────────────────────────────────────────

/// Icon + label/value on one row, then one footer line, so every card in the
/// strip has the same height. Tapping opens the details behind the number.
class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.footer,
    required this.semantics,
    required this.tone,
    required this.icon,
    this.badge,
    this.highlight = false,
    this.onTap,
  });

  final String label;
  final String value;
  final Widget footer;
  final String semantics;
  final _Tone tone;
  final IconData icon;

  /// Shown right after the value (the attendance %).
  final Widget? badge;

  /// Colors the number (used for pending leaves).
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: onTap != null,
      label: '$label: $value. $semantics',
      hint: onTap != null ? 'Show details' : null,
      // The child's semantics are excluded, so the tap is declared here too.
      onTap: onTap,
      excludeSemantics: true,
      child: _Surface(
        onTap: onTap,
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
                      Row(
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                value,
                                style: _T.value.copyWith(color: highlight ? tone.fg : DashK.gray900),
                              ),
                            ),
                          ),
                          if (badge != null) ...[const SizedBox(width: 6), badge!],
                        ],
                      ),
                    ],
                  ),
                ),
                // The web's ↗ "view details" marker.
                if (onTap != null) const Icon(Icons.arrow_outward_rounded, size: 14, color: DashK.gray400),
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

class _RateBar extends StatelessWidget {
  const _RateBar({required this.rate, required this.color});

  final int rate;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 4,
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

// ── KPI details (the web's TeamDetailModal) ─────────────────────────────────

enum _Detail {
  team('My team', 'Everyone in your team and their status today', Icons.groups_outlined, _indigo),
  present('Present today', 'Team members who have attended today', Icons.how_to_reg_outlined, _emerald),
  lateIn('Late arrivals', 'Late in the morning or back late from lunch today', Icons.schedule_rounded, _amber),
  leaves('Pending leaves', 'Leave requests waiting for your decision', Icons.description_outlined, _red);

  const _Detail(this.title, this.subtitle, this.icon, this.tone);

  final String title;
  final String subtitle;
  final IconData icon;
  final _Tone tone;
}

const _presentTypes = ['PRESENT', 'FULL_DAY', 'HALF_DAY'];

bool _isPresent(TeamMember m) =>
    m.dayType != null ? _presentTypes.contains(m.dayType) : (m.status == 'Present' || m.status == 'Half Day');

/// A leave request still waiting for the team lead (and HR).
class _PendingLeave {
  const _PendingLeave({
    required this.employeeName,
    required this.leaveTypeName,
    required this.startDate,
    required this.endDate,
    required this.reason,
  });

  final String employeeName;
  final String leaveTypeName;
  final String startDate;
  final String endDate;
  final String reason;
}

class _TeamDetailSheet extends StatefulWidget {
  const _TeamDetailSheet({required this.kind, required this.members});

  final _Detail kind;
  final List<TeamMember> members;

  @override
  State<_TeamDetailSheet> createState() => _TeamDetailSheetState();
}

class _TeamDetailSheetState extends State<_TeamDetailSheet> {
  List<_PendingLeave> _leaves = const [];
  late bool _loading = widget.kind == _Detail.leaves;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    if (widget.kind == _Detail.leaves) _loadLeaves();
  }

  /// Requests pending for both the team lead and HR (the web's filter).
  Future<void> _loadLeaves() async {
    try {
      final res = await api.get('/core/leaves/requests/');
      final data = res.data;
      final list = data is Map ? data['results'] : data;
      final pending = <_PendingLeave>[
        for (final e in (list is List ? list : const []))
          if (e is Map && e['tl_status'] == 'PENDING' && e['status'] == 'PENDING')
            _PendingLeave(
              employeeName: '${e['employee_name'] ?? ''}',
              leaveTypeName: '${e['leave_type_name'] ?? ''}',
              startDate: '${e['start_date'] ?? ''}',
              endDate: '${e['end_date'] ?? ''}',
              reason: '${e['reason'] ?? ''}',
            ),
      ];
      if (mounted) setState(() => _leaves = pending);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load leave requests. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtDay(String d) {
    final date = parseDateOnly(d);
    return date == null ? d : formatDDMMM(date);
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final q = _search.trim().toLowerCase();

    var list = widget.members;
    if (kind == _Detail.present) list = list.where(_isPresent).toList();
    if (kind == _Detail.lateIn) {
      list = list.where((m) => _isPresent(m) && (m.lateMinutes > 0 || m.lateAfterLunchMinutes > 0)).toList();
    }
    list = list
        .where((m) => q.isEmpty || m.name.toLowerCase().contains(q) || m.employeeCode.toLowerCase().contains(q))
        .toList();
    final shownLeaves = _leaves.where((l) => q.isEmpty || l.employeeName.toLowerCase().contains(q)).toList();
    final count = kind == _Detail.leaves ? shownLeaves.length : list.length;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 6, 10),
              child: Row(
                children: [
                  _IconBox(icon: kind.icon, tone: kind.tone, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: kind.title,
                              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: DashK.gray900),
                            ),
                            if (!_loading)
                              TextSpan(
                                text: '  $count',
                                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: DashK.gray400),
                              ),
                          ]),
                        ),
                        Text(kind.subtitle, style: _T.subtitle),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20, color: DashK.gray400),
                  ),
                ],
              ),
            ),
            _divider,

            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                style: const TextStyle(fontSize: 13, color: DashK.gray900),
                decoration: InputDecoration(
                  hintText: kind == _Detail.leaves ? 'Search employee name' : 'Search name or employee code',
                  hintStyle: const TextStyle(fontSize: 13, color: DashK.gray400),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18, color: DashK.gray400),
                  filled: true,
                  fillColor: DashK.gray50,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: DashK.gray200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: DashK.indigo500, width: 1.5),
                  ),
                ),
              ),
            ),

            // List
            Expanded(child: _list(list, shownLeaves, count, q.isNotEmpty)),

            // Footer
            _divider,
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                child: Text(
                  kind == _Detail.leaves ? 'Tap a request to open Team Leave Requests.' : "Today's attendance for your team.",
                  style: _T.caption,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<TeamMember> members, List<_PendingLeave> leaves, int count, bool searching) {
    if (_loading) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, __) => const _Bone(height: 48, radius: 10),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: DashK.red600)),
        ),
      );
    }
    if (count == 0) {
      return Center(
        child: Text(searching ? 'No matches.' : 'Nothing to show for today.', style: _T.subtitle),
      );
    }

    if (widget.kind == _Detail.leaves) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        itemCount: leaves.length,
        separatorBuilder: (_, __) => _divider,
        itemBuilder: (_, i) => _leaveRow(leaves[i]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      itemCount: members.length,
      separatorBuilder: (_, __) => _divider,
      itemBuilder: (_, i) => _memberRow(members[i]),
    );
  }

  Widget _leaveRow(_PendingLeave l) {
    final dates = l.endDate != l.startDate ? '${_fmtDay(l.startDate)} – ${_fmtDay(l.endDate)}' : _fmtDay(l.startDate);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        final router = GoRouter.of(context);
        Navigator.of(context).pop();
        router.go('/team/leaves');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.employeeName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: DashK.gray900)),
                  if (l.reason.isNotEmpty)
                    Text(l.reason, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.subtitle),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _Tag(text: l.leaveTypeName, tone: const _Tone(_K.blue50, _K.blue200, _K.blue700)),
                const SizedBox(height: 4),
                Text(dates, style: const TextStyle(fontSize: 11, color: DashK.gray500, fontFeatures: _T.tabular)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberRow(TeamMember m) {
    final status = attendanceStatus(m.dayType, m.punchStatus, m.leaveName);
    final firstIn = m.firstIn ?? '';

    Widget? detail;
    if (widget.kind == _Detail.lateIn) {
      detail = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.lateMinutes > 0)
            Text(
              '${m.lateMinutes}m late in${firstIn.isNotEmpty ? ' · $firstIn' : ''}',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: DashK.red600),
            ),
          if (m.lateAfterLunchMinutes > 0)
            Text(
              '${m.lateAfterLunchMinutes}m late after lunch',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _K.orange600),
            ),
        ],
      );
    } else if (firstIn.isNotEmpty) {
      final end = (m.lastOut != null && m.lastOut!.isNotEmpty) ? ' – ${m.lastOut}' : (m.inOffice ? ' – Working' : '');
      detail = Text('$firstIn$end', style: const TextStyle(fontSize: 11, color: DashK.gray600, fontFeatures: _T.tabular));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: DashK.indigo50, shape: BoxShape.circle),
            child: Text(
              _initials(m.name),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: DashK.indigo600),
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
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: DashK.gray900),
                ),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: m.employeeCode, style: const TextStyle(fontFeatures: _T.tabular)),
                    if (m.designation.isNotEmpty) TextSpan(text: ' · ${m.designation}'),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: DashK.gray500),
                ),
                if (detail != null) ...[const SizedBox(height: 2), detail],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: status.hint ?? '',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: status.style.bg,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: status.style.border),
              ),
              child: Text(
                status.label,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: status.style.fg),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Team live punches ───────────────────────────────────────────────────────

class _TeamPunchFeed extends StatelessWidget {
  const _TeamPunchFeed({required this.punches});

  final List<TeamPunch> punches;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            icon: Icons.monitor_heart_outlined,
            tone: _indigo,
            title: 'Team punches',
            subtitle: punches.isEmpty ? null : '${punches.length} recent',
            trailing: const _LiveIndicator(),
          ),
          const SizedBox(height: 4),
          if (punches.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 8),
              child: _EmptyState(
                icon: Icons.schedule_rounded,
                title: 'No team activity yet today',
                message: 'Punches from your team appear here as they happen.',
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const ClampingScrollPhysics(),
                itemCount: punches.length,
                separatorBuilder: (_, __) => _divider,
                itemBuilder: (_, i) => _TeamPunchRow(punch: punches[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _TeamPunchRow extends StatelessWidget {
  const _TeamPunchRow({required this.punch});

  final TeamPunch punch;

  @override
  Widget build(BuildContext context) {
    final isIn = isInPunch(punch.punchType, punch.ignoreReason);
    final tone = isIn ? _emerald : _amber;
    final hint = punchLabelHint(punch.ignoreReason);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          _IconBox(icon: isIn ? Icons.login_rounded : Icons.logout_rounded, tone: tone, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: punch.employeeName,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: DashK.gray900),
                ),
                TextSpan(
                  text: '  ${punch.deviceName ?? punch.source}',
                  style: const TextStyle(fontSize: 11, color: DashK.gray400),
                ),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (punch.ignoreReason != null) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: hint ?? '',
              triggerMode: TooltipTriggerMode.tap,
              child: _MiniChip(
                text: punchLabel(punch.punchType, punch.ignoreReason),
                tone: _gray,
                icon: Icons.info_outline_rounded,
              ),
            ),
          ],
          const SizedBox(width: 8),
          Text(fmtWallTime(punch.timestamp), style: _T.time),
        ],
      ),
    );
  }
}

// ── Quick actions ───────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.pendingLeaves});

  final int pendingLeaves;

  static const _links = [
    ('Team leave requests', '/team/leaves', Icons.event_note_outlined),
    ('Team attendance', '/team/attendance', Icons.fact_check_outlined),
    ('Apply for my leave', '/portal/leaves', Icons.beach_access_outlined),
    ('My attendance', '/portal/attendance', Icons.calendar_month_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pendingLeaves > 0) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            decoration: BoxDecoration(
              color: DashK.amber50,
              borderRadius: BorderRadius.circular(_cardRadius),
              border: Border.all(color: DashK.amber200),
            ),
            child: Row(
              children: [
                const Icon(Icons.pending_actions_outlined, size: 18, color: DashK.amber600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$pendingLeaves leave request${pendingLeaves != 1 ? 's' : ''} waiting',
                    maxLines: 2,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _K.amber900),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: DashK.amber600,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => context.go('/team/leaves'),
                  child: const Text('Review'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        _Surface(
          padding: EdgeInsets.zero,
          clip: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Text('Quick links', style: _T.title),
              ),
              for (final (i, (title, route, icon)) in _links.indexed) ...[
                if (i > 0) const Padding(padding: EdgeInsets.only(left: 46), child: _divider),
                InkWell(
                  onTap: () => context.go(route),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        _IconBox(icon: icon, tone: _gray, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: DashK.gray700),
                          ),
                        ),
                        if (route == '/team/leaves' && pendingLeaves > 0) ...[
                          _CountBadge(count: pendingLeaves, tone: _amber),
                          const SizedBox(width: 4),
                        ],
                        const Icon(Icons.chevron_right_rounded, size: 18, color: DashK.gray300),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 2),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Team roster ─────────────────────────────────────────────────────────────

class _Roster extends StatefulWidget {
  const _Roster({
    required this.members,
    required this.total,
    required this.showLastOut,
    required this.showDepartment,
    required this.showLate,
    required this.hPad,
  });

  final List<TeamMember> members;
  final int total;

  // Columns appear as the screen gets wider, like the web table.
  final bool showLastOut;
  final bool showDepartment;
  final bool showLate;
  final double hPad;

  @override
  State<_Roster> createState() => _RosterState();
}

class _RosterState extends State<_Roster> {
  static final _filters = <(String, bool Function(TeamMember))>[
    ('All', (TeamMember _) => true),
    ('Present', (TeamMember m) => m.status == 'Present' || m.status == 'Late' || m.status == 'Half Day'),
    ('Late', (TeamMember m) => m.status == 'Late' || m.lateMinutes > 0 || m.lateAfterLunchMinutes > 0),
    ('Absent', (TeamMember m) => m.status == 'Absent'),
    ('On leave', (TeamMember m) => m.dayType == 'ON_LEAVE'),
  ];

  int _filter = 0;

  Widget _row(List<(int, Widget)> cells, {Color? bg, double vPad = 7}) {
    return Container(
      color: bg,
      padding: EdgeInsets.symmetric(horizontal: widget.hPad, vertical: vPad),
      child: Row(
        children: [
          for (final (i, (flex, cell)) in cells.indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(flex: flex, child: cell),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.members;
    final counts = [for (final f in _filters) members.where(f.$2).length];
    final visible = members.where(_filters[_filter].$2).toList();

    final chips = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _filters.length; i++)
          if (i == 0 || counts[i] > 0 || i == _filter) ...[
            if (i > 0) const SizedBox(width: 5),
            _FilterChip(
              label: _filters[i].$1,
              count: counts[i],
              selected: i == _filter,
              onTap: () => setState(() => _filter = i),
            ),
          ],
      ],
    );

    return _Surface(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title and filters on one row when there's room.
          Padding(
            padding: EdgeInsets.fromLTRB(widget.hPad, 10, widget.hPad, 8),
            child: LayoutBuilder(
              builder: (context, c) {
                final header = _CardHeader(
                  icon: Icons.badge_outlined,
                  tone: _indigo,
                  title: 'Team roster',
                  subtitle: '${widget.total} direct report${widget.total != 1 ? 's' : ''}',
                );
                if (members.isEmpty) return header;
                if (c.maxWidth >= 640) {
                  return Row(
                    children: [
                      Expanded(child: header),
                      const SizedBox(width: 10),
                      Flexible(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: chips),
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: 8),
                    SingleChildScrollView(scrollDirection: Axis.horizontal, child: chips),
                  ],
                );
              },
            ),
          ),
          _divider,
          _row(
            [
              (4, const Text('Member', style: _T.columnHead)),
              if (widget.showDepartment) (3, const Text('Department', style: _T.columnHead)),
              (3, const Text('Status', style: _T.columnHead)),
              (widget.showLastOut ? 2 : 3, const Text('First in', style: _T.columnHead)),
              if (widget.showLastOut) (2, const Text('Last out', style: _T.columnHead)),
              if (widget.showLate) (2, const Text('Late', style: _T.columnHead)),
            ],
            bg: DashK.gray50,
            vPad: 6,
          ),
          _divider,
          if (members.isEmpty)
            Padding(
              padding: EdgeInsets.all(widget.hPad),
              child: const _EmptyState(
                icon: Icons.group_off_outlined,
                title: 'No team members assigned',
                message: 'Members appear here once HR assigns them to you.',
              ),
            )
          else if (visible.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.hPad, vertical: 20),
              child: const Text(
                'No team members match this filter.',
                textAlign: TextAlign.center,
                style: _T.subtitle,
              ),
            )
          else
            for (final (i, m) in visible.indexed) ...[
              if (i > 0) _divider,
              _row([
                (4, _MemberCell(member: m)),
                if (widget.showDepartment)
                  (
                    3,
                    Text(
                      m.departmentName.isNotEmpty ? m.departmentName : (m.branchName.isNotEmpty ? m.branchName : '—'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: DashK.gray500),
                    ),
                  ),
                (3, Align(alignment: Alignment.centerLeft, child: _StatusBadge(member: m))),
                (widget.showLastOut ? 2 : 3, _TimeText(m.firstIn)),
                if (widget.showLastOut) (2, _TimeText(m.lastOut)),
                if (widget.showLate) (2, _LateCell(member: m)),
              ]),
            ],
        ],
      ),
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
    final fg = selected ? DashK.indigo600 : DashK.gray600;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? DashK.indigo50 : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? DashK.indigo200 : DashK.gray200)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: selected ? DashK.indigo500 : DashK.gray400,
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

class _MemberCell extends StatelessWidget {
  const _MemberCell({required this.member});

  final TeamMember member;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final (bg, fg) = m.status == 'Present'
        ? (_K.emerald100, _K.emerald700)
        : m.status == 'Absent'
            ? (_K.red100, DashK.red700)
            : (m.status == 'Late' || m.lateMinutes > 0)
                ? (_K.amber100, DashK.amber700)
                : (DashK.gray100, DashK.gray600);

    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Text(
            _initials(m.name),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.25, color: DashK.gray900),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '#${m.employeeCode}',
                      style: const TextStyle(color: DashK.gray400, fontFeatures: _T.tabular),
                    ),
                    if (m.designation.isNotEmpty) TextSpan(text: '  ${m.designation}'),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, height: 1.25, color: DashK.gray500),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.member});

  final TeamMember member;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final tone = m.status == 'Present'
        ? const _Tone(DashK.emerald50, DashK.emerald200, _K.emerald700)
        : m.status == 'Absent'
            ? const _Tone(DashK.red50, DashK.red200, DashK.red700)
            : m.dayType == 'ON_LEAVE'
                ? const _Tone(_K.blue50, _K.blue200, _K.blue700)
                : (m.status == 'Weekend' || m.status == 'Off Day')
                    ? const _Tone(DashK.gray100, DashK.gray200, DashK.gray500)
                    : m.status == 'Half Day'
                        ? const _Tone(DashK.indigo50, DashK.indigo200, _K.indigo700)
                        : const _Tone(DashK.gray50, DashK.gray200, DashK.gray400);

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: tone.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: tone.border),
        ),
        child: Text(m.status, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: tone.fg)),
      ),
    );
  }
}

class _TimeText extends StatelessWidget {
  const _TimeText(this.value);

  final String? value;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final empty = v == null || v.isEmpty;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        empty ? '--' : v,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: empty ? DashK.gray300 : DashK.gray700,
          fontFeatures: _T.tabular,
        ),
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
    if (m.lateMinutes <= 0 && m.lateAfterLunchMinutes <= 0) {
      return const Text('—', style: TextStyle(fontSize: 12.5, color: DashK.gray300));
    }
    return Wrap(
      spacing: 4,
      runSpacing: 3,
      children: [
        if (m.lateMinutes > 0) _MiniChip(text: '+${m.lateMinutes}m in', tone: _red),
        if (m.lateAfterLunchMinutes > 0) _MiniChip(text: '+${m.lateAfterLunchMinutes}m lunch', tone: _orange),
      ],
    );
  }
}

// ── Broadcast alert composer ────────────────────────────────────────────────

class _BroadcastDialog extends StatefulWidget {
  const _BroadcastDialog({required this.senderName});

  final String senderName;

  @override
  State<_BroadcastDialog> createState() => _BroadcastDialogState();
}

class _BroadcastDialogState extends State<_BroadcastDialog> {
  final _title = TextEditingController();
  final _message = TextEditingController();
  bool _sending = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    _message.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  bool get _canSend => !_sending && _title.text.trim().isNotEmpty && _message.text.trim().isNotEmpty;

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() {
      _sending = true;
      _error = null;
      _success = null;
    });
    try {
      final res = await notificationService.sendBroadcast(
        targetGroup: 'MY_TEAM',
        title: _title.text,
        message: _message.text,
      );
      if (!mounted) return;
      setState(() {
        _success = res.message.isNotEmpty ? res.message : 'Alert sent to your team.';
        _title.clear();
        _message.clear();
      });
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) Navigator.of(context).pop();
      });
    } catch (err) {
      if (!mounted) return;
      var message = 'The alert could not be sent. Try again.';
      if (err is DioException && err.response?.data is Map) {
        final e = (err.response!.data as Map)['error'];
        if (e is String) message = e;
      }
      setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const _IconBox(icon: Icons.campaign_outlined, tone: _emerald, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Team announcement',
                          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: DashK.gray900),
                        ),
                        Text.rich(
                          TextSpan(
                            text: 'To all your team members, from ',
                            style: const TextStyle(fontSize: 11.5, color: DashK.gray500),
                            children: [
                              TextSpan(
                                text: widget.senderName,
                                style: const TextStyle(fontWeight: FontWeight.w600, color: _K.emerald700),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20, color: DashK.gray400),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                _Notice(
                  icon: Icons.error_outline_rounded,
                  text: _error!,
                  tone: const _Tone(_K.rose50, _K.rose100, _K.rose700),
                ),
              ],
              if (_success != null) ...[
                const SizedBox(height: 10),
                _Notice(
                  icon: Icons.check_circle_outline_rounded,
                  text: _success!,
                  tone: const _Tone(DashK.emerald50, _K.emerald100, _K.emerald700),
                ),
              ],
              const SizedBox(height: 14),
              const _FieldLabel('Subject'),
              _Input(controller: _title, hint: 'e.g. Team sync at 4 PM', action: TextInputAction.next),
              const SizedBox(height: 10),
              const _FieldLabel('Message'),
              _Input(
                controller: _message,
                hint: 'Write what your team needs to know',
                lines: 3,
                action: TextInputAction.newline,
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: DashK.gray600,
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 6),
                  Opacity(
                    opacity: _canSend ? 1 : 0.5,
                    child: _GradientButton(
                      onTap: _canSend ? _send : null,
                      radius: 9,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_sending)
                            const SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          else
                            const Icon(Icons.send_rounded, size: 14, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            _sending ? 'Sending…' : 'Send to team',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: DashK.gray600)),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({required this.controller, required this.hint, this.lines = 1, this.action});

  final TextEditingController controller;
  final String hint;
  final int lines;
  final TextInputAction? action;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(color: c, width: w),
        );
    return TextField(
      controller: controller,
      minLines: lines,
      maxLines: lines == 1 ? 1 : 8,
      textInputAction: action,
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(fontSize: 13, height: 1.4, color: DashK.gray900),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: DashK.gray400),
        filled: true,
        fillColor: DashK.gray50,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        enabledBorder: border(DashK.gray200),
        focusedBorder: border(DashK.emerald500, 1.5),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.tone});

  final IconData icon;
  final String text;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: tone.bg,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: tone.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: tone.fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tone.fg)),
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
      label: 'Loading team dashboard',
      child: Column(
        children: [
          const LinearProgressIndicator(minHeight: 2, color: DashK.indigo500, backgroundColor: DashK.indigo50),
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
                        SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Bone(width: 150, height: 16),
                            SizedBox(height: 6),
                            _Bone(width: 190, height: 10),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _Bone(height: 40),
                    const SizedBox(height: 12),
                    DashGrid(
                      columns: md ? 4 : 2,
                      gap: 10,
                      children: [for (var i = 0; i < 4; i++) const _Bone(height: 76)],
                    ),
                    const SizedBox(height: 12),
                    const _Bone(height: 260),
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

/// White card with a hairline border; optionally tappable.
class _Surface extends StatelessWidget {
  const _Surface({
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.onTap,
    this.clip = false,
  });

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
        border: Border.all(color: DashK.gray100),
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
        if (subtitle != null) ...[
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, this.message});

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return DashedBox(
      background: DashK.gray50,
      color: DashK.gray200,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(color: DashK.gray100, shape: BoxShape.circle),
              child: Icon(icon, size: 16, color: DashK.gray400),
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
  const _LiveIndicator({this.dot = DashK.emerald400, this.fg = DashK.emerald600});

  final Color dot;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DashPulse(child: DashDot(color: dot)),
        const SizedBox(width: 5),
        Text('Live', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
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
  const _MiniChip({required this.text, required this.tone, this.icon});

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
          Text(
            text,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: tone.fg, fontFeatures: _T.tabular),
          ),
          if (icon != null) ...[
            const SizedBox(width: 3),
            Icon(icon, size: 10, color: tone.fg),
          ],
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: tone.border),
      ),
      child: Text(
        '$count',
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: tone.fg, fontFeatures: _T.tabular),
      ),
    );
  }
}

/// Emerald-to-teal gradient button (`from-emerald-500 to-teal-600`).
class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.onTap, required this.child, required this.radius, required this.padding});

  final VoidCallback? onTap;
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: const LinearGradient(colors: [DashK.emerald500, _K.teal600]),
          boxShadow: [
            BoxShadow(color: DashK.emerald500.withValues(alpha: 0.18), blurRadius: 5, offset: const Offset(0, 2)),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Side by side on wide screens (with optional flex), stacked on narrow ones.
class _Split extends StatelessWidget {
  const _Split({
    required this.wide,
    required this.gap,
    required this.children,
    this.flex,
  });

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