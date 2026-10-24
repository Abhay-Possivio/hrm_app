// The two layouts of the web app:
//  - AdminShell:  AppLayout.tsx + Sidebar.tsx + Topbar.tsx (company admin, HR/IT)
//  - PortalShell: EmployeePortalLayout.tsx + EmployeePortalSidebar.tsx +
//                 EmployeePortalTopbar.tsx (employees, team leads)
//
// Phones get the menu as a drawer; screens 1024px and wider keep it docked
// on the left, like the web app.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:hrm_app/app/layout/noti_bell.dart';
import 'package:hrm_app/app/session.dart';
import 'package:hrm_app/auth/auth_store.dart';

const _pageBg = Color(0xFFF8F9FC);
const _gray50 = Color(0xFFF9FAFB);
const _gray200 = Color(0xFFE5E7EB);
const _gray400 = Color(0xFF9CA3AF);
const _gray500 = Color(0xFF6B7280);
const _gray600 = Color(0xFF4B5563);
const _gray900 = Color(0xFF111827);
const _red500 = Color(0xFFEF4444);

// ── Navigation model ────────────────────────────────────────────────────────

class NavEntry {
  const NavEntry(this.label, this.icon, this.path, {this.exact = false});

  final String label;
  final IconData icon;
  final String path;

  /// Like NavLink's `end`: only active on this exact path.
  final bool exact;

  bool isActive(String location) {
    if (exact || path == '/') return location == path;
    return location == path || location.startsWith('$path/');
  }
}

class NavSection {
  const NavSection(this.label, this.entries);

  final String label;
  final List<NavEntry> entries;
}

/// Sidebar.tsx, without the superadmin block.
List<NavSection> adminSections(Map<String, dynamic> user) {
  final isCompanyAdmin = user.isCompanyAdmin;
  final isTeamLead = user.isTeamLead;
  final isBranchStaff = !isCompanyAdmin && !isTeamLead;

  return [
    if (isCompanyAdmin || isBranchStaff) ...[
      NavSection(isCompanyAdmin ? 'Enterprise' : 'Branch', const [
        NavEntry('Dashboard', Icons.dashboard_outlined, '/'),
      ]),
      const NavSection('Workforce', [
        NavEntry('Employees', Icons.groups_outlined, '/admin/employees'),
        NavEntry('Attendance', Icons.description_outlined, '/admin/attendance', exact: true),
        NavEntry('Leave Management', Icons.description_outlined, '/admin/leaves'),
        NavEntry('Corrections', Icons.edit_outlined, '/admin/corrections'),
        NavEntry('Overtime Approval', Icons.timer_outlined, '/admin/overtime'),
        NavEntry('Holidays', Icons.event_available_outlined, '/admin/holidays'),
        NavEntry('Violations', Icons.gpp_maybe_outlined, '/admin/violations'),
        NavEntry('Reports', Icons.bar_chart_outlined, '/admin/reports'),
        NavEntry('Configuration', Icons.settings_outlined, '/admin/attendance/settings'),
        NavEntry('Hardware Devices', Icons.smartphone_outlined, '/admin/devices'),
      ]),
      if (isCompanyAdmin)
        const NavSection('Organization', [
          NavEntry('Branches', Icons.place_outlined, '/admin/branches'),
          NavEntry('Access Control', Icons.verified_user_outlined, '/admin/users'),
          NavEntry('Audit Trail', Icons.history, '/audit'),
        ]),
    ],
    if (isTeamLead)
      const NavSection('Team Management', [
        NavEntry('Team Dashboard', Icons.dashboard_outlined, '/'),
        NavEntry('Leave Requests', Icons.description_outlined, '/team/leaves'),
        NavEntry('Team Attendance', Icons.bar_chart_outlined, '/team/attendance'),
        NavEntry('Team Corrections', Icons.edit_outlined, '/team/corrections'),
        NavEntry('Team Overtime', Icons.timer_outlined, '/team/overtime'),
      ]),
  ];
}

/// EmployeePortalSidebar.tsx
List<NavSection> portalSections(Map<String, dynamic> user) {
  final isTeamLead = user.isTeamLead;
  return [
    NavSection('Self Service', [
      NavEntry(
        isTeamLead ? 'Team Dashboard' : 'My Dashboard',
        Icons.dashboard_outlined,
        isTeamLead ? '/team/dashboard' : '/portal',
        exact: true,
      ),
      if (isTeamLead)
        const NavEntry('My Personal Dashboard', Icons.account_circle_outlined, '/portal/dashboard'),
      const NavEntry('My Attendance', Icons.calendar_month_outlined, '/portal/attendance'),
      const NavEntry('Apply for Leave', Icons.assignment_outlined, '/portal/leaves'),
      const NavEntry('Alerts & Messages', Icons.notifications_none, '/portal/alerts'),
    ]),
    const NavSection('Personal', [
      NavEntry('My Profile', Icons.account_circle_outlined, '/portal/profile'),
    ]),
    if (isTeamLead)
      const NavSection('Team Management', [
        NavEntry('Team Dashboard', Icons.dashboard_outlined, '/team/dashboard'),
        NavEntry('Team Attendance', Icons.bar_chart_outlined, '/team/attendance'),
        NavEntry('Team Leave Requests', Icons.assignment_turned_in_outlined, '/team/leaves'),
        NavEntry('Team Corrections', Icons.edit_outlined, '/team/corrections'),
        NavEntry('Team Overtime', Icons.timer_outlined, '/team/overtime'),
      ]),
  ];
}

// ── Sidebar styles (indigo console vs. emerald portal) ──────────────────────

class _NavStyle {
  const _NavStyle({
    required this.width,
    required this.padding,
    required this.logoSize,
    required this.logoRadius,
    required this.logoGradient,
    required this.logoInitialSize,
    required this.logoNameSize,
    required this.logoGap,
    required this.labelSize,
    required this.labelColor,
    required this.sectionGap,
    required this.itemPadding,
    required this.itemRadius,
    required this.itemFontSize,
    required this.itemWeight,
    required this.iconSize,
    required this.iconGap,
    required this.activeBg,
    required this.activeFg,
    required this.activeBorder,
  });

  final double width;
  final EdgeInsets padding;
  final double logoSize;
  final double logoRadius;
  final List<Color> logoGradient;
  final double logoInitialSize;
  final double logoNameSize;
  final double logoGap;
  final double labelSize;
  final Color labelColor;
  final double sectionGap;
  final EdgeInsets itemPadding;
  final double itemRadius;
  final double itemFontSize;
  final FontWeight itemWeight;
  final double iconSize;
  final double iconGap;
  final Color activeBg;
  final Color activeFg;
  final Color activeBorder;

  // Sizes are a little larger than the compact web sidebar so items are
  // comfortable to tap.
  static const admin = _NavStyle(
    width: 250,
    padding: EdgeInsets.all(16),
    logoSize: 28,
    logoRadius: 6,
    logoGradient: [Color(0xFF6366F1), Color(0xFFA855F7)],
    logoInitialSize: 14,
    logoNameSize: 16,
    logoGap: 24,
    labelSize: 9,
    labelColor: _gray400,
    sectionGap: 16,
    itemPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    itemRadius: 8,
    itemFontSize: 13,
    itemWeight: FontWeight.w600,
    iconSize: 18,
    iconGap: 10,
    activeBg: Color(0xFFEEF2FF),
    activeFg: Color(0xFF4338CA),
    activeBorder: Color(0xFFE0E7FF),
  );

  static const portal = _NavStyle(
    width: 280,
    padding: EdgeInsets.all(24),
    logoSize: 32,
    logoRadius: 8,
    logoGradient: [Color(0xFF10B981), Color(0xFF14B8A6)],
    logoInitialSize: 18,
    logoNameSize: 18,
    logoGap: 40,
    labelSize: 10,
    labelColor: _gray600,
    sectionGap: 32,
    itemPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    itemRadius: 12,
    itemFontSize: 14,
    itemWeight: FontWeight.w500,
    iconSize: 20,
    iconGap: 12,
    activeBg: Color(0xFFECFDF5),
    activeFg: Color(0xFF059669),
    activeBorder: Color(0xFFA7F3D0),
  );
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.style,
    required this.companyName,
    required this.sections,
    required this.location,
  });

  final _NavStyle style;
  final String companyName;
  final List<NavSection> sections;
  final String location;

  void _go(BuildContext context, String path) {
    Scaffold.maybeOf(context)?.closeDrawer();
    if (path != location) context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: style.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo
            Padding(
              padding: EdgeInsets.only(bottom: style.logoGap),
              child: Row(
                children: [
                  Container(
                    width: style.logoSize,
                    height: style.logoSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(style.logoRadius),
                      gradient: LinearGradient(
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                        colors: style.logoGradient,
                      ),
                    ),
                    child: Text(
                      companyName.characters.first.toUpperCase(),
                      style: TextStyle(
                        fontSize: style.logoInitialSize,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      companyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: style.logoNameSize,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: _gray900,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Navigation
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (var s = 0; s < sections.length; s++) ...[
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        style.itemPadding.left,
                        s == 0 ? 0 : style.sectionGap,
                        0,
                        6,
                      ),
                      child: Text(
                        sections[s].label.toUpperCase(),
                        style: TextStyle(
                          fontSize: style.labelSize,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: style.labelColor,
                        ),
                      ),
                    ),
                    for (final entry in sections[s].entries)
                      _NavTile(
                        style: style,
                        icon: entry.icon,
                        label: entry.label,
                        active: entry.isActive(location),
                        onTap: () => _go(context, entry.path),
                      ),
                  ],
                ],
              ),
            ),

            // Logout
            _NavTile(
              style: style,
              icon: Icons.logout,
              label: 'Logout',
              active: false,
              color: _red500.withValues(alpha: 0.8),
              onTap: () {
                Scaffold.maybeOf(context)?.closeDrawer();
                context.read<AuthStore>().logout();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.style,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.color,
  });

  final _NavStyle style;
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? (active ? style.activeFg : _gray500);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(style.itemRadius),
      side: active ? BorderSide(color: style.activeBorder) : BorderSide.none,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        selected: active,
        button: true,
        child: Material(
          color: active ? style.activeBg : Colors.transparent,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: Padding(
              padding: style.itemPadding,
              child: Row(
                children: [
                  Icon(icon, size: style.iconSize, color: fg),
                  SizedBox(width: style.iconGap),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: style.itemFontSize,
                        fontWeight: style.itemWeight,
                        color: fg,
                      ),
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

// ── Shared frame ────────────────────────────────────────────────────────────

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _today({bool withYear = false}) {
  final now = DateTime.now();
  final base = 'Today, ${_months[now.month - 1]} ${now.day}';
  return withYear ? '$base, ${now.year}' : base;
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.style,
    required this.sidebar,
    required this.appBar,
    required this.child,
  });

  final _NavStyle style;
  final Widget sidebar;
  final PreferredSizeWidget Function(bool docked) appBar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1024) {
          return Scaffold(
            backgroundColor: _pageBg,
            body: Row(
              children: [
                Container(
                  width: style.width,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(right: BorderSide(color: _gray200)),
                  ),
                  child: sidebar,
                ),
                Expanded(
                  child: Scaffold(
                    backgroundColor: _pageBg,
                    appBar: appBar(true),
                    body: child,
                  ),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: _pageBg,
          appBar: appBar(false),
          drawer: Drawer(
            width: style.width,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(),
            child: sidebar,
          ),
          body: child,
        );
      },
    );
  }
}

PreferredSizeWidget _topBar({
  required String title,
  required Widget subtitle,
  required List<Widget> actions,
}) {
  return AppBar(
    backgroundColor: Colors.white,
    foregroundColor: _gray900,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    shape: const Border(bottom: BorderSide(color: _gray200)),
    titleSpacing: 16,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _gray900),
        ),
        subtitle,
      ],
    ),
    actions: [...actions, const SizedBox(width: 12)],
  );
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    // Hidden on narrow phones, like `hidden min-[400px]:block` on the web.
    if (MediaQuery.sizeOf(context).width < 400) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _gray50,
        border: Border.all(color: _gray200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _gray500),
      ),
    );
  }
}

// ── Admin console ───────────────────────────────────────────────────────────

class AdminShell extends StatelessWidget {
  const AdminShell({
    super.key,
    required this.location,
    required this.title,
    required this.child,
  });

  final String location;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthStore>().user ?? const <String, dynamic>{};
    const style = _NavStyle.admin;

    return _Frame(
      style: style,
      sidebar: _SideNav(
        style: style,
        companyName: user.companyName,
        sections: adminSections(user),
        location: location,
      ),
      appBar: (docked) => _topBar(
        title: title,
        subtitle: const Text(
          'Real-time management & analytics',
          style: TextStyle(fontSize: 12, color: _gray500),
        ),
        actions: [
          _DateChip(text: _today()),
          if (!user.isCompanyAdmin) ...[
            const NotificationBell(),
            const SizedBox(width: 8),
          ],
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _gray50,
              border: Border.all(color: _gray200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.person_outline, size: 16, color: _gray400),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ── Employee portal ─────────────────────────────────────────────────────────

class PortalShell extends StatelessWidget {
  const PortalShell({
    super.key,
    required this.location,
    required this.title,
    required this.child,
  });

  final String location;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthStore>().user ?? const <String, dynamic>{};
    const style = _NavStyle.portal;

    // "/" shows the portal home, so highlight its menu item there too.
    final navLocation = location == '/' ? (user.isTeamLead ? '/team/dashboard' : '/portal') : location;

    return _Frame(
      style: style,
      sidebar: _SideNav(
        style: style,
        companyName: user.companyName,
        sections: portalSections(user),
        location: navLocation,
      ),
      appBar: (docked) => _topBar(
        title: title,
        subtitle: Text.rich(
          TextSpan(
            text: 'Welcome back, ',
            style: const TextStyle(fontSize: 12, color: _gray500),
            children: [
              TextSpan(
                text: user.username,
                style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF059669)),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          _DateChip(text: _today(withYear: true)),
          const NotificationBell(),
          const SizedBox(width: 8),
          Tooltip(
            message: 'My profile',
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.go('/portal/profile'),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_outline, size: 20, color: Color(0xFF059669)),
              ),
            ),
          ),
        ],
      ),
      child: child,
    );
  }
}