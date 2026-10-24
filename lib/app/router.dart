// Port of app/AppRouter.tsx and app/ProtectedRoute.tsx, without the
// superuser (platform) screens, which show UnsupportedPage.
//
// Phone back button: pages with their own on-screen back button (employee
// profile, Bulk Edit, Device Mapping) go where that button goes; every other
// page goes to the dashboard ("/"); the dashboard exits the app. Open dialogs,
// sheets and the side menu still close first.
//
// The app always handles back itself, the dashboard included, instead of
// handing it to Android on the dashboard. Switching that on and off could get
// out of step after the app returned from the background, making back exit
// from any page.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:hrm_app/app/layout/app_shell.dart';
import 'package:hrm_app/app/session.dart';
import 'package:hrm_app/auth/auth_store.dart';
import 'package:hrm_app/login.dart';
import 'package:hrm_app/pages/access_control.dart';
import 'package:hrm_app/pages/admin_dash.dart';
import 'package:hrm_app/pages/admin_emp.dart';
import 'package:hrm_app/pages/admin_leave.dart';
import 'package:hrm_app/pages/alerts.dart';
import 'package:hrm_app/pages/attendance.dart';
import 'package:hrm_app/pages/attend_settings.dart';
import 'package:hrm_app/pages/audit_trail.dart';
import 'package:hrm_app/pages/branches.dart';
import 'package:hrm_app/pages/bulk_edit.dart';
import 'package:hrm_app/pages/company_admin_dash.dart';
import 'package:hrm_app/pages/corrections_review.dart';
import 'package:hrm_app/pages/device_fleet.dart';
import 'package:hrm_app/pages/device_mapping.dart';
import 'package:hrm_app/pages/emp_attendance.dart';
import 'package:hrm_app/pages/employee_dash.dart';
import 'package:hrm_app/pages/employees.dart';
import 'package:hrm_app/pages/emp_profile.dart';
import 'package:hrm_app/pages/holiday_calendar.dart';
import 'package:hrm_app/pages/leave_app.dart';
import 'package:hrm_app/pages/overtime_approval.dart';
import 'package:hrm_app/pages/pass_reset.dart';
import 'package:hrm_app/pages/reports.dart';
import 'package:hrm_app/pages/team_attendance.dart';
import 'package:hrm_app/pages/teamleave_req.dart';
import 'package:hrm_app/pages/teamlead_dash.dart';
import 'package:hrm_app/pages/unsupported.dart';
import 'package:hrm_app/pages/violations.dart';

enum _Area { admin, portal }

class _Screen {
  const _Screen(this.path, this.title, this.area, this.build, {this.backTo = '/'});

  final String path;
  final String title;
  final _Area area;
  final Widget Function(GoRouterState state) build;

  /// Where the phone's back button goes. Matches the page's on-screen back
  /// button where it has one; otherwise the dashboard.
  final String backTo;
}

// ── Dashboards (the "/" route picks one by role) ────────────────────────────

Widget _adminDashboard() => const AdminDashboard();

Widget _companyAdminDashboard() => const CompanyAdminDashboard();

Widget _employeeDashboard() => const EmployeeDashboard();

Widget _teamLeadDashboard() => const TeamLeadDashboard();

// ── Every other screen ──────────────────────────────────────────────────────

final _screens = <_Screen>[
  // Admin console (staff; the last three are company admin only)
  _Screen('/admin/employees', 'Employees', _Area.admin, (s) => const EmployeesPage()),
  _Screen('/admin/employees/bulk-edit', 'Bulk Edit', _Area.admin,
      (s) => BulkEditPage(loginMode: s.uri.queryParameters['mode'] == 'login'),
      backTo: '/admin/employees'),
  _Screen('/admin/employees/:employeeId', 'Employee', _Area.admin,
      (s) => AdminEmployeePage(employeeId: s.pathParameters['employeeId']!),
      backTo: '/admin/employees'),
  _Screen('/admin/attendance', 'Attendance', _Area.admin, (s) => const AttendancePage()),
  _Screen('/admin/attendance/settings', 'Configuration', _Area.admin, (s) => const AttendanceSettingsPage()),
  _Screen('/admin/leaves', 'Leave Management', _Area.admin, (s) => const AdminLeavePage()),
  _Screen('/admin/corrections', 'Corrections', _Area.admin, (s) => const CorrectionsReviewPage(scope: 'all')),
  _Screen('/admin/overtime', 'Overtime Approval', _Area.admin, (s) => const OvertimeApprovalPage()),
  _Screen('/admin/holidays', 'Holidays', _Area.admin, (s) => const HolidayCalendarPage()),
  _Screen('/admin/violations', 'Violations', _Area.admin, (s) => const ViolationsPage()),
  _Screen('/admin/reports', 'Reports', _Area.admin, (s) => const ReportsPage()),
  _Screen('/admin/devices', 'Hardware Devices', _Area.admin, (s) => const DeviceFleetPage()),
  _Screen('/admin/hardware/mappings/:deviceId', 'Device Mapping', _Area.admin,
      (s) => DeviceMappingPage(deviceId: int.tryParse(s.pathParameters['deviceId'] ?? '') ?? 0),
      backTo: '/admin/devices'),
  _Screen('/alerts', 'Alerts', _Area.admin, (s) => const AlertsPage()),
  _Screen('/admin/branches', 'Branches', _Area.admin, (s) => const BranchesPage()),
  _Screen('/admin/users', 'Access Control', _Area.admin, (s) => const AccessControlPage()),
  _Screen('/audit', 'Audit Trail', _Area.admin, (s) => const AuditTrailPage()),

  // Employee portal (any signed-in user)
  _Screen('/portal/dashboard', 'My Dashboard', _Area.portal, (s) => _employeeDashboard()),
  _Screen('/portal/attendance', 'My Attendance', _Area.portal, (s) => const EmployeeAttendancePage()),
  _Screen('/portal/leaves', 'Apply for Leave', _Area.portal, (s) => const LeaveApplicationPage()),
  _Screen('/portal/alerts', 'Alerts & Messages', _Area.portal, (s) => const AlertsPage()),
  _Screen('/portal/profile', 'My Profile', _Area.portal, (s) => const EmployeeProfilePage()),

  // Team lead (portal layout)
  _Screen('/team/dashboard', 'Team Dashboard', _Area.portal, (s) => _teamLeadDashboard()),
  _Screen('/team/attendance', 'Team Attendance', _Area.portal, (s) => const TeamAttendancePage()),
  _Screen('/team/leaves', 'Team Leave Requests', _Area.portal, (s) => const TeamLeaveRequestsPage()),
  _Screen('/team/corrections', 'Team Corrections', _Area.portal, (s) => const CorrectionsReviewPage(scope: 'team')),
  _Screen('/team/overtime', 'Team Overtime', _Area.portal, (s) => const OvertimeApprovalPage()),
];

// ── Guards (ProtectedRoute.tsx) ─────────────────────────────────────────────

bool _isPublic(String loc) =>
    loc == '/login' || loc == '/forgot-password' || loc.startsWith('/reset-password/');

String? _guard(Map<String, dynamic>? user, String loc) {
  if (user == null) return _isPublic(loc) ? null : '/login';

  // Platform screens are web-only.
  if (user.isSuperuser) return loc == '/unsupported' ? null : '/unsupported';
  if (loc == '/login' || loc == '/unsupported') return '/';

  final companyAdminOnly =
      loc.startsWith('/admin/branches') || loc.startsWith('/admin/users') || loc.startsWith('/audit');
  final staffOnly = companyAdminOnly || loc.startsWith('/admin') || loc == '/alerts';

  if (staffOnly && user.isEmployeePortal) return '/';
  if (companyAdminOnly && !user.isCompanyAdmin) return '/';
  if (loc.startsWith('/team') && !user.isTeamLead) return '/';
  return null;
}

// ── Router ──────────────────────────────────────────────────────────────────

Widget _inShell(
  _Area area,
  String title,
  GoRouterState state,
  Widget child, {
  bool home = false,
  String backTo = '/',
}) {
  final location = state.uri.path;
  // Back on the dashboard exits the app; every other page goes to [backTo].
  final page = _BackTo(target: home ? null : backTo, child: child);
  return area == _Area.admin
      ? AdminShell(location: location, title: title, child: page)
      : PortalShell(location: location, title: title, child: page);
}

/// Whether [loc] is this user's home dashboard (besides "/" and "/portal").
bool _isHomeScreen(Map<String, dynamic>? user, String loc) {
  final u = user ?? const <String, dynamic>{};
  // Team leads' home is the Team Dashboard; their "My Personal Dashboard"
  // (/portal/dashboard) is a separate page. For employees it's the same screen.
  if (loc == '/team/dashboard') return u.isTeamLead;
  if (loc == '/portal/dashboard') return !u.isTeamLead;
  return false;
}

/// Handles the phone's back button for a page: goes to [target], or exits
/// the app when [target] is null (the dashboard). It sits inside the shell's
/// Scaffold so it can close an open side menu first.
class _BackTo extends StatefulWidget {
  const _BackTo({required this.target, required this.child});

  /// Where back goes; null = exit the app.
  final String? target;
  final Widget child;

  @override
  State<_BackTo> createState() => _BackToState();
}

class _BackToState extends State<_BackTo> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android may forget that the app handles back while it sits in the
    // background; say so again when it comes back.
    if (state == AppLifecycleState.resumed) {
      SystemNavigator.setFrameworkHandlesBack(true);
    }
  }

  void _onBack() {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
      return;
    }
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop(); // a page opened on top of this one
      return;
    }
    final target = widget.target;
    if (target == null) {
      SystemNavigator.pop(); // dashboard: leave the app
    } else {
      router.go(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: widget.child,
    );
  }
}

/// The home screen for this user, same choice as the "/" route in AppRouter.tsx.
Widget _home(Map<String, dynamic> user, GoRouterState state) {
  if (user.isEmployeePortal) {
    return user.isTeamLead
        ? _inShell(_Area.portal, 'Team Dashboard', state, _teamLeadDashboard(), home: true)
        : _inShell(_Area.portal, 'My Dashboard', state, _employeeDashboard(), home: true);
  }
  return user.isCompanyAdmin
      ? _inShell(_Area.admin, 'Dashboard', state, _companyAdminDashboard(), home: true)
      : _inShell(_Area.admin, 'Dashboard', state, _adminDashboard(), home: true);
}

GoRouter createRouter(AuthStore store) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: store, // re-check the guards on login and logout
    redirect: (context, state) => _guard(store.user, state.matchedLocation),
    // Unknown paths go home, like the `*` route on the web.
    onException: (context, state, router) => router.go('/'),
    routes: [
      // Public
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const PasswordResetMaintenancePage()),
      GoRoute(
        path: '/reset-password/:uid/:token',
        builder: (_, __) => const PasswordResetMaintenancePage(),
      ),
      GoRoute(path: '/unsupported', builder: (_, __) => const UnsupportedPage()),

      // Home: dashboard chosen by role
      GoRoute(
        path: '/',
        builder: (context, state) => _home(store.user ?? const {}, state),
      ),
      GoRoute(
        path: '/portal',
        builder: (context, state) {
          final user = store.user ?? const <String, dynamic>{};
          return user.isTeamLead
              ? _inShell(_Area.portal, 'Team Dashboard', state, _teamLeadDashboard(), home: true)
              : _inShell(_Area.portal, 'My Dashboard', state, _employeeDashboard(), home: true);
        },
      ),

      for (final screen in _screens)
        GoRoute(
          path: screen.path,
          builder: (context, state) => _inShell(
            screen.area,
            screen.title,
            state,
            screen.build(state),
            home: _isHomeScreen(store.user, state.uri.path),
            backTo: screen.backTo,
          ),
        ),
    ],
  );
}