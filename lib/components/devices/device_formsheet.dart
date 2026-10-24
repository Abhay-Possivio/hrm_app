// Port of features/admin/devices/DeviceFormModal.tsx: provision a new device
// or configure an existing one (name, serial number, branch, punch method).
// Opens as a bottom sheet on phones.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:hrm_app/services/branch_service.dart';
import 'package:hrm_app/services/devicefleet_service.dart';
import 'package:hrm_app/utils/toast.dart';

class _K {
  static const gray50 = Color(0xFFF9FAFB);
  static const gray100 = Color(0xFFF3F4F6);
  static const gray200 = Color(0xFFE5E7EB);
  static const gray300 = Color(0xFFD1D5DB);
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
  static const indigo700 = Color(0xFF4338CA);
  static const indigo900 = Color(0xFF312E81);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber200 = Color(0xFFFDE68A);
  static const amber600 = Color(0xFFD97706);
  static const amber800 = Color(0xFF92400E);
  static const red600 = Color(0xFFDC2626);
}

/// Opens the form; resolves true when the device was saved.
Future<bool> showDeviceForm(BuildContext context, {Device? device, required List<BranchOption> branches}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    constraints: const BoxConstraints(maxWidth: 576),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _DeviceForm(device: device, branches: branches),
  );
  return saved == true;
}

class _DeviceForm extends StatefulWidget {
  const _DeviceForm({required this.device, required this.branches});

  final Device? device;
  final List<BranchOption> branches;

  @override
  State<_DeviceForm> createState() => _DeviceFormState();
}

class _DeviceFormState extends State<_DeviceForm> {
  late final _name = TextEditingController(text: widget.device?.name ?? '');
  late final _code = TextEditingController(text: widget.device?.deviceCode ?? '');
  late int? _branchId = widget.device?.branchId ?? (widget.branches.length == 1 ? widget.branches.first.id : null);
  late String _punchMode = widget.device?.punchMode ?? 'DEVICE_CONTROLLED';
  late String _dedicated = widget.device?.dedicatedPunchType ?? 'IN';
  bool _saving = false;
  String? _error;

  bool get _editing => widget.device != null;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _code.text.trim().isEmpty || _branchId == null) {
      setState(() => _error = 'Device name, serial number and branch are required.');
      return;
    }
    final d = widget.device;
    final data = <String, dynamic>{
      'device_code': _code.text.trim(),
      'name': _name.text.trim(),
      'location': d?.location ?? '',
      'device_type': d?.deviceType ?? 'FINGERPRINT',
      'brand': d?.brand ?? 'ZKTECO',
      // The web form always sends ADMS, which would switch an existing
      // TCP/IP or SDK device to ADMS on edit. Keep the device's own type.
      'connection_type': d?.connectionType ?? 'ADMS',
      'sync_enabled': d?.syncEnabled ?? true,
      'branch_id': _branchId,
      'punch_mode': _punchMode,
      'dedicated_punch_type': _dedicated,
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (d != null) {
        await updateDevice(d.id, data);
        if (mounted) showToast(context, 'Device protocol updated');
      } else {
        await createDevice(data);
        if (mounted) showToast(context, 'Device node provisioned');
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = _fieldErrors(err) ?? 'Failed to establish device link');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// "device_code: already exists" style messages from the server, like the web toasts.
  String? _fieldErrors(Object err) {
    final message = apiError(err, '');
    if (message.isNotEmpty) return message;
    if (err is DioException) {
      final data = err.response?.data;
      if (data is Map && data.isNotEmpty) {
        return data.entries
            .map((e) => '${e.key}: ${e.value is List && (e.value as List).isNotEmpty ? (e.value as List).first : e.value}')
            .join('\n');
      }
    }
    return null;
  }

  InputDecoration _decoration({String? hint, bool enabled = true}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: _K.gray400),
        filled: true,
        fillColor: enabled ? _K.gray50 : _K.gray100,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _K.gray200),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _K.gray200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _K.indigo500.withValues(alpha: 0.6)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2, color: _K.gray500);
    final wide = MediaQuery.sizeOf(context).width >= 480;

    final nameField = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('DEVICE IDENTITY NAME *', style: label),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          autofocus: !_editing,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(fontSize: 14),
          decoration: _decoration(hint: 'e.g. Front Door Lobby'),
        ),
      ],
    );
    final codeField = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('SERIAL NUMBER (SN) *', style: label),
        const SizedBox(height: 8),
        TextField(
          controller: _code,
          enabled: !_editing,
          style: const TextStyle(fontSize: 14),
          decoration: _decoration(hint: 'e.g. SYZ8240000002', enabled: !_editing),
        ),
        const SizedBox(height: 4),
        Text(
          _editing ? 'UNMODIFIABLE HARDWARE SN' : 'MUST MATCH DEVICE LABEL EXACTLY',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 10, letterSpacing: 1, color: _K.gray600),
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.memory, size: 20, color: _K.indigo600),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              _editing ? 'Configure Hardware Node' : 'Provision Hardware Node',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _K.gray900),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Register physical biometrics scanning devices to your network.',
                        style: TextStyle(fontSize: 12, color: _K.gray500),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  style: IconButton.styleFrom(backgroundColor: _K.gray50),
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close, size: 20, color: _K.gray500),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: nameField), const SizedBox(width: 16), Expanded(child: codeField)],
              )
            else ...[
              nameField,
              const SizedBox(height: 16),
              codeField,
            ],
            const SizedBox(height: 20),
            const Text('NETWORK LOCATION (BRANCH) *', style: label),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: widget.branches.any((b) => b.id == _branchId) ? _branchId : null,
              isExpanded: true,
              hint: const Text('Select assigned branch...', style: TextStyle(fontSize: 14)),
              decoration: _decoration(),
              items: [for (final b in widget.branches) DropdownMenuItem(value: b.id, child: Text(b.name))],
              onChanged: (v) => setState(() => _branchId = v),
            ),
            const SizedBox(height: 24),

            // Punch method
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _K.gray50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _K.gray100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Attendance Punch Method', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _K.gray900)),
                          Text('How will this device record attendance?', style: TextStyle(fontSize: 12, color: _K.gray500)),
                        ],
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: _K.indigo600, visualDensity: VisualDensity.compact),
                        onPressed: () => showDialog<void>(context: context, builder: (_) => const _PunchMethodHelp()),
                        icon: const Icon(Icons.help_outline, size: 14),
                        label: const Text('What is this option for?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ModeCard(
                    selected: _punchMode == 'DEVICE_CONTROLLED',
                    title: 'Device controls IN / OUT',
                    text: 'Used when employees select IN or OUT directly on the device, or when using two devices '
                        'configured as IN and OUT on the devices themselves.',
                    onTap: () => setState(() => _punchMode = 'DEVICE_CONTROLLED'),
                  ),
                  const SizedBox(height: 10),
                  _ModeCard(
                    selected: _punchMode == 'SYSTEM_TOGGLE',
                    title: 'System determines IN / OUT',
                    text: 'Used for a single device that does not provide separate IN/OUT options. The system determines '
                        'punch direction chronologically (1st → IN, 2nd → OUT, 3rd → IN, 4th → OUT).',
                    onTap: () => setState(() => _punchMode = 'SYSTEM_TOGGLE'),
                    extra: Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _K.amber50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _K.amber200),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 14, color: _K.amber600),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                style: TextStyle(fontSize: 11, color: _K.amber800),
                                children: [
                                  TextSpan(text: 'Warning: ', style: TextStyle(fontWeight: FontWeight.w700)),
                                  TextSpan(
                                    text: 'A missing or unrecorded punch may cause subsequent punches to be '
                                        'interpreted in reverse order.',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ModeCard(
                    selected: _punchMode == 'SEPARATE_DEVICE',
                    title: 'Separate IN / OUT devices',
                    text: 'Used when two devices are required because the devices do not provide an IN/OUT selection. '
                        'Each device is dedicated to one punch direction.',
                    onTap: () => setState(() => _punchMode = 'SEPARATE_DEVICE'),
                    extra: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'This device will be used for:',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.gray700),
                          ),
                          RadioListTile<String>(
                            value: 'IN',
                            groupValue: _dedicated,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('IN (Check In)', style: TextStyle(fontSize: 13)),
                            onChanged: (v) => setState(() => _dedicated = v ?? 'IN'),
                          ),
                          RadioListTile<String>(
                            value: 'OUT',
                            groupValue: _dedicated,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('OUT (Check Out)', style: TextStyle(fontSize: 13)),
                            onChanged: (v) => setState(() => _dedicated = v ?? 'OUT'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ADMS setup instructions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _K.indigo50.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _K.indigo100),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📡 Direct ADMS Push Setup',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _K.indigo900)),
                  SizedBox(height: 6),
                  Text.rich(
                    TextSpan(
                      style: TextStyle(fontSize: 12, height: 1.5, color: _K.gray700),
                      children: [
                        TextSpan(text: 'This device connects '),
                        TextSpan(text: 'directly to the cloud server', style: TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: ' over HTTP/HTTPS.'),
                      ],
                    ),
                  ),
                  SizedBox(height: 8),
                  _Step(n: 1, text: 'On the physical device go to Cloud Server Settings / ADMS.'),
                  _Step(n: 2, text: 'Set Server Address to IP given by admin.'),
                  _Step(n: 3, text: 'Set Server Port to 443.'),
                  _Step(n: 4, text: 'Save and reboot — punches and biometrics will auto-sync live directly with the cloud.'),
                  SizedBox(height: 8),
                  Text(
                    'The Serial Number above must match the Serial Number printed on the device label exactly.',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.indigo700),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _K.red600)),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _K.gray600,
                      side: const BorderSide(color: _K.gray200),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Abort', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _K.indigo600,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_editing ? 'Commit Changes' : 'Initialize Link', style: const TextStyle(fontWeight: FontWeight.w700)),
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

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.selected, required this.title, required this.text, required this.onTap, this.extra});

  final bool selected;
  final String title;
  final String text;
  final VoidCallback onTap;

  /// Shown under the description while this option is selected.
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: selected ? _K.indigo600 : _K.gray200, width: selected ? 1.5 : 1),
    );
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? _K.indigo50.withValues(alpha: 0.4) : Colors.white,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? _K.indigo600 : Colors.transparent,
                    border: Border.all(color: selected ? _K.indigo600 : _K.gray300),
                  ),
                  child: selected
                      ? Center(
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _K.gray900)),
                      const SizedBox(height: 4),
                      Text(text, style: const TextStyle(fontSize: 12, height: 1.4, color: _K.gray600)),
                      if (selected && extra != null) extra!,
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

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});

  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 18, child: Text('$n.', style: const TextStyle(fontSize: 12, color: _K.gray700))),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, height: 1.4, color: _K.gray700))),
        ],
      ),
    );
  }
}

class _PunchMethodHelp extends StatelessWidget {
  const _PunchMethodHelp();

  @override
  Widget build(BuildContext context) {
    Widget section(String title, List<Widget> body) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _K.gray900)),
              const SizedBox(height: 6),
              ...body,
            ],
          ),
        );
    const p = TextStyle(fontSize: 13, height: 1.5, color: _K.gray600);

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 576),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.help_outline, color: _K.indigo600),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Understanding Punch Methods',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _K.gray900)),
                        Text('Choosing the right mode for your physical scanner setup',
                            style: TextStyle(fontSize: 12, color: _K.gray500)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              section('1. Device controls IN / OUT', const [
                Text(
                  'Use this option when the physical device has dedicated keys allowing employees to select IN or OUT '
                  'before scanning.',
                  style: p,
                ),
                SizedBox(height: 6),
                Text(
                  'This also covers setups with two devices where one device is permanently configured as IN and '
                  'another as OUT using the device’s internal hardware settings. Both setups rely on the state '
                  'provided directly by the scanner.',
                  style: p,
                ),
              ]),
              section('2. System determines IN / OUT', [
                const Text(
                  'Use this option for a single scanner that only records raw punches without any IN/OUT selection keys.',
                  style: p,
                ),
                const SizedBox(height: 6),
                const Text('The system determines direction automatically by chronological order:', style: p),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: _K.gray50, borderRadius: BorderRadius.circular(8)),
                  child: const Text(
                    '1st: IN  →  2nd: OUT  →  3rd: IN  →  4th: OUT',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600, color: _K.gray800),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Note: If an employee forgets to scan when leaving or entering, subsequent punches for that day may be '
                  'interpreted in reverse order.',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: _K.amber800),
                ),
              ]),
              section('3. Separate IN / OUT devices', const [
                Text(
                  'Use this option when you install two separate scanners (e.g. one at the entrance and one at the exit) '
                  'that do not support state selection on the devices themselves.',
                  style: p,
                ),
                SizedBox(height: 6),
                Text(
                  'You configure the role of the current device as either IN or OUT here. The second device is '
                  'provisioned separately using the same flow and configured with the opposite role.',
                  style: p,
                ),
              ]),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _K.indigo600),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}