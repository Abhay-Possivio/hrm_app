// Port of features/employee/profile/EmployeeProfilePage.tsx ("My Profile").
//
// Layout (compact):
//   [temporary-password banner → Change password]
//   Identity card: avatar · name · designation · ID (tap to copy) · role
//   Employment details | Work schedule
//   Account security

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hrm_app/auth/auth_service.dart';
import 'package:hrm_app/components/auth/pass_reset.dart';
import 'package:hrm_app/services/empportal_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';
import 'package:hrm_app/utils/toast.dart';

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
  static const teal50 = Color(0xFFF0FDFA);
  static const teal200 = Color(0xFF99F6E4);
  static const teal500 = Color(0xFF14B8A6);
  static const teal600 = Color(0xFF0D9488);
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo200 = Color(0xFFC7D2FE);
  static const indigo600 = Color(0xFF4F46E5);
  static const red50 = Color(0xFFFEF2F2);
  static const red200 = Color(0xFFFECACA);
  static const red600 = Color(0xFFDC2626);
  static const red800 = Color(0xFF991B1B);
}

/// A tinted color set: soft background, border, and foreground.
class _Tone {
  const _Tone(this.bg, this.border, this.fg);

  final Color bg;
  final Color border;
  final Color fg;
}

const _emerald = _Tone(_K.emerald50, _K.emerald200, _K.emerald600);
const _teal = _Tone(_K.teal50, _K.teal200, _K.teal600);
const _indigo = _Tone(_K.indigo50, _K.indigo200, _K.indigo600);
const _gray = _Tone(_K.gray100, _K.gray200, _K.gray600);

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3, color: _K.gray900);
  static const subtitle = TextStyle(fontSize: 12, height: 1.3, color: _K.gray500);
  static const rowLabel = TextStyle(fontSize: 13, color: _K.gray500);
  static const rowValue = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray900, fontFeatures: tabular);
}

const _cardRadius = 16.0;
const _divider = Divider(height: 1, thickness: 1, color: _K.gray100);

// ── Helpers ─────────────────────────────────────────────────────────────────

/// "2 years 3 months", "5 months", or "Joined today".
String _serviceDuration(DateTime? start) {
  if (start == null) return '—';
  final now = DateTime.now();
  var months = (now.year - start.year) * 12 + now.month - start.month;
  if (now.day < start.day) months--;
  if (months < 0) months = 0;
  final years = months ~/ 12;
  final rest = months % 12;
  final parts = [
    if (years > 0) '$years ${years == 1 ? 'year' : 'years'}',
    if (rest > 0) '$rest ${rest == 1 ? 'month' : 'months'}',
  ];
  return parts.isEmpty ? 'Less than a month' : parts.join(' ');
}

String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

// ── Page ────────────────────────────────────────────────────────────────────

class EmployeeProfilePage extends StatefulWidget {
  const EmployeeProfilePage({super.key});

  @override
  State<EmployeeProfilePage> createState() => _EmployeeProfilePageState();
}

class _EmployeeProfilePageState extends State<EmployeeProfilePage> {
  EmployeeProfile? _profile;
  bool _mustChangePassword = false;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await employeePortalService.fetchMe();
      // must_change_password comes from the account, not the employee record.
      final account = await authService.me();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _mustChangePassword = account['must_change_password'] == true;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  void _retry() {
    setState(() => _loading = true);
    _load();
  }

  void _changePassword() => showPasswordResetDialog(
        context,
        intro: 'To update your password, we will send a secure recovery link to your registered email address:',
        noEmailError: 'No registered email address found for your account.',
      );

  Future<void> _copyId(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) showToast(context, 'Employee ID copied');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _PageSkeleton();

    final p = _profile;
    return RefreshIndicator(
      color: _K.emerald600,
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sm = width >= 640;
          final md = width >= 768;
          final gap = sm ? 20.0 : 16.0;

          if (p == null) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(sm ? 24 : 16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: _EmptyState(
                      icon: Icons.person_off_outlined,
                      title: "Your profile couldn't be loaded",
                      message: _failed
                          ? 'Check your connection, then retry or pull down to refresh.'
                          : 'Pull down to refresh.',
                      action: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _K.emerald600,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry'),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          final employment = _EmploymentCard(profile: p, onCopyId: () => _copyId(p.employeeCode));
          final schedule = _ScheduleCard(profile: p);

          final sections = <Widget>[
            if (_mustChangePassword)
              _Banner(
                icon: Icons.warning_amber_rounded,
                title: 'Change your temporary password',
                message: 'You are signed in with a temporary password. Set your own before you continue.',
                actionLabel: 'Change password',
                onAction: _changePassword,
              ),
            if (_failed)
              _Banner(
                icon: Icons.cloud_off_outlined,
                title: "Couldn't refresh your profile",
                message: 'Showing the last details we loaded.',
                actionLabel: 'Retry',
                onAction: _load,
              ),
            _IdentityCard(profile: p, wide: sm, onCopyId: () => _copyId(p.employeeCode)),
            if (md)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: employment),
                  SizedBox(width: gap),
                  Expanded(flex: 2, child: schedule),
                ],
              )
            else ...[
              employment,
              schedule,
            ],
            _SecurityCard(mustChangePassword: _mustChangePassword, onChangePassword: _changePassword),
          ];

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(sm ? 24 : 16),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
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

// ── Identity ────────────────────────────────────────────────────────────────

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.profile, required this.wide, required this.onCopyId});

  final EmployeeProfile profile;
  final bool wide;
  final VoidCallback onCopyId;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final size = wide ? 72.0 : 60.0;
    final subtitle = [
      if (p.designation != null && p.designation!.isNotEmpty) p.designation!,
      if (p.department != null && p.department!.isNotEmpty) p.department!,
    ].join(', ');

    return _Surface(
      padding: EdgeInsets.all(wide ? 20 : 16),
      child: Row(
        children: [
          // Avatar with the emerald → teal ring
          Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(2.5),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
                colors: [_K.emerald500, _K.teal500],
              ),
            ),
            child: Container(
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: _K.emerald50, shape: BoxShape.circle),
              child: Text(
                _initials(p.name),
                style: TextStyle(
                  fontSize: wide ? 24 : 20,
                  fontWeight: FontWeight.w700,
                  color: _K.emerald600,
                ),
              ),
            ),
          ),
          SizedBox(width: wide ? 18 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    p.name.trim().isEmpty ? 'My profile' : p.name.trim(),
                    style: TextStyle(
                      fontSize: wide ? 22 : 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      height: 1.25,
                      color: _K.gray900,
                    ),
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 13, color: _K.gray500)),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (p.employeeCode.isNotEmpty)
                      _Chip(
                        icon: Icons.badge_outlined,
                        text: 'ID ${p.employeeCode}',
                        tone: _gray,
                        trailingIcon: Icons.copy_rounded,
                        tooltip: 'Copy employee ID',
                        onTap: onCopyId,
                      ),
                    _Chip(
                      icon: p.isTeamLead ? Icons.groups_outlined : Icons.person_outline_rounded,
                      text: p.isTeamLead ? 'Team lead' : 'Employee',
                      tone: p.isTeamLead ? _indigo : _emerald,
                    ),
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

// ── Employment details ──────────────────────────────────────────────────────

class _EmploymentCard extends StatelessWidget {
  const _EmploymentCard({required this.profile, required this.onCopyId});

  final EmployeeProfile profile;
  final VoidCallback onCopyId;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final joined = parseDateOnly(p.dateOfJoining);
    String orNot(String? v, String fallback) => (v == null || v.trim().isEmpty) ? fallback : v;

    final rows = <Widget>[
      _InfoRow(
        icon: Icons.badge_outlined,
        label: 'Employee ID',
        value: orNot(p.employeeCode, 'Not set'),
        trailing: p.employeeCode.isEmpty
            ? null
            : IconButton(
                tooltip: 'Copy employee ID',
                onPressed: onCopyId,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                icon: const Icon(Icons.copy_rounded, size: 14, color: _K.gray400),
              ),
      ),
      _InfoRow(icon: Icons.work_outline_rounded, label: 'Designation', value: orNot(p.designation, 'Not set')),
      _InfoRow(icon: Icons.account_tree_outlined, label: 'Department', value: orNot(p.department, 'Not assigned')),
      _InfoRow(icon: Icons.apartment_rounded, label: 'Branch', value: orNot(p.branch, 'Not assigned')),
      _InfoRow(
        icon: Icons.shield_outlined,
        label: 'Portal role',
        value: p.isTeamLead ? 'Team lead' : 'Employee',
      ),
      _InfoRow(
        icon: Icons.event_outlined,
        label: 'Date joined',
        value: joined != null ? '${formatMMMM(joined)} ${formatDD(joined)}, ${joined.year}' : 'Not set',
        sub: joined != null ? 'Service: ${_serviceDuration(joined)}' : null,
      ),
    ];

    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardHeader(
            icon: Icons.work_history_outlined,
            tone: _emerald,
            title: 'Employment',
            subtitle: 'Details from your HR record',
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) _divider,
            rows[i],
          ],
          const SizedBox(height: 8),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.info_outline_rounded, size: 13, color: _K.gray400),
              ),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Something wrong here? Ask your HR administrator to update your record.',
                  style: TextStyle(fontSize: 11, height: 1.35, color: _K.gray400),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value, this.sub, this.trailing});

  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final muted = value == 'Not set' || value == 'Not assigned';
    return Semantics(
      label: '$label: $value${sub != null ? ', $sub' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 16, color: _K.gray400),
            ),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: Text(label, style: _T.rowLabel)),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    textAlign: TextAlign.right,
                    style: _T.rowValue.copyWith(
                      color: muted ? _K.gray400 : _K.gray900,
                      fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
                    ),
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(sub!, textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: _K.emerald600)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 4), trailing!],
          ],
        ),
      ),
    );
  }
}

// ── Work schedule ───────────────────────────────────────────────────────────

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.profile});

  final EmployeeProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final shift = p.shift;
    final shiftName = p.shift?.name;

    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            icon: Icons.schedule_rounded,
            tone: _teal,
            title: 'Work schedule',
            subtitle: shift == null ? 'No shift assigned' : (shiftName ?? 'Assigned shift'),
          ),
          const SizedBox(height: 6),
          if (shift == null)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: _EmptyState(
                icon: Icons.event_busy_outlined,
                title: 'No shift assigned',
                message: 'Ask HR to assign a shift to see your timings here.',
              ),
            )
          else ...[
            for (final (i, row) in <(IconData, String, String, Color?)>[
              (
                Icons.access_time_rounded,
                'Timing',
                '${fmtRawTime(shift.startTime)} – ${fmtRawTime(shift.endTime)}',
                null,
              ),
              if (p.graceMinutes != null) (Icons.timelapse_rounded, 'Grace period', '${p.graceMinutes} min', _K.emerald600),
              if (p.lunchStart != null && p.lunchEnd != null)
                (Icons.restaurant_outlined, 'Lunch break', '${fmtRawTime(p.lunchStart)} – ${fmtRawTime(p.lunchEnd)}', null),
            ].indexed) ...[
              if (i > 0) _divider,
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Icon(row.$1, size: 16, color: _K.gray400),
                    const SizedBox(width: 10),
                    Expanded(child: Text(row.$2, style: _T.rowLabel)),
                    Text(row.$3, style: _T.rowValue.copyWith(color: row.$4 ?? _K.gray900)),
                  ],
                ),
              ),
            ],
            if (shift.workingDays.isNotEmpty) ...[
              _divider,
              const SizedBox(height: 10),
              const Text('Working days', style: _T.rowLabel),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final (i, d) in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].indexed) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(child: _DayChip(day: d, on: shift.workingDays.contains(d))),
                  ],
                ],
              ),
              const SizedBox(height: 4),
            ],
          ],
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
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? _K.teal50 : _K.gray50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? _K.teal200 : _K.gray100),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            day,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: on ? _K.teal600 : _K.gray300),
          ),
        ),
      ),
    );
  }
}

// ── Security ────────────────────────────────────────────────────────────────

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({required this.mustChangePassword, required this.onChangePassword});

  final bool mustChangePassword;
  final VoidCallback onChangePassword;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardHeader(
            icon: Icons.lock_outline_rounded,
            tone: _emerald,
            title: 'Account security',
            subtitle: 'Sign-in and password',
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final button = mustChangePassword
                  ? FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _K.red600,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      onPressed: onChangePassword,
                      icon: const Icon(Icons.key_rounded, size: 16),
                      label: const Text('Change password now'),
                    )
                  : OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _K.gray700,
                        side: const BorderSide(color: _K.gray200),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      onPressed: onChangePassword,
                      icon: const Icon(Icons.key_rounded, size: 16),
                      label: const Text('Change password'),
                    );

              final text = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Password', style: _T.title),
                      const SizedBox(width: 8),
                      if (mustChangePassword)
                        const _Chip(text: 'Temporary', tone: _Tone(_K.red50, _K.red200, _K.red600)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    "We'll email a secure reset link to your registered address.",
                    style: TextStyle(fontSize: 12, height: 1.4, color: _K.gray500),
                  ),
                ],
              );

              if (c.maxWidth >= 480) {
                return Row(children: [Expanded(child: text), const SizedBox(width: 16), button]);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [text, const SizedBox(height: 12), button],
              );
            },
          ),
          const SizedBox(height: 12),
          _divider,
          const SizedBox(height: 10),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.support_agent_rounded, size: 14, color: _K.gray400),
              ),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  "If you notice sign-in activity you don't recognize, contact your HR administrator right away.",
                  style: TextStyle(fontSize: 12, height: 1.4, color: _K.gray500),
                ),
              ),
            ],
          ),
        ],
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
      label: 'Loading your profile',
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
                  padding: EdgeInsets.all(sm ? 24 : 16),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _Bone(height: 104),
                            const SizedBox(height: 16),
                            if (md)
                              const Row(
                                children: [
                                  Expanded(flex: 3, child: _Bone(height: 320)),
                                  SizedBox(width: 20),
                                  Expanded(flex: 2, child: _Bone(height: 320)),
                                ],
                              )
                            else ...[
                              const _Bone(height: 300),
                              const SizedBox(height: 16),
                              const _Bone(height: 200),
                            ],
                            const SizedBox(height: 16),
                            const _Bone(height: 150),
                          ],
                        ),
                      ),
                    ),
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
  const _Bone({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(color: _K.gray100, borderRadius: BorderRadius.circular(_cardRadius)),
    );
  }
}

// ── Small shared pieces ─────────────────────────────────────────────────────

/// White card with a hairline border.
class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: _K.gray100),
        boxShadow: const [BoxShadow(color: Color(0x08101828), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: child,
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.icon, required this.tone, required this.title, this.subtitle});

  final IconData icon;
  final _Tone tone;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _IconBox(icon: icon, tone: tone, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.title),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 1),
                Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.subtitle),
              ],
            ],
          ),
        ),
      ],
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

class _Chip extends StatelessWidget {
  const _Chip({
    required this.text,
    required this.tone,
    this.icon,
    this.trailingIcon,
    this.tooltip,
    this.onTap,
  });

  final String text;
  final _Tone tone;
  final IconData? icon;
  final IconData? trailingIcon;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: tone.border),
    );
    Widget chip = Material(
      color: tone.bg,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 13, color: tone.fg), const SizedBox(width: 5)],
              Text(
                text,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tone.fg, fontFeatures: _T.tabular),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 5),
                Icon(trailingIcon, size: 12, color: tone.fg.withValues(alpha: 0.6)),
              ],
            ],
          ),
        ),
      ),
    );
    if (tooltip != null) chip = Tooltip(message: tooltip!, child: chip);
    return chip;
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
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
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
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: _K.red50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _K.red200),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: _K.red600),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _K.red800)),
                  const SizedBox(height: 1),
                  Text(message, style: const TextStyle(fontSize: 12, height: 1.4, color: _K.red600)),
                ],
              ),
            ),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: _K.red800,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}