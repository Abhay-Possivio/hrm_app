// Port of features/admin/users/UserManagementPage.tsx ("Access Control",
// company admins only): staff accounts with their role and branch scope,
// provisioning new staff, editing branch access, and suspend / restore.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:hrm_app/services/branch_service.dart';
import 'package:hrm_app/services/tenantuser_service.dart';
import 'package:hrm_app/utils/toast.dart';

const _roles = [
  ('HR', 'HR Manager'),
  ('TEAM_LEAD', 'Team Lead'),
  ('BRANCH_MANAGER', 'Branch Manager'),
  ('VIEWER', 'IT Support / Viewer'),
];

class _K {
  static const gray50 = Color(0xFFF9FAFB);
  static const gray100 = Color(0xFFF3F4F6);
  static const gray200 = Color(0xFFE5E7EB);
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
  static const indigo700 = Color(0xFF4338CA);
  static const purple50 = Color(0xFFFAF5FF);
  static const purple200 = Color(0xFFE9D5FF);
  static const purple600 = Color(0xFF9333EA);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const red50 = Color(0xFFFEF2F2);
  static const red200 = Color(0xFFFECACA);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
}

class AccessControlPage extends StatefulWidget {
  const AccessControlPage({super.key});

  @override
  State<AccessControlPage> createState() => _AccessControlPageState();
}

class _AccessControlPageState extends State<AccessControlPage> {
  List<TenantUser> _users = const [];
  List<BranchOption> _branches = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        branchService.fetchBranchOptions(),
        tenantUserService.fetchUsers(),
      ]);
      if (!mounted) return;
      setState(() {
        _branches = results[0] as List<BranchOption>;
        _users = results[1] as List<TenantUser>;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to synchronize with server.');
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _provision() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 512),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ProvisionForm(branches: _branches),
    );
    if (created == true) {
      if (mounted) showToast(context, 'Staff account created');
      _load();
    }
  }

  Future<void> _toggleSuspend(TenantUser u) async {
    if (!u.isSuspended) {
      // The web suspends immediately; ask first, since it locks the person out.
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Suspend ${u.username}?'),
          content: const Text('They will no longer be able to sign in until access is restored.'),
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
      await tenantUserService.toggleSuspension(u.id);
      if (!mounted) return;
      setState(() => _users = [for (final x in _users) x.id == u.id ? x.copyWith(isSuspended: !x.isSuspended) : x]);
    } catch (_) {
      if (mounted) showToast(context, 'Action failed.', error: true);
    }
  }

  Future<void> _editBranches(TenantUser u) async {
    final ids = await showDialog<List<int>>(
      context: context,
      builder: (_) => _BranchAccessDialog(user: u, branches: _branches),
    );
    if (ids == null || !mounted) return;
    setState(() {
      _users = [
        for (final x in _users)
          x.id == u.id
              ? x.copyWith(branches: [
                  for (final b in _branches)
                    if (ids.contains(b.id)) TenantUserBranch(id: b.id, name: b.name),
                ])
              : x,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
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
              const Text(
                'Access Control',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: _K.gray900),
              ),
              const SizedBox(height: 4),
              const Text('Delegate authority and manage organization staff', style: TextStyle(fontSize: 14, color: _K.gray500)),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _K.red50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _K.red200),
                  ),
                  child: Text(_error!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.red600)),
                ),
              ],
            ],
          );
          final add = FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _K.indigo600,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _provision,
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const Text('Provision Staff', style: TextStyle(fontWeight: FontWeight.w700)),
          );

          Widget body;
          if (_loading) {
            body = const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(color: _K.indigo500)),
            );
          } else if (_users.isEmpty) {
            body = const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(Icons.gpp_maybe_outlined, size: 40, color: _K.gray400),
                  SizedBox(height: 12),
                  Text('No subordinate users identified.', style: TextStyle(fontSize: 14, color: _K.gray500)),
                ],
              ),
            );
          } else {
            body = _Grid(
              columns: lg ? 3 : (md ? 2 : 1),
              gap: 16,
              children: [
                for (final u in _users)
                  _UserCard(user: u, onEditBranches: () => _editBranches(u), onToggleSuspend: () => _toggleSuspend(u)),
              ],
            );
          }

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
              body,
            ],
          );
        },
      ),
    );
  }
}

// ── One staff account ───────────────────────────────────────────────────────

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.onEditBranches, required this.onToggleSuspend});

  final TenantUser user;
  final VoidCallback onEditBranches;
  final VoidCallback onToggleSuspend;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final admin = u.isCompanyAdmin;

    Widget scopePill(String text, {Color bg = _K.indigo50, Color fg = _K.indigo700, Color border = _K.indigo100, bool italic = false}) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: border)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.place_outlined, size: 12, color: fg),
              const SizedBox(width: 4),
              Text(
                text,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, fontStyle: italic ? FontStyle.italic : FontStyle.normal, color: fg),
              ),
            ],
          ),
        );

    return Opacity(
      opacity: u.isSuspended ? 0.7 : 1,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: u.isSuspended ? _K.red200 : _K.gray100),
          boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: admin ? _K.purple50 : _K.indigo50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: admin ? _K.purple200 : _K.indigo200),
                  ),
                  child: Text(
                    u.username.isEmpty ? '?' : u.username.characters.first.toUpperCase(),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: admin ? _K.purple600 : _K.indigo600),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: admin ? _K.purple50 : _K.gray100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: admin ? _K.purple200 : _K.gray200),
                  ),
                  child: Text(
                    admin ? 'ADMIN' : (u.role.isNotEmpty ? u.role : 'STAFF'),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: admin ? _K.purple600 : _K.gray600),
                  ),
                ),
                if (!admin)
                  IconButton(
                    tooltip: 'Edit branches',
                    visualDensity: VisualDensity.compact,
                    onPressed: onEditBranches,
                    icon: const Icon(Icons.edit_outlined, size: 16, color: _K.gray400),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(u.username, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900)),
            if (u.email.isNotEmpty) Text(u.email, style: const TextStyle(fontSize: 12, color: _K.gray500)),
            const SizedBox(height: 4),
            Text(
              u.isSuspended ? 'ACCESS_REVOKED' : 'VERIFIED_ACTIVE',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: u.isSuspended ? _K.red500 : _K.emerald600,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: admin
                  ? [scopePill('Global Scope', bg: _K.purple50, fg: _K.purple600, border: _K.purple200)]
                  : u.branches.isEmpty
                      ? [scopePill('No Branches Assigned', bg: _K.gray50, fg: _K.gray400, border: _K.gray200, italic: true)]
                      : [for (final b in u.branches) scopePill(b.name)],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: _K.gray100),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: u.isSuspended ? _K.emerald500.withValues(alpha: 0.1) : _K.red50,
                  foregroundColor: u.isSuspended ? _K.emerald600 : _K.red600,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: onToggleSuspend,
                icon: Icon(u.isSuspended ? Icons.lock_open : Icons.lock_outline, size: 14),
                label: Text(
                  u.isSuspended ? 'RESTORE' : 'SUSPEND',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Edit branch access ──────────────────────────────────────────────────────

class _BranchAccessDialog extends StatefulWidget {
  const _BranchAccessDialog({required this.user, required this.branches});

  final TenantUser user;
  final List<BranchOption> branches;

  @override
  State<_BranchAccessDialog> createState() => _BranchAccessDialogState();
}

class _BranchAccessDialogState extends State<_BranchAccessDialog> {
  late final Set<int> _ids = {for (final b in widget.user.branches) b.id};
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await tenantUserService.assignBranches(widget.user.id, _ids.toList());
      if (mounted) Navigator.of(context).pop(_ids.toList());
    } catch (_) {
      if (mounted) showToast(context, 'Failed to update branches.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 448, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: _K.indigo50, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.edit_outlined, size: 18, color: _K.indigo600),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Edit Branch Access', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _K.gray900)),
                        Text.rich(TextSpan(
                          text: 'Reassign branches for ',
                          style: const TextStyle(fontSize: 12, color: _K.gray500),
                          children: [
                            TextSpan(text: widget.user.username, style: const TextStyle(fontWeight: FontWeight.w700, color: _K.gray700)),
                          ],
                        )),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: _K.gray400),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 4),
              child: Text(
                'BRANCH SCOPE',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: _K.gray500),
              ),
            ),
            Flexible(
              child: widget.branches.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No branches configured.', style: TextStyle(fontSize: 13, color: _K.gray400)),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final b in widget.branches)
                          CheckboxListTile(
                            value: _ids.contains(b.id),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            secondary: const Icon(Icons.place_outlined, size: 16, color: _K.gray400),
                            title: Text(b.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            onChanged: (v) => setState(() => v == true ? _ids.add(b.id) : _ids.remove(b.id)),
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _K.gray600,
                        side: const BorderSide(color: _K.gray200),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _K.indigo600,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check, size: 16),
                      label: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Provision a staff account ───────────────────────────────────────────────

class _ProvisionForm extends StatefulWidget {
  const _ProvisionForm({required this.branches});

  final List<BranchOption> branches;

  @override
  State<_ProvisionForm> createState() => _ProvisionFormState();
}

class _ProvisionFormState extends State<_ProvisionForm> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _admin = false;
  String _role = 'HR';
  final Set<int> _branchIds = {};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_username.text.trim().isEmpty || _email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Username, email and initial password are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await tenantUserService.createUser(
        username: _username.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        role: _role,
        isCompanyAdmin: _admin,
        branches: _branchIds.toList(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (!mounted) return;
      // Field errors as on the web: "USERNAME: already exists | PASSWORD: too short"
      String message = 'Creation failed. Please try again.';
      if (err is DioException && err.response?.data is Map) {
        final data = err.response!.data as Map;
        message = data.entries
            .map((e) => '${'${e.key}'.toUpperCase()}: ${e.value is List ? (e.value as List).join(', ') : e.value}')
            .join(' | ');
      }
      setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration({String? hint, Widget? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: _K.gray400),
        suffixIcon: suffix,
        filled: true,
        fillColor: _K.gray50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _K.gray200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _K.indigo500),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: _K.gray500);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: _K.indigo50, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.verified_user_outlined, color: _K.indigo600),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Provision Staff Access', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _K.gray900)),
                      Text('Configure credentials, role, and branch scope.', style: TextStyle(fontSize: 12, color: _K.gray500)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close, color: _K.gray400),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('USERNAME', style: label),
            const SizedBox(height: 6),
            TextField(controller: _username, autocorrect: false, decoration: _decoration(hint: 'john.hr')),
            const SizedBox(height: 16),
            const Text('EMAIL ADDRESS', style: label),
            const SizedBox(height: 6),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: _decoration(hint: 'hr@company.com'),
            ),
            const SizedBox(height: 16),
            const Text('INITIAL PASSWORD', style: label),
            const SizedBox(height: 6),
            TextField(
              controller: _password,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: _decoration(
                suffix: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                  icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: _K.gray400),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Admin toggle
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              decoration: BoxDecoration(
                color: _admin ? _K.purple50 : _K.gray50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _admin ? _K.purple200 : _K.gray200),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Admin Privileges', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _K.gray900)),
                        Text('Grants global, company-wide access', style: TextStyle(fontSize: 12, color: _K.gray500)),
                      ],
                    ),
                  ),
                  Switch(
                    value: _admin,
                    activeTrackColor: _K.purple600,
                    onChanged: (v) => setState(() => _admin = v),
                  ),
                ],
              ),
            ),

            if (!_admin) ...[
              const SizedBox(height: 16),
              const Text('DESIGNATED ROLE', style: label),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _role,
                isExpanded: true,
                decoration: _decoration(),
                items: [for (final (v, name) in _roles) DropdownMenuItem(value: v, child: Text(name))],
                onChanged: (v) => setState(() => _role = v ?? 'HR'),
              ),
              const SizedBox(height: 16),
              const Text('BRANCH SCOPE', style: label),
              const SizedBox(height: 6),
              if (widget.branches.isEmpty)
                const Text('No branches configured.', style: TextStyle(fontSize: 13, color: _K.gray400))
              else
                Container(
                  decoration: BoxDecoration(
                    color: _K.gray50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _K.gray200),
                  ),
                  child: Column(
                    children: [
                      for (final b in widget.branches)
                        CheckboxListTile(
                          value: _branchIds.contains(b.id),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(b.name, style: const TextStyle(fontSize: 14)),
                          onChanged: (v) => setState(() => v == true ? _branchIds.add(b.id) : _branchIds.remove(b.id)),
                        ),
                    ],
                  ),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _K.red50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _K.red200),
                ),
                child: Text(_error!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.red600)),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _K.gray600,
                      side: const BorderSide(color: _K.gray200),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _K.indigo600,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _saving ? null : _submit,
                    child: Text(_saving ? 'Provisioning...' : 'Provision', style: const TextStyle(fontWeight: FontWeight.w700)),
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