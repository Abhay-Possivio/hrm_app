// Port of features/admin/attendance/settings/AttendanceSettingsPage.tsx
// ("Configuration"): pick the scope (company-wide defaults or one branch),
// then a settings section.
//
// Wide screens get one side navigation (scope picker + sections) beside the
// form; phones get the scope picker and section tabs above the form. The
// forms themselves are the shared ones from components/settings.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrm_app/app/session.dart';
import 'package:hrm_app/auth/auth_store.dart';
import 'package:hrm_app/components/settings/attendrule_form.dart';
import 'package:hrm_app/components/settings/overtime.dart';
import 'package:hrm_app/components/settings/scheduled_exceptions.dart';
import 'package:hrm_app/components/settings/settings_widgets.dart';
import 'package:hrm_app/components/settings/shift_temp.dart';
import 'package:hrm_app/components/settings/weeklyschedule_form.dart';
import 'package:hrm_app/services/attendsettings_service.dart';
import 'package:hrm_app/services/branch_service.dart';
import 'package:hrm_app/utils/toast.dart';

typedef _C = SettingsColors;

/// Tints used only on this page (same Tailwind families as SettingsColors).
class _K {
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber200 = Color(0xFFFDE68A);
  static const amber700 = Color(0xFFB45309);
  static const red50 = Color(0xFFFEF2F2);
  static const red200 = Color(0xFFFECACA);
  static const red700 = Color(0xFFB91C1C);
}

enum _Category {
  rules('General rules', 'Late grace period and thresholds', Icons.tune_rounded),
  schedule('Working hours', 'Standard weekly timings', Icons.schedule_rounded),
  exceptions('Date overrides', 'Holidays and specific days', Icons.event_outlined),
  overtime('Overtime', 'Calculation and approval', Icons.bolt_rounded),
  shifts('Shift templates', 'Reusable shift patterns', Icons.dashboard_outlined);

  const _Category(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;
}

class _T {
  static const title = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3, color: _C.gray900);
  static const subtitle = TextStyle(fontSize: 12, height: 1.35, color: _C.gray500);
  static const label = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _C.gray500);
}

const _cardRadius = 16.0;

// ── Page ────────────────────────────────────────────────────────────────────

class AttendanceSettingsPage extends StatefulWidget {
  const AttendanceSettingsPage({super.key});

  @override
  State<AttendanceSettingsPage> createState() => _AttendanceSettingsPageState();
}

class _AttendanceSettingsPageState extends State<AttendanceSettingsPage> {
  List<BranchOption> _branches = const [];
  int? _branchId; // null = global defaults
  _Category _category = _Category.rules;

  Map<String, dynamic> _rules = const {};
  Map<String, dynamic> _schedule = const {};
  List<ScheduledException> _exceptions = const [];
  bool _loading = true;
  bool _loadedOnce = false;
  bool _showExceptionForm = false;
  String? _error;
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final user = context.read<AuthStore>().user ?? const <String, dynamic>{};
    try {
      final branches = await branchService.fetchBranchOptions();
      if (!mounted) return;
      setState(() => _branches = branches);
      // HR / branch managers start on their (first) branch, as on the web.
      if (!user.isCompanyAdmin && !user.isSuperuser && branches.isNotEmpty) {
        _branchId = branches.first.id;
      }
    } catch (_) {
      // No branches: only the global scope.
    }
    await _load();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        attendanceSettingsService.getRules(branchId: _branchId),
        attendanceSettingsService.getSchedule(branchId: _branchId),
        attendanceSettingsService.getExceptions(branchId: _branchId),
      ]);
      if (!mounted || id != _loadId) return;
      setState(() {
        _rules = results[0] as Map<String, dynamic>;
        _schedule = results[1] as Map<String, dynamic>;
        _exceptions = results[2] as List<ScheduledException>;
        _loadedOnce = true;
      });
    } catch (err) {
      if (mounted && id == _loadId) setState(() => _error = apiError(err, 'Could not load the settings.'));
    } finally {
      if (mounted && id == _loadId) setState(() => _loading = false);
    }
  }

  void _selectBranch(int? id) {
    if (id == _branchId) return;
    setState(() {
      _branchId = id;
      _showExceptionForm = false;
    });
    _load();
  }

  void _selectCategory(_Category c) {
    if (c == _category) return;
    setState(() {
      _category = c;
      _showExceptionForm = false;
    });
  }

  Future<bool> _saveRules(Map<String, dynamic> data) async {
    try {
      await attendanceSettingsService.updateRules(data, branchId: _branchId);
      if (mounted) showToast(context, 'Saved for $_scopeName');
      _load();
      return true;
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to save attendance rules'), error: true);
      return false;
    }
  }

  Future<bool> _saveSchedule(Map<String, dynamic> data) async {
    try {
      final updated = await attendanceSettingsService.updateSchedule(data, branchId: _branchId);
      if (!mounted) return true;
      setState(() => _schedule = updated);
      showToast(context, 'Weekly schedule saved for $_scopeName');
      await _load();
      return true;
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to save weekly schedule'), error: true);
      return false;
    }
  }

  Future<bool> _confirmReset(String what) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Reset $what for $_scopeName?',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _C.gray900),
        ),
        content: Text(
          "The branch's own $what are removed and it goes back to the global defaults.",
          style: const TextStyle(fontSize: 13, height: 1.45, color: _C.gray600),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _C.gray600),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _C.indigo600,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset to defaults'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _resetRules() async {
    final id = _branchId;
    if (id == null || !await _confirmReset('rules')) return;
    try {
      await attendanceSettingsService.resetRules(id);
      if (mounted) showToast(context, 'Rules reset to the global defaults');
      _load();
    } catch (_) {
      if (mounted) showToast(context, 'Failed to reset rules', error: true);
    }
  }

  Future<void> _resetSchedule() async {
    final id = _branchId;
    if (id == null || !await _confirmReset('working hours')) return;
    try {
      await attendanceSettingsService.resetSchedule(id);
      if (mounted) showToast(context, 'Working hours reset to the global defaults');
      _load();
    } catch (_) {
      if (mounted) showToast(context, 'Failed to reset schedule', error: true);
    }
  }

  String get _scopeName {
    if (_branchId == null) return 'Global defaults';
    for (final b in _branches) {
      if (b.id == _branchId) return b.name;
    }
    return 'Branch';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final lg = constraints.maxWidth >= 1024;
        final pad = constraints.maxWidth >= 640 ? 24.0 : 16.0;

        if (lg) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 280,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(right: BorderSide(color: _C.gray100)),
                ),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(16, pad, 16, pad),
                  children: [_sideNav()],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: _C.indigo600,
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(pad),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 960),
                          child: _content(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        return RefreshIndicator(
          color: _C.indigo600,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(pad),
            children: [
              const _PageTitle(),
              const SizedBox(height: 14),
              _ScopePicker(
                branches: _branches,
                branchId: _branchId,
                scopeName: _scopeName,
                onSelect: _selectBranch,
              ),
              const SizedBox(height: 12),
              _categoryTabs(),
              const SizedBox(height: 16),
              _content(),
            ],
          ),
        );
      },
    );
  }

  // ── Navigation ──

  Widget _sideNav() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PageTitle(),
        const SizedBox(height: 18),
        const Text('Scope', style: _T.label),
        const SizedBox(height: 6),
        _ScopePicker(
          branches: _branches,
          branchId: _branchId,
          scopeName: _scopeName,
          onSelect: _selectBranch,
        ),
        const SizedBox(height: 20),
        const Text('Settings', style: _T.label),
        const SizedBox(height: 6),
        for (final c in _Category.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _NavTile(category: c, selected: _category == c, onTap: () => _selectCategory(c)),
          ),
      ],
    );
  }

  Widget _categoryTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, c) in _Category.values.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            _TabChip(icon: c.icon, label: c.label, selected: _category == c, onTap: () => _selectCategory(c)),
          ],
        ],
      ),
    );
  }

  // ── Main content ──

  Widget _content() {
    final global = _branchId == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section header
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _K.indigo50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _K.indigo100),
              ),
              child: Icon(_category.icon, size: 20, color: _C.indigo600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      _category.label,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: _C.gray900),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(_category.description, style: _T.subtitle),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _ScopePill(global: global, name: _scopeName),
          ],
        ),
        const SizedBox(height: 16),

        if (global) ...[
          const _Banner(
            bg: _K.amber50,
            border: _K.amber200,
            fg: _K.amber700,
            icon: Icons.public_rounded,
            title: 'Editing company-wide defaults',
            message: 'These settings apply to every branch that has not overridden them. Changes affect attendance '
                'calculations across the organization.',
          ),
          const SizedBox(height: 16),
        ],

        if (_error != null) ...[
          _Banner(
            bg: _K.red50,
            border: _K.red200,
            fg: _K.red700,
            icon: Icons.error_outline_rounded,
            title: _loadedOnce ? "Couldn't refresh these settings" : "Couldn't load these settings",
            message: _error!,
            actionLabel: 'Retry',
            onAction: _load,
          ),
          const SizedBox(height: 16),
        ],

        if (_loading && !_loadedOnce)
          const _FormSkeleton()
        else if (!_loadedOnce)
          const SizedBox.shrink()
        else
          AnimatedOpacity(
            opacity: _loading ? 0.55 : 1,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(
              ignoring: _loading,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(minHeight: 2, color: _C.indigo500, backgroundColor: _K.indigo50),
                    ),
                  switch (_category) {
                    _Category.rules => AttendanceRuleForm(
                        key: ValueKey('rules-$_branchId'),
                        initialData: _rules,
                        onSave: _saveRules,
                        onReset: _branchId != null ? _resetRules : null,
                      ),
                    _Category.schedule => WeeklyScheduleForm(
                        key: ValueKey('schedule-$_branchId'),
                        initialData: _schedule,
                        onSave: _saveSchedule,
                        onReset: _branchId != null ? _resetSchedule : null,
                      ),
                    _Category.exceptions => _exceptionsSection(),
                    _Category.overtime => OvertimeSettingsForm(
                        key: ValueKey('overtime-$_branchId'),
                        initialData: _rules,
                        onSave: _saveRules,
                      ),
                    _Category.shifts => ShiftTemplatesList(
                        key: ValueKey('shifts-$_branchId'),
                        branchId: _branchId,
                      ),
                  },
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _exceptionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _showExceptionForm
              ? ScheduledExceptionForm(
                  branchId: _branchId,
                  onSuccess: () {
                    setState(() => _showExceptionForm = false);
                    _load();
                  },
                  onCancel: () => setState(() => _showExceptionForm = false),
                )
              : Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _C.gray200),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_exceptions.length} override${_exceptions.length == 1 ? '' : 's'}',
                              style: _T.title,
                            ),
                            const SizedBox(height: 1),
                            const Text('Days that work differently from the weekly schedule.', style: _T.subtitle),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _C.indigo600,
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        onPressed: () => setState(() => _showExceptionForm = true),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add override'),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 16),
        ScheduledExceptionsList(exceptions: _exceptions, onDelete: _load),
      ],
    );
  }
}

// ── Navigation pieces ───────────────────────────────────────────────────────

class _PageTitle extends StatelessWidget {
  const _PageTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _C.gray50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _C.gray200),
          ),
          child: const Icon(Icons.settings_outlined, size: 18, color: _C.gray600),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Configuration',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: _C.gray900),
              ),
              Text('Attendance settings', style: _T.subtitle),
            ],
          ),
        ),
      ],
    );
  }
}

/// Current scope as a field; tap to choose global defaults or a branch.
class _ScopePicker extends StatelessWidget {
  const _ScopePicker({
    required this.branches,
    required this.branchId,
    required this.scopeName,
    required this.onSelect,
  });

  final List<BranchOption> branches;
  final int? branchId;
  final String scopeName;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    final global = branchId == null;

    Widget item(int? id, String label, IconData icon, {String? sub}) {
      final selected = id == branchId;
      return Row(
        children: [
          Icon(icon, size: 18, color: selected ? _C.indigo600 : _C.gray400),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? _C.indigo600 : _C.gray700,
                  ),
                ),
                if (sub != null) Text(sub, style: const TextStyle(fontSize: 11, color: _C.gray500)),
              ],
            ),
          ),
          if (selected) const Icon(Icons.check_rounded, size: 16, color: _C.indigo600),
        ],
      );
    }

    // PopupMenuButton values can't be null, so -1 stands for global.
    return PopupMenuButton<int>(
      tooltip: 'Change scope',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (v) => onSelect(v == -1 ? null : v),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: -1,
          child: item(null, 'Global defaults', Icons.public_rounded, sub: 'Applies to every branch'),
        ),
        if (branches.isNotEmpty) const PopupMenuDivider(height: 8),
        for (final b in branches) PopupMenuItem(value: b.id, child: item(b.id, b.name, Icons.apartment_rounded)),
      ],
      child: Semantics(
        button: true,
        label: 'Scope: $scopeName. Tap to change',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _C.gray200),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: global ? _K.amber50 : _K.indigo50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  global ? Icons.public_rounded : Icons.apartment_rounded,
                  size: 16,
                  color: global ? _K.amber700 : _C.indigo600,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scopeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _C.gray900),
                    ),
                    Text(
                      global ? 'Company-wide' : 'Branch override',
                      style: const TextStyle(fontSize: 11, color: _C.gray500),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.unfold_more_rounded, size: 18, color: _C.gray400),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScopePill extends StatelessWidget {
  const _ScopePill({required this.global, required this.name});

  final bool global;
  final String name;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: global ? _K.amber50 : _K.indigo50,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: global ? _K.amber200 : _K.indigo100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(global ? Icons.public_rounded : Icons.apartment_rounded, size: 12,
                color: global ? _K.amber700 : _C.indigo600),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: global ? _K.amber700 : _C.indigo600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.category, required this.selected, required this.onTap});

  final _Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? _K.indigo50 : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(category.icon, size: 18, color: selected ? _C.indigo600 : _C.gray400),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.label,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? _C.indigo600 : _C.gray700,
                        ),
                      ),
                      Text(
                        category.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: _C.gray500),
                      ),
                    ],
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

class _TabChip extends StatelessWidget {
  const _TabChip({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(side: BorderSide(color: selected ? _C.indigo500 : _C.gray200));
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? _C.indigo500 : Colors.white,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: selected ? Colors.white : _C.gray500),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? Colors.white : _C.gray700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Small pieces ────────────────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  const _Banner({
    required this.bg,
    required this.border,
    required this.fg,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final Color bg;
  final Color border;
  final Color fg;
  final IconData icon;
  final String title;
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
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: fg)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
                  const SizedBox(height: 2),
                  Text(message, style: const TextStyle(fontSize: 12, height: 1.45, color: _C.gray600)),
                ],
              ),
            ),
            if (hasAction)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: fg,
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

/// Placeholder shown while a scope's settings load for the first time.
class _FormSkeleton extends StatelessWidget {
  const _FormSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bone(double h, {double? w}) => Container(
          width: w ?? double.infinity,
          height: h,
          decoration: BoxDecoration(color: _C.gray100, borderRadius: BorderRadius.circular(8)),
        );

    return Semantics(
      label: 'Loading settings',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_cardRadius),
          border: Border.all(color: _C.gray100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LinearProgressIndicator(minHeight: 2, color: _C.indigo500, backgroundColor: _K.indigo50),
            const SizedBox(height: 16),
            for (var i = 0; i < 4; i++) ...[
              bone(12, w: 140),
              const SizedBox(height: 8),
              bone(42),
              const SizedBox(height: 18),
            ],
            Align(alignment: Alignment.centerRight, child: bone(40, w: 140)),
          ],
        ),
      ),
    );
  }
}