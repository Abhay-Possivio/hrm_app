// Ports of ScheduledExceptionForm.tsx and ScheduledExceptionsList.tsx
// ("Date Overrides": holidays and special working days).

import 'package:flutter/material.dart';

import 'package:hrm_app/components/settings/settings_widgets.dart';
import 'package:hrm_app/services/attendsettings_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';
import 'package:hrm_app/utils/toast.dart';

typedef _C = SettingsColors;

class ScheduledExceptionForm extends StatefulWidget {
  const ScheduledExceptionForm({super.key, required this.branchId, required this.onSuccess, required this.onCancel});

  final int? branchId;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;

  @override
  State<ScheduledExceptionForm> createState() => _ScheduledExceptionFormState();
}

class _ScheduledExceptionFormState extends State<ScheduledExceptionForm> {
  DateTime? _date;
  final _reason = TextEditingController();
  bool _working = false;
  String? _start;
  String? _end;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_date == null || _reason.text.trim().isEmpty) {
      setState(() => _error = 'Choose a date and enter a reason.');
      return;
    }
    if (_working && (_start == null || _end == null)) {
      setState(() => _error = 'Enter the start and end time for the working day.');
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'Add Schedule Exception',
      message: 'Are you sure you want to add this schedule exception? This will apply the calendar override immediately.',
      confirmLabel: 'Save Exception',
    );
    if (!ok) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await attendanceSettingsService.createException(
        date: toDateKey(_date!),
        isWorkingDay: _working,
        startTime: _working ? _start : null,
        endTime: _working ? _end : null,
        reason: _reason.text.trim(),
        branchId: widget.branchId,
      );
      if (!mounted) return;
      showToast(context, 'Schedule exception saved successfully');
      widget.onSuccess();
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to save exception. Check if one already exists for this date.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 1, color: _C.gray400);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _C.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 20, color: _C.gray900),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Add Schedule Exception', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _C.gray900)),
              ),
              IconButton(tooltip: 'Close', onPressed: widget.onCancel, icon: const Icon(Icons.close, color: _C.gray500)),
            ],
          ),
          const SizedBox(height: 16),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _C.red50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _C.red200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: _C.red600),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(fontSize: 14, color: _C.red600))),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          SettingsFieldGrid(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('DATE', style: label),
                  const SizedBox(height: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
                    child: InputDecorator(
                      decoration: settingsInputDecoration().copyWith(
                        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16, color: _C.gray400),
                      ),
                      child: Text(
                        _date == null ? 'Pick a date' : formatDDMMMYYYY(_date!),
                        style: TextStyle(fontSize: 14, color: _date == null ? _C.gray400 : _C.gray900),
                      ),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('REASON', style: label),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _reason,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 14),
                    decoration: settingsInputDecoration().copyWith(hintText: 'e.g. National Holiday, Half-day'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _working,
            onChanged: (v) => setState(() => _working = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: _C.emerald500,
            title: const Text('Is Working Day?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _C.gray700)),
          ),
          if (_working)
            Row(
              children: [
                Expanded(child: TimeSetting(label: 'Start Time', value: _start, onChanged: (v) => setState(() => _start = v))),
                const SizedBox(width: 16),
                Expanded(child: TimeSetting(label: 'End Time', value: _end, onChanged: (v) => setState(() => _end = v))),
              ],
            ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: _C.gray100),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: _C.gray400),
                onPressed: widget.onCancel,
                child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _C.indigo500,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: Text(_saving ? 'Saving...' : 'Save Exception', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ScheduledExceptionsList extends StatefulWidget {
  const ScheduledExceptionsList({super.key, required this.exceptions, required this.onDelete});

  final List<ScheduledException> exceptions;
  final VoidCallback onDelete;

  @override
  State<ScheduledExceptionsList> createState() => _ScheduledExceptionsListState();
}

class _ScheduledExceptionsListState extends State<ScheduledExceptionsList> {
  int? _deleting;

  Future<void> _delete(ScheduledException ex) async {
    final ok = await confirmAction(
      context,
      title: 'Delete Exception',
      message: 'Are you sure you want to delete this schedule exception? This action cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!ok) return;
    setState(() => _deleting = ex.id);
    try {
      await attendanceSettingsService.deleteException(ex.id);
      if (!mounted) return;
      showToast(context, 'Schedule exception deleted successfully');
      widget.onDelete();
    } catch (_) {
      if (mounted) showToast(context, 'Failed to delete schedule exception', error: true);
    } finally {
      if (mounted) setState(() => _deleting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.exceptions.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 48),
        decoration: BoxDecoration(
          color: _C.gray50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.gray100),
        ),
        child: const Column(
          children: [
            Icon(Icons.event_busy_outlined, size: 32, color: _C.gray600),
            SizedBox(height: 12),
            Text('No scheduled exceptions found.', style: TextStyle(fontSize: 14, color: _C.gray500)),
          ],
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _C.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.gray200),
      ),
      child: Column(
        children: [
          for (var i = 0; i < widget.exceptions.length; i++)
            _row(widget.exceptions[i], divider: i < widget.exceptions.length - 1),
        ],
      ),
    );
  }

  Widget _row(ScheduledException ex, {required bool divider}) {
    final d = parseDateOnly(ex.date);
    final type = ex.isWorkingDay
        ? 'WORKING DAY${ex.startTime != null ? ' (${shortTime(ex.startTime)} - ${shortTime(ex.endTime) ?? ''})' : ''}'
        : 'HOLIDAY / OFF';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      decoration: BoxDecoration(border: divider ? const Border(bottom: BorderSide(color: _C.gray100)) : null),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      d != null ? '${formatMMM(d)} ${d.day}, ${d.year}' : ex.date,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _C.gray900),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: ex.isWorkingDay ? _C.emerald50 : _C.red50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: ex.isWorkingDay ? _C.emerald200 : _C.red200),
                      ),
                      child: Text(
                        type,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: ex.isWorkingDay ? _C.emerald600 : _C.red600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(ex.reason, style: const TextStyle(fontSize: 14, color: _C.gray500)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete exception',
            onPressed: _deleting == ex.id ? null : () => _delete(ex),
            icon: const Icon(Icons.delete_outline, size: 18, color: _C.gray500),
          ),
        ],
      ),
    );
  }
}