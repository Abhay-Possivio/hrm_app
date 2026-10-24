// Port of features/admin/devices/DeviceMappingPage.tsx
// (/admin/hardware/mappings/:deviceId, "Device Identity Mapping").
//
// Links the user IDs stored on a device to employees, handles punches from
// unknown device users (create & map, map to an existing employee, dismiss,
// auto-link), recovers punches that never reached attendance, and clones
// employees + fingerprints from another device with live progress.
//
// Compact layout:
//   Header: back · device name · code / ADMS chips · history-import status (one line each)
//   Actions (one row): Clone employees (primary) · Sync · Auto-link · Recover
//   Wide: Mappings | Unresolved punches side by side
//   Phones: a slim tab switch for the two lists

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hrm_app/components/ui/pagination_bar.dart';
import 'package:hrm_app/services/devicefleet_service.dart';
import 'package:hrm_app/services/employee_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';
import 'package:hrm_app/utils/toast.dart';

const _pageSize = 10;

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
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const emerald800 = Color(0xFF065F46);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber100 = Color(0xFFFEF3C7);
  static const amber200 = Color(0xFFFDE68A);
  static const amber400 = Color(0xFFFBBF24);
  static const amber600 = Color(0xFFD97706);
  static const amber800 = Color(0xFF92400E);
  static const blue100 = Color(0xFFDBEAFE);
  static const blue200 = Color(0xFFBFDBFE);
  static const blue800 = Color(0xFF1E40AF);
  static const red50 = Color(0xFFFEF2F2);
  static const red100 = Color(0xFFFEE2E2);
  static const red200 = Color(0xFFFECACA);
  static const red500 = Color(0xFFEF4444);
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

const _indigo = _Tone(_K.indigo50, _K.indigo200, _K.indigo600);
const _emerald = _Tone(_K.emerald50, _K.emerald200, _K.emerald600);
const _amber = _Tone(_K.amber50, _K.amber200, _K.amber600);
const _red = _Tone(_K.red50, _K.red200, _K.red600);
const _gray = _Tone(_K.gray100, _K.gray200, _K.gray600);

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.3, color: _K.gray900);
  static const subtitle = TextStyle(fontSize: 11.5, height: 1.35, color: _K.gray500);
  static const fieldLabel = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.gray700);
  static const columnHead = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.gray500);
}

const _cardRadius = 14.0;
const _divider = Divider(height: 1, thickness: 1, color: _K.gray100);

String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

/// "Mon, 12 Oct 2026" from a raw device timestamp.
String _logDate(String ts) {
  final d = ts.length >= 10 ? parseDateOnly(ts.substring(0, 10)) : null;
  return d != null ? '${formatEEE(d)}, ${formatDDMMMYYYY(d)}' : (ts.length >= 10 ? ts.substring(0, 10) : ts);
}

// ── Page ────────────────────────────────────────────────────────────────────

class DeviceMappingPage extends StatefulWidget {
  const DeviceMappingPage({super.key, required this.deviceId});

  final int deviceId;

  @override
  State<DeviceMappingPage> createState() => _DeviceMappingPageState();
}

class _DeviceMappingPageState extends State<DeviceMappingPage> {
  Device? _device;
  List<Device> _devices = const [];
  List<Employee> _employees = const [];

  bool _mappingsTab = true;
  List<DeviceEmployeeMapping> _mappings = const [];
  int _mappingTotal = 0;
  int _mappingPage = 1;
  bool _loadingMappings = true;
  bool _mappingsFailed = false;

  List<UnresolvedDeviceLog> _logs = const [];
  int _logTotal = 0;
  int _logPage = 1;
  bool _loadingLogs = true;
  bool _logsFailed = false;

  // Add-mapping form
  bool _adding = false;
  final _uid = TextEditingController();
  Employee? _pickedEmployee;
  bool _creating = false;
  String? _uidError;
  String? _employeeError;

  bool _autoLinking = false;
  bool _syncing = false;
  bool _recovering = false;
  final Set<int> _dismissing = {};

  int get _id => widget.deviceId;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _loadMappings();
    _loadLogs();
    employeeService.fetchAllEmployees().then((list) {
      if (mounted) setState(() => _employees = list);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _uid.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    try {
      final all = await getAllDevices();
      if (!mounted) return;
      setState(() {
        _devices = all;
        for (final d in all) {
          if (d.id == _id) _device = d;
        }
      });
    } catch (_) {
      // Header just shows the generic subtitle.
    }
  }

  Future<void> _loadMappings() async {
    setState(() => _loadingMappings = true);
    try {
      final res = await getDeviceMappings(_id, page: _mappingPage);
      if (!mounted) return;
      setState(() {
        _mappings = res.results;
        _mappingTotal = res.count;
        _mappingsFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _mappingsFailed = true);
    } finally {
      if (mounted) setState(() => _loadingMappings = false);
    }
  }

  Future<void> _loadLogs() async {
    setState(() => _loadingLogs = true);
    try {
      final res = await getUnresolvedLogs(_id, page: _logPage);
      if (!mounted) return;
      setState(() {
        _logs = res.results;
        _logTotal = res.count;
        _logsFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _logsFailed = true);
    } finally {
      if (mounted) setState(() => _loadingLogs = false);
    }
  }

  Future<bool> _confirm(String title, String message, String action, {bool destructive = true}) async {
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
              backgroundColor: destructive ? _K.red600 : _K.indigo600,
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

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _createMapping() async {
    final employee = _pickedEmployee;
    setState(() {
      _uidError = _uid.text.trim().isEmpty ? 'Enter the user ID stored on the device.' : null;
      _employeeError = employee == null ? 'Choose an employee.' : null;
    });
    if (_uidError != null || _employeeError != null) return;

    setState(() => _creating = true);
    try {
      await createDeviceMapping(_id, deviceUserId: _uid.text.trim(), employeeId: employee!.id);
      if (!mounted) return;
      showToast(context, 'Device user ${_uid.text.trim()} linked to ${employee.name}.');
      setState(() {
        _uid.clear();
        _pickedEmployee = null;
        _adding = false;
      });
      _loadMappings();
      _loadLogs();
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to create mapping.'), error: true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _cancelAdd() => setState(() {
        _adding = false;
        _uid.clear();
        _pickedEmployee = null;
        _uidError = null;
        _employeeError = null;
      });

  Future<void> _deleteMapping(DeviceEmployeeMapping m) async {
    final ok = await _confirm(
      'Unlink device user ${m.deviceUserId}?',
      'New punches from this device user will no longer count for ${m.employeeName}; they will appear under '
          'unresolved punches instead.',
      'Unlink',
    );
    if (!ok) return;
    try {
      await deleteDeviceMapping(_id, m.id);
      if (mounted) showToast(context, 'Device user ${m.deviceUserId} unlinked.');
      _loadMappings();
    } catch (_) {
      if (mounted) showToast(context, 'Failed to delete mapping.', error: true);
    }
  }

  Future<void> _dismissLog(UnresolvedDeviceLog log) async {
    setState(() => _dismissing.add(log.id));
    try {
      await resolveLog(log.id);
      if (mounted) showToast(context, 'Punch dismissed.');
      _loadLogs();
    } catch (_) {
      if (mounted) showToast(context, 'Failed to resolve log.', error: true);
    } finally {
      if (mounted) setState(() => _dismissing.remove(log.id));
    }
  }

  Future<void> _dismissAll() async {
    final ok = await _confirm(
      'Dismiss all unresolved punches?',
      'All $_logTotal unresolved punch${_logTotal == 1 ? '' : 'es'} for this device will be dismissed without '
          'being added to attendance.',
      'Dismiss all',
    );
    if (!ok) return;
    try {
      await dismissAllUnresolvedLogs(_id);
      if (mounted) showToast(context, 'All unresolved punches dismissed.');
      _loadLogs();
    } catch (_) {
      if (mounted) showToast(context, 'Failed to dismiss logs.', error: true);
    }
  }

  Future<void> _autoLink() async {
    setState(() => _autoLinking = true);
    try {
      final res = await autoLinkDeviceMappings(_id);
      if (!mounted) return;
      showToast(context, res.message);
      _loadMappings();
      _loadLogs();
      if (res.linked > 0) setState(() => _mappingsTab = true);
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to auto-link.'), error: true);
    } finally {
      if (mounted) setState(() => _autoLinking = false);
    }
  }

  Future<void> _recover() async {
    var askDevice = false;
    if (_device?.connectionType == 'ADMS') {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Recover punches', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900)),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Missed punches the server already received will be imported. You can also ask the device to '
                're-upload the history it stores.',
                style: TextStyle(fontSize: 13, height: 1.45, color: _K.gray600),
              ),
              SizedBox(height: 12),
              _ChoiceNote(
                title: 'Import + device history',
                text: 'Also fetches the stored history; the device uploads it on its next check-in.',
              ),
              SizedBox(height: 8),
              _ChoiceNote(title: 'Import only', text: 'Only punches already received by the server.'),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: _K.gray600),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _K.gray700,
                side: const BorderSide(color: _K.gray200),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(context, 'only'),
              child: const Text('Import only'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _K.indigo600,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(context, 'history'),
              child: const Text('Import + history'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      askDevice = choice == 'history';
    }
    setState(() => _recovering = true);
    try {
      final res = await recoverDevicePunches(_id, requestDeviceHistory: askDevice);
      var message = 'Imported ${res.recovered} missed punch${res.recovered == 1 ? '' : 'es'}.';
      if (res.stillUnknown > 0) {
        message += ' ${res.stillUnknown} belong to device users not linked to an employee yet.';
      }
      if (res.historyRequested) message += ' The device will re-upload its stored punches on its next check-in.';
      if (mounted) showToast(context, message);
      _loadLogs();
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to recover punches.'), error: true);
    } finally {
      if (mounted) setState(() => _recovering = false);
    }
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final res = await triggerDeviceSync(_id);
      if (!mounted) return;
      if (res.errors.isNotEmpty) {
        showToast(context, 'Sync partially failed: ${res.errors.first}', error: true);
      } else {
        showToast(context, 'Sync complete. ${res.newLogs} new log${res.newLogs == 1 ? '' : 's'}.');
      }
      _loadMappings();
      _loadLogs();
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Sync failed. Check device connectivity.'), error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _quickCreate(UnresolvedDeviceLog log) async {
    final done = await showDialog<bool>(context: context, builder: (_) => _QuickCreateDialog(log: log));
    if (done == true) {
      _loadMappings();
      _loadLogs();
    }
  }

  /// Opens the add-mapping form with this log's device user ID filled in.
  Future<void> _mapExisting(UnresolvedDeviceLog log) async {
    setState(() {
      _mappingsTab = true;
      _adding = true;
      _uid.text = log.deviceUserId;
      _uidError = null;
    });
    await _pickEmployee();
  }

  Future<void> _openClone() async {
    final started = await showDialog<int>(
      context: context,
      builder: (_) => _CloneDialog(
        target: _device,
        targetId: _id,
        sources: _devices.where((d) => d.id != _id && d.isActive).toList(),
      ),
    );
    if (started == null || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CloneProgressDialog(commandId: started),
    );
    _loadMappings();
  }

  Future<void> _pickEmployee() async {
    final picked = await showModalBottomSheet<Employee>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EmployeePicker(employees: _employees),
    );
    if (picked != null) {
      setState(() {
        _pickedEmployee = picked;
        _employeeError = null;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: _K.indigo600,
      onRefresh: () => Future.wait([_loadDevices(), _loadMappings(), _loadLogs()]),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sm = constraints.maxWidth >= 640;
          final lg = constraints.maxWidth >= 1024;
          final gap = sm ? 14.0 : 12.0;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(sm ? 20 : 12),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(wide: sm),
                      SizedBox(height: gap),
                      _actions(wide: sm),
                      SizedBox(height: gap),
                      if (lg)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _mappingsCard()),
                            SizedBox(width: gap),
                            Expanded(child: _logsCard()),
                          ],
                        )
                      else ...[
                        _tabs(),
                        const SizedBox(height: 10),
                        if (_mappingsTab) _mappingsCard() else _logsCard(),
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

  Widget _header({required bool wide}) {
    final d = _device;
    final history = d?.raw['history_import'];
    Widget? historyLine;
    if (d?.connectionType == 'ADMS') {
      final (text, tone, icon) = history is! Map
          ? ('Punch history import starts when the device next connects.', _gray, Icons.schedule_rounded)
          : history['status'] == 'DONE'
              ? (
                  'History imported: ${history['received'] ?? 0} received, ${history['imported'] ?? 0} new'
                      '${(history['recovered'] ?? 0) != 0 ? ', ${history['recovered']} linked later' : ''}. '
                      'Checked again weekly.',
                  _emerald,
                  Icons.check_circle_outline_rounded,
                )
              : history['status'] == 'FAILED'
                  ? (
                      'History import failed: ${history['error'] ?? 'device rejected the request'}.',
                      _red,
                      Icons.error_outline_rounded,
                    )
                  : ('Importing punch history from the device…', _indigo, Icons.sync_rounded);
      historyLine = Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: tone.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tone.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: tone.fg),
            const SizedBox(width: 5),
            Flexible(child: Text(text, style: TextStyle(fontSize: 11, height: 1.3, color: tone.fg))),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          tooltip: 'Back to devices',
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: _K.gray200),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
          // The web button goes to /admin/hardware, which isn't a route; this is the devices list.
          onPressed: () => context.go('/admin/devices'),
          icon: const Icon(Icons.arrow_back_rounded, size: 18, color: _K.gray600),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  d != null ? d.label : 'Device user mapping',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: wide ? 19 : 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    height: 1.25,
                    color: _K.gray900,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (d != null) ...[_MiniChip(text: d.deviceCode, tone: _gray), const SizedBox(width: 6)],
                  if (d?.connectionType == 'ADMS') ...[
                    const _MiniChip(text: 'ADMS', tone: _indigo),
                    const SizedBox(width: 6),
                  ],
                  const Flexible(
                    child: Text(
                      'Link device user IDs to employees.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _T.subtitle,
                    ),
                  ),
                ],
              ),
              if (historyLine != null) historyLine,
            ],
          ),
        ),
      ],
    );
  }

  Widget _actions({required bool wide}) {
    final clone = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: _K.emerald600,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      onPressed: _openClone,
      icon: const Icon(Icons.fingerprint_rounded, size: 16),
      label: Text(wide ? 'Clone employees here' : 'Clone employees'),
    );

    final secondary = [
      _SecondaryButton(
        icon: Icons.sync_rounded,
        label: _syncing ? 'Syncing…' : 'Sync',
        tooltip: 'Sync logs from the device now',
        busy: _syncing,
        onTap: _syncing ? null : _sync,
        compact: true,
      ),
      _SecondaryButton(
        icon: Icons.bolt_rounded,
        iconColor: _K.amber400,
        label: _autoLinking ? 'Linking…' : 'Auto-link',
        tooltip: 'Match device users to employees by employee code',
        busy: _autoLinking,
        onTap: _autoLinking ? null : _autoLink,
        compact: true,
      ),
      _SecondaryButton(
        icon: Icons.history_rounded,
        iconColor: _K.emerald500,
        label: _recovering ? 'Recovering…' : 'Recover',
        tooltip: 'Recover device punches that never reached attendance',
        busy: _recovering,
        onTap: _recovering ? null : _recover,
        compact: true,
      ),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [clone, ...secondary],
    );
  }

  Widget _tabs() {
    Widget tab(bool value, String label, int count, _Tone tone) {
      final selected = _mappingsTab == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: Material(
            color: selected ? Colors.white : Colors.transparent,
            elevation: selected ? 1 : 0,
            shadowColor: const Color(0x33000000),
            borderRadius: BorderRadius.circular(7),
            child: InkWell(
              borderRadius: BorderRadius.circular(7),
              onTap: () => setState(() => _mappingsTab = value),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? _K.gray900 : _K.gray500,
                        ),
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      _CountBadge(count: count, tone: tone),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _K.gray100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _K.gray200),
      ),
      child: Row(
        children: [
          tab(true, 'Mappings', _mappingTotal, _indigo),
          tab(false, 'Unresolved punches', _logTotal, const _Tone(_K.amber100, _K.amber200, _K.amber800)),
        ],
      ),
    );
  }

  // ── Mappings ──

  Widget _mappingsCard() {
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                const _IconBox(icon: Icons.link_rounded, tone: _indigo, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'Mappings', style: _T.title),
                      TextSpan(
                        text: '  $_mappingTotal linked',
                        style: const TextStyle(fontSize: 11.5, color: _K.gray500, fontFeatures: _T.tabular),
                      ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!_adding)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: _K.indigo600,
                      backgroundColor: _K.indigo50,
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () => setState(() => _adding = true),
                    icon: const Icon(Icons.add_rounded, size: 15),
                    label: const Text('Add'),
                  ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _adding ? _addForm() : const SizedBox(width: double.infinity),
          ),
          SizedBox(
            height: 2,
            child: _loadingMappings && _mappings.isNotEmpty
                ? const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50)
                : const ColoredBox(color: _K.gray100),
          ),
          if (_mappings.isNotEmpty)
            Container(
              color: _K.gray50,
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              child: const Row(
                children: [
                  SizedBox(width: 88, child: Text('Device user', style: _T.columnHead)),
                  Expanded(child: Text('Employee', style: _T.columnHead)),
                ],
              ),
            ),
          if (_mappings.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: _loadingMappings
                  ? const _LoadingLine(text: 'Loading mappings…')
                  : _mappingsFailed
                      ? _EmptyState(
                          icon: Icons.cloud_off_outlined,
                          title: 'Could not load mappings',
                          action: _LinkButton(label: 'Retry', onTap: _loadMappings),
                        )
                      : _EmptyState(
                          icon: Icons.link_off_rounded,
                          title: 'No device users linked yet',
                          message: 'Add a mapping, or try Auto-link to match users by employee code.',
                          action: _LinkButton(label: 'Add mapping', onTap: () => setState(() => _adding = true)),
                        ),
            )
          else
            for (var i = 0; i < _mappings.length; i++) ...[
              if (i > 0) _divider,
              _MappingRow(mapping: _mappings[i], onDelete: () => _deleteMapping(_mappings[i])),
            ],
          if (_mappingTotal > _pageSize)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.gray100))),
              child: PaginationBar(
                page: _mappingPage,
                total: _mappingTotal,
                pageSize: _pageSize,
                onPage: (p) {
                  setState(() => _mappingPage = p);
                  _loadMappings();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _addForm() {
    final picked = _pickedEmployee;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _K.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _K.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final uidField = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Device user ID', style: _T.fieldLabel),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _uid,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14, fontFeatures: _T.tabular),
                    onChanged: (_) {
                      if (_uidError != null) setState(() => _uidError = null);
                    },
                    decoration: _inputDecoration(hint: 'e.g. 1', error: _uidError),
                  ),
                ],
              );
              final employeeField = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Employee', style: _T.fieldLabel),
                  const SizedBox(height: 6),
                  Semantics(
                    button: true,
                    label: picked == null ? 'Choose employee' : 'Employee, ${picked.name}',
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _pickEmployee,
                      child: InputDecorator(
                        decoration: _inputDecoration(error: _employeeError).copyWith(
                          suffixIcon: const Icon(Icons.expand_more_rounded, size: 18, color: _K.gray400),
                        ),
                        child: Text(
                          picked == null
                              ? (_employees.isEmpty ? 'Loading employees…' : 'Search and choose')
                              : '${picked.name} (${picked.employeeCode})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: picked == null ? _K.gray400 : _K.gray900),
                        ),
                      ),
                    ),
                  ),
                ],
              );
              if (c.maxWidth >= 420) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 130, child: uidField),
                    const SizedBox(width: 10),
                    Expanded(child: employeeField),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [uidField, const SizedBox(height: 10), employeeField],
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: _K.gray600,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                onPressed: _creating ? null : _cancelAdd,
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
                onPressed: _creating ? null : _createMapping,
                icon: _creating
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.link_rounded, size: 16),
                label: Text(_creating ? 'Linking…' : 'Link'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Unresolved punches ──

  Widget _logsCard() {
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                const _IconBox(icon: Icons.help_outline_rounded, tone: _amber, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'Unresolved', style: _T.title),
                      TextSpan(
                        text: _logTotal == 0 ? '  none' : '  $_logTotal waiting',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: _logTotal == 0 ? _K.gray500 : _K.amber600,
                          fontWeight: _logTotal == 0 ? FontWeight.w400 : FontWeight.w600,
                          fontFeatures: _T.tabular,
                        ),
                      ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_logTotal > 0) ...[
                  _HeaderIconButton(
                    icon: Icons.bolt_rounded,
                    color: _K.amber600,
                    tooltip: 'Auto-link: match device users to employees by employee code',
                    busy: _autoLinking,
                    onTap: _autoLinking ? null : _autoLink,
                  ),
                  _HeaderIconButton(
                    icon: Icons.delete_sweep_outlined,
                    color: _K.red600,
                    tooltip: 'Dismiss all unresolved punches',
                    onTap: _logs.isEmpty ? null : _dismissAll,
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            height: 2,
            child: _loadingLogs && _logs.isNotEmpty
                ? const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50)
                : const ColoredBox(color: _K.gray100),
          ),
          if (_logs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: _loadingLogs
                  ? const _LoadingLine(text: 'Loading punches…')
                  : _logsFailed
                      ? _EmptyState(
                          icon: Icons.cloud_off_outlined,
                          title: 'Could not load unresolved punches',
                          action: _LinkButton(label: 'Retry', onTap: _loadLogs),
                        )
                      : const _EmptyState(
                          icon: Icons.task_alt_rounded,
                          success: true,
                          title: 'All clear',
                          message: 'Every punch from this device belongs to a linked employee.',
                        ),
            )
          else
            for (var i = 0; i < _logs.length; i++) ...[
              if (i > 0) _divider,
              _LogRow(
                log: _logs[i],
                dismissing: _dismissing.contains(_logs[i].id),
                onCreate: () => _quickCreate(_logs[i]),
                onMapExisting: () => _mapExisting(_logs[i]),
                onDismiss: () => _dismissLog(_logs[i]),
              ),
            ],
          if (_logTotal > _pageSize)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.gray100))),
              child: PaginationBar(
                page: _logPage,
                total: _logTotal,
                pageSize: _pageSize,
                onPage: (p) {
                  setState(() => _logPage = p);
                  _loadLogs();
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Rows ────────────────────────────────────────────────────────────────────

class _MappingRow extends StatelessWidget {
  const _MappingRow({required this.mapping, required this.onDelete});

  final DeviceEmployeeMapping mapping;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final m = mapping;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 2, 4),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _MiniChip(text: m.deviceUserId, tone: _indigo, icon: Icons.badge_outlined),
            ),
          ),
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: _K.gray100, shape: BoxShape.circle),
            child: Text(_initials(m.employeeName),
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _K.gray600)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: m.employeeName,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _K.gray900),
                ),
                TextSpan(
                  text: '  ${m.employeeCode}',
                  style: const TextStyle(fontSize: 11, color: _K.gray500, fontFeatures: _T.tabular),
                ),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Unlink',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            onPressed: onDelete,
            icon: const Icon(Icons.link_off_rounded, size: 17, color: _K.gray400),
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({
    required this.log,
    required this.dismissing,
    required this.onCreate,
    required this.onMapExisting,
    required this.onDismiss,
  });

  final UnresolvedDeviceLog log;
  final bool dismissing;
  final VoidCallback onCreate;
  final VoidCallback onMapExisting;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final isIn = log.punchType == 'IN';
    final ts = log.rawTimestamp;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 2, 6),
      child: Row(
        children: [
          Tooltip(
            message: isIn ? 'In' : (log.punchType == 'OUT' ? 'Out' : log.punchType),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: isIn ? _K.emerald50 : _K.amber50,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: isIn ? _K.emerald200 : _K.amber200),
              ),
              child: Icon(isIn ? Icons.login_rounded : Icons.logout_rounded, size: 14, color: isIn ? _K.emerald600 : _K.amber600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'User ${log.deviceUserId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.25, color: _K.gray900, fontFeatures: _T.tabular),
                ),
                Text(
                  '${_logDate(ts)}, ${fmtWallTime(ts)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, height: 1.25, color: _K.gray500, fontFeatures: _T.tabular),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Create a new employee for device user ${log.deviceUserId}',
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _K.indigo600,
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 9),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
              onPressed: dismissing ? null : onCreate,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 14),
              label: const Text('Create'),
            ),
          ),
          PopupMenuButton<int>(
            tooltip: 'More actions',
            enabled: !dismissing,
            position: PopupMenuPosition.under,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onSelected: (v) {
              if (v == 0) {
                onMapExisting();
              } else {
                onDismiss();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 0,
                child: Row(
                  children: [
                    Icon(Icons.link_rounded, size: 18, color: _K.gray700),
                    SizedBox(width: 10),
                    Text('Map to existing employee', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 1,
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded, size: 18, color: _K.gray700),
                    SizedBox(width: 10),
                    Text('Dismiss this punch', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
            child: SizedBox(
              width: 30,
              height: 30,
              child: Center(
                child: dismissing
                    ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.more_vert_rounded, size: 18, color: _K.gray500),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick create employee from an unknown device user ───────────────────────

class _QuickCreateDialog extends StatefulWidget {
  const _QuickCreateDialog({required this.log});

  final UnresolvedDeviceLog log;

  @override
  State<_QuickCreateDialog> createState() => _QuickCreateDialogState();
}

class _QuickCreateDialogState extends State<_QuickCreateDialog> {
  final _name = TextEditingController();
  late final _code = TextEditingController(text: widget.log.deviceUserId);
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = "Please enter the employee's name.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final message = await quickCreateEmployeeFromLog(widget.log.id, _name.text.trim(), employeeCode: _code.text.trim());
      if (!mounted) return;
      showToast(context, message.isNotEmpty ? message : 'Employee created and linked.');
      Navigator.of(context).pop(true);
    } catch (err) {
      if (mounted) setState(() => _error = apiError(err, 'Failed to create employee.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.log.deviceUserId;
    final canSave = !_saving && _name.text.trim().isNotEmpty;

    return _DialogFrame(
      icon: Icons.person_add_alt_1_outlined,
      tone: _indigo,
      title: 'Create employee',
      subtitle: 'For device user $uid',
      closeEnabled: !_saving,
      maxWidth: 440,
      body: [
        const Text('Full name', style: _T.fieldLabel),
        const SizedBox(height: 6),
        TextField(
          controller: _name,
          autofocus: true,
          enabled: !_saving,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          style: const TextStyle(fontSize: 14),
          decoration: _inputDecoration(hint: 'e.g. John Smith'),
        ),
        const SizedBox(height: 12),
        const Text('Employee code', style: _T.fieldLabel),
        const SizedBox(height: 6),
        TextField(
          controller: _code,
          enabled: !_saving,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => canSave ? _submit() : null,
          style: const TextStyle(fontSize: 14, fontFeatures: _T.tabular),
          decoration: _inputDecoration(hint: uid),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, left: 4),
          child: Text('Defaults to the device user ID.', style: TextStyle(fontSize: 11, color: _K.gray400)),
        ),
        const SizedBox(height: 12),
        _InlineNote(
          icon: Icons.info_outline_rounded,
          text: 'A new employee is created and every pending punch from device user $uid is added to their attendance.',
          tone: const _Tone(_K.indigo50, _K.indigo100, _K.indigo800),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          _InlineNote(icon: Icons.error_outline_rounded, text: _error!, tone: const _Tone(_K.red50, _K.red200, _K.red800)),
        ],
      ],
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
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
            onPressed: canSave ? _submit : null,
            icon: _saving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_rounded, size: 16),
            label: Text(_saving ? 'Creating…' : 'Create and link'),
          ),
        ],
      ),
    );
  }
}

// ── Clone employees + fingerprints from another device ──────────────────────

class _CloneDialog extends StatefulWidget {
  const _CloneDialog({required this.target, required this.targetId, required this.sources});

  final Device? target;
  final int targetId;
  final List<Device> sources;

  @override
  State<_CloneDialog> createState() => _CloneDialogState();
}

class _CloneDialogState extends State<_CloneDialog> {
  int? _sourceId;
  bool _loading = false;
  List<CloneCandidate> _candidates = const [];
  final Set<int> _selected = {};
  String? _compatError;
  bool _sourceOnline = true;
  int? _refreshCommandId;
  Timer? _refreshTimer;
  DateTime? _refreshStarted;
  bool _starting = false;
  String _q = '';

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _selectSource(int? id) async {
    _refreshTimer?.cancel();
    setState(() {
      _sourceId = id;
      _refreshCommandId = null;
      _compatError = null;
      _candidates = const [];
      _selected.clear();
      _q = '';
    });
    if (id != null) await _loadCandidates(refresh: true);
  }

  Future<void> _loadCandidates({required bool refresh}) async {
    final source = _sourceId;
    if (source == null) return;
    setState(() => _loading = true);
    try {
      final res = await getCloneCandidates(widget.targetId, source, refreshSource: refresh);
      if (!mounted || source != _sourceId) return;
      final waiting = refresh &&
          res.refreshCommandId != null &&
          res.refreshStatus != 'COMPLETED' &&
          res.refreshStatus != 'FAILED';
      setState(() {
        _candidates = res.candidates;
        _selected
          ..clear()
          ..addAll(res.candidates.map((c) => c.employeeId));
        _compatError = res.compatibilityError;
        _sourceOnline = res.sourceOnline;
        _refreshCommandId = waiting ? res.refreshCommandId : null;
      });
      if (waiting) _pollRefresh();
    } catch (err) {
      if (!mounted) return;
      showToast(context, apiError(err, 'Failed to fetch clone candidates.'), error: true);
      setState(() {
        _candidates = const [];
        _selected.clear();
        _refreshCommandId = null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// While the source uploads its latest users / fingerprints, check every 2 s
  /// (for up to 90 s), then reload the candidates.
  void _pollRefresh() {
    _refreshStarted = DateTime.now();
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final id = _refreshCommandId;
      if (id == null) {
        _refreshTimer?.cancel();
        return;
      }
      try {
        final status = await getCommandStatus(id);
        final timedOut = DateTime.now().difference(_refreshStarted!).inSeconds > 90;
        if (status.finished || timedOut) {
          _refreshTimer?.cancel();
          if (!mounted) return;
          if (status.status == 'FAILED') {
            showToast(context, 'The source device did not answer; showing the data it last uploaded.', error: true);
          }
          setState(() => _refreshCommandId = null);
          _loadCandidates(refresh: false);
        }
      } catch (_) {
        // Try again on the next tick.
      }
    });
  }

  Future<void> _start({required bool all}) async {
    final source = _sourceId;
    if (source == null) return;
    if (!all && _selected.isEmpty) {
      showToast(context, 'Select at least one employee to clone.', error: true);
      return;
    }
    setState(() => _starting = true);
    try {
      final res = await triggerCloneBiometrics(
        widget.targetId,
        source,
        employeeIds: all ? null : _selected.toList(),
        cloneAll: all,
      );
      if (mounted) Navigator.of(context).pop(res.commandId);
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to initiate clone operation.'), error: true);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.target;
    final q = _q.trim().toLowerCase();
    final shown = _candidates
        .where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.employeeCode.toLowerCase().contains(q))
        .toList();
    final allSelected = _candidates.isNotEmpty && _selected.length == _candidates.length;
    final blocked = _starting || _sourceId == null || _compatError != null || _refreshCommandId != null;
    final withPrints = _candidates.where((c) => c.hasCachedBiometric).length;

    return _DialogFrame(
      icon: Icons.fingerprint_rounded,
      tone: _emerald,
      title: 'Clone employees and fingerprints',
      subtitle: 'To ${t?.label ?? 'this device'} (${t?.deviceCode ?? widget.targetId})',
      maxWidth: 680,
      closeEnabled: !_starting,
      body: [
        const Text('Copy from', style: _T.fieldLabel),
        const SizedBox(height: 6),
        if (widget.sources.isEmpty)
          const _InlineNote(
            icon: Icons.info_outline_rounded,
            text: 'No other active device is available to copy from.',
            tone: _Tone(_K.gray50, _K.gray200, _K.gray600),
          )
        else
          DropdownButtonFormField<int>(
            value: _sourceId,
            isExpanded: true,
            hint: const Text('Choose a source device', style: TextStyle(fontSize: 14, color: _K.gray400)),
            icon: const Icon(Icons.expand_more_rounded, size: 20, color: _K.gray500),
            borderRadius: BorderRadius.circular(10),
            style: const TextStyle(fontSize: 14, color: _K.gray900),
            decoration: _inputDecoration(),
            items: [
              for (final d in widget.sources)
                DropdownMenuItem(
                  value: d.id,
                  child: Text(
                    '${d.label} (${d.deviceCode})${d.branchName != null ? ', ${d.branchName}' : ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _starting ? null : _selectSource,
          ),
        if (_sourceId != null) ...[
          if (_compatError != null) ...[
            const SizedBox(height: 10),
            _InlineNote(icon: Icons.error_outline_rounded, text: _compatError!, tone: const _Tone(_K.red50, _K.red200, _K.red800)),
          ],
          if (_refreshCommandId != null) ...[
            const SizedBox(height: 10),
            const _InlineNote(
              icon: Icons.sync_rounded,
              text: 'Reading the latest users and fingerprints from the source device. The list updates automatically.',
              tone: _Tone(_K.indigo50, _K.indigo200, _K.indigo800),
              busy: true,
            ),
          ],
          if (!_sourceOnline && _refreshCommandId == null) ...[
            const SizedBox(height: 10),
            const _InlineNote(
              icon: Icons.wifi_off_rounded,
              text: 'The source device is offline. Cloning uses the fingerprints it last uploaded to the server.',
              tone: _Tone(_K.amber50, _K.amber200, _K.amber800),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Missing on this device (${_candidates.length})', style: _T.title),
                    Text(
                      _candidates.isEmpty
                          ? 'The source uploads its latest fingerprints before delivery.'
                          : '$withPrints with fingerprints on the source, ${_selected.length} selected',
                      style: _T.subtitle,
                    ),
                  ],
                ),
              ),
              if (_candidates.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: _K.indigo600,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => setState(() {
                    if (allSelected) {
                      _selected.clear();
                    } else {
                      _selected.addAll(_candidates.map((c) => c.employeeId));
                    }
                  }),
                  child: Text(allSelected ? 'Select none' : 'Select all'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading)
            const _LoadingLine(text: 'Comparing the two devices…')
          else if (_candidates.isEmpty)
            const _EmptyState(
              icon: Icons.task_alt_rounded,
              success: true,
              title: 'Nobody is missing',
              message: 'Every employee on the source device is already on this device.',
            )
          else ...[
            if (_candidates.length > 8) ...[
              TextField(
                onChanged: (v) => setState(() => _q = v),
                style: const TextStyle(fontSize: 13.5),
                decoration: _inputDecoration(hint: 'Filter by name or code', icon: Icons.search_rounded),
              ),
              const SizedBox(height: 8),
            ],
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _K.gray200),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    if (i > 0) _divider,
                    CheckboxListTile(
                      value: _selected.contains(shown[i].employeeId),
                      dense: true,
                      activeColor: _K.emerald600,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) => setState(() =>
                          v == true ? _selected.add(shown[i].employeeId) : _selected.remove(shown[i].employeeId)),
                      title: Text(shown[i].name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      subtitle: Text(shown[i].employeeCode,
                          style: const TextStyle(fontSize: 11.5, color: _K.gray500, fontFeatures: _T.tabular)),
                      secondary: shown[i].hasCachedBiometric
                          ? _MiniChip(
                              text: '${shown[i].templateCount} print${shown[i].templateCount == 1 ? '' : 's'}',
                              tone: const _Tone(_K.emerald100, _K.emerald200, _K.emerald800),
                              icon: Icons.fingerprint_rounded,
                            )
                          : _MiniChip(
                              text: _refreshCommandId != null ? 'Checking…' : 'No print',
                              tone: _gray,
                            ),
                    ),
                  ],
                  if (shown.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('No matches.', style: _T.subtitle),
                    ),
                ],
              ),
            ),
          ],
        ],
      ],
      footer: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: _K.gray600,
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            onPressed: _starting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (_sourceId != null)
            Tooltip(
              message: 'Copies every user on the source device, including ones already on this device',
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _K.emerald600,
                  side: const BorderSide(color: _K.emerald200),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                onPressed: blocked ? null : () => _start(all: true),
                child: const Text('Clone everyone'),
              ),
            ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _K.emerald600,
              disabledBackgroundColor: _K.emerald200,
              disabledForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            onPressed: (blocked || _selected.isEmpty) ? null : () => _start(all: false),
            icon: _starting
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.fingerprint_rounded, size: 16),
            label: Text(_starting ? 'Starting…' : 'Clone selected (${_selected.length})'),
          ),
        ],
      ),
    );
  }
}

// ── Live cloning progress ───────────────────────────────────────────────────

const _cloneStatusStyle = {
  'FETCHING_FROM_SOURCE': ('Reading source', _K.amber100, _K.amber800, _K.amber200, true),
  'QUEUED_TARGET': ('Sending to device', _K.indigo100, _K.indigo800, _K.indigo200, true),
  'COMPLETED': ('Cloned', _K.emerald100, _K.emerald800, _K.emerald200, false),
  'USER_ONLY': ('User only, no print on source', _K.blue100, _K.blue800, _K.blue200, false),
  'PARTIAL': ('Cloned, some prints rejected', _K.amber100, _K.amber800, _K.amber200, false),
  'FAILED': ('Failed', _K.red100, _K.red800, _K.red200, false),
  'SKIPPED_CONFLICT': ('Skipped: PIN in use', _K.gray100, _K.gray700, _K.gray200, false),
  'NOT_ON_SOURCE': ('Not on source', _K.gray100, _K.gray700, _K.gray200, false),
};

class _CloneProgressDialog extends StatefulWidget {
  const _CloneProgressDialog({required this.commandId});

  final int commandId;

  @override
  State<_CloneProgressDialog> createState() => _CloneProgressDialogState();
}

class _CloneProgressDialogState extends State<_CloneProgressDialog> {
  DeviceCommandStatus? _status;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final s = await getCommandStatus(widget.commandId);
      if (!mounted) return;
      setState(() => _status = s);
      if (s.finished) _timer?.cancel();
    } catch (_) {
      // Keep polling.
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final state = s?.status ?? 'PROCESSING';
    final done = state == 'COMPLETED';
    final failed = state == 'FAILED';
    final finished = s?.finished ?? false;
    final (tone, label) = done
        ? (_emerald, 'Completed')
        : failed
            ? (_red, 'Failed')
            : (_indigo, 'In progress');
    final progress = (s == null || s.usersFound == 0) ? null : (s.usersCopied / s.usersFound).clamp(0.0, 1.0).toDouble();

    return _DialogFrame(
      icon: done ? Icons.check_circle_outline_rounded : (failed ? Icons.error_outline_rounded : Icons.fingerprint_rounded),
      tone: tone,
      title: 'Cloning progress',
      subtitle: 'Command #${widget.commandId}',
      maxWidth: 600,
      trailing: Semantics(
        liveRegion: true,
        child: _MiniChip(text: label, tone: tone, busy: !finished),
      ),
      body: [
        // Source → target
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _K.gray50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _K.gray100),
          ),
          child: Row(
            children: [
              Expanded(child: _DeviceEnd(icon: Icons.fingerprint_rounded, name: s?.sourceDeviceName ?? 'Source device', done: false)),
              SizedBox(
                width: 56,
                child: done
                    ? const Icon(Icons.arrow_forward_rounded, color: _K.emerald500)
                    : failed
                        ? const Icon(Icons.close_rounded, color: _K.red500)
                        : const ClipRRect(
                            borderRadius: BorderRadius.all(Radius.circular(99)),
                            child: LinearProgressIndicator(minHeight: 3, color: _K.indigo500, backgroundColor: _K.indigo100),
                          ),
              ),
              Expanded(child: _DeviceEnd(icon: Icons.router_outlined, name: s?.targetDeviceName ?? 'This device', done: done)),
            ],
          ),
        ),
        if (s != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _Stat(value: '${s.usersCopied} / ${s.usersFound}', label: 'Users sent')),
              const SizedBox(width: 10),
              Expanded(child: _Stat(value: '${s.templatesCopied} / ${s.templatesFound}', label: 'Fingerprints sent')),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                color: failed ? _K.red500 : _K.emerald500,
                backgroundColor: _K.gray100,
              ),
            ),
          ],
        ],
        const SizedBox(height: 12),
        _InlineNote(
          icon: Icons.info_outline_rounded,
          text: s?.statusDetail ?? 'Cloning started. Reading the latest data from the source device…',
          tone: const _Tone(_K.indigo50, _K.indigo100, _K.indigo800),
        ),

        // Per-employee status
        if (s != null && s.employeeStatuses.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Employees (${s.employeeStatuses.length})', style: _T.title),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _K.gray200),
            ),
            child: Column(
              children: [
                for (var i = 0; i < s.employeeStatuses.length; i++) ...[
                  if (i > 0) _divider,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.employeeStatuses[i].name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _K.gray900)),
                              Text(s.employeeStatuses[i].employeeCode,
                                  style: const TextStyle(fontSize: 11, color: _K.gray500, fontFeatures: _T.tabular)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(child: _CloneBadge(status: s.employeeStatuses[i])),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
      footer: Row(
        children: [
          if (!finished)
            const Expanded(
              child: Text('You can close this; cloning continues on the server.', style: TextStyle(fontSize: 11.5, color: _K.gray500)),
            )
          else
            const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _K.gray900,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(finished ? 'Done' : 'Close'),
          ),
        ],
      ),
    );
  }
}

class _CloneBadge extends StatelessWidget {
  const _CloneBadge({required this.status});

  final CloneEmployeeStatus status;

  @override
  Widget build(BuildContext context) {
    final style = _cloneStatusStyle[status.status] ?? _cloneStatusStyle['QUEUED_TARGET']!;
    final (label, bg, fg, border, spinning) = style;
    final templates = status.templatesCopied ?? status.templatesQueued;
    final showCount = (status.status == 'COMPLETED' || status.status == 'PARTIAL') && (templates ?? 0) > 0;

    return Tooltip(
      message: status.error ?? '',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99), border: Border.all(color: border)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinning)
              SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: fg))
            else if (status.status == 'COMPLETED')
              Icon(Icons.check_rounded, size: 12, color: fg)
            else if (status.status == 'FAILED')
              Icon(Icons.error_outline_rounded, size: 12, color: fg),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '$label${showCount ? ' ($templates print${templates == 1 ? '' : 's'})' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceEnd extends StatelessWidget {
  const _DeviceEnd({required this.icon, required this.name, required this.done});

  final IconData icon;
  final String name;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: done ? _K.emerald50 : _K.indigo50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: done ? _K.emerald200 : _K.indigo200),
          ),
          child: Icon(icon, size: 20, color: done ? _K.emerald600 : _K.indigo600),
        ),
        const SizedBox(height: 6),
        Text(name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _K.gray700)),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: _K.gray50, borderRadius: BorderRadius.circular(10), border: Border.all(color: _K.gray100)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: _K.gray500)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _K.gray900, fontFeatures: _T.tabular)),
        ],
      ),
    );
  }
}

// ── Employee picker (searchable, all employees) ─────────────────────────────

class _EmployeePicker extends StatefulWidget {
  const _EmployeePicker({required this.employees});

  final List<Employee> employees;

  @override
  State<_EmployeePicker> createState() => _EmployeePickerState();
}

class _EmployeePickerState extends State<_EmployeePicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = widget.employees
        .where((e) => q.isEmpty || e.name.toLowerCase().contains(q) || e.employeeCode.toLowerCase().contains(q))
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Choose employee', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900)),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20, color: _K.gray400),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 14),
                decoration: _inputDecoration(hint: 'Search name or code', icon: Icons.search_rounded),
              ),
            ),
            _divider,
            Expanded(
              child: widget.employees.isEmpty
                  ? const Center(child: Text('Loading employees…', style: _T.subtitle))
                  : shown.isEmpty
                      ? const Center(child: Text('No matching employees.', style: _T.subtitle))
                      : ListView.separated(
                          itemCount: shown.length,
                          separatorBuilder: (_, __) => const Padding(padding: EdgeInsets.only(left: 60), child: _divider),
                          itemBuilder: (_, i) {
                            final e = shown[i];
                            return ListTile(
                              dense: true,
                              leading: Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(color: _K.indigo50, shape: BoxShape.circle),
                                child: Text(_initials(e.name),
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _K.indigo600)),
                              ),
                              title: Text(e.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                [e.employeeCode, if (e.branchName.isNotEmpty) e.branchName].join(', '),
                                style: const TextStyle(fontSize: 11.5, color: _K.gray500, fontFeatures: _T.tabular),
                              ),
                              onTap: () => Navigator.of(context).pop(e),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small pieces ────────────────────────────────────────────────────────────

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
    fillColor: Colors.white,
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

class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.body,
    this.footer,
    this.trailing,
    this.maxWidth = 520,
    this.closeEnabled = true,
  });

  final IconData icon;
  final _Tone tone;
  final String title;
  final String subtitle;
  final List<Widget> body;
  final Widget? footer;
  final Widget? trailing;
  final double maxWidth;
  final bool closeEnabled;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 14),
              child: Row(
                children: [
                  _IconBox(icon: icon, tone: tone, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900)),
                        const SizedBox(height: 1),
                        Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.subtitle),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[const SizedBox(width: 8), trailing!],
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: closeEnabled ? () => Navigator.of(context).pop() : null,
                    icon: const Icon(Icons.close_rounded, size: 20, color: _K.gray400),
                  ),
                ],
              ),
            ),
            _divider,
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
              ),
            ),
            if (footer != null)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.gray100))),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// White card with a hairline border.
class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
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

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor = _K.indigo600,
    this.textColor = _K.gray900,
    this.tooltip,
    this.busy = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color iconColor;
  final Color textColor;
  final String? tooltip;
  final bool busy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: textColor,
        side: const BorderSide(color: _K.gray200),
        minimumSize: Size(0, compact ? 34 : 40),
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: TextStyle(fontSize: compact ? 12.5 : 13, fontWeight: FontWeight.w600),
      ),
      onPressed: onTap,
      icon: busy
          ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: iconColor))
          : Icon(icon, size: 17, color: onTap == null ? _K.gray300 : iconColor),
      label: Text(label),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Small icon button for card headers, with a tooltip and a busy spinner.
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      icon: busy
          ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color))
          : Icon(icon, size: 18, color: onTap == null ? _K.gray300 : color),
    );
  }
}

class _ChoiceNote extends StatelessWidget {
  const _ChoiceNote({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.w600, color: _K.gray900)),
        TextSpan(text: text),
      ]),
      style: const TextStyle(fontSize: 12.5, height: 1.4, color: _K.gray600),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.text, required this.tone, this.icon, this.busy = false});

  final String text;
  final _Tone tone;
  final IconData? icon;
  final bool busy;

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
          if (busy) ...[
            SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: tone.fg)),
            const SizedBox(width: 4),
          ] else if (icon != null) ...[
            Icon(icon, size: 12, color: tone.fg),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tone.fg, fontFeatures: _T.tabular),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.tone});

  final int count;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(99)),
      child: Text('$count',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tone.fg, fontFeatures: _T.tabular)),
    );
  }
}

class _InlineNote extends StatelessWidget {
  const _InlineNote({required this.icon, required this.text, required this.tone, this.busy = false});

  final IconData icon;
  final String text;
  final _Tone tone;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tone.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tone.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            busy
                ? Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: tone.fg)),
                  )
                : Icon(icon, size: 16, color: tone.fg),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(fontSize: 12, height: 1.4, color: tone.fg))),
          ],
        ),
      ),
    );
  }
}

class _LoadingLine extends StatelessWidget {
  const _LoadingLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: _K.indigo500)),
          const SizedBox(width: 10),
          Text(text, style: _T.subtitle),
        ],
      ),
    );
  }
}

/// Single-row empty state: icon, title, message and an optional action.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.success = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: success ? _K.emerald50.withValues(alpha: 0.5) : _K.gray50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: success ? _K.emerald200 : _K.gray200),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: success ? _K.emerald100 : _K.gray100, shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: success ? _K.emerald600 : _K.gray400),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _K.gray700)),
                if (message != null)
                  Text(message!, style: const TextStyle(fontSize: 11.5, height: 1.35, color: _K.gray500)),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
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