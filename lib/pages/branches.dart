// Port of features/admin/branches/AdminBranchPage.tsx ("Branches & Locations",
// company admins only): branch counts, search, register / edit a branch, and
// suspend / reactivate one.

import 'package:flutter/material.dart';

import 'package:hrm_app/services/branch_service.dart';
import 'package:hrm_app/utils/toast.dart';

class _K {
  static const gray50 = Color(0xFFF9FAFB);
  static const gray100 = Color(0xFFF3F4F6);
  static const gray200 = Color(0xFFE5E7EB);
  static const gray400 = Color(0xFF9CA3AF);
  static const gray500 = Color(0xFF6B7280);
  static const gray600 = Color(0xFF4B5563);
  static const gray900 = Color(0xFF111827);
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo400 = Color(0xFF818CF8);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald600 = Color(0xFF059669);
  static const purple50 = Color(0xFFFAF5FF);
  static const purple600 = Color(0xFF9333EA);
  static const red50 = Color(0xFFFEF2F2);
  static const red200 = Color(0xFFFECACA);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
}

class BranchesPage extends StatefulWidget {
  const BranchesPage({super.key});

  @override
  State<BranchesPage> createState() => _BranchesPageState();
}

class _BranchesPageState extends State<BranchesPage> {
  List<Branch> _branches = const [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await branchService.fetchBranches();
      if (mounted) setState(() => _branches = list);
    } catch (_) {
      // Keep what's shown; pull down to retry.
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([Branch? branch]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 512),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _BranchForm(branch: branch),
    );
    if (saved == true) _load();
  }

  Future<void> _toggle(Branch b) async {
    if (b.isActive) {
      // The web suspends immediately; ask first, since it affects the whole site.
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Suspend ${b.name}?'),
          content: const Text('The branch will be marked as suspended. You can reactivate it at any time.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _K.red600),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Suspend'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await branchService.toggleBranchStatus(b.id, !b.isActive);
      _load();
    } catch (_) {
      if (mounted) showToast(context, 'Failed to update status.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.toLowerCase();
    final shown = _branches
        .where((b) => b.name.toLowerCase().contains(q) || (b.location ?? '').toLowerCase().contains(q))
        .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sm = width >= 640;
          final md = width >= 768;
          final lg = width >= 1024;

          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _K.emerald50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _K.emerald200),
                ),
                child: const Text(
                  'INFRASTRUCTURE MANAGEMENT',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: _K.emerald600),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Branches & Locations',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: _K.gray900),
              ),
              const SizedBox(height: 4),
              const Text(
                "Manage your company's physical locations, analyze performance by branch, and control operational status.",
                style: TextStyle(fontSize: 14, height: 1.5, color: _K.gray500),
              ),
            ],
          );
          final add = FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _K.indigo500,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Register Branch', style: TextStyle(fontWeight: FontWeight.w700)),
          );

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(sm ? 24 : 16),
            children: [
              if (md)
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: title), const SizedBox(width: 16), add])
              else ...[
                title,
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerLeft, child: add),
              ],
              const SizedBox(height: 24),

              // Stats
              _Grid(
                columns: md ? 3 : 1,
                gap: 12,
                children: [
                  _Stat(icon: Icons.apartment, bg: _K.indigo50, fg: _K.indigo600, label: 'Total Branches', value: '${_branches.length}'),
                  _Stat(
                    icon: Icons.power_settings_new,
                    bg: _K.emerald50,
                    fg: _K.emerald600,
                    label: 'Active Sites',
                    value: '${_branches.where((b) => b.isActive).length}',
                  ),
                  const _Stat(icon: Icons.groups_outlined, bg: _K.purple50, fg: _K.purple600, label: 'Global Coverage', value: 'Full'),
                ],
              ),
              const SizedBox(height: 24),

              // Search
              TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'Search branches by name or location...',
                  hintStyle: const TextStyle(fontSize: 14, color: _K.gray400),
                  prefixIcon: const Icon(Icons.search, size: 18, color: _K.gray500),
                  filled: true,
                  fillColor: _K.gray50,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _K.gray100),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _K.indigo400),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator(color: _K.indigo500)),
                )
              else if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text(
                      _branches.isEmpty ? 'No branches yet. Register your first branch.' : 'No branches match your search.',
                      style: const TextStyle(fontSize: 14, color: _K.gray400),
                    ),
                  ),
                )
              else
                _Grid(
                  columns: lg ? 3 : (md ? 2 : 1),
                  gap: 16,
                  children: [
                    for (final b in shown) _BranchCard(branch: b, onEdit: () => _openForm(b), onToggle: () => _toggle(b)),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({required this.branch, required this.onEdit, required this.onToggle});

  final Branch branch;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final b = branch;
    return Opacity(
      opacity: b.isActive ? 1 : 0.75,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _K.gray100),
          boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: _K.indigo50, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.place_outlined, size: 20, color: _K.indigo600),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(b.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900)),
                          if (!b.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _K.red50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: _K.red200),
                              ),
                              child: const Text(
                                'SUSPENDED',
                                style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: _K.red500),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        b.location ?? 'No location provided',
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: b.location == null ? FontStyle.italic : FontStyle.normal,
                          color: _K.gray500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit branch',
                  visualDensity: VisualDensity.compact,
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18, color: _K.gray400),
                ),
                IconButton(
                  tooltip: b.isActive ? 'Suspend branch' : 'Reactivate branch',
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggle,
                  icon: Icon(Icons.power_settings_new, size: 18, color: b.isActive ? _K.emerald600 : _K.red500),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: _K.gray50),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: _K.indigo500, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${b.employeeCount} Registered Personnel',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.gray600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchForm extends StatefulWidget {
  const _BranchForm({required this.branch});

  final Branch? branch;

  @override
  State<_BranchForm> createState() => _BranchFormState();
}

class _BranchFormState extends State<_BranchForm> {
  late final _name = TextEditingController(text: widget.branch?.name ?? '');
  late final _location = TextEditingController(text: widget.branch?.location ?? '');
  bool _saving = false;
  String? _error;

  bool get _editing => widget.branch != null;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter the branch name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_editing) {
        await branchService.updateBranch(widget.branch!.id, name: _name.text.trim(), location: _location.text.trim());
      } else {
        await branchService.createBranch(name: _name.text.trim(), location: _location.text.trim());
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (mounted) setState(() => _error = apiError(err, 'Operation failed. Name may already exist.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: _K.gray400),
        filled: true,
        fillColor: _K.gray50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _K.gray200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _K.indigo400),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: _K.gray500);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _editing ? 'Modify Branch' : 'Register New Branch',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _K.gray900),
            ),
            const SizedBox(height: 4),
            Text(
              _editing
                  ? 'Adjust site details or update location metadata.'
                  : 'Allocate a new operational node to your corporate network.',
              style: const TextStyle(fontSize: 13, color: _K.gray500),
            ),
            const SizedBox(height: 24),
            const Text('BRANCH NAME', style: label),
            const SizedBox(height: 6),
            TextField(
              controller: _name,
              autofocus: !_editing,
              textCapitalization: TextCapitalization.words,
              decoration: _decoration('e.g. Dubai Head Office'),
            ),
            const SizedBox(height: 16),
            const Text('LOCATION DETAILS', style: label),
            const SizedBox(height: 6),
            TextField(
              controller: _location,
              textCapitalization: TextCapitalization.words,
              decoration: _decoration('e.g. Business Bay, Building A'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(fontSize: 13, color: _K.red600)),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _K.gray500,
                      side: const BorderSide(color: _K.gray200),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('CANCEL', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _K.indigo500,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _saving ? null : _submit,
                    child: Text(
                      _saving ? 'SAVING...' : (_editing ? 'SAVE CHANGES' : 'CREATE SITE'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.bg, required this.fg, required this.label, required this.value});

  final IconData icon;
  final Color bg;
  final Color fg;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _K.gray100),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 22, color: fg),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: _K.gray500)),
              Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _K.gray900)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Equal-width grid (`grid grid-cols-N gap-X`).
class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.gap, required this.children});

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