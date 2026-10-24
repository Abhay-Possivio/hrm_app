// Port of features/admin/employees/AdminEmployeePage.tsx
// (/admin/employees/:employeeId): one employee's profile for HR / admins.
//
// Sections: reporting hierarchy (supervisor, team lead status), identity &
// employment, system access (email / phone / portal login), and two tabs:
// raw device logs and shift assignments. Plus suspend / restore and delete.
//
// Layout (compact):
//   Header: back · avatar · name · code / branch / status chips · Suspend · ⋮ (Delete)
//   Wide: profile cards (1) | Punches / Shift tabs (2)
//   Phones: the same, stacked
//   Each card reads as a label/value list; Edit turns it into a form with
//   Cancel / Save at the bottom.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hrm_app/components/employees/empshift_form.dart';
import 'package:hrm_app/services/branch_service.dart';
import 'package:hrm_app/services/dept_service.dart';
import 'package:hrm_app/services/employee_service.dart';
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
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo200 = Color(0xFFC7D2FE);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const indigo900 = Color(0xFF312E81);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);
  static const emerald800 = Color(0xFF065F46);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber200 = Color(0xFFFDE68A);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);
  static const red50 = Color(0xFFFEF2F2);
  static const red100 = Color(0xFFFEE2E2);
  static const red200 = Color(0xFFFECACA);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);
}

/// A tinted color set: soft background, border, and foreground.
class _Tone {
  const _Tone(this.bg, this.border, this.fg);

  final Color bg;
  final Color border;
  final Color fg;
}

const _indigo = _Tone(_K.indigo50, _K.indigo200, _K.indigo600);
const _emerald = _Tone(_K.emerald50, _K.emerald200, _K.emerald700);
const _red = _Tone(_K.red50, _K.red200, _K.red700);
const _gray = _Tone(_K.gray100, _K.gray200, _K.gray600);

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3, color: _K.gray900);
  static const subtitle = TextStyle(fontSize: 12, height: 1.35, color: _K.gray500);
  static const fieldLabel = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.gray700);
  static const rowLabel = TextStyle(fontSize: 13, color: _K.gray500);
}

const _cardRadius = 16.0;
const _divider = Divider(height: 1, thickness: 1, color: _K.gray100);

const _employmentTypes = {'FT': 'Full-time', 'PT': 'Part-time', 'CT': 'Contract'};
const _genders = {'M': 'Male', 'F': 'Female', 'O': 'Other'};

String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

/// "12 Mar 2026" for a "YYYY-MM-DD" value, or null.
String? _date(String? raw) {
  final d = parseDateOnly(raw);
  return d == null ? null : formatDDMMMYYYY(d);
}

/// Whole years between [raw] and today.
int? _yearsSince(String? raw) {
  final d = parseDateOnly(raw);
  if (d == null) return null;
  final now = DateTime.now();
  var years = now.year - d.year;
  if (now.month < d.month || (now.month == d.month && now.day < d.day)) years--;
  return years < 0 ? null : years;
}

/// "Mon, 28 Sep 2026" and "09:05:30 AM" from a wall-clock punch timestamp.
(String date, String time) _punchDateTime(String ts) {
  final d = parseDateOnly(ts);
  final m = RegExp(r'T(\d{2}):(\d{2})(?::(\d{2}))?').firstMatch(ts);
  final date = d == null ? ts : '${formatEEE(d)}, ${formatDD(d)} ${formatMMM(d)} ${d.year}';
  if (m == null) return (date, '');
  final h = int.parse(m.group(1)!);
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return (date, '${h12.toString().padLeft(2, '0')}:${m.group(2)}:${m.group(3) ?? '00'} ${h >= 12 ? 'PM' : 'AM'}');
}

// ── Page ────────────────────────────────────────────────────────────────────

class AdminEmployeePage extends StatefulWidget {
  const AdminEmployeePage({super.key, required this.employeeId});

  final String employeeId;

  @override
  State<AdminEmployeePage> createState() => _AdminEmployeePageState();
}

class _AdminEmployeePageState extends State<AdminEmployeePage> {
  Employee? _employee;
  List<AttendanceLog> _logs = const [];
  List<BranchOption> _branches = const [];
  List<Department> _departments = const [];
  List<Employee> _potentialLeads = const [];
  bool _loading = true;
  bool _logsLoading = true;
  String? _error;
  bool _saving = false;
  bool _togglingStatus = false;
  bool _historyTab = true;
  bool _showAllLogs = false;

  // Which card is being edited
  bool _editProfile = false;
  bool _editAccess = false;
  bool _editHierarchy = false;

  // Identity & employment form
  final _name = TextEditingController();
  final _designation = TextEditingController();
  int _branchId = 0;
  int? _departmentId;
  String _employmentType = 'FT';
  String _gender = '';
  String? _dob;
  String? _doj;
  String? _nameError;

  // System access form
  final _email = TextEditingController();
  final _phone = TextEditingController();
  String? _emailError;

  // Hierarchy form
  int? _teamLead;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _designation, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        employeeService.fetchEmployeeById(widget.employeeId),
        branchService.fetchBranchOptions(),
        departmentService.fetchDepartments(),
      ]);
      final emp = results[0] as Employee;
      if (!mounted) return;
      setState(() {
        _employee = emp;
        _branches = results[1] as List<BranchOption>;
        _departments = results[2] as List<Department>;
        _error = null;
        _fillForms(emp);
      });

      final all = await employeeService.fetchEmployees(pageSize: 1000);
      final logs = await employeeService.fetchEmployeeLogs(widget.employeeId);
      if (!mounted) return;
      setState(() {
        _potentialLeads = all.results.where((e) => e.isTeamLead && e.id != emp.id).toList();
        _logs = logs.results;
      });
    } catch (err) {
      if (mounted) setState(() => _error = apiError(err, 'Unknown connection error'));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _logsLoading = false;
        });
      }
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load();
  }

  void _fillForms(Employee e) {
    _name.text = e.name;
    _designation.text = e.designation ?? '';
    _branchId = e.branchId;
    _departmentId = e.departmentId;
    _employmentType = e.employmentType ?? 'FT';
    _gender = e.gender ?? '';
    _dob = e.dateOfBirth;
    _doj = e.dateOfJoining;
    _email.text = e.email ?? '';
    _phone.text = e.phone ?? '';
    _teamLead = e.teamLead;
    _nameError = null;
    _emailError = null;
  }

  Future<bool> _confirm(String title, String message, {String action = 'Confirm', bool danger = true}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900)),
        content: Text(message, style: const TextStyle(fontSize: 13, height: 1.45, color: _K.gray600)),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _K.gray600),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: danger ? _K.red600 : _K.indigo600,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Runs a save, reloads on success, and reports errors.
  Future<bool> _run(Future<void> Function() action, {required String failure, String? success}) async {
    setState(() => _saving = true);
    try {
      await action();
      await _load();
      if (success != null && mounted) showToast(context, success);
      return true;
    } catch (err) {
      if (mounted) showToast(context, apiError(err, failure), error: true);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleStatus() async {
    final e = _employee!;
    if (e.isActive) {
      final ok = await _confirm(
        'Suspend ${e.name}?',
        'Their portal login stops working until you restore access. Attendance records are kept.',
        action: 'Suspend',
      );
      if (!ok) return;
    }
    setState(() => _togglingStatus = true);
    try {
      await employeeService.patchEmployeeStatus(widget.employeeId, !e.isActive);
      if (!mounted) return;
      setState(() => _employee = Employee.fromJson({...e.raw, 'is_active': !e.isActive}));
      showToast(context, e.isActive ? '${e.name} suspended' : 'Access restored for ${e.name}');
    } catch (_) {
      if (mounted) showToast(context, 'Failed to update status', error: true);
    } finally {
      if (mounted) setState(() => _togglingStatus = false);
    }
  }

  Future<void> _delete() async {
    final e = _employee!;
    final ok = await _confirm(
      'Delete ${e.name} permanently?',
      'All attendance logs, schedules and portal access for this employee are deleted. This cannot be undone. '
          'To keep their history, suspend them instead.',
      action: 'Delete permanently',
    );
    if (!ok) return;
    setState(() => _saving = true);
    try {
      await employeeService.deleteEmployee(widget.employeeId);
      if (!mounted) return;
      showToast(context, '${e.name} deleted');
      context.go('/admin/employees');
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to delete the employee.'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Enter the full name.');
      return;
    }
    final ok = await _run(
      () => employeeService.updateEmployee(widget.employeeId, {
        'name': _name.text.trim(),
        'branch_id': _branchId,
        'department_id': _departmentId,
        'designation': _designation.text.trim(),
        'date_of_joining': _doj,
        'date_of_birth': _dob,
        'gender': _gender,
        'employment_type': _employmentType,
        'national_id': _employee?.nationalId ?? '',
      }),
      failure: 'Failed to update the profile.',
      success: 'Profile saved',
    );
    if (ok && mounted) setState(() => _editProfile = false);
  }

  Future<void> _saveAccess() async {
    final email = _email.text.trim();
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _emailError = 'Enter a valid email address.');
      return;
    }
    final ok = await _run(
      () => employeeService.updateEmployee(widget.employeeId, {'email': email, 'phone': _phone.text.trim()}),
      failure: 'Failed to update contact/access info.',
      success: 'Contact details saved',
    );
    if (ok && mounted) setState(() => _editAccess = false);
  }

  Future<void> _saveHierarchy() async {
    final ok = await _run(
      () => employeeService.updateEmployee(widget.employeeId, {'team_lead': _teamLead}),
      failure: 'Hierarchy update failed.',
      success: 'Supervisor updated',
    );
    if (ok && mounted) setState(() => _editHierarchy = false);
  }

  Future<void> _revokeAccess() async {
    final ok = await _confirm(
      'Revoke portal access?',
      "${_employee!.name}'s login account is deleted. Saving an email again creates a new one.",
      action: 'Revoke',
    );
    if (!ok) return;
    await _run(
      () => employeeService.revokePortalAccess(widget.employeeId),
      failure: 'Failed to revoke access.',
      success: 'Portal access revoked',
    );
  }

  Future<void> _promote() async {
    final team = await showDialog<String>(context: context, builder: (_) => const _PromotionDialog());
    if (team == null || team.trim().isEmpty) return;
    await _run(
      () => employeeService.updateEmployee(widget.employeeId, {'is_team_lead': true, 'team_name': team.trim()}),
      failure: 'Hierarchy update failed.',
      success: 'Promoted to team lead. Portal access updated.',
    );
  }

  Future<void> _revokeLead() async {
    final ok = await _confirm(
      'Remove team lead status?',
      '${_employee!.name} will no longer manage "${_employee!.teamName ?? 'their team'}".',
      action: 'Remove',
    );
    if (!ok) return;
    await _run(
      () => employeeService.updateEmployee(widget.employeeId, {'is_team_lead': false, 'team_name': ''}),
      failure: 'Hierarchy update failed.',
      success: 'Team lead status removed',
    );
  }

  Future<void> _addDepartment() async {
    final name = await showDialog<String>(context: context, builder: (_) => const _DepartmentDialog());
    if (name == null || name.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final dept = await departmentService.createDepartment(name.trim());
      if (!mounted) return;
      setState(() {
        final exists = _departments.any((d) => d.id == dept.id || d.name.toLowerCase() == dept.name.toLowerCase());
        if (!exists) _departments = [..._departments, dept];
        _departmentId = dept.id;
      });
      showToast(context, 'Department "${dept.name}" selected.');
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to create department'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _afterShiftChange() async {
    setState(() => _logsLoading = true);
    try {
      final logs = await employeeService.fetchEmployeeLogs(widget.employeeId);
      final emp = await employeeService.fetchEmployeeById(widget.employeeId);
      if (!mounted) return;
      setState(() {
        _logs = logs.results;
        _employee = emp;
      });
    } catch (_) {
      // Keep what's shown.
    } finally {
      if (mounted) setState(() => _logsLoading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _PageSkeleton();

    final e = _employee;
    if (_error != null && e == null) {
      return _ErrorState(
        message: _error!,
        onRetry: _retry,
        onBack: () => context.go('/admin/employees'),
      );
    }
    if (e == null) {
      return _ErrorState(
        message: 'This employee record could not be found.',
        onRetry: _retry,
        onBack: () => context.go('/admin/employees'),
      );
    }

    return RefreshIndicator(
      color: _K.indigo600,
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sm = width >= 640;
          final lg = width >= 1024;
          final gap = sm ? 20.0 : 16.0;

          final leftColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _identityCard(e),
              SizedBox(height: gap),
              _hierarchyCard(e),
              SizedBox(height: gap),
              _accessCard(e),
            ],
          );
          final tabs = _tabsCard(e);

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(sm ? 24 : 16),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(e, wide: sm),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        _Banner(message: "Couldn't refresh: $_error", onRetry: _load),
                      ],
                      SizedBox(height: gap),
                      if (lg)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 2, child: leftColumn),
                            SizedBox(width: gap),
                            Expanded(flex: 3, child: tabs),
                          ],
                        )
                      else ...[
                        leftColumn,
                        SizedBox(height: gap),
                        tabs,
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

  Widget _header(Employee e, {required bool wide}) {
    final busy = _saving || _togglingStatus;

    final statusButton = e.isActive
        ? OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _K.amber700,
              side: const BorderSide(color: _K.amber200),
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            onPressed: busy ? null : _toggleStatus,
            icon: _togglingStatus
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _K.amber700))
                : const Icon(Icons.lock_outline_rounded, size: 16),
            label: const Text('Suspend'),
          )
        : FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _K.emerald600,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            onPressed: busy ? null : _toggleStatus,
            icon: _togglingStatus
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.lock_open_rounded, size: 16),
            label: const Text('Restore access'),
          );

    final menu = PopupMenuButton<int>(
      tooltip: 'More actions',
      enabled: !busy,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (_) => _delete(),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 0,
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: _K.red600),
              SizedBox(width: 10),
              Text('Delete permanently', style: TextStyle(fontSize: 13, color: _K.red600)),
            ],
          ),
        ),
      ],
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _K.gray200),
        ),
        child: const Icon(Icons.more_vert_rounded, size: 20, color: _K.gray600),
      ),
    );

    final identity = Row(
      children: [
        IconButton(
          tooltip: 'Back to employees',
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: _K.gray200),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () => context.go('/admin/employees'),
          icon: const Icon(Icons.arrow_back_rounded, size: 20, color: _K.gray600),
        ),
        const SizedBox(width: 12),
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: e.isActive ? _K.indigo50 : _K.gray100,
            shape: BoxShape.circle,
            border: Border.all(color: e.isActive ? _K.indigo200 : _K.gray200),
          ),
          child: Text(
            _initials(e.name),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: e.isActive ? _K.indigo600 : _K.gray500),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  e.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: wide ? 22 : 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.2,
                    color: _K.gray900,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Chip(text: '#${e.employeeCode}', tone: _indigo),
                  if (e.branchName.isNotEmpty) _Chip(text: e.branchName, tone: _gray, icon: Icons.apartment_rounded),
                  _Chip(
                    text: e.isActive ? 'Active' : 'Suspended',
                    tone: e.isActive ? _emerald : _red,
                    icon: e.isActive ? Icons.check_circle_outline_rounded : Icons.lock_outline_rounded,
                  ),
                  if (e.isTeamLead) const _Chip(text: 'Team lead', tone: _indigo, icon: Icons.groups_outlined),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    if (wide) {
      return Row(children: [Expanded(child: identity), const SizedBox(width: 12), statusButton, const SizedBox(width: 8), menu]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        identity,
        const SizedBox(height: 12),
        Row(children: [Expanded(child: statusButton), const SizedBox(width: 8), menu]),
      ],
    );
  }

  // ── Identity & employment ──

  Widget _identityCard(Employee e) {
    final editing = _editProfile;
    final age = _yearsSince(e.dateOfBirth);
    final tenure = _yearsSince(e.dateOfJoining);

    final view = _InfoList(rows: [
      ('Full name', e.name, null),
      ('Designation', e.designation, null),
      ('Branch', e.branchName.isNotEmpty ? e.branchName : null, null),
      ('Department', e.departmentName, null),
      ('Employment', _employmentTypes[e.employmentType], null),
      ('Gender', _genders[e.gender], null),
      ('Date of birth', _date(e.dateOfBirth), age != null ? '$age years old' : null),
      (
        'Date of joining',
        _date(e.dateOfJoining),
        tenure != null ? (tenure == 0 ? 'Less than a year' : '$tenure year${tenure == 1 ? '' : 's'} of service') : null,
      ),
    ]);

    Widget pair(Widget a, Widget b) => LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 380
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)],
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 12), b]),
        );

    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormField(
          label: 'Full name',
          child: TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 14),
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
            decoration: _inputDecoration(error: _nameError),
          ),
        ),
        _FormField(
          label: 'Designation',
          child: TextField(
            controller: _designation,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 14),
            decoration: _inputDecoration(hint: 'e.g. Software engineer'),
          ),
        ),
        pair(
          _FormField(
            label: 'Branch',
            child: DropdownButtonFormField<int>(
              value: _branches.any((b) => b.id == _branchId) ? _branchId : null,
              isExpanded: true,
              borderRadius: BorderRadius.circular(10),
              icon: const Icon(Icons.expand_more_rounded, size: 20, color: _K.gray500),
              style: const TextStyle(fontSize: 14, color: _K.gray900),
              decoration: _inputDecoration(),
              items: [for (final b in _branches) DropdownMenuItem(value: b.id, child: Text(b.name, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _branchId = v ?? _branchId),
            ),
          ),
          _FormField(
            label: 'Department',
            trailing: _LinkButton(label: 'New', icon: Icons.add_rounded, onTap: _saving ? null : _addDepartment),
            child: DropdownButtonFormField<int?>(
              value: _departments.any((d) => d.id == _departmentId) ? _departmentId : null,
              isExpanded: true,
              borderRadius: BorderRadius.circular(10),
              icon: const Icon(Icons.expand_more_rounded, size: 20, color: _K.gray500),
              style: const TextStyle(fontSize: 14, color: _K.gray900),
              decoration: _inputDecoration(),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('None')),
                for (final d in _departments)
                  DropdownMenuItem<int?>(value: d.id, child: Text(d.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _departmentId = v),
            ),
          ),
        ),
        pair(
          _FormField(
            label: 'Employment type',
            child: DropdownButtonFormField<String>(
              value: _employmentTypes.containsKey(_employmentType) ? _employmentType : 'FT',
              isExpanded: true,
              borderRadius: BorderRadius.circular(10),
              icon: const Icon(Icons.expand_more_rounded, size: 20, color: _K.gray500),
              style: const TextStyle(fontSize: 14, color: _K.gray900),
              decoration: _inputDecoration(),
              items: [for (final t in _employmentTypes.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
              onChanged: (v) => setState(() => _employmentType = v ?? 'FT'),
            ),
          ),
          _FormField(
            label: 'Gender',
            child: DropdownButtonFormField<String>(
              value: _gender == '' || _genders.containsKey(_gender) ? _gender : '',
              isExpanded: true,
              borderRadius: BorderRadius.circular(10),
              icon: const Icon(Icons.expand_more_rounded, size: 20, color: _K.gray500),
              style: const TextStyle(fontSize: 14, color: _K.gray900),
              decoration: _inputDecoration(),
              items: [
                const DropdownMenuItem(value: '', child: Text('Not set', style: TextStyle(color: _K.gray400))),
                for (final g in _genders.entries) DropdownMenuItem(value: g.key, child: Text(g.value)),
              ],
              onChanged: (v) => setState(() => _gender = v ?? ''),
            ),
          ),
        ),
        pair(
          _FormField(
            label: 'Date of birth',
            child: _DateInput(value: _dob, onChanged: (v) => setState(() => _dob = v)),
          ),
          _FormField(
            label: 'Date of joining',
            child: _DateInput(value: _doj, onChanged: (v) => setState(() => _doj = v)),
          ),
        ),
      ],
    );

    return _SectionCard(
      icon: Icons.badge_outlined,
      tone: _indigo,
      title: 'Identity and employment',
      editing: editing,
      saving: _saving,
      onEdit: () => setState(() => _editProfile = true),
      onSave: _saveProfile,
      onCancel: () => setState(() {
        _editProfile = false;
        _fillForms(e);
      }),
      child: editing ? form : view,
    );
  }

  // ── Reporting hierarchy ──

  Widget _hierarchyCard(Employee e) {
    final supervisor = _editHierarchy
        ? _FormField(
            label: 'Reports to',
            child: DropdownButtonFormField<int?>(
              value: _potentialLeads.any((l) => l.id == _teamLead) ? _teamLead : null,
              isExpanded: true,
              borderRadius: BorderRadius.circular(10),
              icon: const Icon(Icons.expand_more_rounded, size: 20, color: _K.gray500),
              style: const TextStyle(fontSize: 14, color: _K.gray900),
              decoration: _inputDecoration(),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('No supervisor (top level)')),
                for (final l in _potentialLeads)
                  DropdownMenuItem<int?>(
                    value: l.id,
                    child: Text('${l.name} (${l.teamName ?? 'Team lead'})', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _teamLead = v),
            ),
          )
        : Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: e.teamLeadName != null ? _K.indigo50 : _K.gray100,
                  shape: BoxShape.circle,
                ),
                child: e.teamLeadName != null
                    ? Text(_initials(e.teamLeadName!),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _K.indigo600))
                    : const Icon(Icons.vertical_align_top_rounded, size: 16, color: _K.gray400),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.teamLeadName ?? 'No supervisor',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _K.gray900)),
                    Text(e.teamLeadName != null ? 'Reports to' : 'Top level', style: _T.subtitle),
                  ],
                ),
              ),
            ],
          );

    final leadership = Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: e.isTeamLead ? _K.indigo50.withValues(alpha: 0.6) : _K.gray50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: e.isTeamLead ? _K.indigo100 : _K.gray100),
      ),
      child: Row(
        children: [
          Icon(e.isTeamLead ? Icons.groups_rounded : Icons.person_outline_rounded,
              size: 18, color: e.isTeamLead ? _K.indigo600 : _K.gray400),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.isTeamLead ? 'Team lead of ${e.teamName ?? 'an unnamed team'}' : 'Not a team lead',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: e.isTeamLead ? _K.indigo900 : _K.gray700,
                  ),
                ),
                Text(
                  e.isTeamLead ? 'Approves leave and corrections for their team.' : 'Does not manage anyone.',
                  style: _T.subtitle,
                ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: e.isTeamLead ? _K.red600 : _K.indigo600,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            onPressed: _saving ? null : (e.isTeamLead ? _revokeLead : _promote),
            child: Text(e.isTeamLead ? 'Remove' : 'Promote'),
          ),
        ],
      ),
    );

    return _SectionCard(
      icon: Icons.account_tree_outlined,
      tone: e.isTeamLead ? _indigo : _gray,
      title: 'Reporting',
      editing: _editHierarchy,
      saving: _saving,
      editLabel: 'Change',
      onEdit: () => setState(() => _editHierarchy = true),
      onSave: _saveHierarchy,
      onCancel: () => setState(() {
        _editHierarchy = false;
        _teamLead = e.teamLead;
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [supervisor, const SizedBox(height: 12), leadership],
      ),
    );
  }

  // ── System access ──

  Widget _accessCard(Employee e) {
    final editing = _editAccess;
    final username = e.email ?? (e.portalUsername?.replaceFirst(RegExp(r'^c\d+__'), '') ?? '—');

    final portal = Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: e.portalEnabled ? _K.emerald50.withValues(alpha: 0.6) : _K.gray50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: e.portalEnabled ? _K.emerald100 : _K.gray100),
      ),
      child: Row(
        children: [
          Icon(
            e.portalEnabled ? Icons.verified_user_outlined : Icons.lock_clock_outlined,
            size: 18,
            color: e.portalEnabled ? _K.emerald600 : _K.gray400,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.portalEnabled ? 'Portal login active' : 'No portal login yet',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: e.portalEnabled ? _K.emerald800 : _K.gray700,
                  ),
                ),
                const SizedBox(height: 1),
                e.portalEnabled
                    ? Text.rich(
                        TextSpan(children: [
                          const TextSpan(text: 'Username '),
                          TextSpan(
                            text: username,
                            style: const TextStyle(fontWeight: FontWeight.w600, color: _K.emerald700),
                          ),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: _K.gray500),
                      )
                    : const Text(
                        'Saving an email creates a login, with the employee code as the first password.',
                        style: _T.subtitle,
                      ),
              ],
            ),
          ),
          if (e.portalEnabled)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: _K.red600,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              onPressed: _saving ? null : _revokeAccess,
              child: const Text('Revoke'),
            ),
        ],
      ),
    );

    return _SectionCard(
      icon: Icons.key_outlined,
      tone: e.portalEnabled ? _emerald : _gray,
      title: 'Contact and portal access',
      editing: editing,
      saving: _saving,
      saveColor: _K.emerald600,
      onEdit: () => setState(() => _editAccess = true),
      onSave: _saveAccess,
      onCancel: () => setState(() {
        _editAccess = false;
        _fillForms(e);
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (editing) ...[
            _FormField(
              label: 'Email (login username)',
              child: TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontSize: 14),
                onChanged: (_) {
                  if (_emailError != null) setState(() => _emailError = null);
                },
                decoration: _inputDecoration(hint: 'name@company.com', icon: Icons.mail_outline_rounded, error: _emailError),
              ),
            ),
            _FormField(
              label: 'Phone',
              child: TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 14),
                decoration: _inputDecoration(hint: '+1 234 567 8900', icon: Icons.phone_outlined),
              ),
            ),
          ] else ...[
            _InfoList(rows: [('Email', e.email, null), ('Phone', e.phone, null)]),
            const SizedBox(height: 10),
          ],
          portal,
        ],
      ),
    );
  }

  // ── Tabs: logs and shifts ──

  Widget _tabsCard(Employee e) {
    Widget tab(bool value, String label, IconData icon, {int? count}) {
      final selected = _historyTab == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: InkWell(
            onTap: () => setState(() => _historyTab = value),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: selected ? _K.indigo600 : Colors.transparent, width: 2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: selected ? _K.indigo600 : _K.gray400),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? _K.indigo600 : _K.gray500,
                      ),
                    ),
                  ),
                  if (count != null && count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: selected ? _K.indigo50 : _K.gray100,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: selected ? _K.indigo600 : _K.gray500,
                          fontFeatures: _T.tabular,
                        ),
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

    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _K.gray100))),
            child: Row(
              children: [
                tab(true, 'Device punches', Icons.fingerprint_rounded, count: _logs.length),
                tab(false, 'Shift and schedule', Icons.schedule_rounded),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _historyTab ? _logsView() : EmployeeShiftForm(employeeId: e.id, onSuccess: _afterShiftChange),
          ),
        ],
      ),
    );
  }

  Widget _logsView() {
    if (_logsLoading && _logs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _K.indigo500)),
            SizedBox(width: 10),
            Text('Loading punches…', style: _T.subtitle),
          ],
        ),
      );
    }
    if (_logs.isEmpty) {
      return const _EmptyState(
        icon: Icons.fingerprint_rounded,
        title: 'No punches recorded',
        message: 'Punches appear here once this employee uses an attendance device.',
      );
    }

    final shown = _showAllLogs ? _logs : _logs.take(10).toList();

    // Group under the punch date.
    final rows = <Widget>[];
    String? day;
    for (final log in shown) {
      final (date, _) = _punchDateTime(log.timestamp);
      if (date != day) {
        day = date;
        rows.add(Padding(
          padding: EdgeInsets.only(top: rows.isEmpty ? 0 : 12, bottom: 6),
          child: Semantics(
            header: true,
            child: Text(date, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.gray500)),
          ),
        ));
      }
      rows.add(_LogRow(log: log));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Text('Raw punches from devices', style: _T.title)),
            if (_logsLoading)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _K.indigo500))
            else
              Text(
                _showAllLogs || _logs.length <= 10 ? '${_logs.length} total' : 'Latest 10 of ${_logs.length}',
                style: const TextStyle(fontSize: 12, color: _K.gray500, fontFeatures: _T.tabular),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ...rows,
        if (_logs.length > 10 && !_showAllLogs) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: _K.indigo600,
              side: const BorderSide(color: _K.indigo200),
              minimumSize: const Size.fromHeight(38),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            onPressed: () => setState(() => _showAllLogs = true),
            child: Text('Show all (${_logs.length - 10} more)'),
          ),
        ],
      ],
    );
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────────

class _LogRow extends StatelessWidget {
  const _LogRow({required this.log});

  final AttendanceLog log;

  @override
  Widget build(BuildContext context) {
    // Device logs carry no ignore reason, so only IN / OUT apply here.
    final isIn = isInPunch(log.punchType, null);
    final isOut = log.punchType == 'OUT' || log.punchType == 'CHECK_OUT';
    final tone = isIn
        ? const _Tone(_K.emerald50, _K.emerald200, _K.emerald600)
        : isOut
            ? const _Tone(_K.amber50, _K.amber200, _K.amber600)
            : _gray;
    final (_, time) = _punchDateTime(log.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _K.gray100),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: tone.bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tone.border),
            ),
            child: Icon(
              isIn ? Icons.login_rounded : (isOut ? Icons.logout_rounded : Icons.touch_app_outlined),
              size: 15,
              color: tone.fg,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text(time,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray900, fontFeatures: _T.tabular)),
          ),
          _Chip(text: punchLabel(log.punchType, null), tone: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 4,
              children: [
                _Chip(text: log.source, tone: _gray),
                if (log.deviceName != null)
                  _Chip(
                    text: '${log.deviceName}${log.deviceCode != null ? ' (${log.deviceCode})' : ''}',
                    tone: _indigo,
                    icon: Icons.router_outlined,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Card with a title, an Edit button, and Cancel / Save under the form while editing.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.tone,
    required this.title,
    required this.editing,
    required this.saving,
    required this.onEdit,
    required this.onSave,
    required this.onCancel,
    required this.child,
    this.saveColor = _K.indigo600,
    this.editLabel = 'Edit',
  });

  final IconData icon;
  final _Tone tone;
  final String title;
  final bool editing;
  final bool saving;
  final VoidCallback onEdit;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final Widget child;
  final Color saveColor;
  final String editLabel;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      borderColor: editing ? _K.indigo200 : _K.gray100,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: tone.bg,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: tone.border),
                  ),
                  child: Icon(icon, size: 16, color: tone.fg),
                ),
                const SizedBox(width: 10),
                Expanded(child: Semantics(header: true, child: Text(title, style: _T.title))),
                if (!editing)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: _K.indigo600,
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    onPressed: saving ? null : onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: Text(editLabel),
                  )
                else
                  const _Chip(text: 'Editing', tone: _indigo),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedSize(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: child,
            ),
            if (editing) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: _K.gray600,
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: saving ? null : onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: saveColor,
                      disabledBackgroundColor: saveColor.withValues(alpha: 0.5),
                      disabledForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: saving ? null : onSave,
                    icon: saving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded, size: 16),
                    label: Text(saving ? 'Saving…' : 'Save'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Label / value rows; empty values read "Not set" in grey.
class _InfoList extends StatelessWidget {
  const _InfoList({required this.rows});

  /// (label, value, note under the value)
  final List<(String, String?, String?)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) _divider,
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: Text(rows[i].$1, style: _T.rowLabel)),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SelectableText(
                        (rows[i].$2 == null || rows[i].$2!.trim().isEmpty) ? 'Not set' : rows[i].$2!,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: (rows[i].$2 == null || rows[i].$2!.trim().isEmpty) ? FontWeight.w400 : FontWeight.w600,
                          color: (rows[i].$2 == null || rows[i].$2!.trim().isEmpty) ? _K.gray400 : _K.gray900,
                          fontFeatures: _T.tabular,
                        ),
                      ),
                      if (rows[i].$3 != null)
                        Text(rows[i].$3!, textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: _K.gray500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({required this.label, required this.child, this.trailing});

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 22,
            child: Row(
              children: [
                Expanded(child: Text(label, style: _T.fieldLabel)),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

InputDecoration _inputDecoration({String? hint, IconData? icon, String? error}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 14, color: _K.gray400),
    errorText: error,
    errorStyle: const TextStyle(fontSize: 12, color: _K.red600),
    prefixIcon: icon == null ? null : Icon(icon, size: 16, color: _K.gray500),
    prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 20),
    filled: true,
    fillColor: _K.gray50,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: border(_K.gray200),
    enabledBorder: border(_K.gray200),
    focusedBorder: border(_K.indigo500, 1.5),
    errorBorder: border(_K.red200),
    focusedErrorBorder: border(_K.red600, 1.5),
  );
}

/// Date field ("YYYY-MM-DD" or null) that opens the date picker.
class _DateInput extends StatelessWidget {
  const _DateInput({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final date = parseDateOnly(value);
    return Semantics(
      button: true,
      label: date == null ? 'Not set, pick a date' : formatDDMMMYYYY(date),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: date ?? DateTime.now(),
            firstDate: DateTime(1940),
            lastDate: DateTime(2100),
          );
          if (picked != null) onChanged(toDateKey(picked));
        },
        child: InputDecorator(
          decoration: _inputDecoration(icon: Icons.calendar_today_outlined).copyWith(
            contentPadding: const EdgeInsets.only(left: 0, top: 4, bottom: 4),
            suffixIcon: date == null
                ? null
                : IconButton(
                    tooltip: 'Clear date',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onChanged(null),
                    icon: const Icon(Icons.close_rounded, size: 16, color: _K.gray400),
                  ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Text(
              date == null ? 'Not set' : formatDDMMMYYYY(date),
              style: TextStyle(fontSize: 14, color: date == null ? _K.gray400 : _K.gray900, fontFeatures: _T.tabular),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Name dialogs ────────────────────────────────────────────────────────────

class _PromotionDialog extends StatefulWidget {
  const _PromotionDialog();

  @override
  State<_PromotionDialog> createState() => _PromotionDialogState();
}

class _PromotionDialogState extends State<_PromotionDialog> {
  final _team = TextEditingController();

  @override
  void dispose() {
    _team.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _NameDialog(
      icon: Icons.groups_rounded,
      title: 'Promote to team lead',
      description: 'Name the team this employee will lead. They can then approve leave and corrections for it.',
      label: 'Team name',
      hint: 'e.g. Creative production',
      controller: _team,
      confirm: 'Promote',
    );
  }
}

class _DepartmentDialog extends StatefulWidget {
  const _DepartmentDialog();

  @override
  State<_DepartmentDialog> createState() => _DepartmentDialogState();
}

class _DepartmentDialogState extends State<_DepartmentDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _NameDialog(
      icon: Icons.account_tree_outlined,
      title: 'New department',
      description: 'The department becomes available across the company.',
      label: 'Department name',
      hint: 'e.g. Engineering',
      controller: _name,
      confirm: 'Add department',
    );
  }
}

/// Dialog asking for one name; pops the trimmed text or null.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.icon,
    required this.title,
    required this.description,
    required this.label,
    required this.hint,
    required this.controller,
    required this.confirm,
  });

  final IconData icon;
  final String title;
  final String description;
  final String label;
  final String hint;
  final TextEditingController controller;
  final String confirm;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  void _submit() {
    final text = widget.controller.text.trim();
    if (text.isNotEmpty) Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = widget.controller.text.trim().isNotEmpty;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _K.indigo50,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: _K.indigo200),
                    ),
                    child: Icon(widget.icon, size: 18, color: _K.indigo600),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(widget.description, style: const TextStyle(fontSize: 13, height: 1.45, color: _K.gray600)),
              const SizedBox(height: 16),
              Text(widget.label, style: _T.fieldLabel),
              const SizedBox(height: 6),
              TextField(
                controller: widget.controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                style: const TextStyle(fontSize: 14),
                decoration: _inputDecoration(hint: widget.hint),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: _K.gray600,
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _K.indigo600,
                      disabledBackgroundColor: _K.indigo200,
                      disabledForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: canConfirm ? _submit : null,
                    child: Text(widget.confirm),
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

// ── States ──────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry, required this.onBack});

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(color: _K.red50, shape: BoxShape.circle),
                child: const Icon(Icons.person_off_outlined, size: 22, color: _K.red500),
              ),
              const SizedBox(height: 12),
              const Text(
                'Employee record not available',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900),
              ),
              const SizedBox(height: 4),
              Text(message, textAlign: TextAlign.center, style: _T.subtitle),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _K.gray700,
                      side: const BorderSide(color: _K.gray200),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('Employees'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _K.indigo600,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Retry'),
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

class _PageSkeleton extends StatelessWidget {
  const _PageSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bone(double h) => Container(
          height: h,
          decoration: BoxDecoration(color: _K.gray100, borderRadius: BorderRadius.circular(_cardRadius)),
        );

    return Semantics(
      label: 'Loading employee',
      child: Column(
        children: [
          const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final lg = c.maxWidth >= 1024;
                return ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.all(c.maxWidth >= 640 ? 24 : 16),
                  children: [
                    bone(56),
                    const SizedBox(height: 20),
                    if (lg)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 2, child: Column(children: [bone(320), const SizedBox(height: 20), bone(160)])),
                          const SizedBox(width: 20),
                          Expanded(flex: 3, child: bone(500)),
                        ],
                      )
                    else ...[
                      bone(320),
                      const SizedBox(height: 16),
                      bone(160),
                    ],
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

/// White card with a hairline border.
class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.borderColor = _K.gray100});

  final Widget child;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: borderColor),
        boxShadow: const [BoxShadow(color: Color(0x08101828), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: child,
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: tone.fg), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: tone.fg, fontFeatures: _T.tabular),
            ),
          ),
        ],
      ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
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
          Text(title, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _K.gray700)),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(message!, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, height: 1.4, color: _K.gray500)),
          ],
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
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: _K.red50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _K.red200),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, size: 18, color: _K.red700),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 13, height: 1.4, color: _K.red700))),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: _K.red700,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
  const _LinkButton({required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 14, color: _K.indigo600), const SizedBox(width: 2)],
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.indigo600)),
            ],
          ),
        ),
      ),
    );
  }
}