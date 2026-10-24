// Port of features/employee/leaves/LeaveApplicationPage.tsx
// ("Apply for Leave": the employee's leave history and the application form).
//
// Like the web page reloading when the tab regains focus, this reloads when
// the app comes back to the foreground. Pull down to refresh.
//
// Layout (compact):
//   Header: title + subtitle · [Apply for leave]
//   [load-error banner]
//   Pending | Approved | Declined   (tap to filter the history)
//   Planning tip
//   History: filter chips · request cards (tap to expand, reapply if declined)

import 'package:flutter/material.dart';

import 'package:hrm_app/components/ui/daterange_cal.dart';
import 'package:hrm_app/services/leave_service.dart';
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
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const emerald950 = Color(0xFF022C22);
  static const teal50 = Color(0xFFF0FDFA);
  static const teal200 = Color(0xFF99F6E4);
  static const teal600 = Color(0xFF0D9488);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber200 = Color(0xFFFDE68A);
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);
  static const red50 = Color(0xFFFEF2F2);
  static const red200 = Color(0xFFFECACA);
  static const red600 = Color(0xFFDC2626);
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo200 = Color(0xFFC7D2FE);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const indigo700 = Color(0xFF4338CA);
  static const indigo950 = Color(0xFF1E1B4B);
}

/// A tinted color set: soft background, border, and foreground.
class _Tone {
  const _Tone(this.bg, this.border, this.fg);

  final Color bg;
  final Color border;
  final Color fg;
}

const _emerald = _Tone(_K.emerald50, _K.emerald200, _K.emerald600);
const _amber = _Tone(_K.amber50, _K.amber200, _K.amber600);
const _red = _Tone(_K.red50, _K.red200, _K.red600);
const _teal = _Tone(_K.teal50, _K.teal200, _K.teal600);

_Tone _statusTone(String status) => switch (status) {
      'APPROVED' => _emerald,
      'DECLINED' => _red,
      _ => _amber,
    };

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3, color: _K.gray900);
  static const subtitle = TextStyle(fontSize: 12, height: 1.3, color: _K.gray500);
  static const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _K.gray500);
  static const fieldLabel = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray700);
  static const caption = TextStyle(fontSize: 11, height: 1.3, color: _K.gray400);
}

const _cardRadius = 16.0;

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Calendar days from [s] to [e], inclusive (DST-safe).
int _dayCount(DateTime s, DateTime e) =>
    DateTime.utc(e.year, e.month, e.day).difference(DateTime.utc(s.year, s.month, s.day)).inDays + 1;

String _daysLabel(int n) => '$n day${n == 1 ? '' : 's'}';

/// "APPROVED" → "Approved".
String _sentenceCase(String s) {
  final t = s.replaceAll('_', ' ').trim().toLowerCase();
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

/// "12 Mar 2026 – 14 Mar 2026", or a single date for one-day leave.
String _rangeText(String startRaw, String endRaw) {
  final s = parseDateOnly(startRaw);
  final e = parseDateOnly(endRaw.isEmpty ? startRaw : endRaw);
  final a = s != null ? formatDDMMMYYYY(s) : startRaw;
  final b = e != null ? formatDDMMMYYYY(e) : endRaw;
  return (b.isEmpty || a == b) ? a : '$a – $b';
}

/// Values to pre-fill the form with (used by "Reapply").
class _Draft {
  const _Draft({this.leaveType, this.start = '', this.end = '', this.reason = ''});

  final int? leaveType;
  final String start;
  final String end;
  final String reason;
}

// ── Page ────────────────────────────────────────────────────────────────────

class LeaveApplicationPage extends StatefulWidget {
  const LeaveApplicationPage({super.key});

  @override
  State<LeaveApplicationPage> createState() => _LeaveApplicationPageState();
}

class _LeaveApplicationPageState extends State<LeaveApplicationPage> with WidgetsBindingObserver {
  List<LeaveType> _types = const [];
  List<LeaveRequest> _requests = const [];
  bool _loading = true;
  String? _error;
  String _filter = 'ALL';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        leaveService.fetchLeaveTypes(),
        leaveService.fetchLeaveRequests(myOwn: true),
      ]);
      if (!mounted) return;
      setState(() {
        _types = results[0] as List<LeaveType>;
        _requests = results[1] as List<LeaveRequest>;
        _error = null;
      });
    } catch (_) {
      // Keep what's shown; the banner offers a retry.
      if (mounted) setState(() => _error = 'Could not load your leave requests.');
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([_Draft draft = const _Draft()]) async {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      clipBehavior: Clip.antiAlias,
      builder: (_) => _ApplyForm(types: _types, draft: draft),
    );
    if (submitted == true) {
      setState(() => _filter = 'ALL');
      _load();
    }
  }

  void _reapply(LeaveRequest req) {
    LeaveType? type;
    for (final t in _types) {
      if (t.name == req.leaveTypeName || t.id == req.leaveType) {
        type = t;
        break;
      }
    }
    _openForm(_Draft(
      leaveType: type?.id ?? req.leaveType,
      start: req.startDate,
      end: req.endDate,
      reason: req.reason.isNotEmpty ? '[Reapplied] ${req.reason}' : '',
    ));
  }

  void _toggleFilter(String status) => setState(() => _filter = _filter == status ? 'ALL' : status);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _PageSkeleton();

    int count(String s) => _requests.where((r) => r.status == s).length;
    final pending = count('PENDING');
    final approved = count('APPROVED');
    final declined = count('DECLINED');
    final visible = _filter == 'ALL' ? _requests : _requests.where((r) => r.status == _filter).toList();

    return RefreshIndicator(
      color: _K.emerald600,
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sm = width >= 640;
          final md = width >= 768;
          final gap = sm ? 20.0 : 16.0;

          final sections = <Widget>[
            _PageHeader(wide: sm, onApply: () => _openForm()),
            if (_error != null)
              _Banner(
                tone: _red,
                icon: Icons.error_outline_rounded,
                actionLabel: 'Retry',
                onAction: _load,
                child: Text('${_error!} Pull down or tap Retry to try again.'),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Grid(
                  columns: 3,
                  gap: sm ? 12 : 8,
                  children: [
                    _StatCard(
                      icon: Icons.schedule_rounded,
                      tone: _amber,
                      value: pending,
                      label: 'Pending',
                      compact: !sm,
                      selected: _filter == 'PENDING',
                      onTap: () => _toggleFilter('PENDING'),
                    ),
                    _StatCard(
                      icon: Icons.check_circle_outline_rounded,
                      tone: _emerald,
                      value: approved,
                      label: 'Approved',
                      compact: !sm,
                      selected: _filter == 'APPROVED',
                      onTap: () => _toggleFilter('APPROVED'),
                    ),
                    _StatCard(
                      icon: Icons.cancel_outlined,
                      tone: _red,
                      value: declined,
                      label: 'Declined',
                      compact: !sm,
                      selected: _filter == 'DECLINED',
                      onTap: () => _toggleFilter('DECLINED'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(Icons.lightbulb_outline_rounded, size: 14, color: _K.amber500),
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Apply at least 3 days in advance for planned time off.',
                        style: TextStyle(fontSize: 12, height: 1.35, color: _K.gray500),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            _historyCard(
              visible: visible,
              counts: {'ALL': _requests.length, 'PENDING': pending, 'APPROVED': approved, 'DECLINED': declined},
              wide: md,
            ),
          ];

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(sm ? 24 : 16),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < sections.length; i++) ...[
                        if (i > 0) SizedBox(height: gap),
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

  Widget _historyCard({
    required List<LeaveRequest> visible,
    required Map<String, int> counts,
    required bool wide,
  }) {
    const filters = [('ALL', 'All'), ('PENDING', 'Pending'), ('APPROVED', 'Approved'), ('DECLINED', 'Declined')];

    return _Surface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: _CardHeader(
              icon: Icons.history_rounded,
              tone: _teal,
              title: 'Application history',
              subtitle: _requests.isEmpty
                  ? 'Your requests appear here'
                  : '${_requests.length} request${_requests.length == 1 ? '' : 's'} in total',
            ),
          ),
          if (_requests.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  for (final (i, (value, label)) in filters.indexed)
                    if (i == 0 || (counts[value] ?? 0) > 0 || _filter == value) ...[
                      if (i > 0) const SizedBox(width: 6),
                      _FilterChip(
                        label: label,
                        count: counts[value] ?? 0,
                        selected: _filter == value,
                        onTap: () => setState(() => _filter = value),
                      ),
                    ],
                ],
              ),
            ),
          const Divider(height: 1, thickness: 1, color: _K.gray100),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _requests.isEmpty
                ? _EmptyState(
                    icon: Icons.event_note_outlined,
                    title: 'No leave requests yet',
                    message: 'When you apply for leave, its status and any comments from HR show up here.',
                    action: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: _K.emerald600,
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () => _openForm(),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Apply for leave'),
                    ),
                  )
                : visible.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No ${_sentenceCase(_filter).toLowerCase()} requests.',
                          textAlign: TextAlign.center,
                          style: _T.subtitle,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < visible.length; i++) ...[
                            if (i > 0) const SizedBox(height: 10),
                            _RequestCard(
                              key: ValueKey('${visible[i].createdAt}-${visible[i].startDate}-$i'),
                              request: visible[i],
                              wide: wide,
                              onReapply: () => _reapply(visible[i]),
                            ),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.wide, required this.onApply});

  final bool wide;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final title = Row(
      children: [
        const _IconBox(icon: Icons.beach_access_outlined, tone: _emerald, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'My leave',
                  style: TextStyle(
                    fontSize: wide ? 22 : 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.25,
                    color: _K.gray900,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              const Text('Request time off and track approvals.', style: _T.subtitle),
            ],
          ),
        ),
      ],
    );

    final button = _GradientButton(
      onTap: onApply,
      radius: 10,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_rounded, size: 18, color: Colors.white),
          SizedBox(width: 6),
          Text('Apply for leave', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );

    if (wide) {
      return Row(children: [Expanded(child: title), const SizedBox(width: 16), button]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [title, const SizedBox(height: 14), button],
    );
  }
}

// ── Stat cards ──────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.tone,
    required this.value,
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final _Tone tone;
  final int value;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Phones: icon and number on one line, label below (fits three across).
  final bool compact;

  static const _valueStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.15,
    color: _K.gray900,
    fontFeatures: _T.tabular,
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label requests: $value${selected ? ', filter on' : ', tap to filter'}',
      excludeSemantics: true,
      child: _Surface(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        color: selected ? tone.bg : Colors.white,
        borderColor: selected ? tone.border : _K.gray100,
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _IconBox(icon: icon, tone: tone, size: 26),
                      const Spacer(),
                      Text('$value', style: _valueStyle),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.label),
                ],
              )
            : Row(
                children: [
                  _IconBox(icon: icon, tone: tone, size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$value', style: _valueStyle),
                        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.label),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── History ─────────────────────────────────────────────────────────────────

class _RequestCard extends StatefulWidget {
  const _RequestCard({super.key, required this.request, required this.wide, required this.onReapply});

  final LeaveRequest request;
  final bool wide;
  final VoidCallback onReapply;

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final tone = _statusTone(r.status);
    final start = parseDateOnly(r.startDate);
    final end = parseDateOnly(r.endDate.isEmpty ? r.startDate : r.endDate);
    final days = (start != null && end != null) ? _dayCount(start, end) : null;
    final created = DateTime.tryParse(r.createdAt)?.toLocal();

    final hasTl = r.hasTeamLead && r.tlStatus != null;
    final tlComment = (r.tlComment != null && r.tlComment!.isNotEmpty) ? r.tlComment : null;
    final longText = r.reason.length > 90 || (tlComment?.length ?? 0) > 90 || r.hrComment.length > 90;
    final maxLines = _expanded ? null : 2;

    final summary = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IconBox(icon: Icons.event_note_outlined, tone: tone, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      r.leaveTypeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _K.gray900),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(text: r.statusDisplay, tone: tone),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 12, color: _K.gray400),
                      const SizedBox(width: 5),
                      Text(
                        _rangeText(r.startDate, r.endDate),
                        style: const TextStyle(fontSize: 12, color: _K.gray700, fontFeatures: _T.tabular),
                      ),
                    ],
                  ),
                  if (days != null)
                    Text(
                      _daysLabel(days),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.gray500),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Applied ${created != null ? formatDDMMMYYYY(created) : r.createdAt}',
                style: _T.caption,
              ),
            ],
          ),
        ),
      ],
    );

    final details = Container(
      width: widget.wide ? 340 : double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _K.gray50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _K.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Note(
            icon: Icons.chat_bubble_outline_rounded,
            iconColor: _K.gray400,
            label: 'Reason',
            labelColor: _K.gray500,
            text: r.reason.isNotEmpty ? r.reason : 'No reason given',
            textColor: r.reason.isNotEmpty ? _K.gray700 : _K.gray400,
            maxLines: maxLines,
          ),
          if (hasTl) ...[
            const _NoteDivider(),
            _Note(
              icon: Icons.how_to_reg_outlined,
              iconColor: _K.indigo500,
              label: 'Team lead: ${_sentenceCase(r.tlStatus!)}',
              labelColor: _K.indigo600,
              text: tlComment,
              textColor: _K.indigo950,
              maxLines: maxLines,
            ),
          ],
          if (r.hrComment.isNotEmpty) ...[
            const _NoteDivider(),
            _Note(
              icon: Icons.verified_outlined,
              iconColor: _K.emerald500,
              label: 'HR response',
              labelColor: _K.emerald600,
              text: r.hrComment,
              textColor: _K.emerald950,
              maxLines: maxLines,
            ),
          ],
          if (longText || r.status == 'DECLINED') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (longText)
                  _LinkButton(
                    label: _expanded ? 'Show less' : 'Show more',
                    onTap: () => setState(() => _expanded = !_expanded),
                  ),
                const Spacer(),
                if (r.status == 'DECLINED')
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: _K.indigo50,
                      foregroundColor: _K.indigo700,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    onPressed: widget.onReapply,
                    icon: const Icon(Icons.replay_rounded, size: 14),
                    label: const Text('Reapply'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _K.gray200),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: widget.wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: summary), const SizedBox(width: 16), details],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [summary, const SizedBox(height: 10), details],
              ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.labelColor,
    required this.text,
    required this.textColor,
    required this.maxLines,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;
  final String? text;
  final Color textColor;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: iconColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: labelColor)),
              if (text != null) ...[
                const SizedBox(height: 1),
                Text(
                  text!,
                  maxLines: maxLines,
                  overflow: maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, height: 1.4, color: textColor),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NoteDivider extends StatelessWidget {
  const _NoteDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Divider(height: 1, thickness: 1, color: _K.gray200),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.text, required this.tone});

  final String text;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tone.border),
      ),
      child: Text(
        _sentenceCase(text),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tone.fg),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.count, required this.selected, required this.onTap});

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? _K.emerald600 : _K.gray600;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? _K.emerald50 : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? _K.emerald200 : _K.gray200)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: selected ? _K.emerald500 : _K.gray400,
                    fontFeatures: _T.tabular,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Application form ────────────────────────────────────────────────────────

class _ApplyForm extends StatefulWidget {
  const _ApplyForm({required this.types, required this.draft});

  final List<LeaveType> types;
  final _Draft draft;

  @override
  State<_ApplyForm> createState() => _ApplyFormState();
}

class _ApplyFormState extends State<_ApplyForm> {
  late int? _type = widget.types.any((t) => t.id == widget.draft.leaveType) ? widget.draft.leaveType : null;
  late String _start = widget.draft.start;
  late String _end = widget.draft.end;
  late final _reason = TextEditingController(text: widget.draft.reason);
  bool _submitting = false;
  String? _error;
  String? _success;
  String? _typeError;
  String? _dateError;
  String? _reasonError;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  int? get _days {
    final s = parseDateOnly(_start);
    final e = parseDateOnly(_end.isEmpty ? _start : _end);
    if (s == null || e == null) return null;
    return _dayCount(s, e);
  }

  /// True when the leave starts within the next 3 days.
  bool get _shortNotice {
    final s = parseDateOnly(_start);
    if (s == null) return false;
    final now = DateTime.now();
    final ahead = _dayCount(DateTime(now.year, now.month, now.day), s) - 1;
    return ahead >= 0 && ahead < 3;
  }

  Future<void> _submit() async {
    final type = _type;
    setState(() {
      _typeError = type == null ? 'Choose a leave type.' : null;
      _dateError = _start.isEmpty ? 'Select your leave dates on the calendar.' : null;
      _reasonError = _reason.text.trim().isEmpty ? 'Tell HR why you need this time off.' : null;
      _error = null;
    });
    if (_typeError != null || _dateError != null || _reasonError != null) return;

    setState(() {
      _submitting = true;
      _success = null;
    });
    try {
      await leaveService.createLeaveRequest(
        leaveType: type!,
        startDate: _start,
        endDate: _end.isEmpty ? _start : _end,
        reason: _reason.text,
      );
      if (!mounted) return;
      setState(() => _success = 'Leave request submitted. You can track it in your history.');
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (mounted) setState(() => _error = apiError(err, 'Failed to submit application.'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _decoration({String? hint, String? error}) {
    OutlineInputBorder border(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: w));
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 14, color: _K.gray400),
      errorText: error,
      errorStyle: const TextStyle(fontSize: 12, color: _K.red600),
      filled: true,
      fillColor: _K.gray50,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border(_K.gray200),
      enabledBorder: border(_K.gray200),
      focusedBorder: border(_K.emerald500, 1.5),
      errorBorder: border(_K.red200),
      focusedErrorBorder: border(_K.red600, 1.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;
    final hasDates = _start.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 14),
            decoration: BoxDecoration(
              border: const Border(bottom: BorderSide(color: _K.gray100)),
              gradient: LinearGradient(
                colors: [
                  Color.alphaBlend(_K.emerald500.withValues(alpha: 0.05), Colors.white),
                  Color.alphaBlend(_K.teal600.withValues(alpha: 0.04), Colors.white),
                ],
              ),
            ),
            child: Row(
              children: [
                const _IconBox(icon: Icons.send_outlined, tone: _emerald, size: 40),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Apply for leave',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _K.gray900),
                      ),
                      SizedBox(height: 2),
                      Text('Your request goes to your approvers.', style: _T.subtitle),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  visualDensity: VisualDensity.compact,
                  onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded, size: 20, color: _K.gray400),
                ),
              ],
            ),
          ),

          // Form
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Leave type', style: _T.fieldLabel),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    value: _type,
                    isExpanded: true,
                    hint: const Text('Choose a leave type', style: TextStyle(fontSize: 14, color: _K.gray400)),
                    icon: const Icon(Icons.expand_more_rounded, size: 20, color: _K.gray500),
                    borderRadius: BorderRadius.circular(10),
                    style: const TextStyle(fontSize: 14, color: _K.gray900),
                    decoration: _decoration(error: _typeError),
                    items: [
                      for (final t in widget.types)
                        DropdownMenuItem(value: t.id, child: Text(t.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() {
                      _type = v;
                      _typeError = null;
                    }),
                  ),
                  const SizedBox(height: 18),
                  const Text('Dates', style: _T.fieldLabel),
                  const SizedBox(height: 6),
                  Container(
                    padding: EdgeInsets.fromLTRB(12, hasDates ? 4 : 10, hasDates ? 4 : 12, hasDates ? 4 : 10),
                    decoration: BoxDecoration(
                      color: hasDates ? _K.emerald50 : _K.gray50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _dateError != null ? _K.red200 : (hasDates ? _K.emerald200 : _K.gray200),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.date_range_outlined,
                          size: 16,
                          color: hasDates ? _K.emerald600 : _K.gray400,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            hasDates ? _rangeText(_start, _end) : 'Tap a start and end date below',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: hasDates ? FontWeight.w600 : FontWeight.w400,
                              color: hasDates ? _K.gray900 : _K.gray400,
                              fontFeatures: _T.tabular,
                            ),
                          ),
                        ),
                        if (days != null)
                          Text(
                            _daysLabel(days),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.emerald600),
                          ),
                        if (hasDates)
                          IconButton(
                            tooltip: 'Clear dates',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() {
                              _start = '';
                              _end = '';
                            }),
                            icon: const Icon(Icons.close_rounded, size: 16, color: _K.gray500),
                          ),
                      ],
                    ),
                  ),
                  if (_dateError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 12),
                      child: Text(_dateError!, style: const TextStyle(fontSize: 12, color: _K.red600)),
                    ),
                  const SizedBox(height: 10),
                  Center(
                    child: DateRangeCalendar(
                      start: _start,
                      end: _end,
                      onChanged: (s, e) => setState(() {
                        _start = s;
                        _end = e;
                        _dateError = null;
                      }),
                    ),
                  ),
                  if (_shortNotice) ...[
                    const SizedBox(height: 10),
                    const _InlineNote(
                      icon: Icons.info_outline_rounded,
                      text: 'This starts within 3 days. Planned leave should be requested at least 3 days ahead, '
                          'so approval may take longer.',
                      tone: _Tone(_K.amber50, _K.amber200, _K.amber700),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text('Reason', style: _T.fieldLabel),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _reason,
                    minLines: 3,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 14, height: 1.4, color: _K.gray900),
                    decoration: _decoration(hint: 'Briefly explain why you need this time off', error: _reasonError),
                    onChanged: (_) {
                      if (_reasonError != null) setState(() => _reasonError = null);
                    },
                  ),
                ],
              ),
            ),
          ),

          // Footer (stays visible above the keyboard)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: _K.gray100)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  _InlineNote(icon: Icons.error_outline_rounded, text: _error!, tone: _red),
                  const SizedBox(height: 10),
                ],
                if (_success != null) ...[
                  _InlineNote(icon: Icons.check_circle_outline_rounded, text: _success!, tone: _emerald),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _K.gray600,
                          side: const BorderSide(color: _K.gray200),
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Opacity(
                        opacity: (_submitting || _success != null) ? 0.6 : 1,
                        child: _GradientButton(
                          onTap: (_submitting || _success != null) ? null : _submit,
                          radius: 10,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_submitting)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              else
                                const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                              const SizedBox(width: 8),
                              Text(
                                _submitting ? 'Submitting…' : 'Submit request',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
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
            Icon(icon, size: 16, color: tone.fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w500, color: tone.fg)),
            ),
          ],
        ),
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
      label: 'Loading your leave requests',
      child: Column(
        children: [
          const LinearProgressIndicator(minHeight: 2, color: _K.emerald500, backgroundColor: _K.emerald50),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final sm = c.maxWidth >= 640;
                return ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.all(sm ? 24 : 16),
                  children: [
                    const Row(
                      children: [
                        _Bone(width: 44, height: 44, radius: 13),
                        SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Bone(width: 120, height: 18),
                            SizedBox(height: 8),
                            _Bone(width: 220, height: 12),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _Grid(
                      columns: 3,
                      gap: sm ? 12 : 8,
                      children: [for (var i = 0; i < 3; i++) const _Bone(height: 58)],
                    ),
                    const SizedBox(height: 20),
                    const _Bone(height: 120),
                    const SizedBox(height: 12),
                    const _Bone(height: 120),
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
  const _Bone({this.width, required this.height, this.radius = _cardRadius});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(color: _K.gray100, borderRadius: BorderRadius.circular(radius)),
    );
  }
}

// ── Small shared pieces ─────────────────────────────────────────────────────

/// White card with a hairline border; optionally tappable.
class _Surface extends StatelessWidget {
  const _Surface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color = Colors.white,
    this.borderColor = _K.gray100,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(_cardRadius);
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(borderRadius: radius, onTap: onTap, child: content),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius,
        border: Border.all(color: borderColor),
        boxShadow: const [BoxShadow(color: Color(0x08101828), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: content,
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
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, height: 1.4, color: _K.gray500),
              ),
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
          children: [
            Icon(icon, size: 18, color: tone.fg),
            const SizedBox(width: 10),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(fontSize: 13, height: 1.4, color: tone.fg),
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
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.indigo600)),
        ),
      ),
    );
  }
}

/// Emerald-to-teal gradient button (`from-emerald-500 to-teal-600`).
class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.onTap, required this.child, required this.radius, required this.padding});

  final VoidCallback? onTap;
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: const LinearGradient(colors: [_K.emerald500, _K.teal600]),
          boxShadow: [
            BoxShadow(color: _K.emerald500.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Equal-width grid built from rows, so every card in a row is the same height.
class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.gap, required this.children});

  final int columns;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var start = 0; start < children.length; start += columns) {
      final cells = children.sublist(start, (start + columns).clamp(0, children.length));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < columns; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(child: i < cells.length ? cells[i] : const SizedBox.shrink()),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          rows[i],
        ],
      ],
    );
  }
}