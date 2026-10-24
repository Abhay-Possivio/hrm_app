// Port of features/admin/employees/BulkEditPage.tsx ("Bulk Edit Workforce",
// /admin/employees/bulk-edit): edit many employees' profile details and login
// email / phone in one list, 10 per page, each with its own Save buttons.
//
// Two modes, as on the web: Standard (profile + login) and Login Setup Only
// (?mode=login).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hrm_app/components/ui/pagination_bar.dart';
import 'package:hrm_app/services/branch_service.dart';
import 'package:hrm_app/services/dept_service.dart';
import 'package:hrm_app/services/employee_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';
import 'package:hrm_app/utils/toast.dart';

const _pageSize = 10;
const _types = [('FT', 'Full-Time'), ('PT', 'Part-Time'), ('CT', 'Contract')];
const _genders = [('', 'Select Gender'), ('M', 'Male'), ('F', 'Female'), ('O', 'Other')];

class _K {
  static const gray50 = Color(0xFFF9FAFB);
  static const gray100 = Color(0xFFF3F4F6);
  static const gray200 = Color(0xFFE5E7EB);
  static const gray400 = Color(0xFF9CA3AF);
  static const gray500 = Color(0xFF6B7280);
  static const gray600 = Color(0xFF4B5563);
  static const gray700 = Color(0xFF374151);
  static const gray800 = Color(0xFF1F2937);
  static const gray900 = Color(0xFF111827);
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald600 = Color(0xFF059669);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber200 = Color(0xFFFDE68A);
  static const amber700 = Color(0xFFB45309);
  static const blue50 = Color(0xFFEFF6FF);
  static const blue200 = Color(0xFFBFDBFE);
  static const blue600 = Color(0xFF2563EB);
}

/// Editable copy of one employee's fields.
class _RowForm {
  _RowForm(Employee e)
      : name = TextEditingController(text: e.name),
        designation = TextEditingController(text: e.designation ?? ''),
        email = TextEditingController(text: e.email ?? ''),
        phone = TextEditingController(text: e.phone ?? ''),
        branchId = e.branchId,
        departmentId = e.departmentId,
        employmentType = e.employmentType ?? 'FT',
        gender = e.gender ?? '',
        dateOfBirth = e.dateOfBirth,
        dateOfJoining = e.dateOfJoining;

  final TextEditingController name;
  final TextEditingController designation;
  final TextEditingController email;
  final TextEditingController phone;
  int branchId;
  int? departmentId;
  String employmentType;
  String gender;
  String? dateOfBirth;
  String? dateOfJoining;

  void dispose() {
    name.dispose();
    designation.dispose();
    email.dispose();
    phone.dispose();
  }
}

class BulkEditPage extends StatefulWidget {
  const BulkEditPage({super.key, this.loginMode = false});

  /// "Login Setup Only" mode (?mode=login).
  final bool loginMode;

  @override
  State<BulkEditPage> createState() => _BulkEditPageState();
}

class _BulkEditPageState extends State<BulkEditPage> {
  List<Employee> _employees = const [];
  final Map<int, _RowForm> _forms = {};
  int _total = 0;
  int _page = 1;
  bool _loading = true;
  int _loadId = 0;

  List<BranchOption> _branches = const [];
  List<Department> _departments = const [];

  String _search = '';
  String _branch = '';
  String _profile = 'all'; // all | incomplete | complete
  String _login = 'all'; // all | unset | set
  Timer? _debounce;

  int? _savingProfile;
  int? _savingLogin;

  @override
  void initState() {
    super.initState();
    Future.wait([branchService.fetchBranchOptions(), departmentService.fetchDepartments()]).then((r) {
      if (!mounted) return;
      setState(() {
        _branches = r[0] as List<BranchOption>;
        _departments = r[1] as List<Department>;
      });
    }).catchError((_) {
      if (mounted) showToast(context, 'Failed to load branches or departments', error: true);
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant BulkEditPage old) {
    super.didUpdateWidget(old);
    if (old.loginMode != widget.loginMode) {
      _page = 1;
      _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final f in _forms.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    setState(() => _loading = true);
    try {
      final res = await employeeService.fetchEmployees(
        q: _search,
        page: _page,
        pageSize: _pageSize,
        branchId: _branch.isEmpty ? null : _branch,
        profileStatus: (!widget.loginMode && _profile != 'all') ? _profile.toUpperCase() : null,
        loginStatus: _login != 'all' ? _login.toUpperCase() : null,
      );
      if (!mounted || id != _loadId) return;
      setState(() {
        for (final f in _forms.values) {
          f.dispose();
        }
        _forms
          ..clear()
          ..addAll({for (final e in res.results) e.id: _RowForm(e)});
        _employees = res.results;
        _total = res.count;
      });
    } catch (_) {
      if (mounted && id == _loadId) showToast(context, 'Failed to load employees', error: true);
    } finally {
      if (mounted && id == _loadId) setState(() => _loading = false);
    }
  }

  void _filter(VoidCallback change) {
    setState(() {
      change();
      _page = 1;
    });
    _load();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _filter(() => _search = v));
  }

  Future<void> _refreshOne(int id) async {
    try {
      final fresh = await employeeService.fetchEmployeeById(id);
      if (!mounted) return;
      setState(() => _employees = [for (final e in _employees) e.id == id ? fresh : e]);
    } catch (_) {
      // The saved values are already in the form.
    }
  }

  Future<void> _saveProfile(Employee e) async {
    final f = _forms[e.id];
    if (f == null) return;
    setState(() => _savingProfile = e.id);
    try {
      await employeeService.updateEmployee(e.id, {
        'name': f.name.text.trim(),
        'branch_id': f.branchId,
        'department_id': f.departmentId,
        'designation': f.designation.text.trim(),
        'employment_type': f.employmentType,
        'gender': f.gender,
        'date_of_birth': f.dateOfBirth,
        'date_of_joining': f.dateOfJoining,
      });
      if (mounted) showToast(context, 'Profile details saved successfully');
      await _refreshOne(e.id);
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to update profile details'), error: true);
    } finally {
      if (mounted) setState(() => _savingProfile = null);
    }
  }

  Future<void> _saveLogin(Employee e) async {
    final f = _forms[e.id];
    if (f == null) return;
    setState(() => _savingLogin = e.id);
    try {
      await employeeService.updateEmployee(e.id, {'email': f.email.text.trim(), 'phone': f.phone.text.trim()});
      if (mounted) showToast(context, 'Credentials/contact details saved');
      await _refreshOne(e.id);
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to update credentials'), error: true);
    } finally {
      if (mounted) setState(() => _savingLogin = null);
    }
  }

  Future<void> _newDepartment(int employeeId) async {
    final name = await showDialog<String>(context: context, builder: (_) => const _DepartmentDialog());
    if (name == null || name.trim().isEmpty) return;
    try {
      final dept = await departmentService.createDepartment(name.trim());
      if (!mounted) return;
      setState(() {
        final exists = _departments.any((d) => d.id == dept.id || d.name.toLowerCase() == dept.name.toLowerCase());
        if (!exists) _departments = [..._departments, dept];
        _forms[employeeId]?.departmentId = dept.id;
      });
      showToast(context, 'Department "${dept.name}" created and selected.');
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to create department'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final login = widget.loginMode;

    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sm = width >= 640;
          final md = width >= 768;

          final title = Row(
            children: [
              IconButton(
                tooltip: 'Back to employees',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: _K.gray200),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => context.go('/admin/employees'),
                icon: const Icon(Icons.arrow_back, color: _K.gray600),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bulk Edit Workforce',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: _K.gray900),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Quickly edit profile details and setup credentials for all employees in a clean list format.',
                      style: TextStyle(fontSize: 13, color: _K.gray500),
                    ),
                  ],
                ),
              ),
            ],
          );
          final modeButton = FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: login ? _K.gray900 : _K.indigo600,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => context.go(login ? '/admin/employees/bulk-edit' : '/admin/employees/bulk-edit?mode=login'),
            icon: Icon(login ? Icons.person_outline : Icons.lock_outline, size: 16),
            label: Text(login ? 'Standard Bulk Edit' : 'Login Setup Only', style: const TextStyle(fontWeight: FontWeight.w600)),
          );

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(sm ? 24 : 16),
            children: [
              if (md)
                Row(children: [Expanded(child: title), const SizedBox(width: 16), modeButton])
              else ...[
                title,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: modeButton),
              ],
              const SizedBox(height: 20),

              // Filters
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _K.gray100),
                  boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      onChanged: _onSearch,
                      decoration: const InputDecoration(
                        hintText: 'Search name or code...',
                        hintStyle: TextStyle(fontSize: 14, color: _K.gray400),
                        prefixIcon: Icon(Icons.search, size: 18, color: _K.gray400),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const Divider(height: 1, color: _K.gray100),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Select(
                          value: _branch,
                          options: [('', 'All Branches'), for (final b in _branches) ('${b.id}', b.name)],
                          onChanged: (v) => _filter(() => _branch = v),
                        ),
                        if (!login)
                          _Select(
                            value: _profile,
                            options: const [('all', 'All Profiles'), ('incomplete', 'Incomplete'), ('complete', 'Complete')],
                            onChanged: (v) => _filter(() => _profile = v),
                          ),
                        _Select(
                          value: _login,
                          options: const [
                            ('all', 'All Login Statuses'),
                            ('unset', 'Without Login Setup'),
                            ('set', 'With Login Setup'),
                          ],
                          onChanged: (v) => _filter(() => _login = v),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (_loading && _employees.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 56),
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: _K.indigo600),
                      SizedBox(height: 12),
                      Text('Loading workforce directory...', style: TextStyle(fontSize: 14, color: _K.gray500)),
                    ],
                  ),
                )
              else if (_employees.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 56),
                  child: Column(
                    children: [
                      Icon(Icons.gpp_maybe_outlined, size: 40, color: _K.gray400),
                      SizedBox(height: 12),
                      Text('No employees found matching filters',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _K.gray900)),
                      SizedBox(height: 4),
                      Text('Try adjusting your filters or search query.', style: TextStyle(fontSize: 12, color: _K.gray500)),
                    ],
                  ),
                )
              else ...[
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                for (final e in _employees)
                  if (_forms[e.id] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _EmployeeCard(
                        key: ValueKey('bulk-${e.id}'),
                        employee: e,
                        form: _forms[e.id]!,
                        loginMode: login,
                        wide: md,
                        branches: _branches,
                        departments: _departments,
                        savingProfile: _savingProfile == e.id,
                        savingLogin: _savingLogin == e.id,
                        onChanged: () => setState(() {}),
                        onNewDepartment: () => _newDepartment(e.id),
                        onSaveProfile: () => _saveProfile(e),
                        onSaveLogin: () => _saveLogin(e),
                      ),
                    ),
              ],
              if (!_loading && _total > _pageSize)
                PaginationBar(
                  page: _page,
                  total: _total,
                  pageSize: _pageSize,
                  onPage: (p) {
                    setState(() => _page = p);
                    _load();
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── One employee ────────────────────────────────────────────────────────────

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    super.key,
    required this.employee,
    required this.form,
    required this.loginMode,
    required this.wide,
    required this.branches,
    required this.departments,
    required this.savingProfile,
    required this.savingLogin,
    required this.onChanged,
    required this.onNewDepartment,
    required this.onSaveProfile,
    required this.onSaveLogin,
  });

  final Employee employee;
  final _RowForm form;
  final bool loginMode;
  final bool wide;
  final List<BranchOption> branches;
  final List<Department> departments;
  final bool savingProfile;
  final bool savingLogin;
  final VoidCallback onChanged;
  final VoidCallback onNewDepartment;
  final VoidCallback onSaveProfile;
  final VoidCallback onSaveLogin;

  @override
  Widget build(BuildContext context) {
    final e = employee;
    final f = form;

    Widget badge(String text, bool good, {Color? bg, Color? fg, Color? border}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: bg ?? (good ? _K.emerald50 : _K.amber50),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border ?? (good ? _K.emerald200 : _K.amber200)),
          ),
          child: Text(
            text.toUpperCase(),
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1, color: fg ?? (good ? _K.emerald600 : _K.amber700)),
          ),
        );

    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: _K.indigo50, borderRadius: BorderRadius.circular(12), border: Border.all(color: _K.indigo100)),
          child: Text(
            e.name.isEmpty ? '?' : e.name.characters.first.toUpperCase(),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.indigo600),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _K.gray900)),
              Text('#${e.employeeCode}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: _K.gray500)),
              const SizedBox(height: 6),
              Text('Branch: ${e.branchName}', style: const TextStyle(fontSize: 12, color: _K.gray600)),
              Text('Department: ${e.departmentName ?? 'Not Set'}', style: const TextStyle(fontSize: 12, color: _K.gray600)),
              Text('Designation: ${e.designation ?? 'Not Set'}', style: const TextStyle(fontSize: 12, color: _K.gray600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  badge(e.profileCompleted ? 'Completed' : 'Incomplete', e.profileCompleted),
                  e.portalEnabled
                      ? badge('Login Active', true, bg: _K.blue50, fg: _K.blue600, border: _K.blue200)
                      : badge('No Login', false, bg: _K.gray100, fg: _K.gray500, border: _K.gray200),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final loginFields = _Fields(
      wide: wide,
      children: [
        _Labeled(
          label: 'Email',
          child: TextField(
            controller: f.email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            style: const TextStyle(fontSize: 14),
            decoration: _decoration(hint: 'email@company.com'),
          ),
        ),
        _Labeled(
          label: 'Phone',
          child: TextField(
            controller: f.phone,
            keyboardType: TextInputType.phone,
            style: const TextStyle(fontSize: 14),
            decoration: _decoration(hint: 'Phone number'),
          ),
        ),
      ],
    );
    final loginButton = Align(
      alignment: Alignment.centerRight,
      child: _SaveButton(
        icon: Icons.lock_outline,
        label: savingLogin ? 'Saving...' : (loginMode ? 'Save Login Credentials' : 'Save Login'),
        color: _K.gray900,
        onPressed: savingLogin ? null : onSaveLogin,
      ),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _K.gray100),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          identity,
          const Divider(height: 32, color: _K.gray100),
          if (loginMode) ...[
            loginFields,
            const SizedBox(height: 12),
            loginButton,
          ] else ...[
            _Fields(
              wide: wide,
              children: [
                _Labeled(
                  label: 'Full Name',
                  child: TextField(
                    controller: f.name,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(fontSize: 14),
                    decoration: _decoration(hint: 'Full Name'),
                  ),
                ),
                _Labeled(
                  label: 'Designation',
                  child: TextField(
                    controller: f.designation,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(fontSize: 14),
                    decoration: _decoration(hint: 'Designation'),
                  ),
                ),
                _Labeled(
                  label: 'Branch',
                  child: DropdownButtonFormField<int>(
                    value: branches.any((b) => b.id == f.branchId) ? f.branchId : null,
                    isExpanded: true,
                    decoration: _decoration(),
                    items: [for (final b in branches) DropdownMenuItem(value: b.id, child: Text(b.name, overflow: TextOverflow.ellipsis))],
                    onChanged: (v) {
                      if (v != null) f.branchId = v;
                      onChanged();
                    },
                  ),
                ),
                _Labeled(
                  label: 'Department',
                  action: InkWell(
                    onTap: onNewDepartment,
                    child: const Text('+ New Dept',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _K.indigo600)),
                  ),
                  child: DropdownButtonFormField<int?>(
                    value: departments.any((d) => d.id == f.departmentId) ? f.departmentId : null,
                    isExpanded: true,
                    decoration: _decoration(),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('None')),
                      for (final d in departments)
                        DropdownMenuItem<int?>(value: d.id, child: Text(d.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) {
                      f.departmentId = v;
                      onChanged();
                    },
                  ),
                ),
                _Labeled(
                  label: 'Type',
                  child: DropdownButtonFormField<String>(
                    value: f.employmentType,
                    isExpanded: true,
                    decoration: _decoration(),
                    items: [for (final (v, name) in _types) DropdownMenuItem(value: v, child: Text(name))],
                    onChanged: (v) {
                      f.employmentType = v ?? 'FT';
                      onChanged();
                    },
                  ),
                ),
                _Labeled(
                  label: 'Gender',
                  child: DropdownButtonFormField<String>(
                    value: _genders.any((g) => g.$1 == f.gender) ? f.gender : '',
                    isExpanded: true,
                    decoration: _decoration(),
                    items: [for (final (v, name) in _genders) DropdownMenuItem(value: v, child: Text(name))],
                    onChanged: (v) {
                      f.gender = v ?? '';
                      onChanged();
                    },
                  ),
                ),
                _Labeled(
                  label: 'Date of Birth',
                  child: _DateInput(
                    value: f.dateOfBirth,
                    onChanged: (v) {
                      f.dateOfBirth = v;
                      onChanged();
                    },
                  ),
                ),
                _Labeled(
                  label: 'Date of Joining',
                  child: _DateInput(
                    value: f.dateOfJoining,
                    onChanged: (v) {
                      f.dateOfJoining = v;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: _SaveButton(
                icon: Icons.save_outlined,
                label: savingProfile ? 'Saving...' : 'Save Profile',
                color: _K.indigo600,
                onPressed: savingProfile ? null : onSaveProfile,
              ),
            ),
            const Divider(height: 32, color: _K.gray100),
            const Text(
              'LOGIN / CONTACT',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: _K.gray400),
            ),
            const SizedBox(height: 10),
            loginFields,
            const SizedBox(height: 12),
            loginButton,
          ],
        ],
      ),
    );
  }
}

// ── Small pieces ────────────────────────────────────────────────────────────

InputDecoration _decoration({String? hint}) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 14, color: _K.gray400),
      filled: true,
      fillColor: _K.gray50,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _K.gray200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _K.indigo500),
      ),
    );

/// Two fields per row on wide screens, one on phones.
class _Fields extends StatelessWidget {
  const _Fields({required this.wide, required this.children});

  final bool wide;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = wide ? 2 : 1;
        const gap = 16.0;
        final w = ((constraints.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: 12,
          children: [for (final c in children) SizedBox(width: w, child: c)],
        );
      },
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child, this.action});

  final String label;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: _K.gray500),
              ),
            ),
            if (action != null) action!,
          ],
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _DateInput extends StatelessWidget {
  const _DateInput({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final date = parseDateOnly(value);
    return InkWell(
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
        decoration: _decoration().copyWith(
          contentPadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
          suffixIcon: date == null
              ? const Icon(Icons.calendar_today_outlined, size: 16, color: _K.gray400)
              : IconButton(
                  tooltip: 'Clear date',
                  onPressed: () => onChanged(null),
                  icon: const Icon(Icons.close, size: 16, color: _K.gray400),
                ),
        ),
        child: Text(
          date == null ? 'Not set' : formatDDMMMYYYY(date),
          style: TextStyle(fontSize: 14, color: date == null ? _K.gray400 : _K.gray800),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.icon, required this.label, required this.color, required this.onPressed});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    );
  }
}

/// Compact dropdown (components/ui/CustomSelect.tsx).
class _Select extends StatelessWidget {
  const _Select({required this.value, required this.options, required this.onChanged});

  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _K.gray50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _K.gray200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.any((o) => o.$1 == value) ? value : options.first.$1,
          isDense: true,
          borderRadius: BorderRadius.circular(12),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _K.gray700),
          items: [for (final (v, label) in options) DropdownMenuItem(value: v, child: Text(label))],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
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
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.apartment, color: _K.indigo600),
      title: const Text('Add Department'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Create a new department node. This department will be available globally for this branch.',
            style: TextStyle(fontSize: 13, color: _K.gray500),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: _decoration(hint: 'e.g. Sales, Quality, Devops'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _K.indigo600),
          onPressed: _name.text.trim().isEmpty ? null : () => Navigator.of(context).pop(_name.text.trim()),
          child: const Text('Add Department'),
        ),
      ],
    );
  }
}