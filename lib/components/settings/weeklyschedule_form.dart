// Port of features/admin/attendance/settings/WeeklyScheduleForm.tsx
// ("Working Hours": which days are worked and their start / end times).

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hrm_app/components/settings/settings_widgets.dart';

const _days = [
  ('mon', 'Monday'),
  ('tue', 'Tuesday'),
  ('wed', 'Wednesday'),
  ('thu', 'Thursday'),
  ('fri', 'Friday'),
  ('sat', 'Saturday'),
  ('sun', 'Sunday'),
];

class WeeklyScheduleForm extends StatefulWidget {
  const WeeklyScheduleForm({super.key, required this.initialData, required this.onSave, this.onReset});

  final Map<String, dynamic> initialData;
  final Future<bool> Function(Map<String, dynamic> data) onSave;
  final Future<void> Function()? onReset;

  @override
  State<WeeklyScheduleForm> createState() => _WeeklyScheduleFormState();
}

class _WeeklyScheduleFormState extends State<WeeklyScheduleForm> {
  late Map<String, dynamic> _data = _clean(widget.initialData);
  bool _saving = false;
  bool _saved = false;
  Timer? _savedTimer;

  /// Times as "HH:MM" (the server sends "HH:MM:SS").
  static Map<String, dynamic> _clean(Map<String, dynamic> d) {
    final out = {...d};
    for (final (key, _) in _days) {
      out['${key}_start'] = shortTime(out['${key}_start']);
      out['${key}_end'] = shortTime(out['${key}_end']);
    }
    return out;
  }

  @override
  void didUpdateWidget(covariant WeeklyScheduleForm old) {
    super.didUpdateWidget(old);
    if (!identical(old.initialData, widget.initialData)) _data = _clean(widget.initialData);
  }

  @override
  void dispose() {
    _savedTimer?.cancel();
    super.dispose();
  }

  bool _working(String day) => _data['${day}_working'] != false;

  Future<void> _copyMonday() async {
    if (!_working('mon')) {
      final ok = await confirmAction(
        context,
        title: 'Copy Monday Schedule',
        message: 'Monday is marked as OFF. This will mark all days as OFF for the entire week. Do you want to continue?',
        confirmLabel: 'Apply to All',
        danger: true,
      );
      if (!ok) return;
    }
    setState(() {
      for (final (key, _) in _days.skip(1)) {
        _data['${key}_working'] = _data['mon_working'];
        _data['${key}_start'] = _data['mon_start'];
        _data['${key}_end'] = _data['mon_end'];
      }
    });
  }

  Future<void> _save() async {
    final ok = await confirmAction(
      context,
      title: 'Save Schedule',
      message: 'Are you sure you want to save the weekly schedule? This will update working hours and status immediately.',
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
      title: 'Reset Schedule',
      message: "Are you sure you want to reset this branch's schedule to the company defaults? "
          'This will erase all custom working hours for this branch.',
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
      icon: Icons.calendar_today_outlined,
      title: 'Weekly Schedule',
      subtitle: 'Set working days and shift timings',
      actions: [
        TextButton.icon(
          style: TextButton.styleFrom(
            backgroundColor: SettingsColors.indigo50,
            foregroundColor: SettingsColors.indigo600,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _copyMonday,
          icon: const Icon(Icons.copy, size: 14),
          label: const Text('Copy Mon to All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ),
        if (widget.onReset != null) ResetToDefaultsButton(onPressed: _saving ? null : _reset),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (key, label) in _days) ...[
            _DayRow(
              label: label,
              working: _working(key),
              start: _data['${key}_start'] as String?,
              end: _data['${key}_end'] as String?,
              onWorking: (v) => setState(() => _data['${key}_working'] = v),
              onStart: (v) => setState(() => _data['${key}_start'] = v),
              onEnd: (v) => setState(() => _data['${key}_end'] = v),
            ),
            const SizedBox(height: 8),
          ],
          SettingsSaveRow(
            saving: _saving,
            saved: _saved,
            label: 'Save Schedule',
            savedText: 'Schedule saved',
            onSave: _save,
          ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.label,
    required this.working,
    required this.start,
    required this.end,
    required this.onWorking,
    required this.onStart,
    required this.onEnd,
  });

  final String label;
  final bool working;
  final String? start;
  final String? end;
  final ValueChanged<bool> onWorking;
  final ValueChanged<String> onStart;
  final ValueChanged<String> onEnd;

  @override
  Widget build(BuildContext context) {
    final day = Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: working ? SettingsColors.emerald500 : SettingsColors.red500,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SettingsColors.gray900)),
        ),
        Semantics(
          label: '$label working day',
          child: Switch(value: working, activeTrackColor: SettingsColors.emerald500, onChanged: onWorking),
        ),
      ],
    );

    final times = Row(
      children: [
        Expanded(child: TimeSetting(value: start, enabled: working, onChanged: onStart, placeholder: 'Start')),
        const SizedBox(width: 12),
        Expanded(child: TimeSetting(value: end, enabled: working, onChanged: onEnd, placeholder: 'End')),
      ],
    );

    return Opacity(
      opacity: working ? 1 : 0.75,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: working ? SettingsColors.gray50 : SettingsColors.red500.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: working ? SettingsColors.gray100 : SettingsColors.red500.withValues(alpha: 0.1)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 560
              ? Row(children: [SizedBox(width: 200, child: day), const SizedBox(width: 16), Expanded(child: times)])
              : Column(children: [day, const SizedBox(height: 8), times]),
        ),
      ),
    );
  }
}