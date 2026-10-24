// Port of features/admin/attendance/settings/OvertimeSettingsForm.tsx
// ("Overtime Setup"). Saves into the same rules record as General Rules.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hrm_app/components/settings/settings_widgets.dart';

typedef _C = SettingsColors;

class OvertimeSettingsForm extends StatefulWidget {
  const OvertimeSettingsForm({super.key, required this.initialData, required this.onSave});

  /// The full rules map (overtime fields live there).
  final Map<String, dynamic> initialData;
  final Future<bool> Function(Map<String, dynamic> data) onSave;

  @override
  State<OvertimeSettingsForm> createState() => _OvertimeSettingsFormState();
}

class _OvertimeSettingsFormState extends State<OvertimeSettingsForm> {
  late Map<String, dynamic> _data = {...widget.initialData};
  bool _saving = false;
  bool _saved = false;
  Timer? _savedTimer;

  @override
  void didUpdateWidget(covariant OvertimeSettingsForm old) {
    super.didUpdateWidget(old);
    if (!identical(old.initialData, widget.initialData)) _data = {...widget.initialData};
  }

  @override
  void dispose() {
    _savedTimer?.cancel();
    super.dispose();
  }

  int _int(String key, int fallback) {
    final v = _data[key];
    return v is num ? v.round() : int.tryParse('$v') ?? fallback;
  }

  bool _bool(String key) => _data[key] == true;
  void _set(String key, dynamic value) => setState(() => _data[key] = value);

  /// Keeps a value between 0 and 720 minutes, like the web inputs.
  int _clamp720(int v) => v < 0 ? 0 : (v > 720 ? 720 : v);

  Future<void> _save() async {
    final ok = await confirmAction(
      context,
      title: 'Save Overtime Rules',
      message: 'Are you sure you want to save these overtime rules? This will update calculation logic immediately.',
      confirmLabel: 'Save',
    );
    if (!ok) return;
    setState(() => _saving = true);
    final success = await widget.onSave(_data);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = success;
    });
    _savedTimer?.cancel();
    if (success) {
      _savedTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _saved = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _bool('allow_overtime_compensation');
    final dailyTotal = (_data['ot_calculation_method'] ?? 'AFTER_SHIFT') == 'DAILY_TOTAL';
    final needsApproval = _bool('ot_requires_approval');

    return SettingsCard(
      icon: Icons.bolt,
      title: 'Overtime Settings',
      subtitle: 'Configure how extra hours are calculated and compensated',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Enable overtime
          _SwitchBox(
            title: 'Enable Overtime Compensation',
            description: 'Calculate extra minutes worked beyond the defined schedule',
            value: enabled,
            onChanged: (v) => _set('allow_overtime_compensation', v),
            boxed: true,
          ),

          if (enabled) ...[
            const SizedBox(height: 24),
            SettingsFieldGrid(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _CapsLabel('Calculation Method'),
                    DropdownButtonFormField<String>(
                      value: dailyTotal ? 'DAILY_TOTAL' : 'AFTER_SHIFT',
                      isExpanded: true,
                      decoration: settingsInputDecoration(),
                      items: const [
                        DropdownMenuItem(value: 'AFTER_SHIFT', child: Text('After Shift Hours', style: TextStyle(fontSize: 14))),
                        DropdownMenuItem(value: 'DAILY_TOTAL', child: Text('Total Daily Minutes', style: TextStyle(fontSize: 14))),
                      ],
                      onChanged: (v) => _set('ot_calculation_method', v ?? 'AFTER_SHIFT'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(Icons.info_outline, size: 12, color: _C.gray600),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            dailyTotal
                                ? 'Counts all work minutes today; OT starts after a threshold.'
                                : 'Counts time specifically before start or after end of shift.',
                            style: const TextStyle(fontSize: 11, color: _C.gray600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                NumberSetting(
                  key: ValueKey(dailyTotal),
                  label: dailyTotal ? 'DAILY OT THRESHOLD (MINUTES)' : 'MIN. OT EFFORT (MINUTES)',
                  value: dailyTotal ? _int('ot_daily_threshold_minutes', 0) : _int('ot_min_minutes', 0),
                  help: dailyTotal
                      ? 'Minutes of total work required before OT starts (e.g., 480 for 8hrs).'
                      : 'Minimum extra time worked to be recognized as overtime leg.',
                  onChanged: (v) => _set(dailyTotal ? 'ot_daily_threshold_minutes' : 'ot_min_minutes', v),
                ),
              ],
            ),
            if (!dailyTotal)
              CheckboxListTile(
                value: _bool('ot_include_early_in'),
                onChanged: (v) => _set('ot_include_early_in', v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: _C.indigo500,
                title: const Text('Include early check-ins as overtime', style: TextStyle(fontSize: 14, color: _C.gray700)),
              ),
          ],

          // Overtime approval
          const _Divider(),
          _SwitchBox(
            title: 'Require Overtime Approval',
            description: 'When on, calculated overtime is payable only after HR or the team lead approves it on the '
                'Overtime Approval page. The payroll export shows calculated, approved and pending overtime separately.',
            value: needsApproval,
            onChanged: (v) => _set('ot_requires_approval', v),
          ),
          if (needsApproval) ...[
            const SizedBox(height: 12),
            SettingsFieldGrid(
              children: [
                NumberSetting(
                  label: 'AUTO-APPROVE UP TO (MINUTES PER DAY)',
                  value: _int('ot_auto_approve_minutes', 0),
                  help: '0 = every overtime day needs a decision.',
                  onChanged: (v) => _set('ot_auto_approve_minutes', _clamp720(v)),
                ),
              ],
            ),
          ],

          // Punch capture windows (apply even when overtime is off)
          const _Divider(),
          const Text('Punch Capture Windows', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _C.gray900)),
          const SizedBox(height: 4),
          const Text(
            'Actual clock-outs are always kept. Punches up to the overtime window after shift end count as work and '
            'overtime. If an employee is still clocked in when the window closes, the day is marked "Missing '
            'clock-out" (hours count only until their last real clock-out) for HR to regularise.',
            style: TextStyle(fontSize: 11, height: 1.5, color: _C.gray500),
          ),
          const SizedBox(height: 12),
          SettingsFieldGrid(
            children: [
              NumberSetting(
                label: 'OVERTIME WINDOW AFTER SHIFT (MINUTES)',
                value: _int('ot_window_minutes', 300),
                help: 'Default 300 (5 hours): a 09:00–17:00 shift captures punches until 22:00.',
                onChanged: (v) => _set('ot_window_minutes', _clamp720(v)),
              ),
              NumberSetting(
                label: 'EARLY CHECK-IN WINDOW (MINUTES)',
                value: _int('early_in_window_minutes', 240),
                help: 'How long before shift start an IN punch still belongs to that shift (default 240).',
                onChanged: (v) => _set('early_in_window_minutes', _clamp720(v)),
              ),
            ],
          ),

          SettingsSaveRow(
            saving: _saving,
            saved: _saved,
            label: 'Save Overtime Rules',
            savedText: 'Settings updated successfully',
            onSave: _save,
          ),
        ],
      ),
    );
  }
}

class _SwitchBox extends StatelessWidget {
  const _SwitchBox({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.boxed = false,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _C.gray900)),
              const SizedBox(height: 4),
              Text(description, style: const TextStyle(fontSize: 12, height: 1.4, color: _C.gray500)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Semantics(label: title, child: Switch(value: value, activeTrackColor: _C.indigo500, onChanged: onChanged)),
      ],
    );
    if (!boxed) return row;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.gray200),
      ),
      child: row,
    );
  }
}

class _CapsLabel extends StatelessWidget {
  const _CapsLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: _C.gray500),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Divider(height: 1, color: _C.gray100),
    );
  }
}