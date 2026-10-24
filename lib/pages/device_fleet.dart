// Port of features/admin/devices/DeviceFleetPage.tsx ("Hardware Integrations"):
// the company's attendance devices with live status, log sync, employee
// mapping, enable / disable, edit and delete.
//
// The list refreshes quietly every 10 s so the status pills stay live
// (paused while the app is in the background). Wide screens get a table with
// column headers; on phones each device is a compact two-line row.
//
// Compact layout:
//   Header (one line): icon · title · live/updated · Add device
//   [load-error banner]
//   Fleet card: title · count · status filter chips · refresh
//               table (wide) / two-line rows (phones) · pagination
//   Sync + Map users always visible as icon buttons; the rest in a ⋮ menu.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:hrm_app/app/session.dart';
import 'package:hrm_app/auth/auth_store.dart';
import 'package:hrm_app/components/devices/device_formsheet.dart';
import 'package:hrm_app/components/ui/pagination_bar.dart';
import 'package:hrm_app/services/branch_service.dart';
import 'package:hrm_app/services/devicefleet_service.dart';
import 'package:hrm_app/utils/toast.dart';

const _pageSize = 10;

// ── Design tokens ───────────────────────────────────────────────────────────

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
  static const indigo200 = Color(0xFFC7D2FE);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const blue50 = Color(0xFFEFF6FF);
  static const blue200 = Color(0xFFBFDBFE);
  static const blue600 = Color(0xFF2563EB);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber200 = Color(0xFFFDE68A);
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  static const red50 = Color(0xFFFEF2F2);
  static const red200 = Color(0xFFFECACA);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);
}

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.3, color: _K.gray900);
  static const subtitle = TextStyle(fontSize: 11.5, height: 1.3, color: _K.gray500);
  static const caption = TextStyle(fontSize: 11, height: 1.3, color: _K.gray500);
  static const meta = TextStyle(fontSize: 11.5, height: 1.3, color: _K.gray600);
  static const columnHead = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.gray500);
}

const _cardRadius = 14.0;
const _divider = Divider(height: 1, thickness: 1, color: _K.gray100);

// ── Time helpers ────────────────────────────────────────────────────────────

/// Server times without a zone are UTC (the web adds "Z" too).
DateTime? _serverTime(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final hasZone = iso.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(iso);
  return DateTime.tryParse(hasZone ? iso : '${iso}Z')?.toLocal();
}

String _hhmm(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Short relative time: "now", "4m", "3h", "1d", "12 Oct", or "never".
String _ago(String? iso) {
  final d = _serverTime(iso);
  if (d == null) return 'never';
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${d.day} ${_months[d.month - 1]}';
}

/// "12 Oct 2026, 09:41 AM" for tooltips.
String _exact(String? iso) {
  final d = _serverTime(iso);
  if (d == null) return 'Never';
  return '${d.day} ${_months[d.month - 1]} ${d.year}, ${_hhmm(d)}';
}

// ── Status ──────────────────────────────────────────────────────────────────

enum _State { online, offline, networkError, disabled }

class _Status {
  const _Status(this.state, this.label, this.bg, this.border, this.fg, this.dot, {this.live = false});

  final _State state;
  final String label;
  final Color bg;
  final Color border;
  final Color fg;
  final Color dot;
  final bool live;
}

const _online = _Status(_State.online, 'Online', _K.emerald50, _K.emerald200, _K.emerald600, _K.emerald500, live: true);
const _offline = _Status(_State.offline, 'Offline', _K.amber50, _K.amber200, _K.amber600, _K.amber500);
const _networkError = _Status(_State.networkError, 'Network error', _K.red50, _K.red200, _K.red600, _K.red500);
const _disabled = _Status(_State.disabled, 'Disabled', _K.gray100, _K.gray200, _K.gray500, _K.gray400);

_Status _statusOf(Device d) {
  if (!d.isActive) return _disabled;
  // Seen (heartbeat, punch or poll) within the last 2 minutes = online.
  final seen = _serverTime(d.lastSeenAt);
  if (seen != null) {
    final diff = DateTime.now().difference(seen).inSeconds;
    if (diff >= -10 && diff <= 120) return _online;
  }
  if (d.isDirectlyConnected && d.lastSyncStatus == 'FAILED') return _networkError;
  return _offline;
}

String _deviceName(Device d) => (d.name != null && d.name!.isNotEmpty) ? d.name! : 'Unnamed device';

// ── Page ────────────────────────────────────────────────────────────────────

class DeviceFleetPage extends StatefulWidget {
  const DeviceFleetPage({super.key});

  @override
  State<DeviceFleetPage> createState() => _DeviceFleetPageState();
}

class _DeviceFleetPageState extends State<DeviceFleetPage> with WidgetsBindingObserver {
  List<Device> _devices = const [];
  List<BranchOption> _branches = const [];
  int _total = 0;
  int _page = 1;
  bool _loading = true;
  bool _loadedOnce = false;
  bool _silentFailed = false;
  String? _error;
  DateTime? _updatedAt;
  int? _syncing;
  _State? _filter;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    branchService.fetchBranchOptions().then((b) {
      if (mounted) setState(() => _branches = b);
    }).catchError((_) {});
    _load();
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load(silent: true);
      _start();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await getDevices(page: _page);
      if (!mounted) return;
      setState(() {
        _devices = res.results;
        _total = res.count;
        _updatedAt = DateTime.now();
        _loadedOnce = true;
        _silentFailed = false;
        _error = null;
      });
    } catch (err) {
      if (!mounted) return;
      if (silent) {
        setState(() => _silentFailed = true);
      } else {
        setState(() => _error = apiError(err, 'Failed to load devices'));
      }
    } finally {
      if (!silent && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([Device? device]) async {
    final saved = await showDeviceForm(context, device: device, branches: _branches);
    if (saved) _load();
  }

  Future<void> _sync(Device d) async {
    setState(() => _syncing = d.id);
    try {
      if (d.connectionType == 'ADMS') {
        final message = await triggerAdmsResync(d.id);
        if (mounted) showToast(context, message.isNotEmpty ? message : 'Resync requested. The device will send its logs shortly.');
      } else if (d.isDirectlyConnected) {
        final res = await triggerDeviceSync(d.id);
        if (mounted) {
          if (res.errors.isNotEmpty) {
            showToast(context, 'Sync partially failed: ${res.errors.first}', error: true);
          } else {
            showToast(context, 'Sync complete. ${res.newLogs} new log${res.newLogs == 1 ? '' : 's'}.');
          }
        }
      }
      _load();
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to trigger sync'), error: true);
    } finally {
      if (mounted) setState(() => _syncing = null);
    }
  }

  Future<void> _mappings(Device d) async {
    if (d.connectionType != 'ADMS') {
      context.go('/admin/hardware/mappings/${d.id}');
      return;
    }
    // ADMS devices first get asked for their user list.
    showToast(context, 'Requesting the user list from ${_deviceName(d)}…');
    try {
      final message = await triggerAdmsUserSync(d.id);
      if (!mounted) return;
      showToast(context, message.isNotEmpty ? message : 'User list requested.');
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (mounted) context.go('/admin/hardware/mappings/${d.id}');
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to trigger user sync request'), error: true);
    }
  }

  Future<void> _toggle(Device d) async {
    final enable = !d.isActive;
    if (!enable) {
      final ok = await _confirm(
        title: 'Disable ${_deviceName(d)}?',
        message: 'Punches from this device stop syncing until you enable it again.',
        action: 'Disable',
        destructive: false,
      );
      if (!ok) return;
    }
    try {
      await toggleDeviceStatus(d.id, enable);
      if (mounted) showToast(context, '${d.label} ${enable ? 'enabled' : 'disabled'}');
      _load();
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to update device status'), error: true);
    }
  }

  Future<void> _delete(Device d) async {
    final ok = await _confirm(
      title: 'Delete ${_deviceName(d)}?',
      message: 'The device (${d.deviceCode}) is removed from the fleet and its punches stop syncing. '
          "This can't be undone.",
      action: 'Delete device',
      destructive: true,
    );
    if (!ok) return;
    try {
      await deleteDevice(d.id);
      if (!mounted) return;
      showToast(context, '${_deviceName(d)} deleted');
      if (_devices.length == 1 && _page > 1) setState(() => _page--);
      _load();
    } catch (_) {
      if (mounted) showToast(context, 'Failed to delete device', error: true);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    required bool destructive,
  }) async {
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
              backgroundColor: destructive ? _K.red600 : _K.gray900,
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

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthStore>().user ?? const <String, dynamic>{};
    final canProvision = user.isSuperuser || user['role'] == 'HR';

    if (_loading && !_loadedOnce && _error == null) return const _PageSkeleton();

    final counts = {for (final s in _State.values) s: 0};
    for (final d in _devices) {
      final s = _statusOf(d).state;
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final shown = _filter == null ? _devices : _devices.where((d) => _statusOf(d).state == _filter).toList();

    return RefreshIndicator(
      color: _K.indigo600,
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sm = width >= 640;
          final lg = width >= 1024;
          final gap = sm ? 14.0 : 12.0;

          final sections = <Widget>[
            _header(wide: sm, canProvision: canProvision),
            if (_error != null)
              _Banner(
                icon: Icons.error_outline_rounded,
                message: _error!,
                actionLabel: 'Retry',
                onAction: _load,
              ),
            _devicesCard(shown: shown, counts: counts, wide: lg, canProvision: canProvision),
          ];

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(sm ? 20 : 12),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
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

  Widget _header({required bool wide, required bool canProvision}) {
    final updated = _updatedAt == null ? null : TimeOfDay.fromDateTime(_updatedAt!).format(context);

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _K.indigo50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _K.indigo200),
          ),
          child: const Icon(Icons.router_outlined, size: 18, color: _K.indigo600),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Attendance devices',
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
              if (updated != null)
                Semantics(
                  liveRegion: true,
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _silentFailed ? _K.amber500 : _K.emerald500,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          _silentFailed ? 'Connection issue, retrying' : 'Live, updated $updated',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: _silentFailed ? _K.amber600 : _K.gray500),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (canProvision) ...[
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _K.indigo600,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add_rounded, size: 17),
            label: Text(wide ? 'Add device' : 'Add'),
          ),
        ],
      ],
    );
  }

  Widget _devicesCard({
    required List<Device> shown,
    required Map<_State, int> counts,
    required bool wide,
    required bool canProvision,
  }) {
    final from = _total == 0 ? 0 : (_page - 1) * _pageSize + 1;
    final to = (_page - 1) * _pageSize + _devices.length;

    Widget body;
    if (_devices.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(12),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('Loading devices…', textAlign: TextAlign.center, style: _T.subtitle),
              )
            : _EmptyState(
                icon: Icons.router_outlined,
                title: 'No devices yet',
                message: canProvision
                    ? 'Add a biometric or RFID scanner to start collecting punches.'
                    : 'Ask HR to add the attendance devices for your branches.',
                action: canProvision ? _LinkButton(label: 'Add device', onTap: () => _openForm()) : null,
              ),
      );
    } else if (shown.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Flexible(child: Text('No devices with this status on this page.', style: _T.subtitle)),
            const SizedBox(width: 6),
            _LinkButton(label: 'Show all', onTap: () => setState(() => _filter = null)),
          ],
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) _divider,
            _DeviceRow(
              device: shown[i],
              wide: wide,
              syncing: _syncing == shown[i].id,
              onSync: () => _sync(shown[i]),
              onMappings: () => _mappings(shown[i]),
              onToggle: () => _toggle(shown[i]),
              onEdit: () => _openForm(shown[i]),
              onDelete: () => _delete(shown[i]),
            ),
          ],
        ],
      );
    }

    final chips = _devices.isEmpty
        ? null
        : _StatusChips(
            counts: counts,
            selected: _filter,
            onSelect: (s) => setState(() => _filter = _filter == s ? null : s),
          );

    final refresh = IconButton(
      tooltip: 'Refresh now',
      visualDensity: VisualDensity.compact,
      onPressed: _loading ? null : _load,
      icon: _loading
          ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.refresh_rounded, size: 19, color: _K.gray500),
    );

    final title = Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'Fleet', style: _T.title),
        TextSpan(
          text: _total == 0
              ? '  none'
              : _total > _devices.length
                  ? '  $from–$to of $_total'
                  : '  $_total',
          style: const TextStyle(fontSize: 12, color: _K.gray500, fontFeatures: _T.tabular),
        ),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: LayoutBuilder(
              builder: (context, c) {
                if (chips == null || c.maxWidth >= 600) {
                  return Row(
                    children: [
                      title,
                      const SizedBox(width: 12),
                      Expanded(
                        child: chips == null
                            ? const SizedBox.shrink()
                            : Align(
                                alignment: Alignment.centerRight,
                                child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: chips),
                              ),
                      ),
                      refresh,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [Expanded(child: title), refresh]),
                    SingleChildScrollView(scrollDirection: Axis.horizontal, child: chips),
                    const SizedBox(height: 4),
                  ],
                );
              },
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
              padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
              child: _tableRow(
                device: const Text('Device', style: _T.columnHead),
                type: const Text('Type', style: _T.columnHead),
                branch: const Text('Branch', style: _T.columnHead),
                status: const Text('Status', style: _T.columnHead),
                activity: const Text('Activity', style: _T.columnHead),
                actions: const SizedBox.shrink(),
              ),
            ),
          body,
          if (_total > _pageSize)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.gray100))),
              child: PaginationBar(
                page: _page,
                total: _total,
                pageSize: _pageSize,
                onPage: (p) {
                  setState(() {
                    _page = p;
                    _filter = null;
                  });
                  _load();
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Status filter chips ─────────────────────────────────────────────────────

class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.counts, required this.selected, required this.onSelect});

  final Map<_State, int> counts;
  final _State? selected;
  final ValueChanged<_State> onSelect;

  @override
  Widget build(BuildContext context) {
    const order = [_online, _offline, _networkError, _disabled];
    final visible = [
      for (final s in order)
        if ((counts[s.state] ?? 0) > 0 || selected == s.state) s,
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, s) in visible.indexed) ...[
          if (i > 0) const SizedBox(width: 5),
          _SummaryChip(
            status: s,
            count: counts[s.state] ?? 0,
            selected: selected == s.state,
            onTap: () => onSelect(s.state),
          ),
        ],
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.status, required this.count, required this.selected, required this.onTap});

  final _Status status;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(side: BorderSide(color: selected ? status.fg : status.border, width: selected ? 1.5 : 1));
    return Semantics(
      button: true,
      selected: selected,
      label: '${status.label}: $count on this page${selected ? ', filter on' : ', tap to filter'}',
      excludeSemantics: true,
      child: Material(
        color: status.bg,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusDot(status: status),
                const SizedBox(width: 5),
                Text(status.label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: status.fg)),
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: status.fg, fontFeatures: _T.tabular),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── One device ──────────────────────────────────────────────────────────────

Widget _tableRow({
  required Widget device,
  required Widget type,
  required Widget branch,
  required Widget status,
  required Widget activity,
  required Widget actions,
}) {
  return Row(
    children: [
      Expanded(flex: 4, child: device),
      const SizedBox(width: 10),
      Expanded(flex: 2, child: type),
      const SizedBox(width: 10),
      Expanded(flex: 3, child: branch),
      const SizedBox(width: 10),
      Expanded(flex: 2, child: status),
      const SizedBox(width: 10),
      Expanded(flex: 3, child: activity),
      const SizedBox(width: 6),
      SizedBox(width: 108, child: Align(alignment: Alignment.centerRight, child: actions)),
    ],
  );
}

enum _MenuAction { toggle, edit, delete }

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.wide,
    required this.syncing,
    required this.onSync,
    required this.onMappings,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final Device device;
  final bool wide;
  final bool syncing;
  final VoidCallback onSync;
  final VoidCallback onMappings;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final fingerprint = d.deviceType == 'FINGERPRINT';
    final status = _statusOf(d);
    final canSync = d.isDirectlyConnected || d.connectionType == 'ADMS';
    final adms = d.connectionType == 'ADMS';
    final syncTip = adms ? 'Request logs (ADMS devices also push automatically)' : 'Sync logs now';
    final mapTip = adms ? 'Request the user list and map employees' : 'Map device users to employees';
    final typeText = [fingerprint ? 'Biometric' : 'RFID', if (adms) 'ADMS' else if (d.isDirectlyConnected) 'Direct'].join(', ');
    final syncFailed = d.isDirectlyConnected && d.lastSyncStatus == 'FAILED';

    final icon = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: fingerprint ? _K.blue50 : _K.indigo50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fingerprint ? _K.blue200 : _K.indigo200),
      ),
      child: Icon(
        fingerprint ? Icons.fingerprint_rounded : Icons.contactless_outlined,
        size: 16,
        color: fingerprint ? _K.blue600 : _K.indigo600,
      ),
    );

    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _deviceName(d),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.25,
            color: d.name != null && d.name!.isNotEmpty ? _K.gray900 : _K.gray500,
          ),
        ),
        Text(
          d.deviceCode,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, height: 1.25, color: _K.gray500, fontFeatures: _T.tabular),
        ),
      ],
    );

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: status.bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: status.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusDot(status: status),
          const SizedBox(width: 4),
          Text(status.label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: status.fg)),
        ],
      ),
    );

    /// "Seen 2m ago · Synced 1h ago, failed" on one line; exact times in the tooltip.
    final activity = Tooltip(
      message: 'Last seen: ${_exact(d.lastSeenAt)}'
          '${d.isDirectlyConnected ? '\nLast synced: ${_exact(d.lastSyncedAt)}' : ''}',
      child: Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'Seen ', style: TextStyle(color: _K.gray400)),
          TextSpan(text: _ago(d.lastSeenAt)),
          if (d.isDirectlyConnected) ...[
            const TextSpan(text: '  ·  Synced ', style: TextStyle(color: _K.gray400)),
            TextSpan(text: _ago(d.lastSyncedAt)),
            if (syncFailed)
              const TextSpan(text: ', failed', style: TextStyle(color: _K.red600, fontWeight: FontWeight.w600)),
          ],
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5, color: _K.gray700, fontFeatures: _T.tabular),
      ),
    );

    final menu = PopupMenuButton<_MenuAction>(
      tooltip: 'More actions',
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (a) {
        switch (a) {
          case _MenuAction.toggle:
            onToggle();
          case _MenuAction.edit:
            onEdit();
          case _MenuAction.delete:
            onDelete();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _MenuAction.edit,
          child: _MenuRow(icon: Icons.edit_outlined, label: 'Edit device'),
        ),
        PopupMenuItem(
          value: _MenuAction.toggle,
          child: _MenuRow(
            icon: Icons.power_settings_new_rounded,
            label: d.isActive ? 'Disable device' : 'Enable device',
            color: d.isActive ? _K.gray700 : _K.emerald600,
          ),
        ),
        const PopupMenuDivider(height: 8),
        const PopupMenuItem(
          value: _MenuAction.delete,
          child: _MenuRow(icon: Icons.delete_outline_rounded, label: 'Delete device', color: _K.red600),
        ),
      ],
      child: const SizedBox(
        width: 30,
        height: 30,
        child: Icon(Icons.more_vert_rounded, size: 18, color: _K.gray500),
      ),
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canSync) ...[
          _IconAction(icon: Icons.sync_rounded, tooltip: syncTip, busy: syncing, onTap: syncing ? null : onSync),
          const SizedBox(width: 4),
          _IconAction(icon: Icons.people_alt_outlined, tooltip: mapTip, onTap: onMappings),
        ],
        menu,
      ],
    );

    if (wide) {
      return Opacity(
        opacity: d.isActive ? 1 : 0.7,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
          child: _tableRow(
            device: Row(children: [icon, const SizedBox(width: 8), Expanded(child: nameBlock)]),
            type: Text(typeText, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.meta),
            branch: Text(
              d.branchName ?? 'Unassigned',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _T.meta.copyWith(color: d.branchName == null ? _K.gray400 : _K.gray600),
            ),
            status: Align(alignment: Alignment.centerLeft, child: badge),
            activity: activity,
            actions: actions,
          ),
        ),
      );
    }

    // Phone: two lines — identity + actions, then status · type · branch · activity.
    return Opacity(
      opacity: d.isActive ? 1 : 0.75,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                icon,
                const SizedBox(width: 8),
                Expanded(child: nameBlock),
                actions,
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 38, right: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  badge,
                  Text(
                    '$typeText  ·  ${d.branchName ?? 'Unassigned'}',
                    style: _T.caption,
                  ),
                  activity,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final _Status status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: status.dot,
        shape: BoxShape.circle,
        boxShadow: status.live ? [BoxShadow(color: status.dot.withValues(alpha: 0.5), blurRadius: 5)] : null,
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.color = _K.gray700});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 13, color: color)),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.tooltip, required this.onTap, this.busy = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(7),
      side: const BorderSide(color: _K.indigo200),
    );
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: Material(
          color: _K.indigo50,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: SizedBox(
              width: 30,
              height: 30,
              child: Center(
                child: busy
                    ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: _K.indigo600))
                    : Icon(icon, size: 16, color: _K.indigo600),
              ),
            ),
          ),
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
      label: 'Loading devices',
      child: Column(
        children: [
          const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => ListView(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.all(c.maxWidth >= 640 ? 20 : 12),
                children: [bone(40), const SizedBox(height: 12), bone(360)],
              ),
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

/// Single-row empty state: icon, title, message and an optional action.
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
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: _K.gray50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _K.gray200),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(color: _K.gray100, shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: _K.gray400),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _K.gray700)),
                if (message != null) Text(message!, style: const TextStyle(fontSize: 11.5, height: 1.35, color: _K.gray500)),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.message, this.actionLabel, this.onAction});

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final hasAction = actionLabel != null && onAction != null;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(12, 6, hasAction ? 4 : 12, 6),
        decoration: BoxDecoration(
          color: _K.red50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _K.red200),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: _K.red700),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 12.5, height: 1.35, color: _K.red700))),
            if (hasAction)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: _K.red700,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
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