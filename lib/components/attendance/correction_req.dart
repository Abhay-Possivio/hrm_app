// Port of components/attendance/CorrectionRequestModal.tsx:
// the employee asks HR to add a missing punch for one attendance day.
// Opens as a bottom sheet on phones.

import 'package:flutter/material.dart';

import 'package:hrm_app/services/hr_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';
import 'package:hrm_app/utils/toast.dart';

const _gray50 = Color(0xFFF9FAFB);
const _gray100 = Color(0xFFF3F4F6);
const _gray200 = Color(0xFFE5E7EB);
const _gray400 = Color(0xFF9CA3AF);
const _gray500 = Color(0xFF6B7280);
const _gray600 = Color(0xFF4B5563);
const _gray900 = Color(0xFF111827);
const _indigo600 = Color(0xFF4F46E5);
const _red600 = Color(0xFFDC2626);

/// Correction status badge colors (CORRECTION_STATUS_STYLE).
StatusStyle correctionStatusStyle(String status) => switch (status) {
      'PENDING' => StatusStyle.amber,
      'TL_APPROVED' => StatusStyle.sky,
      'APPROVED' => StatusStyle.emerald,
      'DECLINED' => StatusStyle.red,
      _ => const StatusStyle(Color(0xFFF9FAFB), Color(0xFF6B7280), Color(0xFFE5E7EB)),
    };

/// Correction status text (CORRECTION_STATUS_LABEL).
String? correctionStatusLabel(String status) => switch (status) {
      'PENDING' => 'Pending',
      'TL_APPROVED' => 'Waiting for HR',
      'APPROVED' => 'Approved',
      'DECLINED' => 'Declined',
      'CANCELLED' => 'Cancelled',
      _ => null,
    };

/// Opens the form. Returns true when a request was sent.
Future<bool> showCorrectionRequestSheet(
  BuildContext context, {
  required String date,
  String? suggestedType, // "IN" | "OUT"
  String? suggestedTime, // "HH:MM" or "HH:MM:SS"
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _CorrectionForm(date: date, suggestedType: suggestedType, suggestedTime: suggestedTime),
  );
  if (sent == true && context.mounted) showToast(context, 'Request sent for approval');
  return sent == true;
}

class _CorrectionForm extends StatefulWidget {
  const _CorrectionForm({required this.date, this.suggestedType, this.suggestedTime});

  final String date;
  final String? suggestedType;
  final String? suggestedTime;

  @override
  State<_CorrectionForm> createState() => _CorrectionFormState();
}

class _CorrectionFormState extends State<_CorrectionForm> {
  late String _punchType = widget.suggestedType ?? 'OUT';
  late String _time = _initialTime();
  bool _nextDay = false;
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  String _initialTime() {
    final t = widget.suggestedTime;
    if (t != null && t.length >= 5) return t.substring(0, 5);
    return widget.suggestedType == 'IN' ? '09:00' : '17:00';
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final parts = _time.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0),
    );
    if (picked != null) {
      setState(() => _time = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _submit() async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Please give a reason');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await correctionService.create(
        date: widget.date,
        punchType: _punchType,
        time: _time,
        nextDay: _nextDay,
        reason: _reason.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (mounted) setState(() => _error = apiError(err, 'Could not send the request'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = parseDateOnly(widget.date);
    const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _gray600);

    return Padding(
      // Keep the form above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: _gray200, borderRadius: BorderRadius.circular(999)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Request attendance correction',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _gray900),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close, color: _gray500),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Attendance day
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _gray50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _gray100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ATTENDANCE DAY',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1, color: _gray500),
                  ),
                  Text(
                    day != null ? formatEEEEddMMMyyyy(day) : widget.date,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _gray900),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Missing punch
            const Text('Missing punch', style: label),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final t in const ['IN', 'OUT']) ...[
                  if (t == 'OUT') const SizedBox(width: 8),
                  Expanded(child: _TypeButton(type: t, selected: _punchType == t, onTap: () => setState(() => _punchType = t))),
                ],
              ],
            ),
            const SizedBox(height: 20),

            // Time + next day
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Time', style: label),
                      const SizedBox(height: 4),
                      Semantics(
                        button: true,
                        label: 'Time, $_time',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _pickTime,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: _gray50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _gray200),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    fmtRawTime(_time),
                                    style: const TextStyle(fontSize: 14, color: _gray900),
                                  ),
                                ),
                                const Icon(Icons.schedule, size: 18, color: _gray400),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _nextDay = !_nextDay),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(value: _nextDay, onChanged: (v) => setState(() => _nextDay = v ?? false)),
                        const Flexible(
                          child: Text(
                            'After midnight (next day)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _gray600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Reason
            const Text('Reason', style: label),
            const SizedBox(height: 4),
            TextField(
              controller: _reason,
              maxLength: 1000,
              minLines: 3,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 14, color: _gray900),
              decoration: InputDecoration(
                hintText: 'e.g. Forgot to punch out, device was offline...',
                hintStyle: const TextStyle(fontSize: 14, color: _gray400),
                filled: true,
                fillColor: _gray50,
                contentPadding: const EdgeInsets.all(12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _gray200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _indigo600, width: 1.5),
                ),
              ),
            ),
            const Text(
              'Your team lead (if you have one) reviews the request first, then HR approves it. '
              'The punch is added to your attendance only after approval.',
              style: TextStyle(fontSize: 11, height: 1.5, color: _gray500),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(_error!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _red600)),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: _gray600,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _indigo600,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _saving ? null : _submit,
                  child: Text(_saving ? 'Sending...' : 'Send request', style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({required this.type, required this.selected, required this.onTap});

  final String type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isIn = type == 'IN';
    final (bg, border, fg) = !selected
        ? (Colors.white, _gray200, _gray500)
        : isIn
            ? (const Color(0xFFECFDF5), const Color(0xFF6EE7B7), const Color(0xFF047857))
            : (const Color(0xFFFFFBEB), const Color(0xFFFCD34D), const Color(0xFFB45309));

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                isIn ? 'Clock-in' : 'Clock-out',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}