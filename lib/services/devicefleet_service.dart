// Port of services/deviceFleetService.ts (Device Mapping adds the mapping calls).

import 'package:hrm_app/api/api_client.dart';

int _int(dynamic v) => v is num ? v.round() : int.tryParse('$v') ?? 0;
int? _intOrNull(dynamic v) => v == null ? null : (v is num ? v.round() : int.tryParse('$v'));
String _str(dynamic v) => v == null ? '' : '$v';
String? _strOrNull(dynamic v) => (v == null || '$v'.isEmpty) ? null : '$v';
bool _bool(dynamic v) => v == true || v == 1 || v == 'true';
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : const {};

class Device {
  const Device({
    required this.id,
    required this.deviceCode,
    this.name,
    this.ipAddress,
    this.location,
    required this.deviceType,
    required this.connectionType,
    this.brand,
    required this.port,
    required this.syncEnabled,
    this.lastSyncedAt,
    this.lastSyncStatus,
    this.branchId,
    this.branchName,
    required this.isActive,
    this.lastSeenAt,
    this.punchMode,
    this.dedicatedPunchType,
    this.raw = const {},
  });

  final int id;
  final String deviceCode;
  final String? name;
  final String? ipAddress;
  final String? location;
  final String deviceType;

  /// API | TCPIP | SDK_TCP | BRIDGE | ADMS | API_PULL | MANUAL
  final String connectionType;

  /// ZKTECO | HIKVISION | GENERIC
  final String? brand;
  final int port;
  final bool syncEnabled;
  final String? lastSyncedAt;
  final String? lastSyncStatus;
  final int? branchId;
  final String? branchName;
  final bool isActive;
  final String? lastSeenAt;

  /// DEVICE_CONTROLLED | SYSTEM_TOGGLE | SEPARATE_DEVICE
  final String? punchMode;

  /// "IN" or "OUT" when punchMode is SEPARATE_DEVICE.
  final String? dedicatedPunchType;
  final Map<String, dynamic> raw;

  /// Name to show (falls back to the serial number).
  String get label => (name != null && name!.isNotEmpty) ? name! : deviceCode;

  /// Devices the server can talk to directly (push employees, pull users).
  bool get isDirectlyConnected => const ['TCPIP', 'SDK_TCP', 'BRIDGE'].contains(connectionType);

  factory Device.fromJson(Map<String, dynamic> j) => Device(
        id: _int(j['id']),
        deviceCode: _str(j['device_code']),
        name: _strOrNull(j['name']),
        ipAddress: _strOrNull(j['ip_address']),
        location: _strOrNull(j['location']),
        deviceType: _str(j['device_type']),
        connectionType: _str(j['connection_type']),
        brand: _strOrNull(j['brand']),
        port: _int(j['port']),
        syncEnabled: _bool(j['sync_enabled']),
        lastSyncedAt: _strOrNull(j['last_synced_at']),
        lastSyncStatus: _strOrNull(j['last_sync_status']),
        branchId: _intOrNull(j['branch_id']),
        branchName: _strOrNull(j['branch_name']),
        isActive: _bool(j['is_active']),
        lastSeenAt: _strOrNull(j['last_seen_at']),
        punchMode: _strOrNull(j['punch_mode']),
        dedicatedPunchType: _strOrNull(j['dedicated_punch_type']),
        raw: j,
      );
}

class DevicePage {
  const DevicePage({required this.results, required this.count});

  final List<Device> results;
  final int count;
}

Future<DevicePage> getDevices({int page = 1, Object? branchId}) async {
  final res = await api.get('/core/devices/', queryParameters: {
    'page': page,
    if (branchId != null && '$branchId'.isNotEmpty) 'branch_id': branchId,
    't': DateTime.now().millisecondsSinceEpoch, // no cached copies
  });
  final j = _map(res.data);
  return DevicePage(
    results: [
      for (final e in (j['results'] as List? ?? const []))
        if (e is Map) Device.fromJson(Map<String, dynamic>.from(e)),
    ],
    count: _int(j['count']),
  );
}

/// Imports the users enrolled on a device as employees.
Future<({int newLogs, int unresolved, int duplicates, List<String> errors})> syncEmployeesFromDevice(int deviceId) async {
  final res = await api.post('/core/devices/admin/$deviceId/sync-employees/');
  final j = _map(res.data);
  return (
    newLogs: _int(j['new_logs']),
    unresolved: _int(j['unresolved']),
    duplicates: _int(j['duplicates']),
    errors: [for (final e in (j['errors'] as List? ?? const [])) '$e'],
  );
}

Future<Device> createDevice(Map<String, dynamic> data) async {
  final res = await api.post('/core/devices/admin/', data: data);
  return Device.fromJson(_map(res.data));
}

Future<Device> updateDevice(int id, Map<String, dynamic> data) async {
  final res = await api.put('/core/devices/admin/$id/', data: data);
  return Device.fromJson(_map(res.data));
}

Future<void> toggleDeviceStatus(int id, bool isActive) async {
  await api.patch('/core/devices/admin/$id/', data: {'is_active': isActive});
}

Future<void> deleteDevice(int id) async {
  await api.delete('/core/devices/admin/$id/');
}

/// Pulls new punch logs from a directly connected device.
Future<({int newLogs, List<String> errors})> triggerDeviceSync(int deviceId) async {
  final res = await api.post('/core/devices/admin/$deviceId/sync/');
  final j = _map(res.data);
  return (newLogs: _int(j['new_logs']), errors: [for (final e in (j['errors'] as List? ?? const [])) '$e']);
}

/// Asks an ADMS (cloud push) device to resend its logs. Returns the server message.
Future<String> triggerAdmsResync(int deviceId) async {
  final res = await api.post('/core/devices/admin/adms-resync/', data: {'device_id': deviceId});
  return _str(_map(res.data)['message']);
}

/// Asks an ADMS device to send its user list (for mapping employees).
Future<String> triggerAdmsUserSync(int deviceId) async {
  final res = await api.post('/core/devices/admin/adms-user-sync/', data: {'device_id': deviceId});
  return _str(_map(res.data)['message']);
}

/// Every device, across all pages.
Future<List<Device>> getAllDevices() async {
  final all = <Device>[];
  var page = 1;
  while (true) {
    final res = await getDevices(page: page);
    all.addAll(res.results);
    if (res.results.isEmpty || all.length >= res.count) break;
    page++;
  }
  return all;
}

// ── Employee mappings (device user ID → employee) ──────────────────────────

class DeviceEmployeeMapping {
  const DeviceEmployeeMapping({
    required this.id,
    required this.deviceUserId,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
  });

  final int id;
  final String deviceUserId;
  final int employeeId;
  final String employeeName;
  final String employeeCode;

  factory DeviceEmployeeMapping.fromJson(Map<String, dynamic> j) => DeviceEmployeeMapping(
        id: _int(j['id']),
        deviceUserId: _str(j['device_user_id']),
        employeeId: _int(j['employee_id']),
        employeeName: _str(j['employee_name']),
        employeeCode: _str(j['employee_code']),
      );
}

List<Map<String, dynamic>> _results(dynamic data) {
  final list = _map(data)['results'];
  return list is List ? [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)] : const [];
}

Future<({List<DeviceEmployeeMapping> results, int count})> getDeviceMappings(int deviceId, {int page = 1}) async {
  final res = await api.get('/core/devices/admin/$deviceId/mappings/', queryParameters: {'page': page});
  return (
    results: [for (final r in _results(res.data)) DeviceEmployeeMapping.fromJson(r)],
    count: _int(_map(res.data)['count']),
  );
}

Future<void> createDeviceMapping(int deviceId, {required String deviceUserId, required int employeeId}) async {
  await api.post('/core/devices/admin/$deviceId/mappings/', data: {
    'device_user_id': deviceUserId,
    'employee_id': employeeId,
  });
}

Future<void> deleteDeviceMapping(int deviceId, int mappingId) async {
  await api.delete('/core/devices/admin/$deviceId/mappings/$mappingId/');
}

/// Links device users to employees whose code matches. Returns (message, linked).
Future<({String message, int linked})> autoLinkDeviceMappings(int deviceId) async {
  final res = await api.post('/core/devices/admin/$deviceId/mappings/auto-link/');
  final j = _map(res.data);
  return (message: _str(j['message']), linked: _int(j['linked']));
}

/// Imports device punches that never reached attendance. For ADMS devices it
/// can also ask the device to re-upload the punch history it stores.
Future<({int recovered, int stillUnknown, bool historyRequested})> recoverDevicePunches(
  int deviceId, {
  bool includeResolved = true,
  bool requestDeviceHistory = false,
}) async {
  final res = await api.post('/core/devices/admin/$deviceId/recover-punches/', data: {
    'include_resolved': includeResolved,
    'request_device_history': requestDeviceHistory,
  });
  final j = _map(res.data);
  final history = _map(j['device_history']);
  return (
    recovered: _int(j['recovered']),
    stillUnknown: _int(j['still_unknown']),
    historyRequested: history['command_id'] != null,
  );
}

// ── Unresolved punch logs (device users not linked yet) ─────────────────────

class UnresolvedDeviceLog {
  const UnresolvedDeviceLog({
    required this.id,
    required this.deviceUserId,
    required this.rawTimestamp,
    required this.punchType,
  });

  final int id;
  final String deviceUserId;
  final String rawTimestamp; // wall-clock
  final String punchType;

  factory UnresolvedDeviceLog.fromJson(Map<String, dynamic> j) => UnresolvedDeviceLog(
        id: _int(j['id']),
        deviceUserId: _str(j['device_user_id']),
        rawTimestamp: _str(j['raw_timestamp']),
        punchType: _str(j['punch_type']),
      );
}

Future<({List<UnresolvedDeviceLog> results, int count})> getUnresolvedLogs(int deviceId, {int page = 1}) async {
  final res = await api.get('/core/devices/unresolved-logs/', queryParameters: {'page': page, 'device_id': deviceId});
  return (
    results: [for (final r in _results(res.data)) UnresolvedDeviceLog.fromJson(r)],
    count: _int(_map(res.data)['count']),
  );
}

/// Marks one log as handled (dismisses it).
Future<void> resolveLog(int logId) async {
  await api.patch('/core/devices/unresolved-logs/$logId/');
}

Future<void> dismissAllUnresolvedLogs(int deviceId) async {
  await api.delete('/core/devices/unresolved-logs/', queryParameters: {'device_id': deviceId});
}

/// Creates an employee for an unknown device user and resolves their punches.
Future<String> quickCreateEmployeeFromLog(int logId, String employeeName, {String? employeeCode}) async {
  final res = await api.post('/core/devices/unresolved-logs/quick-create/', data: {
    'log_id': logId,
    'employee_name': employeeName,
    if (employeeCode != null && employeeCode.isNotEmpty) 'employee_code': employeeCode,
  });
  return _str(_map(res.data)['message']);
}

// ── Biometric cloning (copy users + fingerprints between devices) ──────────

class CloneCandidate {
  const CloneCandidate({
    required this.employeeId,
    required this.employeeCode,
    required this.name,
    required this.templateCount,
    required this.hasCachedBiometric,
  });

  final int employeeId;
  final String employeeCode;
  final String name;
  final int templateCount;
  final bool hasCachedBiometric;

  factory CloneCandidate.fromJson(Map<String, dynamic> j) => CloneCandidate(
        employeeId: _int(j['employee_id']),
        employeeCode: _str(j['employee_code']),
        name: _str(j['name']),
        templateCount: _int(j['template_count']),
        hasCachedBiometric: _bool(j['has_cached_biometric']),
      );
}

class CloneCandidates {
  const CloneCandidates({
    required this.candidates,
    required this.sourceOnline,
    required this.compatibilityError,
    required this.refreshCommandId,
    required this.refreshStatus,
  });

  final List<CloneCandidate> candidates;
  final bool sourceOnline;
  final String? compatibilityError;

  /// Set while the source device is uploading its latest users / fingerprints.
  final int? refreshCommandId;
  final String? refreshStatus;
}

Future<CloneCandidates> getCloneCandidates(int targetDeviceId, int sourceDeviceId, {bool refreshSource = true}) async {
  final res = await api.get('/core/devices/admin/$targetDeviceId/clone-candidates/', queryParameters: {
    'source_device_id': sourceDeviceId,
    'refresh': refreshSource ? 1 : 0,
  });
  final j = _map(res.data);
  final refresh = _map(j['source_refresh']);
  return CloneCandidates(
    candidates: [
      for (final c in (j['candidates'] as List? ?? const []))
        if (c is Map) CloneCandidate.fromJson(Map<String, dynamic>.from(c)),
    ],
    sourceOnline: j['source_online'] != false,
    compatibilityError: _strOrNull(j['compatibility_error']),
    refreshCommandId: refresh['command_id'] == null ? null : _int(refresh['command_id']),
    refreshStatus: _strOrNull(refresh['status']),
  );
}

Future<({int commandId, String message, int usersQueued, int templatesQueued})> triggerCloneBiometrics(
  int targetDeviceId,
  int sourceDeviceId, {
  List<int>? employeeIds,
  bool cloneAll = false,
}) async {
  final res = await api.post('/core/devices/admin/clone-biometrics/', data: {
    'target_device_id': targetDeviceId,
    'source_device_id': sourceDeviceId,
    'employee_ids': employeeIds,
    'clone_all': cloneAll,
  });
  final j = _map(res.data);
  return (
    commandId: _int(j['command_id']),
    message: _str(j['message']),
    usersQueued: _int(j['users_queued']),
    templatesQueued: _int(j['templates_queued']),
  );
}

class CloneEmployeeStatus {
  const CloneEmployeeStatus({
    required this.employeeId,
    required this.employeeCode,
    required this.name,
    required this.status,
    this.templatesQueued,
    this.templatesCopied,
    this.error,
  });

  final int employeeId;
  final String employeeCode;
  final String name;

  /// FETCHING_FROM_SOURCE | QUEUED_TARGET | COMPLETED | USER_ONLY | PARTIAL |
  /// FAILED | SKIPPED_CONFLICT | NOT_ON_SOURCE
  final String status;
  final int? templatesQueued;
  final int? templatesCopied;
  final String? error;

  factory CloneEmployeeStatus.fromJson(Map<String, dynamic> j) => CloneEmployeeStatus(
        employeeId: _int(j['employee_id']),
        employeeCode: _str(j['employee_code']),
        name: _str(j['name']),
        status: _str(j['status']),
        templatesQueued: j['templates_queued'] == null ? null : _int(j['templates_queued']),
        templatesCopied: j['templates_copied'] == null ? null : _int(j['templates_copied']),
        error: _strOrNull(j['error']),
      );
}

/// Status of a queued device command (cloning, source refresh, ...).
class DeviceCommandStatus {
  const DeviceCommandStatus({
    required this.id,
    required this.status,
    required this.sourceDeviceName,
    required this.targetDeviceName,
    this.usersFound = 0,
    this.usersCopied = 0,
    this.templatesFound = 0,
    this.templatesCopied = 0,
    this.statusDetail,
    this.employeeStatuses = const [],
  });

  final int id;

  /// PENDING | PROCESSING | AWAITING_DATA | COMPLETED | FAILED
  final String status;
  final String sourceDeviceName;
  final String targetDeviceName;
  final int usersFound;
  final int usersCopied;
  final int templatesFound;
  final int templatesCopied;
  final String? statusDetail;
  final List<CloneEmployeeStatus> employeeStatuses;

  bool get finished => status == 'COMPLETED' || status == 'FAILED';

  factory DeviceCommandStatus.fromJson(Map<String, dynamic> j) {
    final payload = _map(j['payload']);
    final result = _map(j['result']);
    return DeviceCommandStatus(
      id: _int(j['id']),
      status: _str(j['status']),
      sourceDeviceName: _str(payload['source_device_name']),
      targetDeviceName: _str(payload['target_device_name']),
      usersFound: _int(result['users_found']),
      usersCopied: _int(result['users_copied']),
      templatesFound: _int(result['templates_found']),
      templatesCopied: _int(result['templates_copied']),
      statusDetail: _strOrNull(result['status_detail']),
      employeeStatuses: [
        for (final e in (result['employee_statuses'] as List? ?? const []))
          if (e is Map) CloneEmployeeStatus.fromJson(Map<String, dynamic>.from(e)),
      ],
    );
  }
}

Future<DeviceCommandStatus> getCommandStatus(int commandId) async {
  final res = await api.get('/core/devices/admin/command-status/$commandId/');
  return DeviceCommandStatus.fromJson(_map(res.data));
}