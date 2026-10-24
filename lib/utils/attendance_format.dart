// Port of utils/attendanceFormat.ts (grows as screens are ported).
//
// Punch and summary timestamps from the backend are wall-clock times recorded
// by the device ("2026-09-28T09:05:00", sometimes with a "+00:00" label).
// They're shown exactly as recorded, never converted through a timezone.

import 'dart:ui' show Color;

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _weekdaysFull = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsFull = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _two(int n) => n.toString().padLeft(2, '0');

// ── Times ───────────────────────────────────────────────────────────────────

RegExpMatch? _hhmm(String ts) =>
    RegExp(r'T(\d{2}):(\d{2})').firstMatch(ts) ?? RegExp(r'^(\d{2}):(\d{2})').firstMatch(ts);

/// "09:05 AM" from a wall-clock timestamp; [fallback] when empty.
String fmtWallTime(String? ts, {String fallback = '--:--'}) {
  if (ts == null || ts.isEmpty) return fallback;
  final m = _hhmm(ts);
  if (m == null) return fallback;
  final h = int.parse(m.group(1)!);
  final period = h >= 12 ? 'PM' : 'AM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '${_two(h12)}:${m.group(2)} $period';
}

/// "09:05" (24-hour) from a wall-clock timestamp.
String fmtWallTime24(String? ts, {String fallback = '--:--'}) {
  if (ts == null || ts.isEmpty) return fallback;
  final m = _hhmm(ts);
  return m == null ? fallback : '${m.group(1)}:${m.group(2)}';
}

/// "9:00 AM" from a raw "HH:MM:SS" time (backend TimeField).
String fmtRawTime(String? raw, {String fallback = '--'}) {
  if (raw == null || raw.isEmpty) return fallback;
  final parts = raw.split(':');
  if (parts.length < 2) return raw;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return raw;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${_two(m)} ${h >= 12 ? 'PM' : 'AM'}';
}

/// "7h 05m" (always with hours, "0h 00m" for none).
String fmtDuration(int minutes) {
  if (minutes <= 0) return '0h 00m';
  return '${minutes ~/ 60}h ${_two(minutes % 60)}m';
}

/// "7h 05m", or "45m" under an hour.
String fmtMinutes(num? mins) {
  final rounded = (mins ?? 0).round();
  final total = rounded < 0 ? 0 : rounded;
  final h = total ~/ 60;
  final m = total % 60;
  return h == 0 ? '${m}m' : '${h}h ${_two(m)}m';
}

/// "2026-09-28" from a wall-clock timestamp, or null.
String? wallDate(String? ts) {
  if (ts == null) return null;
  return RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(ts)?.group(1);
}

// ── Dates ───────────────────────────────────────────────────────────────────

/// "YYYY-MM-DD" as a local calendar date (no timezone shift).
DateTime? parseDateOnly(String? value) {
  if (value == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
  if (m == null) return null;
  return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}

/// Local calendar date to "YYYY-MM-DD".
String toDateKey(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

// date-fns patterns used by the screens
String formatEEE(DateTime d) => _weekdays[d.weekday - 1]; // "Mon"
String formatMMM(DateTime d) => _months[d.month - 1]; // "Jan"
String formatMMMM(DateTime d) => _monthsFull[d.month - 1]; // "January"
String formatDD(DateTime d) => _two(d.day); // "05"
String formatDMMM(DateTime d) => '${d.day} ${formatMMM(d)}'; // "5 Jan"
String formatDDMMM(DateTime d) => '${_two(d.day)} ${formatMMM(d)}'; // "05 Jan"
String formatDDMMMYYYY(DateTime d) => '${formatDDMMM(d)} ${d.year}'; // "05 Jan 2026"
String formatEEEDDMMM(DateTime d) => '${formatEEE(d)}, ${formatDDMMM(d)}'; // "Mon, 05 Jan"
String formatEEEMMMd(DateTime d) => '${formatEEE(d)}, ${formatMMM(d)} ${d.day}'; // "Mon, Jan 5"
String formatMMMMd(DateTime d) => '${formatMMMM(d)} ${d.day}'; // "January 5"
String formatMMMMyyyy(DateTime d) => '${formatMMMM(d)} ${d.year}'; // "January 2026"
String formatMMMddyyyy(DateTime d) => '${formatMMM(d)} ${_two(d.day)}, ${d.year}'; // "Jan 05, 2026"
String formatEEEE(DateTime d) => _weekdaysFull[d.weekday - 1]; // "Monday"
String formatEEEEddMMMyyyy(DateTime d) => '${formatEEEE(d)}, ${formatDDMMMYYYY(d)}'; // "Monday, 05 Jan 2026"
String formatYyyyMM(DateTime d) => '${d.year}_${_two(d.month)}'; // "2026_01"

// ── Day and punch status ────────────────────────────────────────────────────

/// Badge colors (the Tailwind `bg-… text-… border-…` classes).
class StatusStyle {
  const StatusStyle(this.bg, this.fg, this.border);

  final Color bg;
  final Color fg;
  final Color border;

  static const emerald = StatusStyle(Color(0xFFECFDF5), Color(0xFF047857), Color(0xFFA7F3D0));
  static const amber = StatusStyle(Color(0xFFFFFBEB), Color(0xFFB45309), Color(0xFFFDE68A));
  static const sky = StatusStyle(Color(0xFFF0F9FF), Color(0xFF0369A1), Color(0xFFBAE6FD));
  static const red = StatusStyle(Color(0xFFFEF2F2), Color(0xFFB91C1C), Color(0xFFFECACA));
  static const violet = StatusStyle(Color(0xFFF5F3FF), Color(0xFF6D28D9), Color(0xFFDDD6FE));
  static const gray = StatusStyle(Color(0xFFF9FAFB), Color(0xFF4B5563), Color(0xFFE5E7EB));
  static const slate = StatusStyle(Color(0xFFF8FAFC), Color(0xFF475569), Color(0xFFE2E8F0));
}

class StatusMeta {
  const StatusMeta(this.label, this.style, {this.hint});

  final String label;
  final StatusStyle style;
  final String? hint;
}

const presentDayTypes = ['FULL_DAY', 'HALF_DAY', 'PRESENT'];

bool isPresentDay(String? dayType) => dayType != null && presentDayTypes.contains(dayType);

const _dayTypeMeta = {
  'FULL_DAY': StatusMeta('Full Day', StatusStyle.emerald),
  'HALF_DAY': StatusMeta('Half Day', StatusStyle.amber),
  'PRESENT': StatusMeta('Present', StatusStyle.sky),
  'ABSENT': StatusMeta('Absent', StatusStyle.red),
  'ON_LEAVE': StatusMeta('On Leave', StatusStyle.violet),
  'OFF_DAY': StatusMeta('Off Day', StatusStyle.gray),
  'NOT_STARTED': StatusMeta('Shift Not Started', StatusStyle.slate),
};

StatusMeta dayTypeMeta(String? dayType) =>
    _dayTypeMeta[dayType ?? ''] ?? StatusMeta(dayType ?? '—', StatusStyle.gray);

const _missingOutHint = 'No clock-out before the overtime window closed. Hours are counted only until '
    'the last real clock-out; add the clock-out to regularise.';

/// Last-punch outcomes that need attention; COMPLETE / NO_PUNCH have none.
const _punchStatusMeta = {
  'IN_PROGRESS': StatusMeta('Working', StatusStyle.emerald,
      hint: 'Clocked in; the shift is still open (overtime window has not ended).'),
  'MISSING_OUT': StatusMeta('Missing clock-out', StatusStyle.red, hint: _missingOutHint),
  'LAST_IN_AS_OUT': StatusMeta('Out recorded as IN', StatusStyle.amber,
      hint: 'The final punch was recorded as IN near the end of the shift and was used as the clock-out.'),
  'MISSED_BREAK_PUNCH': StatusMeta('Missed break punch', StatusStyle.amber,
      hint: 'A break punch is missing; the first punch was used as arrival and the last as departure.'),
};

StatusMeta? punchStatusMeta(String? status) => status == null ? null : _punchStatusMeta[status];

/// One status for a day, combining the day classification with the live punch
/// state: while the shift runs an employee is "Working" or "Out"; afterwards
/// the day result (Full Day / Half Day / ...), or "Missing Out".
StatusMeta attendanceStatus(String? dayType, String? punchStatus, [String? leaveName]) {
  if (dayType == 'ON_LEAVE') {
    return StatusMeta(leaveName ?? 'On Leave', StatusStyle.violet, hint: 'Approved leave');
  }
  switch (punchStatus) {
    case 'IN_PROGRESS':
      return const StatusMeta('Working', StatusStyle.emerald, hint: 'Clocked in; the shift is still running.');
    case 'STEPPED_OUT':
      return const StatusMeta('Out', StatusStyle.slate, hint: 'Clocked out during the shift; may still return.');
    case 'MISSING_OUT':
      return const StatusMeta('Missing Out', StatusStyle.red, hint: _missingOutHint);
  }
  final meta = dayTypeMeta(dayType);
  return StatusMeta(meta.label, meta.style, hint: punchStatusMeta(punchStatus)?.hint);
}

/// Last-out text: the real final clock-out, or why there isn't one.
String lastOutText({String? lastOut, String? punchStatus}) {
  if (lastOut != null && lastOut.isNotEmpty) return fmtWallTime(lastOut);
  if (punchStatus == 'IN_PROGRESS') return 'Working';
  if (punchStatus == 'MISSING_OUT') return 'Missing';
  return '--:--';
}

// ── Punches ─────────────────────────────────────────────────────────────────
// punchType is the direction the attendance engine used; ignoreReason is set
// when a punch was not counted (after the overtime window, unpaired, or
// replaced by a manual correction).

const _ignoreLabels = {
  'replaced': 'Replaced',
  'outside_window': 'After window',
  'unpaired': 'Unpaired',
};

bool isIgnoredPunch(String? ignoreReason) => ignoreReason != null && ignoreReason.isNotEmpty;

/// "IN" / "OUT", or why the punch was not counted.
String punchLabel(String punchType, String? ignoreReason) {
  if (isIgnoredPunch(ignoreReason)) return _ignoreLabels[ignoreReason] ?? 'Ignored';
  if (punchType == 'CHECK_IN') return 'IN';
  if (punchType == 'CHECK_OUT') return 'OUT';
  return punchType;
}

String? punchLabelHint(String? ignoreReason) => switch (ignoreReason) {
      'replaced' => 'Replaced by a manual correction at the same time — not counted',
      'outside_window' => 'After the overtime window closed — not counted',
      'unpaired' => 'Could not be paired with another punch — not counted',
      _ => null,
    };

/// Counted IN punch (ignored punches are neither IN nor OUT).
bool isInPunch(String punchType, String? ignoreReason) =>
    !isIgnoredPunch(ignoreReason) && (punchType == 'IN' || punchType == 'CHECK_IN');

/// The latest punch that was actually counted.
T? lastCountedPunch<T>(List<T> punches, String? Function(T) ignoreReasonOf) {
  for (var i = punches.length - 1; i >= 0; i--) {
    if (!isIgnoredPunch(ignoreReasonOf(punches[i]))) return punches[i];
  }
  return null;
}