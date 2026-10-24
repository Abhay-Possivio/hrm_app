// Port of app/layout/NotificationBell.tsx: unread notifications (plus, for
// HR / admins, leave requests waiting for them) with a red count badge.
// Refreshes every 30 s and whenever notifications are read.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:hrm_app/app/session.dart';
import 'package:hrm_app/auth/auth_store.dart';
import 'package:hrm_app/services/leave_service.dart';
import 'package:hrm_app/services/notification_service.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> with WidgetsBindingObserver {
  int _count = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    notificationEvents.addListener(_load);
    _load();
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    notificationEvents.removeListener(_load);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
      _start();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  Future<void> _load() async {
    final user = context.read<AuthStore>().user ?? const <String, dynamic>{};
    final role = '${user['role'] ?? ''}';
    try {
      var pendingLeaves = 0;
      if (role == 'ADMIN' || role == 'HR' || user.isCompanyAdmin) {
        final leaves = await leaveService.fetchLeaveRequests();
        pendingLeaves = leaves.where((r) => r.status == 'PENDING' && !r.hasTeamLead).length;
      }
      final notes = await notificationService.fetchNotifications(page: 1, unreadOnly: true);
      final unread = notes.count > 0 ? notes.count : notes.results.where((n) => !n.isRead).length;
      if (mounted) setState(() => _count = pendingLeaves + unread);
    } catch (_) {
      // Keep the last count; the next poll retries.
    }
  }

  void _open() {
    final role = '${context.read<AuthStore>().user?['role'] ?? ''}';
    context.go(role == 'EMPLOYEE' || role == 'TEAM_LEAD' ? '/portal/alerts' : '/alerts');
  }

  @override
  Widget build(BuildContext context) {
    final label = _count > 0 ? '$_count new notification${_count == 1 ? '' : 's'}' : 'Notifications';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _open,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: const Icon(Icons.notifications_none, size: 20, color: Color(0xFF9CA3AF)),
                ),
                if (_count > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text(
                        _count > 9 ? '9+' : '$_count',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
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