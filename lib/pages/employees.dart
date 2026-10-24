// Port of features/admin/employees/EmployeesPage.tsx ("Workforce Directory")
// with AddEmployeeModal.tsx and the "Sync from Device" dialog.
//
// The web Add Employee form can also scan a fingerprint through a USB
// scanner plugged into the PC (a local service on localhost:8089). A phone
// can't reach that, so the app form leaves it out; enroll the fingerprint on
// the device itself or from the web console.
//
// Layout (compact):
//   Header: title · count · Add employee · Bulk edit · Sync from device
//   Filters card: search · branch · profile · source · Clear
//   Directory card: table (wide) / rows (phones) · pagination

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hrm_app/components/ui/pagination_bar.dart';
import 'package:hrm_app/services/branch_service.dart';
import 'package:hrm_app/services/devicefleet_service.dart';
import 'package:hrm_app/services/employee_service.dart';
import 'package:hrm_app/utils/toast.dart';

const _pageSize = 25;

const _profileOptions = [
  ('all', 'All profiles'),
  ('incomplete', 'Incomplete'),
  ('complete', 'Complete'),
  ('email_submitted', 'Email added'),
];

const _sourceOptions = [
  ('all', 'All sources'),
  ('synced', 'Synced from device'),
  ('manual', 'Added manually'),
];

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
  static const indigo800 = Color(0xFF3730A3);
  static const blue50 = Color(0xFFEFF6FF);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald500 = Color(0xFF10B981);
  static const emerald700 = Color(0xFF047857);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber200 = Color(0xFFFDE68A);
  static const amber700 = Color(0xFFB45309);
  static const amber800 = Color(0xFF92400E);
  static const red50 = Color(0xFFFEF2F2);
  static const red200 = Color(0xFFFECACA);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);
}

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3, color: _K.gray900);
  static const subtitle = TextStyle(fontSize: 12, height: 1.35, color: _K.gray500);
  static const fieldLabel = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.gray700);
  static const section = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _K.gray900);
  static const columnHead = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.gray500);
}

const _cardRadius = 16.0;
const _divider = Divider(height: 1, thickness: 1, color: _K.gray100);

/// Text for a value that may be null in the model (e.g. a branch name).
String _str(Object? v) => v?.toString() ?? '';

String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

// ── Page ────────────────────────────────────────────────────────────────────

class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key});

  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  List<Employee> _employees = const [];
  int _total = 0;
  int _page = 1;
  bool _loading = true;
  bool _loadedOnce = false;
  String? _error;
  String _search = '';
  String _profile = 'all'; // all | incomplete | complete | email_submitted
  String _source = 'all'; // all | synced | manual (filtered on the phone, like the web)
  String _branch = '';
  List<BranchOption> _branches = const [];
  bool _openingSync = false;
  Timer? _debounce;
  int _loadId = 0;
  final _searchCtrl = TextEditingController();

  int get _activeFilters =>
      (_search.isNotEmpty ? 1 : 0) + (_profile != 'all' ? 1 : 0) + (_source != 'all' ? 1 : 0) + (_branch.isNotEmpty ? 1 : 0);

  @override
  void initState() {
    super.initState();
    _loadBranches();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    try {
      final list = await branchService.fetchBranchOptions();
      if (mounted) setState(() => _branches = list);
    } catch (_) {
      // The branch filter just stays hidden.
    }
  }

  Future<void> _load() async {
    final id = ++_loadId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await employeeService.fetchEmployees(
        q: _search,
        page: _page,
        pageSize: _pageSize,
        profileStatus: _profile == 'all' ? null : _profile.toUpperCase(),
        branchId: _branch.isEmpty ? null : _branch,
      );
      if (!mounted || id != _loadId) return;
      setState(() {
        _employees = res.results;
        _total = res.count;
        _loadedOnce = true;
      });
    } catch (err) {
      if (mounted && id == _loadId) setState(() => _error = apiError(err, 'Could not load employees.'));
    } finally {
      if (mounted && id == _loadId) setState(() => _loading = false);
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final q = value.trim();
      if (q == _search) return;
      _setFilter(() => _search = q);
    });
  }

  void _setFilter(VoidCallback change) {
    setState(() {
      change();
      _page = 1;
    });
    _load();
  }

  void _clearFilters() {
    _debounce?.cancel();
    _searchCtrl.clear();
    _setFilter(() {
      _search = '';
      _profile = 'all';
      _source = 'all';
      _branch = '';
    });
  }

  Future<void> _openAdd() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddEmployeeForm(branches: _branches),
    );
    if (added == true && mounted) {
      showToast(context, 'Employee added.');
      _load();
    }
  }

  Future<void> _openSync() async {
    if (_openingSync) return;
    setState(() => _openingSync = true);
    List<Device> devices;
    try {
      final res = await getDevices();
      devices = res.results.where((d) => d.isDirectlyConnected && d.isActive).toList();
    } catch (_) {
      if (mounted) showToast(context, 'Failed to fetch devices', error: true);
      return;
    } finally {
      if (mounted) setState(() => _openingSync = false);
    }
    if (!mounted) return;
    final synced = await showDialog<bool>(context: context, builder: (_) => _SyncDialog(devices: devices));
    if (synced == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_loadedOnce && _error == null) return const _PageSkeleton();

    final shown = switch (_source) {
      'synced' => _employees.where((e) => e.isSyncedFromDevice).toList(),
      'manual' => _employees.where((e) => !e.isSyncedFromDevice).toList(),
      _ => _employees,
    };

    return RefreshIndicator(
      color: _K.indigo600,
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sm = width >= 640;
          final md = width >= 768;
          final gap = sm ? 20.0 : 16.0;

          final sections = <Widget>[
            _header(wide: md),
            if (_error != null)
              _Banner(message: _error!, actionLabel: 'Retry', onAction: _load),
            _filters(wide: sm),
            _directory(shown: shown, wide: md),
          ];

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
                      for (var i = 0; i < sections.length; i++) ...[
                        if (i > 0) SizedBox(height: i == 1 ? gap : 12),
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
    final add = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: _K.indigo600,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      onPressed: _openAdd,
      icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
      label: const Text('Add employee'),
    );

    final bulk = _OutlineAction(
      icon: Icons.edit_note_rounded,
      label: 'Bulk edit',
      onTap: () => context.go('/admin/employees/bulk-edit'),
    );
    final sync = _OutlineAction(
      icon: Icons.sync_rounded,
      label: 'Sync from device',
      busy: _openingSync,
      onTap: _openSync,
    );

    final title = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _K.indigo50,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: _K.indigo200),
          ),
          child: const Icon(Icons.groups_outlined, size: 22, color: _K.indigo600),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Employees',
                  style: TextStyle(
                    fontSize: wide ? 22 : 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.25,
                    color: _K.gray900,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _loadedOnce
                    ? '$_total ${_activeFilters > 0 ? 'matching ' : ''}employee${_total == 1 ? '' : 's'}. '
                        'Profiles, device sync and fingerprint status.'
                    : 'Profiles, device sync and fingerprint status.',
                style: _T.subtitle,
              ),
            ],
          ),
        ),
      ],
    );

    if (wide) {
      return Row(
        children: [
          Expanded(child: title),
          const SizedBox(width: 12),
          bulk,
          const SizedBox(width: 8),
          sync,
          const SizedBox(width: 8),
          add,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title,
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: add),
            const SizedBox(width: 8),
            PopupMenuButton<int>(
              tooltip: 'More actions',
              position: PopupMenuPosition.under,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onSelected: (v) {
                if (v == 0) {
                  context.go('/admin/employees/bulk-edit');
                } else {
                  _openSync();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 0,
                  child: Row(children: [
                    Icon(Icons.edit_note_rounded, size: 18, color: _K.indigo500),
                    SizedBox(width: 10),
                    Text('Bulk edit', style: TextStyle(fontSize: 13)),
                  ]),
                ),
                PopupMenuItem(
                  value: 1,
                  child: Row(children: [
                    Icon(Icons.sync_rounded, size: 18, color: _K.indigo500),
                    SizedBox(width: 10),
                    Text('Sync from device', style: TextStyle(fontSize: 13)),
                  ]),
                ),
              ],
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _K.gray200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_openingSync)
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      const Icon(Icons.more_horiz_rounded, size: 18, color: _K.gray600),
                    const SizedBox(width: 6),
                    const Text('More', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray700)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Filters ──

  Widget _filters({required bool wide}) {
    final search = ValueListenableBuilder<TextEditingValue>(
      valueListenable: _searchCtrl,
      builder: (context, value, _) => TextField(
        controller: _searchCtrl,
        onChanged: _onSearch,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14, color: _K.gray900),
        decoration: _inputDecoration(
          hint: 'Search name or employee code',
          icon: Icons.search_rounded,
          suffix: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                  onPressed: () {
                    _debounce?.cancel();
                    _searchCtrl.clear();
                    if (_search.isNotEmpty) _setFilter(() => _search = '');
                  },
                  icon: const Icon(Icons.close_rounded, size: 16, color: _K.gray400),
                ),
        ),
      ),
    );

    final selects = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_branches.isNotEmpty)
          _Select(
            icon: Icons.apartment_rounded,
            value: _branch,
            options: [('', 'All branches'), for (final b in _branches) ('${b.id}', b.name)],
            active: _branch.isNotEmpty,
            onChanged: (v) {
              if (v != _branch) _setFilter(() => _branch = v);
            },
          ),
        _Select(
          icon: Icons.assignment_ind_outlined,
          value: _profile,
          options: _profileOptions,
          active: _profile != 'all',
          onChanged: (v) {
            if (v != _profile) _setFilter(() => _profile = v);
          },
        ),
        _Select(
          icon: Icons.device_hub_rounded,
          value: _source,
          options: _sourceOptions,
          active: _source != 'all',
          onChanged: (v) => setState(() => _source = v),
        ),
        if (_activeFilters > 0) _LinkButton(label: 'Clear filters', onTap: _clearFilters),
      ],
    );

    return _Surface(
      padding: const EdgeInsets.all(12),
      child: wide
          ? Row(
              children: [
                Expanded(flex: 2, child: search),
                const SizedBox(width: 12),
                Flexible(flex: 3, child: Align(alignment: Alignment.centerLeft, child: selects)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [search, const SizedBox(height: 10), selects],
            ),
    );
  }

  // ── Directory ──

  Widget _directory({required List<Employee> shown, required bool wide}) {
    final from = _total == 0 ? 0 : (_page - 1) * _pageSize + 1;
    final to = (_page - 1) * _pageSize + _employees.length;

    Widget body;
    if (shown.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Loading employees…', textAlign: TextAlign.center, style: _T.subtitle),
              )
            : _activeFilters > 0
                ? _EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No employees match',
                    message: _source != 'all' && _employees.isNotEmpty
                        ? 'None on this page match the source filter. Try another page or clear filters.'
                        : 'Try another search or clear the filters.',
                    action: _LinkButton(label: 'Clear filters', onTap: _clearFilters),
                  )
                : _EmptyState(
                    icon: Icons.groups_outlined,
                    title: 'No employees yet',
                    message: 'Add employees one by one, or import the users already enrolled on a device.',
                    action: _LinkButton(label: 'Add employee', onTap: _openAdd),
                  ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) _divider,
            _EmployeeRow(
              employee: shown[i],
              wide: wide,
              onOpen: () => context.go('/admin/employees/${shown[i].id}'),
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                const Expanded(child: Text('Directory', style: _T.title)),
                Text(
                  _total == 0
                      ? 'No results'
                      : _source != 'all'
                          ? '${shown.length} of ${_employees.length} on this page'
                          : '$from–$to of $_total',
                  style: const TextStyle(fontSize: 12, color: _K.gray500, fontFeatures: _T.tabular),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 2,
            child: _loading
                ? const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50)
                : const ColoredBox(color: _K.gray100),
          ),
          if (wide && shown.isNotEmpty)
            Container(
              color: _K.gray50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: _tableRow(
                employee: const Text('Employee', style: _T.columnHead),
                branch: const Text('Branch', style: _T.columnHead),
                status: const Text('Account', style: _T.columnHead),
                fingerprint: const Text('Fingerprint', style: _T.columnHead),
              ),
            ),
          AnimatedOpacity(
            opacity: _loading && shown.isNotEmpty ? 0.55 : 1,
            duration: const Duration(milliseconds: 150),
            child: body,
          ),
          if (_total > _pageSize)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.gray100))),
              child: PaginationBar(
                page: _page,
                total: _total,
                pageSize: _pageSize,
                onPage: (p) {
                  setState(() => _page = p);
                  _load();
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Directory row ───────────────────────────────────────────────────────────

Widget _tableRow({
  required Widget employee,
  required Widget branch,
  required Widget status,
  required Widget fingerprint,
}) {
  return Row(
    children: [
      Expanded(flex: 4, child: employee),
      const SizedBox(width: 12),
      Expanded(flex: 3, child: branch),
      const SizedBox(width: 12),
      Expanded(flex: 2, child: status),
      const SizedBox(width: 12),
      Expanded(flex: 2, child: fingerprint),
      const SizedBox(width: 24),
    ],
  );
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({required this.employee, required this.wide, required this.onOpen});

  final Employee employee;
  final bool wide;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final e = employee;

    final avatar = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _K.indigo100),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_K.indigo50, _K.blue50],
        ),
      ),
      child: Text(
        _initials(e.name),
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _K.indigo600),
      ),
    );

    final status = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: e.isActive ? _K.emerald500 : _K.red500, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          e.isActive ? 'Active' : 'Locked',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: e.isActive ? _K.gray700 : _K.red600),
        ),
      ],
    );

    final fingerprint = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: e.hasFingerprint ? _K.emerald50 : _K.amber50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: e.hasFingerprint ? _K.emerald200 : _K.amber200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fingerprint_rounded, size: 13, color: e.hasFingerprint ? _K.emerald700 : _K.amber700),
          const SizedBox(width: 4),
          Text(
            e.hasFingerprint ? 'Enrolled' : 'Not enrolled',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: e.hasFingerprint ? _K.emerald700 : _K.amber700),
          ),
        ],
      ),
    );

    final synced = e.isSyncedFromDevice
        ? const Tooltip(
            message: 'Imported from a device',
            child: Icon(Icons.device_hub_rounded, size: 13, color: _K.gray400),
          )
        : null;

    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                e.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _K.gray900),
              ),
            ),
            if (synced != null) ...[const SizedBox(width: 6), synced],
          ],
        ),
        Text(
          wide ? e.employeeCode : [e.employeeCode, if (_str(e.branchName).isNotEmpty) _str(e.branchName)].join(', '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5, color: _K.gray500, fontFeatures: _T.tabular),
        ),
      ],
    );

    return Semantics(
      button: true,
      label: '${e.name}, ${e.employeeCode}, ${e.isActive ? 'active' : 'locked'}, '
          'fingerprint ${e.hasFingerprint ? 'enrolled' : 'not enrolled'}',
      hint: 'Opens the profile',
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            child: wide
                ? Row(
                    children: [
                      Expanded(
                        child: _tableRow(
                          employee: Row(children: [avatar, const SizedBox(width: 10), Expanded(child: nameBlock)]),
                          branch: Text(
                            _str(e.branchName).isNotEmpty ? _str(e.branchName) : '—',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, color: _K.gray600),
                          ),
                          status: Align(alignment: Alignment.centerLeft, child: status),
                          fingerprint: Align(alignment: Alignment.centerLeft, child: fingerprint),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 18, color: _K.gray300),
                    ],
                  )
                : Row(
                    children: [
                      avatar,
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            nameBlock,
                            const SizedBox(height: 5),
                            Wrap(
                              spacing: 10,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [status, fingerprint],
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 18, color: _K.gray300),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Add employee ────────────────────────────────────────────────────────────

class _AddEmployeeForm extends StatefulWidget {
  const _AddEmployeeForm({required this.branches});

  final List<BranchOption> branches;

  @override
  State<_AddEmployeeForm> createState() => _AddEmployeeFormState();
}

class _AddEmployeeFormState extends State<_AddEmployeeForm> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _designation = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  int? _branchId;

  List<Device> _devices = const [];
  final Set<int> _selectedDevices = {};
  bool _devicesLoading = false;
  bool _devicesFailed = false;
  bool _saving = false;
  String? _error;
  String? _codeError;
  String? _nameError;
  String? _branchError;
  String? _emailError;

  @override
  void dispose() {
    for (final c in [_code, _name, _designation, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _selectBranch(int? id) async {
    setState(() {
      _branchId = id;
      _branchError = null;
      _devices = const [];
      _selectedDevices.clear();
      _devicesFailed = false;
    });
    if (id == null) return;
    setState(() => _devicesLoading = true);
    try {
      final res = await getDevices(branchId: id);
      if (!mounted || _branchId != id) return;
      final devices = res.results.where((d) => d.isDirectlyConnected && d.isActive).toList();
      setState(() {
        _devices = devices;
        _selectedDevices.addAll(devices.map((d) => d.id)); // all selected by default
      });
    } catch (_) {
      if (mounted) setState(() => _devicesFailed = true);
    } finally {
      if (mounted) setState(() => _devicesLoading = false);
    }
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    setState(() {
      _codeError = _code.text.trim().isEmpty ? 'Required.' : null;
      _nameError = _name.text.trim().isEmpty ? 'Required.' : null;
      _branchError = _branchId == null ? 'Choose a branch.' : null;
      _emailError = (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email))
          ? 'Enter a valid email address.'
          : null;
      _error = null;
    });
    if (_codeError != null || _nameError != null || _branchError != null || _emailError != null) return;

    setState(() => _saving = true);
    try {
      await employeeService.createEmployee({
        'employee_code': _code.text.trim(),
        'name': _name.text.trim(),
        'branch_id': _branchId,
        'email': email,
        'phone': _phone.text.trim(),
        'designation': _designation.text.trim(),
        'target_device_ids': _selectedDevices.toList(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (mounted) setState(() => _error = apiError(err, 'Failed to add the employee.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final twoColumns = MediaQuery.sizeOf(context).width >= 480;

    Widget pair(Widget a, Widget b) => twoColumns
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)])
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 12), b]);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _K.indigo50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _K.indigo100),
                  ),
                  child: const Icon(Icons.person_add_alt_1_outlined, size: 20, color: _K.indigo600),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Add employee', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _K.gray900)),
                      SizedBox(height: 2),
                      Text('Create the profile and send it to the branch devices.', style: _T.subtitle),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded, size: 20, color: _K.gray400),
                ),
              ],
            ),
          ),
          _divider,

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Details', style: _T.section),
                  const SizedBox(height: 12),
                  pair(
                    _Field(
                      label: 'Employee code',
                      required: true,
                      controller: _code,
                      hint: 'e.g. 5001',
                      error: _codeError,
                      onChanged: () => setState(() => _codeError = null),
                    ),
                    _Field(
                      label: 'Full name',
                      required: true,
                      controller: _name,
                      hint: 'e.g. John Doe',
                      capitalize: true,
                      error: _nameError,
                      onChanged: () => setState(() => _nameError = null),
                    ),
                  ),
                  const SizedBox(height: 12),
                  pair(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Label('Branch', required: true),
                        DropdownButtonFormField<int>(
                          value: _branchId,
                          isExpanded: true,
                          hint: Text(
                            widget.branches.isEmpty ? 'No branches available' : 'Choose a branch',
                            style: const TextStyle(fontSize: 14, color: _K.gray400),
                          ),
                          icon: const Icon(Icons.expand_more_rounded, size: 20, color: _K.gray500),
                          borderRadius: BorderRadius.circular(10),
                          style: const TextStyle(fontSize: 14, color: _K.gray900),
                          decoration: _inputDecoration(error: _branchError),
                          items: [
                            for (final b in widget.branches) DropdownMenuItem(value: b.id, child: Text(b.name)),
                          ],
                          onChanged: _saving ? null : _selectBranch,
                        ),
                      ],
                    ),
                    _Field(label: 'Designation', controller: _designation, hint: 'e.g. Sales associate', capitalize: true),
                  ),
                  const SizedBox(height: 12),
                  pair(
                    _Field(
                      label: 'Email',
                      controller: _email,
                      hint: 'john@example.com',
                      keyboard: TextInputType.emailAddress,
                      error: _emailError,
                      onChanged: () => setState(() => _emailError = null),
                    ),
                    _Field(label: 'Phone', controller: _phone, hint: 'e.g. 0300 1234567', keyboard: TextInputType.phone),
                  ),

                  // Devices to push the new employee to
                  const SizedBox(height: 20),
                  const Text('Send to devices', style: _T.section),
                  const SizedBox(height: 4),
                  const Text(
                    'The employee is added to the selected attendance devices right away.',
                    style: _T.subtitle,
                  ),
                  const SizedBox(height: 10),
                  if (_branchId == null)
                    const _InlineNote(
                      icon: Icons.apartment_rounded,
                      text: "Choose a branch to see its devices.",
                      bg: _K.gray50,
                      border: _K.gray200,
                      fg: _K.gray600,
                    )
                  else if (_devicesLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _K.indigo500)),
                          SizedBox(width: 8),
                          Text('Loading branch devices…', style: _T.subtitle),
                        ],
                      ),
                    )
                  else if (_devicesFailed)
                    _InlineNote(
                      icon: Icons.error_outline_rounded,
                      text: 'Could not load the branch devices. The employee can still be saved.',
                      bg: _K.red50,
                      border: _K.red200,
                      fg: _K.red700,
                      actionLabel: 'Retry',
                      onAction: () => _selectBranch(_branchId),
                    )
                  else if (_devices.isEmpty)
                    const _InlineNote(
                      icon: Icons.info_outline_rounded,
                      text: 'This branch has no active direct-connected devices. The profile is saved in the system only.',
                      bg: _K.amber50,
                      border: _K.amber200,
                      fg: _K.amber800,
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _K.gray200),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < _devices.length; i++) ...[
                            if (i > 0) _divider,
                            CheckboxListTile(
                              value: _selectedDevices.contains(_devices[i].id),
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() =>
                                      v == true ? _selectedDevices.add(_devices[i].id) : _selectedDevices.remove(_devices[i].id)),
                              controlAffinity: ListTileControlAffinity.leading,
                              activeColor: _K.indigo600,
                              dense: true,
                              title: Text(_devices[i].label,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray900)),
                              subtitle: Text(_devices[i].deviceCode,
                                  style: const TextStyle(fontSize: 11.5, color: _K.gray500, fontFeatures: _T.tabular)),
                            ),
                          ],
                        ],
                      ),
                    ),

                  // Fingerprint: web-only
                  const SizedBox(height: 16),
                  const _InlineNote(
                    icon: Icons.fingerprint_rounded,
                    text: 'Fingerprint scanning with a USB reader is only available in the web console. '
                        'Enroll the fingerprint on the attendance device, or from the web.',
                    bg: _K.indigo50,
                    border: _K.indigo100,
                    fg: _K.indigo800,
                  ),
                ],
              ),
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.gray100))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  _InlineNote(icon: Icons.error_outline_rounded, text: _error!, bg: _K.red50, border: _K.red200, fg: _K.red700),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    if (_branchId != null && _devices.isNotEmpty)
                      Expanded(
                        child: Text(
                          '${_selectedDevices.length} of ${_devices.length} device${_devices.length == 1 ? '' : 's'} selected',
                          style: const TextStyle(fontSize: 12, color: _K.gray500, fontFeatures: _T.tabular),
                        ),
                      )
                    else
                      const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: _K.gray600,
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _K.indigo600,
                        disabledBackgroundColor: _K.indigo200,
                        disabledForegroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox(
                              width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_rounded, size: 16),
                      label: Text(_saving ? 'Saving…' : 'Add employee'),
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

// ── Sync employees from a device ────────────────────────────────────────────

class _SyncDialog extends StatefulWidget {
  const _SyncDialog({required this.devices});

  final List<Device> devices;

  @override
  State<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<_SyncDialog> {
  int? _syncing;

  Future<void> _sync(Device d) async {
    setState(() => _syncing = d.id);
    try {
      final res = await syncEmployeesFromDevice(d.id);
      if (!mounted) return;
      showToast(context, 'Imported ${res.newLogs} employee${res.newLogs == 1 ? '' : 's'} from ${d.label}.');
      Navigator.of(context).pop(true);
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to sync employees'), error: true);
    } finally {
      if (mounted) setState(() => _syncing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 460, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _K.indigo50,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: _K.indigo100),
                    ),
                    child: const Icon(Icons.sync_rounded, size: 18, color: _K.indigo600),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sync from device', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900)),
                        SizedBox(height: 1),
                        Text('Import the employees enrolled on a device.', style: _T.subtitle),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: _syncing != null ? null : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded, size: 20, color: _K.gray400),
                  ),
                ],
              ),
            ),
            _divider,
            Flexible(
              child: widget.devices.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: _EmptyState(
                        icon: Icons.router_outlined,
                        title: 'No devices to sync from',
                        message: 'Only active, direct-connected (TCP/IP) devices can be imported from.',
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: widget.devices.length,
                      separatorBuilder: (_, __) => const Padding(padding: EdgeInsets.only(left: 64), child: _divider),
                      itemBuilder: (_, i) {
                        final d = widget.devices[i];
                        final busy = _syncing == d.id;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(color: _K.gray100, borderRadius: BorderRadius.circular(9)),
                                child: const Icon(Icons.fingerprint_rounded, size: 17, color: _K.gray600),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _K.gray900)),
                                    Text(d.deviceCode,
                                        style: const TextStyle(fontSize: 11.5, color: _K.gray500, fontFeatures: _T.tabular)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _K.indigo600,
                                  disabledBackgroundColor: busy ? _K.indigo500 : _K.gray200,
                                  disabledForegroundColor: busy ? Colors.white : _K.gray500,
                                  minimumSize: const Size(0, 34),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                ),
                                onPressed: _syncing != null ? null : () => _sync(d),
                                icon: busy
                                    ? const SizedBox(
                                        width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.download_rounded, size: 15),
                                label: Text(busy ? 'Importing…' : 'Import'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.gray100))),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: _K.gray700,
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  onPressed: _syncing != null ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Close'),
                ),
              ),
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
    Widget bone(double h) => Container(
          height: h,
          decoration: BoxDecoration(color: _K.gray100, borderRadius: BorderRadius.circular(_cardRadius)),
        );

    return Semantics(
      label: 'Loading employees',
      child: Column(
        children: [
          const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => ListView(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.all(c.maxWidth >= 640 ? 24 : 16),
                children: [bone(48), const SizedBox(height: 16), bone(64), const SizedBox(height: 12), bone(440)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Form pieces ─────────────────────────────────────────────────────────────

InputDecoration _inputDecoration({String? hint, IconData? icon, Widget? suffix, String? error}) {
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
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 20),
    filled: true,
    fillColor: _K.gray50,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: border(_K.gray200),
    enabledBorder: border(_K.gray200),
    disabledBorder: border(_K.gray100),
    focusedBorder: border(_K.indigo500, 1.5),
    errorBorder: border(_K.red200),
    focusedErrorBorder: border(_K.red600, 1.5),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: text),
          if (required) const TextSpan(text: ' *', style: TextStyle(color: _K.red500)),
        ]),
        style: _T.fieldLabel,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboard,
    this.capitalize = false,
    this.required = false,
    this.error,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboard;
  final bool capitalize;
  final bool required;
  final String? error;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label(label, required: required),
        TextField(
          controller: controller,
          keyboardType: keyboard,
          textInputAction: TextInputAction.next,
          textCapitalization: capitalize ? TextCapitalization.words : TextCapitalization.none,
          style: const TextStyle(fontSize: 14),
          onChanged: error == null || onChanged == null ? null : (_) => onChanged!(),
          decoration: _inputDecoration(hint: hint, error: error),
        ),
      ],
    );
  }
}

// ── Small shared pieces ─────────────────────────────────────────────────────

/// White card with a hairline border.
class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
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

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({required this.icon, required this.label, required this.onTap, this.busy = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: _K.gray700,
        side: const BorderSide(color: _K.gray200),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      onPressed: busy ? null : onTap,
      icon: busy
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, size: 17, color: _K.indigo500),
      label: Text(label),
    );
  }
}

/// Compact dropdown (components/ui/CustomSelect.tsx); tinted when it narrows the list.
class _Select extends StatelessWidget {
  const _Select({
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
    this.active = false,
  });

  final IconData icon;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 10, right: 6),
      decoration: BoxDecoration(
        color: active ? _K.indigo50 : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? _K.indigo200 : _K.gray200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: active ? _K.indigo600 : _K.gray400),
          const SizedBox(width: 6),
          Flexible(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: options.any((o) => o.$1 == value) ? value : options.first.$1,
                isDense: true,
                borderRadius: BorderRadius.circular(10),
                icon: Icon(Icons.expand_more_rounded, size: 18, color: active ? _K.indigo600 : _K.gray400),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? _K.indigo600 : _K.gray700,
                ),
                items: [
                  for (final (v, label) in options)
                    DropdownMenuItem(value: v, child: Text(label, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineNote extends StatelessWidget {
  const _InlineNote({
    required this.icon,
    required this.text,
    required this.bg,
    required this.border,
    required this.fg,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final Color bg;
  final Color border;
  final Color fg;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(12, 10, onAction != null ? 4 : 12, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(fontSize: 12, height: 1.4, color: fg))),
            if (actionLabel != null && onAction != null)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: fg,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
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
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final hasAction = actionLabel != null && onAction != null;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(12, 10, hasAction ? 4 : 12, 10),
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
            if (hasAction)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: _K.red700,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                child: Text(actionLabel!),
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.indigo600)),
        ),
      ),
    );
  }
}