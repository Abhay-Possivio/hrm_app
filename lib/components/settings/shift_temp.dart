// Ports of ShiftTemplatesList.tsx and ShiftTemplateForm.tsx
// ("Shift Templates": reusable weekly working patterns that are assigned to
// employees on their profile page).

import 'package:flutter/material.dart';

import 'package:hrm_app/components/settings/settings_widgets.dart';
import 'package:hrm_app/services/shift_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';
import 'package:hrm_app/utils/toast.dart';

typedef _C = SettingsColors;

const _days = [
  ('mon', 'Monday', 'Mon'),
  ('tue', 'Tuesday', 'Tue'),
  ('wed', 'Wednesday', 'Wed'),
  ('thu', 'Thursday', 'Thu'),
  ('fri', 'Friday', 'Fri'),
  ('sat', 'Saturday', 'Sat'),
  ('sun', 'Sunday', 'Sun'),
];

class ShiftTemplatesList extends StatefulWidget {
  const ShiftTemplatesList({super.key, this.branchId});

  final int? branchId;

  @override
  State<ShiftTemplatesList> createState() => _ShiftTemplatesListState();
}

class _ShiftTemplatesListState extends State<ShiftTemplatesList> {
  List<ShiftTemplate> _templates = const [];
  bool _loading = true;

  /// The template being edited, or an empty map for a new one; null = list.
  Map<String, dynamic>? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ShiftTemplatesList old) {
    super.didUpdateWidget(old);
    if (old.branchId != widget.branchId) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await shiftService.getTemplates(branchId: widget.branchId);
      if (mounted) setState(() => _templates = list);
    } catch (_) {
      // Keep what's shown.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _save(Map<String, dynamic> data) async {
    try {
      final id = data['id'];
      if (id is num) {
        await shiftService.updateTemplate(id.toInt(), data);
        if (mounted) showToast(context, 'Shift template updated successfully');
      } else {
        await shiftService.createTemplate(data, branchId: widget.branchId);
        if (mounted) showToast(context, 'Shift template created successfully');
      }
      if (mounted) setState(() => _editing = null);
      _load();
      return true;
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to save shift template'), error: true);
      return false;
    }
  }

  Future<void> _delete(ShiftTemplate t) async {
    final ok = await confirmAction(
      context,
      title: 'Delete Shift Template',
      message: 'Are you sure you want to delete this shift template? This action cannot be undone.',
      confirmLabel: 'Delete Template',
      danger: true,
    );
    if (!ok) return;
    try {
      await shiftService.deleteTemplate(t.id);
      if (mounted) showToast(context, 'Shift template deleted successfully');
      _load();
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Failed to delete shift template'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = _editing;
    if (editing != null) {
      return ShiftTemplateForm(
        initialData: editing,
        onSave: _save,
        onCancel: () => setState(() => _editing = null),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 20, color: _C.indigo600),
                    SizedBox(width: 8),
                    Text('Shift Templates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _C.gray900)),
                  ],
                ),
                Text('Reusable working patterns for employees', style: TextStyle(fontSize: 14, color: _C.gray500)),
              ],
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _C.indigo500,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => setState(() => _editing = {}),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('CREATE TEMPLATE', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_loading)
          const SizedBox(height: 192, child: Center(child: CircularProgressIndicator(color: _C.indigo500)))
        else if (_templates.isEmpty)
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: _C.gray50,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _C.gray100),
            ),
            child: const Column(
              children: [
                CircleAvatar(radius: 28, backgroundColor: _C.gray100, child: Icon(Icons.calendar_today_outlined, color: _C.gray600)),
                SizedBox(height: 16),
                Text('No Shift Templates', style: TextStyle(fontWeight: FontWeight.w700, color: _C.gray900)),
                SizedBox(height: 8),
                Text(
                  'Create templates to quickly assign complex shift patterns to employees.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: _C.gray500),
                ),
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth >= 560 ? 2 : 1;
              const gap = 16.0;
              final w = ((constraints.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final t in _templates)
                    SizedBox(
                      width: w,
                      child: _TemplateCard(
                        template: t,
                        onEdit: () => setState(() => _editing = {...t.raw}),
                        onDelete: () => _delete(t),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onEdit, required this.onDelete});

  final ShiftTemplate template;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    // Hours of the first working weekday, as on the web.
    String hours = 'Flexible Schedule';
    for (final d in const ['mon', 'tue', 'wed', 'thu', 'fri']) {
      final day = template.days[d];
      if (day != null && day.working && day.start != null) {
        hours = '${fmtRawTime(day.start)} – ${fmtRawTime(day.end)}';
        break;
      }
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _C.gray50,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _C.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(template.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _C.gray900)),
              ),
              IconButton(
                tooltip: 'Edit template',
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16, color: _C.gray400),
              ),
              IconButton(
                tooltip: 'Delete template',
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 16, color: _C.gray400),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final (key, _, short) in _days)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      children: [
                        Text(
                          short.toUpperCase(),
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: _C.gray500),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: template.days[key]?.working == true ? _C.emerald500 : _C.gray700,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: _C.gray100),
          const SizedBox(height: 12),
          Text(hours, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _C.indigo600)),
        ],
      ),
    );
  }
}

class ShiftTemplateForm extends StatefulWidget {
  const ShiftTemplateForm({super.key, required this.initialData, required this.onSave, required this.onCancel});

  /// Empty for a new template.
  final Map<String, dynamic> initialData;
  final Future<bool> Function(Map<String, dynamic> data) onSave;
  final VoidCallback onCancel;

  @override
  State<ShiftTemplateForm> createState() => _ShiftTemplateFormState();
}

class _ShiftTemplateFormState extends State<ShiftTemplateForm> {
  late final Map<String, dynamic> _data = _initial();
  late final _name = TextEditingController(text: '${_data['name'] ?? ''}');
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.initialData['id'] != null;

  Map<String, dynamic> _initial() {
    // New templates: Mon–Fri 09:00–18:00, weekend off. (The web form only
    // pre-fills Monday's times, leaving Tue–Fri "working" with no times.)
    final data = <String, dynamic>{
      'name': '',
      for (final (key, _, _) in _days) ...{
        '${key}_working': key != 'sat' && key != 'sun',
        '${key}_start': (key != 'sat' && key != 'sun') ? '09:00' : null,
        '${key}_end': (key != 'sat' && key != 'sun') ? '18:00' : null,
      },
      ...widget.initialData,
    };
    for (final (key, _, _) in _days) {
      data['${key}_start'] = shortTime(data['${key}_start']);
      data['${key}_end'] = shortTime(data['${key}_end']);
    }
    return data;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool _working(String key) => _data['${key}_working'] != false;

  void _copyMonday() {
    setState(() {
      for (final (key, _, _) in _days.skip(1)) {
        _data['${key}_working'] = _data['mon_working'];
        _data['${key}_start'] = _data['mon_start'];
        _data['${key}_end'] = _data['mon_end'];
      }
    });
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the shift a name.');
      return;
    }
    final ok = await confirmAction(
      context,
      title: _isEdit ? 'Update Shift Template' : 'Create Shift Template',
      message: 'Are you sure you want to ${_isEdit ? 'update' : 'create'} this shift template? '
          'This will apply the shift timings immediately.',
      confirmLabel: _isEdit ? 'Update' : 'Create',
    );
    if (!ok) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    _data['name'] = _name.text.trim();
    await widget.onSave(_data);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _C.indigo500.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: Column(
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
                        const Icon(Icons.calendar_today_outlined, size: 20, color: _C.indigo600),
                        const SizedBox(width: 8),
                        Text(
                          _isEdit ? 'Edit Shift Template' : 'New Shift Template',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _C.gray900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('Define a reusable shift pattern', style: TextStyle(fontSize: 14, color: _C.gray500)),
                  ],
                ),
              ),
              IconButton(tooltip: 'Close', onPressed: widget.onCancel, icon: const Icon(Icons.close, color: _C.gray400)),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'SHIFT NAME',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: _C.gray500),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: settingsInputDecoration().copyWith(
              hintText: 'e.g. Night Shift, Security A, Office Hours',
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(fontSize: 13, color: _C.red600)),
          ],
          const SizedBox(height: 20),
          const Divider(height: 1, color: _C.gray100),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'WEEKLY SCHEDULE',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: _C.gray400),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: _C.indigo50,
                  foregroundColor: _C.indigo600,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _copyMonday,
                icon: const Icon(Icons.copy, size: 12),
                label: const Text('COPY MON TO ALL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final (key, label, _) in _days) ...[
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
          const SizedBox(height: 8),
          const Divider(height: 1, color: _C.gray100),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: _C.gray400),
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _C.indigo500,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check, size: 16),
                label: Text(_isEdit ? 'Update Template' : 'Create Template', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
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
          decoration: BoxDecoration(color: working ? _C.emerald500 : _C.gray700, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _C.gray900),
          ),
        ),
        Semantics(
          label: '$label working day',
          child: Transform.scale(
            scale: 0.85,
            child: Switch(value: working, activeTrackColor: _C.emerald500, onChanged: onWorking),
          ),
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
      opacity: working ? 1 : 0.6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: working ? _C.gray50 : _C.red500.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: working ? _C.gray200 : _C.red500.withValues(alpha: 0.1)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 560
              ? Row(children: [SizedBox(width: 220, child: day), const SizedBox(width: 16), Expanded(child: times)])
              : Column(children: [day, const SizedBox(height: 6), times]),
        ),
      ),
    );
  }
}