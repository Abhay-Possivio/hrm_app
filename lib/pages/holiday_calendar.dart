// Port of features/admin/holidays/HolidayCalendarPage.tsx ("Holiday Calendar"):
// a year of month grids with holidays marked, the list of the year's
// holidays, adding a holiday (single day or range), removing one, and copying
// the yearly ones to next year. Company-wide or per branch.
//
// Layout (compact):
//   Header: title · how-it-works toggle · scope · year stepper · Add holiday
//   [load-error banner] [how holidays work]
//   Summary strip: holiday count · next holiday · legend
//   Month grids (3 / 2 / 1 across) | Holiday list + Next year (side column on xl)
//   Tapping a holiday opens its details (remove from there); tapping any other
//   day opens the add form for that date.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrm_app/app/session.dart';
import 'package:hrm_app/auth/auth_store.dart';
import 'package:hrm_app/services/branch_service.dart';
import 'package:hrm_app/services/hr_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';
import 'package:hrm_app/utils/toast.dart';

// ── Design tokens ───────────────────────────────────────────────────────────

class _K {
  static const gray50 = Color(0xFFF9FAFB);
  static const gray100 = Color(0xFFF3F4F6);
  static const gray200 = Color(0xFFE5E7EB);
  static const gray300 = Color(0xFFD1D5DB);
  static const gray400 = Color(0xFF9CA3AF);
  static const gray500 = Color(0xFF6B7280);
  static const gray600 = Color(0xFF4B5563);
  static const gray700 = Color(0xFF374151);
  static const gray900 = Color(0xFF111827);
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo200 = Color(0xFFC7D2FE);
  static const indigo400 = Color(0xFF818CF8);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const indigo700 = Color(0xFF4338CA);
  static const indigo800 = Color(0xFF3730A3);
  static const rose50 = Color(0xFFFFF1F2);
  static const rose100 = Color(0xFFFFE4E6);
  static const rose200 = Color(0xFFFECDD3);
  static const rose500 = Color(0xFFF43F5E);
  static const rose600 = Color(0xFFE11D48);
  static const sky100 = Color(0xFFE0F2FE);
  static const sky700 = Color(0xFF0369A1);
  static const red50 = Color(0xFFFEF2F2);
  static const red200 = Color(0xFFFECACA);
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);
}

/// A tinted color set: soft background, border, and foreground.
class _Tone {
  const _Tone(this.bg, this.border, this.fg);

  final Color bg;
  final Color border;
  final Color fg;
}

const _rose = _Tone(_K.rose50, _K.rose100, _K.rose600);
const _indigo = _Tone(_K.indigo50, _K.indigo100, _K.indigo600);

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3, color: _K.gray900);
  static const subtitle = TextStyle(fontSize: 12, height: 1.3, color: _K.gray500);
  static const fieldLabel = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.gray700);
  static const caption = TextStyle(fontSize: 11, height: 1.3, color: _K.gray400);
}

const _cardRadius = 16.0;
const _divider = Divider(height: 1, thickness: 1, color: _K.gray100);
const _weekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Calendar days from today to [d] (DST-safe; negative in the past).
int _daysFromToday(DateTime d) {
  final t = _today();
  return DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(t.year, t.month, t.day)).inDays;
}

String _whenLabel(int days) => switch (days) {
      0 => 'today',
      1 => 'tomorrow',
      _ => 'in $days days',
    };

String _holidayName(Holiday h) => h.reason.isNotEmpty ? h.reason : (h.isWorkingDay ? 'Special working day' : 'Holiday');

// ── Page ────────────────────────────────────────────────────────────────────

class HolidayCalendarPage extends StatefulWidget {
  const HolidayCalendarPage({super.key});

  @override
  State<HolidayCalendarPage> createState() => _HolidayCalendarPageState();
}

class _HolidayCalendarPageState extends State<HolidayCalendarPage> {
  int _year = DateTime.now().year;
  List<BranchOption> _branches = const [];
  int? _branchId; // null = company-wide (company admins only)
  bool _companyAdmin = false;
  bool _ready = false;
  List<Holiday> _items = const [];
  bool _loading = false;
  bool _copying = false;
  bool _showHelp = false;
  String? _error;
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final user = context.read<AuthStore>().user ?? const <String, dynamic>{};
    _companyAdmin = user.isCompanyAdmin || user.isSuperuser;
    try {
      final branches = await branchService.fetchBranchOptions();
      if (!mounted) return;
      setState(() {
        _branches = branches;
        if (!_companyAdmin && branches.isNotEmpty) _branchId = branches.first.id;
      });
    } catch (_) {
      // No branch list; company admins can still use the company-wide view.
    }
    if (!mounted) return;
    setState(() => _ready = true);
    _load();
  }

  Future<void> _load() async {
    if (!_ready || (!_companyAdmin && _branchId == null)) return;
    final id = ++_loadId;
    setState(() => _loading = true);
    try {
      final list = await holidayService.list(_year, branchId: _branchId);
      if (mounted && id == _loadId) {
        setState(() {
          _items = list;
          _error = null;
        });
      }
    } catch (err) {
      if (mounted && id == _loadId) {
        setState(() {
          _items = const [];
          _error = apiError(err, 'Could not load holidays');
        });
      }
    } finally {
      if (mounted && id == _loadId) setState(() => _loading = false);
    }
  }

  void _setYear(int year) {
    if (year == _year) return;
    setState(() => _year = year);
    _load();
  }

  String get _scopeName {
    if (_branchId == null) return 'all branches';
    for (final b in _branches) {
      if (b.id == _branchId) return b.name;
    }
    return 'this branch';
  }

  Future<void> _openForm(String date) async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddHolidayForm(initialDate: date, branchId: _branchId, scopeName: _scopeName),
    );
    if (added == true) _load();
  }

  void _pick(String key, Holiday? h) {
    if (h != null && !h.isWorkingDay) {
      _showHoliday(h);
      return;
    }
    _openForm(key);
  }

  Future<void> _showHoliday(Holiday h) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (_) => _HolidayDialog(holiday: h, scopeName: _scopeName),
    );
    if (remove == true) _remove(h, confirmed: false);
  }

  Future<void> _remove(Holiday h, {bool confirmed = false}) async {
    final d = parseDateOnly(h.date);
    final ok = confirmed ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text(
                  'Remove holiday?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900),
                ),
                content: Text(
                  '"${_holidayName(h)}" on ${d != null ? formatEEEEddMMMyyyy(d) : h.date} will become a normal '
                  'working day${_branchId == null ? ' in every branch' : ' for $_scopeName'}. '
                  'Attendance for that day is recalculated.',
                  style: const TextStyle(fontSize: 13, height: 1.45, color: _K.gray600),
                ),
                actions: [
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: _K.gray600),
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _K.red600,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ) ==
            true;
    if (!ok) return;
    try {
      await holidayService.remove(h.id, branchId: _branchId);
      if (mounted) showToast(context, '"${_holidayName(h)}" removed');
      _load();
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Could not remove'), error: true);
    }
  }

  Future<void> _copyToNextYear(int yearlyCount) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Copy to ${_year + 1}?',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900),
        ),
        content: Text(
          '$yearlyCount yearly holiday${yearlyCount == 1 ? '' : 's'} will be added to ${_year + 1} for $_scopeName. '
          'Dates that already exist are skipped.',
          style: const TextStyle(fontSize: 13, height: 1.45, color: _K.gray600),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _K.gray600),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _K.indigo600,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Copy'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _copying = true);
    try {
      final res = await holidayService.copyYear(_year, _year + 1, branchId: _branchId);
      if (!mounted) return;
      showToast(
        context,
        '${res.created} holiday${res.created == 1 ? '' : 's'} copied to ${_year + 1}'
        '${res.skipped > 0 ? ', ${res.skipped} skipped' : ''}',
      );
      _setYear(_year + 1);
    } catch (err) {
      if (mounted) showToast(context, apiError(err, 'Copy failed'), error: true);
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const _PageSkeleton();

    final byDate = {for (final h in _items) h.date: h};
    final holidays = _items.where((h) => !h.isWorkingDay).toList()..sort((a, b) => a.date.compareTo(b.date));
    final todayKey = toDateKey(DateTime.now());
    final upcoming = holidays.where((h) => h.date.compareTo(todayKey) >= 0).toList();
    final yearlyCount = holidays.where((h) => h.repeatsYearly).length;
    final noScope = !_companyAdmin && _branchId == null;

    return RefreshIndicator(
      color: _K.indigo600,
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sm = width >= 640;
          final lg = width >= 1024;
          final xl = width >= 1280;
          final gap = sm ? 20.0 : 16.0;

          final months = AnimatedOpacity(
            opacity: _loading ? 0.55 : 1,
            duration: const Duration(milliseconds: 150),
            child: _Grid(
              columns: lg ? 3 : (width >= 360 ? 2 : 1),
              gap: 12,
              children: [
                for (var m = 1; m <= 12; m++)
                  _MonthGrid(year: _year, month: m, byDate: byDate, todayKey: todayKey, onPick: _pick),
              ],
            ),
          );

          final side = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HolidayList(
                year: _year,
                holidays: holidays,
                todayKey: todayKey,
                onOpen: _showHoliday,
                onRemove: _remove,
                onAdd: () => _openForm(_year == DateTime.now().year ? todayKey : '$_year-01-01'),
              ),
              const SizedBox(height: 12),
              _NextYearCard(
                year: _year,
                yearlyCount: yearlyCount,
                copying: _copying,
                onCopy: () => _copyToNextYear(yearlyCount),
              ),
            ],
          );

          final sections = <Widget>[
            _header(wide: lg),
            if (_showHelp)
              const _Banner(
                tone: _Tone(_K.indigo50, _K.indigo200, _K.indigo800),
                icon: Icons.info_outline_rounded,
                child: Text(
                  'Holidays are off days for everyone in scope: nobody is marked absent, and work on a holiday '
                  'counts as overtime. Tap a date to add a holiday, or tap a holiday to see or remove it.',
                ),
              ),
            if (_error != null)
              _Banner(
                tone: const _Tone(_K.red50, _K.red200, _K.red700),
                icon: Icons.error_outline_rounded,
                actionLabel: 'Retry',
                onAction: _load,
                child: Text(_error!),
              ),
            if (noScope)
              const _Banner(
                tone: _Tone(_K.gray50, _K.gray200, _K.gray600),
                icon: Icons.apartment_rounded,
                child: Text('No branch is assigned to your account, so there is no calendar to show.'),
              )
            else ...[
              _SummaryStrip(
                year: _year,
                count: holidays.length,
                next: _year == DateTime.now().year && upcoming.isNotEmpty ? upcoming.first : null,
                loading: _loading,
              ),
              if (xl)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: months), SizedBox(width: gap), SizedBox(width: 340, child: side)],
                )
              else ...[
                months,
                side,
              ],
            ],
          ];

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(sm ? 24 : 16),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < sections.length; i++) ...[
                        if (i > 0) SizedBox(height: sections[i] is _SummaryStrip ? 12 : gap),
                        sections[i],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header({required bool wide}) {
    final thisYear = DateTime.now().year;

    final title = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _IconBox(icon: Icons.event_available_outlined, tone: _rose, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Holiday calendar',
                  style: TextStyle(
                    fontSize: wide ? 22 : 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.25,
                    color: _K.gray900,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Off days for everyone in scope.', style: _T.subtitle),
                  _LinkButton(
                    label: _showHelp ? 'Hide details' : 'How holidays work',
                    onTap: () => setState(() => _showHelp = !_showHelp),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final scope = Container(
      height: 40,
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _K.gray200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.apartment_rounded, size: 16, color: _K.gray400),
          const SizedBox(width: 6),
          Flexible(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                value: _branchId,
                isDense: true,
                borderRadius: BorderRadius.circular(10),
                icon: const Icon(Icons.expand_more_rounded, size: 18, color: _K.gray500),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray700),
                items: [
                  if (_companyAdmin) const DropdownMenuItem<int?>(value: null, child: Text('All branches')),
                  for (final b in _branches)
                    DropdownMenuItem<int?>(value: b.id, child: Text(b.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  if (v == _branchId) return;
                  setState(() => _branchId = v);
                  _load();
                },
              ),
            ),
          ),
        ],
      ),
    );

    final year = Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _K.gray200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Previous year',
            visualDensity: VisualDensity.compact,
            onPressed: () => _setYear(_year - 1),
            icon: const Icon(Icons.chevron_left_rounded, size: 20, color: _K.gray500),
          ),
          Semantics(
            label: 'Year $_year',
            child: Text(
              '$_year',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _K.gray900, fontFeatures: _T.tabular),
            ),
          ),
          IconButton(
            tooltip: 'Next year',
            visualDensity: VisualDensity.compact,
            onPressed: () => _setYear(_year + 1),
            icon: const Icon(Icons.chevron_right_rounded, size: 20, color: _K.gray500),
          ),
          if (_year != thisYear) ...[
            Container(width: 1, height: 20, color: _K.gray200),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: _K.indigo600,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              onPressed: () => _setYear(thisYear),
              child: const Text('This year'),
            ),
          ],
        ],
      ),
    );

    final add = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: _K.indigo600,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      onPressed: (!_companyAdmin && _branchId == null)
          ? null
          : () => _openForm(_year == thisYear ? toDateKey(DateTime.now()) : '$_year-01-01'),
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('Add holiday'),
    );

    final controls = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_companyAdmin || _branches.length > 1) ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240), child: scope),
        year,
        add,
      ],
    );

    if (wide) {
      return Row(children: [Expanded(child: title), const SizedBox(width: 16), controls]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 14), controls]);
  }
}

// ── Summary strip ───────────────────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.year, required this.count, required this.next, required this.loading});

  final int year;
  final int count;
  final Holiday? next;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final nextDate = next == null ? null : parseDateOnly(next!.date);

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              loading ? '…' : '$count',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _K.gray900, fontFeatures: _T.tabular),
            ),
            const SizedBox(width: 4),
            Text('holiday${count == 1 ? '' : 's'} in $year', style: const TextStyle(fontSize: 13, color: _K.gray600)),
          ],
        ),
        if (next != null && nextDate != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _K.rose50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _K.rose100),
            ),
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Next: '),
                TextSpan(text: _holidayName(next!), style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: ', ${formatDD(nextDate)} ${formatMMM(nextDate)} (${_whenLabel(_daysFromToday(nextDate))})'),
              ]),
              style: const TextStyle(fontSize: 12, color: _K.rose600),
            ),
          ),
        const Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            _LegendItem(color: _K.rose500, label: 'Holiday'),
            _LegendItem(color: _K.sky100, border: _K.sky700, label: 'Special working day'),
            _LegendItem(color: Colors.white, border: _K.indigo400, label: 'Today'),
          ],
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label, this.border});

  final Color color;
  final Color? border;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: border != null ? Border.all(color: border!) : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11, color: _K.gray500)),
      ],
    );
  }
}

// ── One month ───────────────────────────────────────────────────────────────

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.year,
    required this.month,
    required this.byDate,
    required this.todayKey,
    required this.onPick,
  });

  final int year;
  final int month; // 1-12
  final Map<String, Holiday> byDate;
  final String todayKey;
  final void Function(String key, Holiday? holiday) onPick;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(year, month, 1);
    final lead = first.weekday - 1; // Monday first
    final total = DateTime(year, month + 1, 0).day;
    final now = DateTime.now();
    final current = now.year == year && now.month == month;

    var count = 0;
    for (var d = 1; d <= total; d++) {
      final h = byDate[toDateKey(DateTime(year, month, d))];
      if (h != null && !h.isWorkingDay) count++;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: current ? _K.indigo200 : _K.gray100),
        boxShadow: const [BoxShadow(color: Color(0x08101828), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatMMMM(first),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: current ? _K.indigo700 : _K.gray900,
                  ),
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: _K.rose50, borderRadius: BorderRadius.circular(99)),
                  child: Text(
                    '$count',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _K.rose600, fontFeatures: _T.tabular),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
            childAspectRatio: 1,
            children: [
              for (final w in _weekdays)
                Center(
                  child: Text(w, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: _K.gray400)),
                ),
              for (var i = 0; i < lead; i++) const SizedBox.shrink(),
              for (var d = 1; d <= total; d++) _dayCell(DateTime(year, month, d)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime day) {
    final key = toDateKey(day);
    final h = byDate[key];
    final holiday = h != null && !h.isWorkingDay;
    final working = h != null && h.isWorkingDay;
    final today = key == todayKey;
    final past = key.compareTo(todayKey) < 0;

    final (Color? bg, Color fg) = holiday
        ? (_K.rose500, Colors.white)
        : working
            ? (_K.sky100, _K.sky700)
            : (null, today ? _K.indigo700 : (past ? _K.gray400 : _K.gray700));

    final tip = h != null ? _holidayName(h) : 'Add holiday';

    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 400),
      child: Semantics(
        button: true,
        label: '${formatEEEEddMMMyyyy(day)}, ${holiday ? 'holiday: $tip. Tap for details' : tip}',
        excludeSemantics: true,
        child: Material(
          color: bg ?? Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
            side: today && bg == null ? const BorderSide(color: _K.indigo400, width: 1.5) : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: () => onPick(key, h),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: holiday || today ? FontWeight.w700 : FontWeight.w500,
                    color: fg,
                    fontFeatures: _T.tabular,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Side panels ─────────────────────────────────────────────────────────────

class _HolidayList extends StatelessWidget {
  const _HolidayList({
    required this.year,
    required this.holidays,
    required this.todayKey,
    required this.onOpen,
    required this.onRemove,
    required this.onAdd,
  });

  final int year;
  final List<Holiday> holidays;
  final String todayKey;
  final void Function(Holiday h) onOpen;
  final void Function(Holiday h) onRemove;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final nextIndex = holidays.indexWhere((h) => h.date.compareTo(todayKey) >= 0);

    return _Surface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: _CardHeader(
              icon: Icons.list_alt_rounded,
              tone: _rose,
              title: '$year holidays',
              subtitle: '${holidays.length} day${holidays.length == 1 ? '' : 's'}',
            ),
          ),
          _divider,
          if (holidays.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: _EmptyState(
                icon: Icons.event_busy_outlined,
                title: 'No holidays in $year',
                message: 'Tap a date on the calendar to add one.',
                action: _LinkButton(label: 'Add holiday', onTap: onAdd),
              ),
            )
          else
            for (var i = 0; i < holidays.length; i++) ...[
              if (i > 0) const Padding(padding: EdgeInsets.only(left: 68), child: _divider),
              _row(holidays[i], next: i == nextIndex, past: holidays[i].date.compareTo(todayKey) < 0),
            ],
        ],
      ),
    );
  }

  Widget _row(Holiday h, {required bool next, required bool past}) {
    final d = parseDateOnly(h.date);
    return Material(
      color: next ? _K.rose50.withValues(alpha: 0.5) : Colors.white,
      child: InkWell(
        onTap: () => onOpen(h),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Opacity(
            opacity: past ? 0.6 : 1,
            child: Row(
              children: [
                Container(
                  width: 40,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _K.rose100),
                  ),
                  child: Column(
                    children: [
                      Text(
                        d != null ? formatMMM(d) : '',
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, height: 1.1, color: _K.rose600),
                      ),
                      Text(
                        d != null ? formatDD(d) : '',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          color: _K.gray900,
                          fontFeatures: _T.tabular,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _holidayName(h),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray900),
                      ),
                      const SizedBox(height: 1),
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(d != null ? formatEEEE(d) : '', style: const TextStyle(fontSize: 11, color: _K.gray500)),
                          if (h.repeatsYearly)
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.repeat_rounded, size: 11, color: _K.indigo600),
                                SizedBox(width: 2),
                                Text('Yearly', style: TextStyle(fontSize: 11, color: _K.indigo600)),
                              ],
                            ),
                          if (next && d != null)
                            Text(
                              _whenLabel(_daysFromToday(d)),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.rose600),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove holiday',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onRemove(h),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: _K.gray400),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NextYearCard extends StatelessWidget {
  const _NextYearCard({required this.year, required this.yearlyCount, required this.copying, required this.onCopy});

  final int year;
  final int yearlyCount;
  final bool copying;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            icon: Icons.copy_all_rounded,
            tone: _indigo,
            title: 'Prepare ${year + 1}',
            subtitle: '$yearlyCount yearly holiday${yearlyCount == 1 ? '' : 's'} to copy',
          ),
          const SizedBox(height: 10),
          const Text(
            'Copies holidays marked "Same date every year" (fixed dates such as New Year). '
            'Moving holidays, such as Eid, need to be added each year.',
            style: TextStyle(fontSize: 12, height: 1.45, color: _K.gray500),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _K.gray700,
              side: const BorderSide(color: _K.gray200),
              minimumSize: const Size.fromHeight(40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            onPressed: (copying || yearlyCount == 0) ? null : onCopy,
            icon: copying
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.copy_rounded, size: 16),
            label: Text(copying ? 'Copying…' : 'Copy to ${year + 1}'),
          ),
          if (yearlyCount == 0)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('No holidays in this year repeat yearly.', textAlign: TextAlign.center, style: _T.caption),
            ),
        ],
      ),
    );
  }
}

// ── Holiday details ─────────────────────────────────────────────────────────

class _HolidayDialog extends StatelessWidget {
  const _HolidayDialog({required this.holiday, required this.scopeName});

  final Holiday holiday;
  final String scopeName;

  @override
  Widget build(BuildContext context) {
    final h = holiday;
    final d = parseDateOnly(h.date);
    final days = d == null ? null : _daysFromToday(d);

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(color: _K.rose500, borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      children: [
                        Text(d != null ? formatMMM(d) : '',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white)),
                        Text(
                          d != null ? formatDD(d) : '',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                            color: Colors.white,
                            fontFeatures: _T.tabular,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_holidayName(h),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900)),
                        const SizedBox(height: 2),
                        Text(d != null ? formatEEEEddMMMyyyy(d) : h.date, style: _T.subtitle),
                        if (days != null && days >= 0) ...[
                          const SizedBox(height: 2),
                          Text(_whenLabel(days)[0].toUpperCase() + _whenLabel(days).substring(1),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.rose600)),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded, size: 20, color: _K.gray400),
                  ),
                ],
              ),
            ),
            _divider,
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailLine(icon: Icons.apartment_rounded, text: 'Applies to $scopeName'),
                  _DetailLine(
                    icon: Icons.repeat_rounded,
                    text: h.repeatsYearly ? 'Same date every year' : 'This year only',
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.gray100))),
              child: Row(
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: _K.red600,
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Remove'),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _K.gray900,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: _K.gray400),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: _K.gray700))),
        ],
      ),
    );
  }
}

// ── Add holiday ─────────────────────────────────────────────────────────────

class _AddHolidayForm extends StatefulWidget {
  const _AddHolidayForm({required this.initialDate, required this.branchId, required this.scopeName});

  final String initialDate;
  final int? branchId;
  final String scopeName;

  @override
  State<_AddHolidayForm> createState() => _AddHolidayFormState();
}

class _AddHolidayFormState extends State<_AddHolidayForm> {
  late DateTime _start = parseDateOnly(widget.initialDate) ?? _today();
  late DateTime _end = _start;
  final _name = TextEditingController();
  bool _repeats = false;
  bool _saving = false;
  String? _nameError;
  String? _error;

  int get _days =>
      DateTime.utc(_end.year, _end.month, _end.day).difference(DateTime.utc(_start.year, _start.month, _start.day)).inDays + 1;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _start, end: _end),
    );
    if (picked == null) return;
    setState(() {
      _start = picked.start;
      _end = picked.end;
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Give the holiday a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await holidayService.addRange(
        startDate: toDateKey(_start),
        endDate: toDateKey(_end),
        reason: _name.text.trim(),
        repeatsYearly: _repeats,
        branchId: widget.branchId,
      );
      if (!mounted) return;
      showToast(context, '$created day${created == 1 ? '' : 's'} added');
      Navigator.of(context).pop(true);
    } catch (err) {
      if (mounted) setState(() => _error = apiError(err, 'Could not save'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rangeText = _start == _end
        ? formatEEEEddMMMyyyy(_start)
        : '${formatDDMMMYYYY(_start)} – ${formatDDMMMYYYY(_end)}';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 14),
            child: Row(
              children: [
                const _IconBox(icon: Icons.event_available_outlined, tone: _rose, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Add holiday', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _K.gray900)),
                      const SizedBox(height: 2),
                      Text('For ${widget.scopeName}', style: _T.subtitle),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded, size: 20, color: _K.gray400),
                ),
              ],
            ),
          ),
          _divider,

          // Form
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Name', style: _T.fieldLabel),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _name,
                    autofocus: true,
                    maxLength: 255,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _saving ? null : _save(),
                    onChanged: (_) {
                      if (_nameError != null) setState(() => _nameError = null);
                    },
                    style: const TextStyle(fontSize: 14),
                    decoration: _inputDecoration(hint: 'e.g. National Day', error: _nameError),
                  ),
                  const SizedBox(height: 6),
                  const Text('Dates', style: _T.fieldLabel),
                  const SizedBox(height: 6),
                  Semantics(
                    button: true,
                    label: 'Holiday dates, $rangeText',
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _pickRange,
                      child: InputDecorator(
                        decoration: _inputDecoration(icon: Icons.date_range_outlined),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(rangeText,
                                  style: const TextStyle(fontSize: 14, color: _K.gray900, fontFeatures: _T.tabular)),
                            ),
                            Text('$_days day${_days == 1 ? '' : 's'}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.rose600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 4),
                    child: Text('Tap to pick one day or a range.', style: _T.caption),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: _K.gray50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: _K.gray200),
                    ),
                    child: SwitchListTile(
                      value: _repeats,
                      onChanged: (v) => setState(() => _repeats = v),
                      activeColor: _K.indigo600,
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      title: const Text('Same date every year',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _K.gray100)),
                      subtitle: const Text('Lets you copy it to next year in one step.',
                          style: TextStyle(fontSize: 11.5, color: _K.gray500)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InlineNote(
                    icon: Icons.info_outline_rounded,
                    text: '${widget.branchId != null ? 'Applies to ${widget.scopeName} only.' : 'Applies to every branch.'} '
                        'Attendance for these days is recalculated automatically.',
                    tone: const _Tone(_K.indigo50, _K.indigo100, _K.indigo800),
                  ),
                ],
              ),
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.gray100))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  _InlineNote(
                    icon: Icons.error_outline_rounded,
                    text: _error!,
                    tone: const _Tone(_K.red50, _K.red200, _K.red700),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: _K.gray600,
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _K.indigo600,
                        disabledBackgroundColor: _K.indigo200,
                        disabledForegroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.add_rounded, size: 18),
                      label: Text(_saving ? 'Saving…' : (_days > 1 ? 'Add $_days days' : 'Add holiday')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Loading skeleton ────────────────────────────────────────────────────────

class _PageSkeleton extends StatelessWidget {
  const _PageSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading holiday calendar',
      child: Column(
        children: [
          const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final sm = c.maxWidth >= 640;
                final lg = c.maxWidth >= 1024;
                return ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.all(sm ? 24 : 16),
                  children: [
                    const _Bone(height: 48),
                    const SizedBox(height: 20),
                    _Grid(
                      columns: lg ? 3 : 2,
                      gap: 12,
                      children: [for (var i = 0; i < 6; i++) const _Bone(height: 190)],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Bone extends StatelessWidget {
  const _Bone({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(color: _K.gray100, borderRadius: BorderRadius.circular(_cardRadius)),
    );
  }
}

// ── Small shared pieces ─────────────────────────────────────────────────────

InputDecoration _inputDecoration({String? hint, IconData? icon, String? error}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 14, color: _K.gray400),
    errorText: error,
    errorStyle: const TextStyle(fontSize: 12, color: _K.red600),
    prefixIcon: icon == null ? null : Icon(icon, size: 16, color: _K.gray500),
    prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 20),
    filled: true,
    fillColor: _K.gray50,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: border(_K.gray200),
    enabledBorder: border(_K.gray200),
    focusedBorder: border(_K.indigo600, 1.5),
    errorBorder: border(_K.red200),
    focusedErrorBorder: border(_K.red600, 1.5),
  );
}

/// White card with a hairline border.
class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: _K.gray100),
        boxShadow: const [BoxShadow(color: Color(0x08101828), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: child,
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.icon, required this.tone, required this.title, this.subtitle});

  final IconData icon;
  final _Tone tone;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _IconBox(icon: icon, tone: tone, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.title),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 1),
                Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.subtitle),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, required this.tone, this.size = 32});

  final IconData icon;
  final _Tone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: tone.border),
      ),
      child: Icon(icon, size: size * 0.5, color: tone.fg),
    );
  }
}

class _InlineNote extends StatelessWidget {
  const _InlineNote({required this.icon, required this.text, required this.tone});

  final IconData icon;
  final String text;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tone.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tone.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: tone.fg),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(fontSize: 12, height: 1.4, color: tone.fg))),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: _K.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _K.gray200),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: _K.gray100, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: _K.gray400),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _K.gray700),
          ),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, height: 1.4, color: _K.gray500),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.tone,
    required this.icon,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final _Tone tone;
  final IconData icon;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final hasAction = actionLabel != null && onAction != null;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(12, 10, hasAction ? 4 : 12, 10),
        decoration: BoxDecoration(
          color: tone.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tone.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: tone.fg)),
            const SizedBox(width: 10),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(fontSize: 13, height: 1.45, color: tone.fg),
                child: child,
              ),
            ),
            if (hasAction)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: tone.fg,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.indigo600)),
        ),
      ),
    );
  }
}

/// Equal-width grid (`grid grid-cols-N gap-X`).
class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.gap, required this.children});

  final int columns;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = ((constraints.maxWidth - gap * (columns - 1)) / columns).floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final c in children) SizedBox(width: w, child: c)],
        );
      },
    );
  }
}