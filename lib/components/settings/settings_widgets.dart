// Building blocks shared by the Configuration forms.

import 'package:flutter/material.dart';

class SettingsColors {
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
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const red50 = Color(0xFFFEF2F2);
  static const red200 = Color(0xFFFECACA);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
  static const amber500 = Color(0xFFF59E0B);
}

typedef _C = SettingsColors;

/// "09:00" from "09:00:00" (or null).
String? shortTime(dynamic v) {
  final s = v == null ? '' : '$v';
  if (s.isEmpty) return null;
  return s.length >= 5 ? s.substring(0, 5) : s;
}

/// Asks to confirm; resolves true when confirmed (ConfirmModal on the web).
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: danger ? _C.red600 : _C.indigo500),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// The light card each settings form sits in.
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: _C.gray900),
            const SizedBox(width: 8),
            Flexible(
              child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _C.gray900)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 14, color: _C.gray500)),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _C.gray50,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _C.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.start,
            spacing: 12,
            runSpacing: 12,
            children: [heading, if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions)],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}

class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _C.gray100))),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: _C.gray400),
      ),
    );
  }
}

/// Lays fields out in [columns] on wide screens and one per row on phones.
class SettingsFieldGrid extends StatelessWidget {
  const SettingsFieldGrid({super.key, required this.children, this.columns = 2});

  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 560 ? columns : 1;
        const gap = 20.0;
        final w = ((constraints.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: 16,
          children: [for (final c in children) SizedBox(width: w, child: c)],
        );
      },
    );
  }
}

InputDecoration settingsInputDecoration({String? suffix, bool enabled = true}) => InputDecoration(
      suffixText: suffix,
      filled: true,
      fillColor: enabled ? Colors.white : _C.gray100,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _C.gray200),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _C.gray100),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _C.indigo500),
      ),
    );

class _FieldShell extends StatelessWidget {
  const _FieldShell({required this.label, required this.child, this.help});

  final String label;
  final Widget child;
  final String? help;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: _C.gray500)),
        const SizedBox(height: 6),
        child,
        if (help != null) ...[
          const SizedBox(height: 4),
          Text(help!, style: const TextStyle(fontSize: 11, color: _C.gray600)),
        ],
      ],
    );
  }
}

/// Whole-number field. Keeps its own text so typing isn't interrupted.
class NumberSetting extends StatefulWidget {
  const NumberSetting({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.help,
    this.suffix,
    this.enabled = true,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final String? help;
  final String? suffix;
  final bool enabled;

  @override
  State<NumberSetting> createState() => _NumberSettingState();
}

class _NumberSettingState extends State<NumberSetting> {
  late final _controller = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(covariant NumberSetting old) {
    super.didUpdateWidget(old);
    // Follow outside changes (reload, reset) without fighting the keyboard.
    if (int.tryParse(_controller.text) != widget.value) _controller.text = '${widget.value}';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FieldShell(
      label: widget.label,
      help: widget.help,
      child: TextField(
        controller: _controller,
        enabled: widget.enabled,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 14, color: _C.gray900),
        decoration: settingsInputDecoration(suffix: widget.suffix, enabled: widget.enabled),
        onChanged: (v) => widget.onChanged(int.tryParse(v.trim()) ?? 0),
      ),
    );
  }
}

/// "HH:MM" time field that opens the time picker; null shows a placeholder.
class TimeSetting extends StatelessWidget {
  const TimeSetting({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.help,
    this.enabled = true,
    this.placeholder = '--:--',
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? help;
  final bool enabled;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final v = shortTime(value);
    final field = Semantics(
      button: true,
      enabled: enabled,
      label: '${label ?? 'Time'}, ${v ?? 'not set'}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: !enabled
            ? null
            : () async {
                final parts = (v ?? '09:00').split(':');
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0),
                );
                if (picked != null) {
                  onChanged('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
                }
              },
        child: InputDecorator(
          isEmpty: false,
          decoration: settingsInputDecoration(enabled: enabled).copyWith(
            suffixIcon: Icon(Icons.schedule, size: 16, color: enabled ? _C.gray400 : _C.gray200),
          ),
          child: Text(
            v ?? placeholder,
            style: TextStyle(fontSize: 14, color: !enabled ? _C.gray400 : (v == null ? _C.gray400 : _C.gray900)),
          ),
        ),
      ),
    );
    if (label == null) return field;
    return _FieldShell(label: label!, help: help, child: field);
  }
}

/// "Changes saved" note + the save button at the bottom of a form.
class SettingsSaveRow extends StatelessWidget {
  const SettingsSaveRow({
    super.key,
    required this.saving,
    required this.saved,
    required this.label,
    required this.savedText,
    required this.onSave,
  });

  final bool saving;
  final bool saved;
  final String label;
  final String savedText;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 16),
      margin: const EdgeInsets.only(top: 24),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _C.gray100))),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          if (saved)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check, size: 14, color: _C.emerald600),
                const SizedBox(width: 4),
                Text(savedText, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _C.emerald600)),
              ],
            ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _C.indigo500,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, size: 16),
            label: Text(saving ? 'Saving...' : label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Small red "Reset to Defaults" link for branch overrides.
class ResetToDefaultsButton extends StatelessWidget {
  const ResetToDefaultsButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(foregroundColor: _C.red600),
      onPressed: onPressed,
      child: const Text('Reset to Defaults', style: TextStyle(fontSize: 12, decoration: TextDecoration.underline)),
    );
  }
}