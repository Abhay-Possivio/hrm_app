// Port of features/admin/employees/EmployeeShiftForm.tsx
// ("Shift & Schedule" tab of an employee's profile): list, add, edit and
// remove shift assignments.

import 'package:flutter/material.dart';

import 'package:hrm_app/services/shift_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';
import 'package:hrm_app/utils/toast.dart';

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
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const orange500 = Color(0xFFF97316);
  static const orange600 = Color(0xFFEA580C);
  static const red50 = Color(0xFFFEF2F2);
  static const red600 = Color(0xFFDC2626);
}

class EmployeeShiftForm extends StatefulWidget {
  const EmployeeShiftForm({super.key, required this.employeeId, this.onSuccess});

  final int employeeId;

  /// Called after an assignment is added, changed or removed.
  final VoidCallback? onSuccess;

  @override
  State<EmployeeShiftForm> createState() => _EmployeeShiftFormState();
}

class _EmployeeShiftFormState extends State<EmployeeShiftForm> {
  List<ShiftTemplate> _templates = const [];
  List<EmployeeShift> _shifts = const [];
  bool _fetching = true;
  bool _saving = false;
  int? _editingId;

  int? _shiftId;
  DateTime _from = _today();
  DateTime? _to;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        shiftService.getTemplates(),
        shiftService.getEmployeeShifts(widget.employeeId),
      ]);
      if (!mounted) return;
      setState(() {
        _templates = results[0] as List<ShiftTemplate>;
        _shifts = results[1] as List<EmployeeShift>;
      });
    } catch (_) {
      // Leave the lists as they are.
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  void _edit(EmployeeShift s) {
    setState(() {
      _editingId = s.id;
      _shiftId = s.shift;
      _from = parseDateOnly(s.effectiveFrom) ?? _today();
      _to = parseDateOnly(s.effectiveTo);
    });
  }

  void _resetForm() {
    setState(() {
      _editingId = null;
      _shiftId = null;
      _from = _today();
      _to = null;
    });
  }

  Future<void> _remove(EmployeeShift s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove shift assignment?'),
        content: Text('"${s.shiftName}" will no longer apply to this employee.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _K.red600),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await shiftService.removeShift(widget.employeeId, s.id);
      await _load();
      widget.onSuccess?.call();
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Could not remove the shift'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submit() async {
    final shiftId = _shiftId;
    if (shiftId == null) return;
    setState(() => _saving = true);
    try {
      final from = toDateKey(_from);
      final to = _to == null ? null : toDateKey(_to!);
      final editing = _editingId;
      if (editing != null) {
        await shiftService.updateShift(widget.employeeId, editing, shift: shiftId, effectiveFrom: from, effectiveTo: to);
      } else {
        await shiftService.assignShift(widget.employeeId, shift: shiftId, effectiveFrom: from, effectiveTo: to);
      }
      await _load();
      _resetForm();
      widget.onSuccess?.call();
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Could not save the shift'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pick({required bool from}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: from ? _from : (_to ?? _from),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => from ? _from = picked : _to = picked);
  }

  @override
  Widget build(BuildContext context) {
    if (_fetching) {
      return const SizedBox(
        height: 128,
        child: Center(
          child: Text(
            'MAPPING SHIFT NODES...',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 3, color: _K.gray700),
          ),
        ),
      );
    }

    final editing = _editingId != null;
    const label = TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: _K.gray600);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_shifts.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'ACTIVE SHIFT ASSIGNMENTS',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: _K.gray500),
            ),
          ),
          for (final s in _shifts)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _K.indigo500.withValues(alpha: _editingId == s.id ? 0.2 : 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _K.indigo500.withValues(alpha: _editingId == s.id ? 0.5 : 0.1)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: _K.indigo50, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.calendar_today_outlined, size: 16, color: _K.indigo600),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.shiftName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _K.gray900)),
                        Text(
                          '${s.effectiveFrom} ${s.effectiveTo != null ? 'to ${s.effectiveTo}' : '(Permanent)'}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: _K.gray500),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit',
                    onPressed: _saving ? null : () => _edit(s),
                    icon: const Icon(Icons.edit_outlined, size: 16, color: _K.gray400),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    style: IconButton.styleFrom(hoverColor: _K.red50),
                    onPressed: _saving ? null : () => _remove(s),
                    icon: const Icon(Icons.delete_outline, size: 16, color: _K.gray500),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
        ],

        // New / edit assignment
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _K.gray50,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _K.gray100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: _K.orange600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      editing ? 'Edit Shift Assignment' : 'Assign New Shift',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _K.gray900),
                    ),
                  ),
                  if (editing)
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: _K.gray500),
                      onPressed: _resetForm,
                      icon: const Icon(Icons.close, size: 12),
                      label: const Text('CANCEL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('TEMPLATE', style: label),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                value: _templates.any((t) => t.id == _shiftId) ? _shiftId : null,
                isExpanded: true,
                hint: const Text('Select Shift Template', style: TextStyle(fontSize: 14)),
                decoration: _decoration(),
                items: [for (final t in _templates) DropdownMenuItem(value: t.id, child: Text(t.name))],
                onChanged: (v) => setState(() => _shiftId = v),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _DateBox(
                      label: 'START DATE',
                      value: formatDDMMMYYYY(_from),
                      onTap: () => _pick(from: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateBox(
                      label: 'END DATE (OPTIONAL)',
                      value: _to == null ? 'No end date' : formatDDMMMYYYY(_to!),
                      onTap: () => _pick(from: false),
                      onClear: _to == null ? null : () => setState(() => _to = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: editing ? _K.orange500 : _K.indigo500,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: (_saving || _shiftId == null) ? null : _submit,
                icon: _saving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check, size: 14),
                label: Text(
                  _saving ? 'PROCESSING...' : (editing ? 'UPDATE ASSIGNMENT' : 'COMMIT ASSIGNMENT'),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _decoration() => InputDecoration(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _K.gray200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _K.indigo500),
        ),
      );
}

class _DateBox extends StatelessWidget {
  const _DateBox({required this.label, required this.value, required this.onTap, this.onClear});

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: _K.gray600)),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.only(left: 14, top: 4, bottom: 4, right: 4),
            constraints: const BoxConstraints(minHeight: 46),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _K.gray200),
            ),
            child: Row(
              children: [
                Expanded(child: Text(value, style: const TextStyle(fontSize: 14, color: _K.gray900))),
                if (onClear != null)
                  IconButton(
                    tooltip: 'Clear end date',
                    visualDensity: VisualDensity.compact,
                    onPressed: onClear,
                    icon: const Icon(Icons.close, size: 16, color: _K.gray400),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Icon(Icons.calendar_today_outlined, size: 16, color: _K.gray400),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}