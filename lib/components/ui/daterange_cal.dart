// Based on components/ui/MultiDateCalendar.tsx.
//
// The web calendar lets you tick several dates, but only the earliest and
// latest are sent (start_date / end_date), and it immediately redraws with
// just those two. So here it's a plain range picker: tap the first day, then
// the last day; every day in between is included.

import 'package:flutter/material.dart';

import 'package:hrm_app/utils/attendance_format.dart';

const _gray100 = Color(0xFFF3F4F6);
const _gray200 = Color(0xFFE5E7EB);
const _gray400 = Color(0xFF9CA3AF);
const _gray500 = Color(0xFF6B7280);
const _gray800 = Color(0xFF1F2937);
const _gray900 = Color(0xFF111827);
const _emerald50 = Color(0xFFECFDF5);
const _emerald100 = Color(0xFFD1FAE5);
const _emerald500 = Color(0xFF10B981);
const _emerald600 = Color(0xFF059669);
const _emerald700 = Color(0xFF047857);
const _teal600 = Color(0xFF0D9488);

class DateRangeCalendar extends StatefulWidget {
  const DateRangeCalendar({super.key, required this.start, required this.end, required this.onChanged});

  /// "YYYY-MM-DD", or empty.
  final String start;
  final String end;

  /// Called with the new start and end ("" when cleared).
  final void Function(String start, String end) onChanged;

  @override
  State<DateRangeCalendar> createState() => _DateRangeCalendarState();
}

class _DateRangeCalendarState extends State<DateRangeCalendar> {
  late DateTime _month = _initialMonth();

  /// True after the first tap of a new range, waiting for the last day.
  bool _pickingEnd = false;

  DateTime _initialMonth() {
    final d = parseDateOnly(widget.start) ?? DateTime.now();
    return DateTime(d.year, d.month);
  }

  void _tap(DateTime day) {
    final key = toDateKey(day);
    if (!_pickingEnd || widget.start.isEmpty) {
      _pickingEnd = true;
      widget.onChanged(key, key);
      return;
    }
    _pickingEnd = false;
    if (key.compareTo(widget.start) < 0) {
      widget.onChanged(key, widget.start);
    } else {
      widget.onChanged(widget.start, key);
    }
  }

  void _today() {
    final key = toDateKey(DateTime.now());
    _pickingEnd = false;
    if (widget.start.isEmpty) {
      widget.onChanged(key, key);
    } else if (key.compareTo(widget.start) < 0) {
      widget.onChanged(key, widget.end.isEmpty ? widget.start : widget.end);
    } else if (key.compareTo(widget.end) > 0) {
      widget.onChanged(widget.start, key);
    }
    setState(() => _month = DateTime(DateTime.now().year, DateTime.now().month));
  }

  void _clear() {
    _pickingEnd = false;
    widget.onChanged('', '');
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.start;
    final end = widget.end.isEmpty ? start : widget.end;
    final todayKey = toDateKey(DateTime.now());
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = DateTime(_month.year, _month.month, 1).weekday % 7; // Sunday first

    final startDate = parseDateOnly(start);
    final endDate = parseDateOnly(end);
    final count = (startDate != null && endDate != null) ? endDate.difference(startDate).inDays + 1 : 0;

    final String summary;
    if (startDate == null) {
      summary = _pickingEnd ? 'Now tap the last day' : 'Tap the first day, then the last day';
    } else if (count <= 1) {
      summary = formatMMMddyyyy(startDate);
    } else {
      summary = '$count days (${formatMMM(startDate)} ${formatDD(startDate)} - ${formatMMM(endDate!)} ${formatDD(endDate)})';
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 384),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _gray200),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 8))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Month header
          Row(
            children: [
              const Icon(Icons.calendar_month_outlined, size: 20, color: _emerald600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatMMMMyyyy(_month),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _gray900),
                ),
              ),
              IconButton(
                tooltip: 'Previous month',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                icon: const Icon(Icons.chevron_left, size: 18, color: _gray400),
              ),
              IconButton(
                tooltip: 'Next month',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                icon: const Icon(Icons.chevron_right, size: 18, color: _gray400),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Weekday names
          Row(
            children: [
              for (final d in const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'])
                Expanded(
                  child: Center(
                    child: Text(
                      d.toUpperCase(),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: _gray400),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),

          // Days
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1.1,
            children: [
              for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
              for (var d = 1; d <= daysInMonth; d++)
                _DayCell(
                  day: DateTime(_month.year, _month.month, d),
                  isEdge: start.isNotEmpty &&
                      (toDateKey(DateTime(_month.year, _month.month, d)) == start ||
                          toDateKey(DateTime(_month.year, _month.month, d)) == end),
                  inRange: start.isNotEmpty &&
                      toDateKey(DateTime(_month.year, _month.month, d)).compareTo(start) > 0 &&
                      toDateKey(DateTime(_month.year, _month.month, d)).compareTo(end) < 0,
                  isToday: toDateKey(DateTime(_month.year, _month.month, d)) == todayKey,
                  onTap: () => _tap(DateTime(_month.year, _month.month, d)),
                ),
            ],
          ),

          // Summary
          const SizedBox(height: 12),
          const Divider(height: 1, color: _gray100),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SELECTED DATES ($count)',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: _gray400),
                    ),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        summary,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _emerald700),
                      ),
                    ),
                  ],
                ),
              ),
              _SmallButton(label: '+ Today', bg: _emerald50, fg: _emerald700, onTap: _today),
              if (start.isNotEmpty) ...[
                const SizedBox(width: 6),
                _SmallButton(label: 'Clear', icon: Icons.restart_alt, bg: _gray100, fg: _gray500, onTap: _clear),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isEdge,
    required this.inRange,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final bool isEdge;
  final bool inRange;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final BoxDecoration? decoration = isEdge
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
              colors: [_emerald600, _teal600],
            ),
            boxShadow: [BoxShadow(color: _emerald600.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))],
          )
        : inRange
            ? BoxDecoration(color: _emerald100, borderRadius: BorderRadius.circular(12))
            : null;

    return Semantics(
      button: true,
      selected: isEdge || inRange,
      label: formatEEEEddMMMyyyy(day),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          decoration: decoration,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isEdge ? FontWeight.w800 : FontWeight.w500,
                  color: isEdge ? Colors.white : (inRange ? _emerald700 : _gray800),
                ),
              ),
              if (isToday && !isEdge)
                Positioned(
                  bottom: 4,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(color: _emerald500, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.bg, required this.fg, required this.onTap, this.icon});

  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}