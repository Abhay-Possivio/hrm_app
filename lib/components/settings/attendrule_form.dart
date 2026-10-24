// Port of features/admin/attendance/settings/AttendanceRuleForm.tsx
// ("General Rules": late grace, half-day threshold, lunch break).

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hrm_app/components/settings/settings_widgets.dart';

class AttendanceRuleForm extends StatefulWidget {
  const AttendanceRuleForm({
    super.key,
    required this.initialData,
    required this.onSave,
    this.onReset,
  });

  final Map<String, dynamic> initialData;

  /// Saves the full rules map; resolves true on success.
  final Future<bool> Function(Map<String, dynamic> data) onSave;

  /// Set for a branch override; resets the branch to the company defaults.
  final Future<void> Function()? onReset;

  @override
  State<AttendanceRuleForm> createState() => _AttendanceRuleFormState();
}

class _AttendanceRuleFormState extends State<AttendanceRuleForm> {
  late Map<String, dynamic> _data = {...widget.initialData};
  bool _saving = false;
  bool _saved = false;
  Timer? _savedTimer;

  @override
  void didUpdateWidget(covariant AttendanceRuleForm old) {
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

  void _set(String key, dynamic value) => setState(() => _data[key] = value);

  Future<void> _save() async {
    final ok = await confirmAction(
      context,
      title: 'Save Rules',
      message: 'Are you sure you want to save these attendance rules? This will apply the settings immediately.',
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

  Future<void> _reset() async {
    final ok = await confirmAction(
      context,
      title: 'Reset Rules',
      message: "Are you sure you want to reset this branch's rules to the company defaults? "
          'This will erase all custom settings for this branch.',
      confirmLabel: 'Reset to Defaults',
      danger: true,
    );
    if (!ok) return;
    setState(() => _saving = true);
    await widget.onReset!();
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      icon: Icons.schedule,
      title: 'Attendance Rules',
      subtitle: 'Configure late policies and break timings',
      actions: [
        if (widget.onReset != null) ResetToDefaultsButton(onPressed: _saving ? null : _reset),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SettingsSectionLabel('Lateness Policy'),
          SettingsFieldGrid(
            children: [
              NumberSetting(
                label: 'Late Grace Period (Minutes)',
                value: _int('late_grace_minutes', 0),
                help: 'Time allowed after shift start before marking late',
                onChanged: (v) => _set('late_grace_minutes', v),
              ),
              TimeSetting(
                label: 'Half Day Late Threshold Time',
                value: shortTime(_data['half_day_late_threshold_time']) ?? '11:00',
                help: 'Arrival time at or after which marks a half-day',
                onChanged: (v) => _set('half_day_late_threshold_time', v),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SettingsSectionLabel('Break Timings'),
          SettingsFieldGrid(
            columns: 3,
            children: [
              TimeSetting(
                label: 'Lunch Start Time',
                value: shortTime(_data['lunch_start_time']),
                onChanged: (v) => _set('lunch_start_time', v),
              ),
              TimeSetting(
                label: 'Lunch End Time',
                value: shortTime(_data['lunch_end_time']),
                onChanged: (v) => _set('lunch_end_time', v),
              ),
              NumberSetting(
                label: 'Duration (Minutes)',
                value: _int('lunch_duration_minutes', 60),
                onChanged: (v) => _set('lunch_duration_minutes', v),
              ),
            ],
          ),
          SettingsSaveRow(
            saving: _saving,
            saved: _saved,
            label: 'Save Changes',
            savedText: 'Changes saved successfully',
            onSave: _save,
          ),
        ],
      ),
    );
  }
}