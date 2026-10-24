// Shared by AdminDashboard (HR / branch staff) and CompanyAdminDashboard.
// Both web dashboards load the same company stats and live punch feed and
// repeat the same feed, violation and trends cards; here they're written once.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hrm_app/components/dashboard/attendance_trends.dart';
import 'package:hrm_app/components/ui/app_card.dart';
import 'package:hrm_app/services/admindash_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';

/// Tailwind colors used by the dashboards.
class DashK {
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
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald400 = Color(0xFF34D399);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber200 = Color(0xFFFDE68A);
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);
  static const red50 = Color(0xFFFEF2F2);
  static const red200 = Color(0xFFFECACA);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);
  static const yellow500 = Color(0xFFEAB308);
  static const yellow600 = Color(0xFFCA8A04);
  static const purple500 = Color(0xFFA855F7);
  static const purple600 = Color(0xFF9333EA);
}

// ═════════════════════════════════════════════════════════════════════════════
// Live data + page frame
// ═════════════════════════════════════════════════════════════════════════════

typedef DashboardSections = List<Widget> Function(
  BuildContext context,
  AdminDashboardData data,
  double width,
  VoidCallback openPunchLog,
);

/// Loads the company stats and keeps them live, like both web dashboards:
/// stats every 10 s, the punch feed every 3 s (a new punch reloads the stats).
/// Polling pauses while the app is in the background; pull down to refresh.
class LiveDashboardView extends StatefulWidget {
  const LiveDashboardView({super.key, required this.sections, this.gap = 32});

  final DashboardSections sections;

  /// Space between sections (`space-y-8` = 32, `space-y-10` = 40).
  final double gap;

  @override
  State<LiveDashboardView> createState() => _LiveDashboardViewState();
}

class _LiveDashboardViewState extends State<LiveDashboardView> with WidgetsBindingObserver {
  AdminDashboardData? _data;
  bool _loading = true;
  String? _loadError;

  /// Shared with the "View all" dialog so it stays live while open.
  final _punches = ValueNotifier<List<LivePunch>>(const []);

  Timer? _statsTimer;
  Timer? _punchTimer;
  bool _polling = false;
  String? _lastPunchKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStats();
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _punches.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadStats();
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _stopPolling();
    }
  }

  void _startPolling() {
    _stopPolling();
    _statsTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadStats());
    _punchTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollPunches());
  }

  void _stopPolling() {
    _statsTimer?.cancel();
    _punchTimer?.cancel();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await adminDashboardService.fetchStats();
      if (!mounted) return;
      setState(() {
        _data = stats;
        _loadError = null;
      });
      _punches.value = stats.recentPunches;
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadError = 'Could not load dashboard data. It will retry automatically.');
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _pollPunches() async {
    if (_polling) return; // no overlapping requests
    _polling = true;
    try {
      final punches = await adminDashboardService.fetchLivePunches();
      final key = '${punches.length}:${punches.isEmpty ? '' : punches.first.id}';
      final changed = _lastPunchKey != null && key != _lastPunchKey;
      _lastPunchKey = key;
      if (!mounted) return;
      final data = _data;
      if (data != null) setState(() => _data = data.copyWith(recentPunches: punches));
      _punches.value = punches;
      if (changed) await _loadStats();
    } catch (_) {
      // Keep the last feed; the next poll retries.
    } finally {
      _polling = false;
    }
  }

  void _openPunchLog() {
    showDialog<void>(context: context, builder: (_) => _PunchLogDialog(punches: _punches));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 4, color: DashK.indigo500),
        ),
      );
    }

    final data = _data;
    if (data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _loadError ?? 'Dashboard data is unavailable.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: DashK.red600),
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: DashK.indigo600,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  setState(() => _loading = true);
                  _loadStats();
                },
                child: const Text('Retry', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => Future.wait([_loadStats(), _pollPunches()]),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sections = widget.sections(context, data, width, _openPunchLog);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(width >= 640 ? 20 : 16),
            children: [
              for (var i = 0; i < sections.length; i++) ...[
                if (i > 0) SizedBox(height: widget.gap),
                sections[i],
              ],
            ],
          );
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Live punch feed
// ═════════════════════════════════════════════════════════════════════════════

class LiveFeedCard extends StatelessWidget {
  const LiveFeedCard({
    super.key,
    required this.punches,
    required this.onViewAll,
    this.title = 'Live Punch Feed',
    this.subtitle = 'Real-time Operational Stream',
    this.titleSize = 20,
    this.columns = 1,
    this.maxHeight = 320,
    this.showDeviceIcon = false,
  });

  final List<LivePunch> punches;
  final VoidCallback onViewAll;
  final String title;
  final String subtitle;
  final double titleSize;
  final int columns;
  final double maxHeight;
  final bool showDeviceIcon;

  @override
  Widget build(BuildContext context) {
    final shown = punches.take(12).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashCardHeader(
            leading: const DashIconBox(
              bg: DashK.indigo50,
              border: DashK.indigo200,
              child: DashPulse(child: Icon(Icons.schedule, size: 20, color: DashK.indigo500)),
            ),
            title: title,
            titleSize: titleSize,
            subtitle: subtitle,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (punches.length > 8) ...[
                  DashSmallButton(label: 'View All', onTap: onViewAll),
                  const SizedBox(width: 8),
                ],
                const DashLiveBadge(),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (shown.isEmpty)
            const DashedBox(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text(
                    'NO PUNCHES TODAY',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: DashK.gray400),
                  ),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                child: DashGrid(
                  columns: columns,
                  gap: 12,
                  children: [
                    for (final p in shown) PunchTile(punch: p, showDeviceIcon: showDeviceIcon),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PunchTile extends StatelessWidget {
  const PunchTile({super.key, required this.punch, this.showDate = false, this.showDeviceIcon = false});

  final LivePunch punch;
  final bool showDate;
  final bool showDeviceIcon;

  @override
  Widget build(BuildContext context) {
    final isIn = isInPunch(punch.punchType, punch.ignoreReason);
    final label = punchLabel(punch.punchType, punch.ignoreReason);
    final hint = punchLabelHint(punch.ignoreReason);
    final date = showDate ? wallDate(punch.timestamp) : null;

    Widget badge = Container(
      width: 36,
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isIn ? DashK.emerald50 : DashK.amber50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isIn ? DashK.emerald200 : DashK.amber200),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: isIn ? DashK.emerald600 : DashK.amber600,
            ),
          ),
        ),
      ),
    );
    if (hint != null) badge = Tooltip(message: hint, child: badge);

    const deviceStyle = TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: DashK.gray400);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DashK.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DashK.gray100),
      ),
      child: Row(
        children: [
          badge,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  punch.employeeName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: DashK.gray900),
                ),
                Row(
                  children: [
                    if (showDeviceIcon) ...[
                      const Icon(Icons.smartphone, size: 10, color: DashK.gray400),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        punch.deviceName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: deviceStyle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                fmtWallTime(punch.timestamp),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: DashK.gray700,
                ),
              ),
              if (date != null)
                Text(date, style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: DashK.gray400)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PunchLogDialog extends StatelessWidget {
  const _PunchLogDialog({required this.punches});

  final ValueListenable<List<LivePunch>> punches;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 576, maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ValueListenableBuilder<List<LivePunch>>(
            valueListenable: punches,
            builder: (context, list, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.schedule, size: 20, color: DashK.indigo600),
                              SizedBox(width: 12),
                              Text(
                                'Live Punch Log',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: DashK.gray900),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Full operational stream for today (${list.length} records).',
                            style: const TextStyle(fontSize: 12, color: DashK.gray500),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      style: IconButton.styleFrom(backgroundColor: DashK.gray50),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20, color: DashK.gray500),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => PunchTile(punch: list[i], showDate: true, showDeviceIcon: true),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: DashK.gray100),
                const SizedBox(height: 16),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: DashK.gray50,
                    foregroundColor: DashK.gray500,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'CLOSE STREAM',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.5),
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

// ═════════════════════════════════════════════════════════════════════════════
// Attendance trends card
// ═════════════════════════════════════════════════════════════════════════════

class TrendsCard extends StatelessWidget {
  const TrendsCard({
    super.key,
    this.subtitle = 'Daily headcount by status with the attendance rate',
    this.chartHeight = 340,
    this.boxedIcon = false,
    this.padding = const EdgeInsets.all(24),
  });

  final String subtitle;
  final double chartHeight;
  final bool boxedIcon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final icon = boxedIcon
        ? Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: DashK.indigo50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: DashK.indigo200),
            ),
            child: const Icon(Icons.bar_chart, size: 24, color: DashK.indigo500),
          )
        : const Icon(Icons.bar_chart, size: 20, color: DashK.indigo500);

    return AppCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashCardHeader(
            title: 'Attendance Trends',
            subtitle: subtitle,
            subtitleCaps: false,
            trailing: icon,
            keepTrailingBeside: true,
          ),
          const SizedBox(height: 24),
          AttendanceTrendsChart(height: chartHeight),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Violations feed
// ═════════════════════════════════════════════════════════════════════════════

class ViolationsCard extends StatelessWidget {
  const ViolationsCard({
    super.key,
    required this.violations,
    required this.wide,
    this.title = 'Intelligence Log',
    this.subtitle = 'Live Anomaly & Violation Feed',
  });

  final List<RecentViolation> violations;
  final bool wide;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashCardHeader(
            leading: const Icon(Icons.gpp_maybe_outlined, size: 22, color: DashK.red500),
            title: title,
            subtitle: subtitle,
            trailing: DashSmallButton(
              label: 'View All Violations',
              icon: Icons.north_east,
              onTap: () => context.go('/admin/violations'),
            ),
          ),
          const SizedBox(height: 24),
          if (violations.isEmpty)
            const DashedBox(
              background: Color(0x80F9FAFB),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40, horizontal: 16),
                child: Column(
                  children: [
                    Icon(Icons.how_to_reg_outlined, size: 40, color: DashK.emerald400),
                    SizedBox(height: 12),
                    Text(
                      'No Compliance Violations Today',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DashK.gray600),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'All employee attendance punches meet configured standard parameters.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: DashK.gray400),
                    ),
                  ],
                ),
              ),
            )
          else
            for (var i = 0; i < violations.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _ViolationTile(v: violations[i], wide: wide),
            ],
        ],
      ),
    );
  }
}

class _ViolationTile extends StatelessWidget {
  const _ViolationTile({required this.v, required this.wide});

  final RecentViolation v;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final type = v.violationType.toUpperCase();
    final critical = type == 'DOUBLE_IN' || type == 'MISSING_OUT';
    final label = v.violationLabel ?? v.violationType.replaceAll('_', ' ');
    final time = v.occurredAt != null ? fmtWallTime(v.occurredAt) : '-';
    final date = v.date ?? '-';

    final details = Row(
      crossAxisAlignment: wide ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: critical ? DashK.red50 : DashK.amber50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: critical ? DashK.red200 : DashK.amber200),
          ),
          child: Icon(Icons.gpp_maybe_outlined, size: 20, color: critical ? DashK.red600 : DashK.amber600),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    v.employeeName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DashK.gray900),
                  ),
                  if (v.employeeCode != null)
                    DashChip(
                      text: v.employeeCode!,
                      mono: true,
                      bg: DashK.gray200.withValues(alpha: 0.6),
                      fg: DashK.gray600,
                    ),
                  if (v.branchName.isNotEmpty)
                    DashChip(
                      text: v.branchName.toUpperCase(),
                      bg: DashK.gray100,
                      fg: DashK.gray400,
                      border: DashK.gray200,
                    ),
                ],
              ),
              if (v.description != null) ...[
                const SizedBox(height: 4),
                Text(
                  v.description!,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.35, color: DashK.gray500),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    final status = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: critical ? DashK.red50 : DashK.amber50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: critical ? DashK.red200 : DashK.amber200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          critical
              ? const DashPulse(child: DashDot(color: DashK.red500))
              : const DashDot(color: DashK.amber500),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
                color: critical ? DashK.red700 : DashK.amber700,
              ),
            ),
          ),
        ],
      ),
    );

    final when = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DashChip(text: time, mono: true, bg: DashK.gray100, fg: DashK.gray700, border: DashK.gray200, fontSize: 11),
        if (wide && date != '-') ...[
          const SizedBox(width: 6),
          Text(date, style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: DashK.gray400)),
        ],
      ],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DashK.gray50.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DashK.gray100),
      ),
      child: wide
          ? Row(
              children: [
                Expanded(child: details),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [status, const SizedBox(height: 4), when],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: DashK.gray200.withValues(alpha: 0.6))),
                  ),
                  child: Row(
                    children: [
                      Flexible(child: status),
                      const SizedBox(width: 8),
                      const Spacer(),
                      when,
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Small building blocks
// ═════════════════════════════════════════════════════════════════════════════

/// Card title row. On narrow cards the trailing widget moves under the title
/// (unless [keepTrailingBeside] is set, for small icons).
class DashCardHeader extends StatelessWidget {
  const DashCardHeader({
    super.key,
    this.leading,
    required this.title,
    this.titleSize = 20,
    this.subtitle,
    this.subtitleCaps = true,
    this.trailing,
    this.keepTrailingBeside = false,
  });

  final Widget? leading;
  final String title;
  final double titleSize;
  final String? subtitle;
  final bool subtitleCaps;
  final Widget? trailing;
  final bool keepTrailingBeside;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: DashK.gray900,
                  ),
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    subtitleCaps ? subtitle!.toUpperCase() : subtitle!,
                    style: subtitleCaps
                        ? const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: DashK.gray400)
                        : const TextStyle(fontSize: 12, color: DashK.gray400),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    if (trailing == null) return titleBlock;

    Widget beside() => Row(
          children: [Expanded(child: titleBlock), const SizedBox(width: 12), trailing!],
        );

    if (keepTrailingBeside) return beside();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 480) return beside();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [titleBlock, const SizedBox(height: 12), trailing!],
        );
      },
    );
  }
}

/// Colored section title with a bar on the left (company admin dashboard).
class DashSectionTitle extends StatelessWidget {
  const DashSectionTitle({super.key, required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 24,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: DashK.gray900),
            ),
          ),
        ),
      ],
    );
  }
}

class DashIconBox extends StatelessWidget {
  const DashIconBox({super.key, required this.bg, required this.border, required this.child, this.radius = 12});

  final Color bg;
  final Color border;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }
}

class DashSmallButton extends StatelessWidget {
  const DashSmallButton({super.key, required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: const BorderSide(color: DashK.indigo200),
    );
    return Material(
      color: DashK.indigo50,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: DashK.indigo600),
              ),
              if (icon != null) ...[
                const SizedBox(width: 4),
                Icon(icon, size: 14, color: DashK.indigo600),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class DashLiveBadge extends StatelessWidget {
  const DashLiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: DashK.emerald50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: DashK.emerald200),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'LIVE',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: DashK.emerald600),
          ),
          SizedBox(width: 6),
          DashPulse(child: DashDot(color: DashK.emerald500, size: 5)),
        ],
      ),
    );
  }
}

class DashChip extends StatelessWidget {
  const DashChip({
    super.key,
    required this.text,
    required this.bg,
    required this.fg,
    this.border,
    this.mono = false,
    this.fontSize = 10,
  });

  final String text;
  final Color bg;
  final Color fg;
  final Color? border;
  final bool mono;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: mono ? 'monospace' : null,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: mono ? 0 : 1,
          color: fg,
        ),
      ),
    );
  }
}

class DashDot extends StatelessWidget {
  const DashDot({super.key, required this.color, this.size = 6});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Gentle fade in and out (Tailwind `animate-pulse`); still when reduce motion is on.
class DashPulse extends StatefulWidget {
  const DashPulse({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<DashPulse> createState() => _DashPulseState();
}

class _DashPulseState extends State<DashPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );
  late final Animation<double> _opacity = Tween(begin: 0.4, end: 1.0).animate(_c);
  Timer? _delayTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _delayTimer?.cancel();
      _c
        ..stop()
        ..value = 1;
    } else if (!_c.isAnimating && _delayTimer == null) {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) _c.repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _opacity, child: widget.child);
}

/// Equal-width grid (`grid grid-cols-N gap-X`).
class DashGrid extends StatelessWidget {
  const DashGrid({super.key, required this.columns, required this.gap, required this.children});

  final int columns;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = ((constraints.maxWidth - gap * (columns - 1)) / columns).floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final c in children) SizedBox(width: w, child: c)],
        );
      },
    );
  }
}

/// Box with a dashed border (`border border-dashed rounded-2xl`).
class DashedBox extends StatelessWidget {
  const DashedBox({super.key, required this.child, this.background, this.color = DashK.gray200});

  final Widget child;
  final Color? background;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _DashedBorderPainter(background, color), child: child);
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter(this.background, this.color);

  final Color? background;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), const Radius.circular(16));
    if (background != null) canvas.drawRRect(rrect, Paint()..color = background!);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 6, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.background != background || old.color != color;
}