// Port of features/admin/dashboard/CompanyAdminDashboard.tsx
// (the "/" screen for company admins).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hrm_app/components/dashboard/live_dash.dart';
import 'package:hrm_app/components/ui/app_card.dart';
import 'package:hrm_app/services/admindash_service.dart';

class CompanyAdminDashboard extends StatelessWidget {
  const CompanyAdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return LiveDashboardView(
      gap: 40, // space-y-10
      sections: (context, data, width, openPunchLog) {
        final md = width >= 768;
        final lg = width >= 1024;

        final overview = _OperationalOverview(attendanceRate: data.kpis.attendanceRate);
        final feed = LiveFeedCard(
          punches: data.recentPunches,
          onViewAll: openPunchLog,
          subtitle: 'Real-time Stream',
          titleSize: 16,
          maxHeight: 400,
          showDeviceIcon: true,
        );

        return [
          _Header(wide: md),

          // Management hub
          const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DashSectionTitle(title: 'Management Hub', color: DashK.indigo500),
              SizedBox(height: 24),
              _ActionCard(
                title: 'Provision HR / IT Staff',
                description:
                    'Create secure login credentials for branch administrators and department heads.',
                icon: Icons.person_add_alt_1_outlined,
                route: '/admin/users',
                cta: 'Access Control',
              ),
            ],
          ),

          // Enterprise assets
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DashSectionTitle(title: 'Enterprise Assets', color: DashK.emerald500),
              const SizedBox(height: 24),
              DashGrid(
                // 4 across on wide screens; 2 across on phones (the web stacks them).
                columns: lg ? 4 : 2,
                gap: lg ? 24 : 12,
                children: [
                  _MetricCard(
                    label: 'Functional Branches',
                    value: data.branchStats.length,
                    icon: Icons.apartment,
                    color: _MetricColor.blue,
                    route: '/admin/branches',
                  ),
                  _MetricCard(
                    label: 'Hardware Fleet',
                    value: data.fleet.totalDevices,
                    icon: Icons.smartphone,
                    color: _MetricColor.indigo,
                    route: '/admin/devices',
                    subValue: '${data.fleet.onlineDevices} Active Now',
                  ),
                  _MetricCard(
                    label: 'Total Workforce',
                    value: data.kpis.totalEmployees,
                    icon: Icons.groups_outlined,
                    color: _MetricColor.purple,
                    route: '/admin/employees',
                    subValue: 'Registered Profiles',
                  ),
                  _MetricCard(
                    label: 'Present Staff',
                    value: data.kpis.presentToday,
                    icon: Icons.how_to_reg_outlined,
                    color: _MetricColor.emerald,
                    route: '/admin/attendance',
                    subValue: 'Active On-Site',
                  ),
                ],
              ),
            ],
          ),

          // Recent highlights: overview + live feed (side by side on wide screens)
          if (lg)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: overview),
                const SizedBox(width: 32),
                Expanded(child: feed),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [overview, const SizedBox(height: 32), feed],
            ),

          ViolationsCard(
            violations: data.recentViolations,
            wide: width >= 640,
            title: 'Intelligence & Violation Feed',
            subtitle: 'Real-time Exception Detection Across All Branches',
          ),

          // Performance trends
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DashSectionTitle(title: 'Performance Trends', color: DashK.purple500),
              const SizedBox(height: 24),
              TrendsCard(
                subtitle: 'Daily headcount by status with the attendance rate, all branches',
                chartHeight: 360,
                boxedIcon: true,
                padding: EdgeInsets.all(width >= 640 ? 32 : 24),
              ),
            ],
          ),
        ];
      },
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: DashK.indigo50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: DashK.indigo200),
                ),
                child: const Text(
                  'ROOT CONTROL',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: DashK.indigo600),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enterprise Console',
                style: TextStyle(
                  fontSize: wide ? 36 : 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                  color: DashK.gray900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Global management and provision center',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: DashK.gray500),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        if (wide) ...[
          const Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'ENTERPRISE IDENTITY',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: DashK.gray400),
              ),
              Text(
                'GLOBAL ROOT NODE',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DashK.gray900),
              ),
            ],
          ),
          const SizedBox(width: 16),
        ],
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [DashK.indigo500, DashK.purple600],
            ),
            boxShadow: [
              BoxShadow(color: DashK.indigo500.withValues(alpha: 0.2), blurRadius: 15, offset: const Offset(0, 8)),
            ],
          ),
          child: const Icon(Icons.verified_user_outlined, size: 24, color: Colors.white),
        ),
      ],
    );
  }
}

// ── Management hub action card ──────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.route,
    required this.cta,
  });

  final String title;
  final String description;
  final IconData icon;
  final String route;
  final String cta;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    return Semantics(
      button: true,
      label: '$title. $cta',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: () => context.go(route),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: DashK.indigo200),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [DashK.indigo50, DashK.indigo100.withValues(alpha: 0.5)],
              ),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  // Large faded icon in the corner
                  Positioned(
                    right: -32,
                    bottom: -32,
                    child: Icon(icon, size: 192, color: DashK.indigo500.withValues(alpha: 0.05)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: DashK.gray200),
                          ),
                          child: const Icon(Icons.add, size: 24, color: DashK.gray700),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          title.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                            color: DashK.gray900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FractionallySizedBox(
                          widthFactor: 0.85,
                          child: Text(
                            description,
                            style: const TextStyle(fontSize: 14, height: 1.6, color: DashK.gray500),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              cta.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                                color: DashK.gray600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.arrow_forward, size: 14, color: DashK.gray600),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Enterprise asset metric cards ───────────────────────────────────────────

enum _MetricColor {
  blue(Color(0xFF3B82F6), Color(0xFFEFF6FF), Color(0xFFBFDBFE)),
  indigo(Color(0xFF6366F1), Color(0xFFEEF2FF), Color(0xFFC7D2FE)),
  purple(Color(0xFFA855F7), Color(0xFFFAF5FF), Color(0xFFE9D5FF)),
  emerald(Color(0xFF10B981), Color(0xFFECFDF5), Color(0xFFA7F3D0));

  const _MetricColor(this.fg, this.bg, this.border);

  final Color fg;
  final Color bg;
  final Color border;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.route,
    this.subValue,
  });

  final String label;
  final int value;
  final IconData icon;
  final _MetricColor color;
  final String route;
  final String? subValue;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: () => context.go(route),
        child: AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DashIconBox(
                    bg: color.bg,
                    border: color.border,
                    radius: 8,
                    child: Icon(icon, size: 20, color: color.fg),
                  ),
                  const Spacer(),
                  const Icon(Icons.north_east, size: 16, color: DashK.gray300),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                label.toUpperCase(),
                maxLines: 2,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: DashK.gray400),
              ),
              const SizedBox(height: 4),
              Text(
                '$value',
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: DashK.gray900),
              ),
              if (subValue != null) ...[
                const SizedBox(height: 4),
                Text(
                  subValue!.toUpperCase(),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: DashK.gray400),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Operational overview ────────────────────────────────────────────────────

class _OperationalOverview extends StatelessWidget {
  const _OperationalOverview({required this.attendanceRate});

  final double attendanceRate;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Operational Overview',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: DashK.gray900),
                ),
              ),
              _BarsIcon(),
            ],
          ),
          const SizedBox(height: 24),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 14, height: 1.6, color: DashK.gray500),
              children: [
                const TextSpan(text: 'Your enterprise is currently operating with an attendance rate of '),
                TextSpan(
                  text: '${attendanceRate.toStringAsFixed(1)}%',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: DashK.emerald600),
                ),
                const TextSpan(
                  text: '. All branch synchronization nodes are currently responding within '
                      'acceptable latency thresholds.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: DashK.gray50,
              foregroundColor: DashK.gray500,
              side: const BorderSide(color: DashK.gray200),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => context.go('/admin/attendance'),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'OPERATIONAL DASHBOARD',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The four little pulsing bars beside "Operational Overview".
class _BarsIcon extends StatelessWidget {
  const _BarsIcon();

  @override
  Widget build(BuildContext context) {
    Widget bar(double height, double alpha, int delayMs) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: DashPulse(
            delay: Duration(milliseconds: delayMs),
            child: Container(
              width: 4,
              height: height,
              decoration: BoxDecoration(
                color: DashK.indigo500.withValues(alpha: alpha),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        );

    return ExcludeSemantics(
      child: SizedBox(
        height: 24,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [bar(12, 0.4, 0), bar(20, 0.6, 200), bar(24, 1, 400), bar(16, 0.3, 100)],
        ),
      ),
    );
  }
}