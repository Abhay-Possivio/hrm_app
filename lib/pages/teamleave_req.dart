// Port of features/team-lead/leaves/TeamLeaveApprovalPage.tsx
// (the team lead approves or declines the team's leave requests; HR decides
// after that).
//
// Layout (compact):
//   Header: title · "HR makes the final decision" · pending tag
//   [load-error banner]
//   Tabs: To review (n) | Decided (n)
//   To review: one card per request (reason, overlap warning, comment,
//              Decline / Approve)
//   Decided:   filter chips · compact rows → details dialog

import 'package:flutter/material.dart';

import 'package:hrm_app/services/notification_service.dart';
import 'package:hrm_app/services/teamlead_service.dart';
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
  static const gray800 = Color(0xFF1F2937);
  static const gray900 = Color(0xFF111827);
  static const slate900 = Color(0xFF0F172A);
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo300 = Color(0xFFA5B4FC);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const indigo900 = Color(0xFF312E81);
  static const purple50 = Color(0xFFFAF5FF);
  static const purple100 = Color(0xFFF3E8FF);
  static const purple600 = Color(0xFF9333EA);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber100 = Color(0xFFFEF3C7);
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald600 = Color(0xFF059669);
  static const rose50 = Color(0xFFFFF1F2);
  static const rose100 = Color(0xFFFFE4E6);
  static const rose600 = Color(0xFFE11D48);
  static const rose700 = Color(0xFFBE123C);
}

/// A tinted color set: soft background, border, and foreground.
class _Tone {
  const _Tone(this.bg, this.border, this.fg);

  final Color bg;
  final Color border;
  final Color fg;
}

const _indigo = _Tone(_K.indigo50, _K.indigo100, _K.indigo600);
const _purple = _Tone(_K.purple50, _K.purple100, _K.purple600);
const _amber = _Tone(_K.amber50, _K.amber100, _K.amber600);
const _emerald = _Tone(_K.emerald50, _K.emerald100, _K.emerald600);
const _rose = _Tone(_K.rose50, _K.rose100, _K.rose600);
const _gray = _Tone(_K.gray100, _K.gray200, _K.gray500);

_Tone _decisionTone(String status) => switch (status) {
      'APPROVED' => _emerald,
      'DECLINED' => _rose,
      _ => _amber,
    };

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3, color: _K.gray900);
  static const subtitle = TextStyle(fontSize: 12, height: 1.3, color: _K.gray500);
  static const label = TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _K.gray500);
}

const _cardRadius = 16.0;
const _divider = Divider(height: 1, thickness: 1, color: _K.gray100);

// ── Helpers ─────────────────────────────────────────────────────────────────

/// "Oct 05 – Oct 07, 2026" (or without the year); one date for one-day leave.
String _period(String start, String end, {bool withYear = true}) {
  final s = parseDateOnly(start);
  final e = parseDateOnly(end);
  if (s == null || e == null) return '$start – $end';
  final tail = withYear ? ', ${e.year}' : '';
  if (s == e) return '${formatMMM(s)} ${formatDD(s)}$tail';
  return '${formatMMM(s)} ${formatDD(s)} – ${formatMMM(e)} ${formatDD(e)}$tail';
}

/// Inclusive calendar days (DST-safe).
int? _days(String start, String end) {
  final s = parseDateOnly(start);
  final e = parseDateOnly(end);
  if (s == null || e == null) return null;
  return DateTime.utc(e.year, e.month, e.day).difference(DateTime.utc(s.year, s.month, s.day)).inDays + 1;
}

String _daysLabel(int n) => '$n day${n == 1 ? '' : 's'}';

bool _overlaps(TeamLeaveRequest a, TeamLeaveRequest b) {
  final aStart = parseDateOnly(a.startDate), aEnd = parseDateOnly(a.endDate);
  final bStart = parseDateOnly(b.startDate), bEnd = parseDateOnly(b.endDate);
  if (aStart == null || aEnd == null || bStart == null || bEnd == null) return false;
  return !aStart.isAfter(bEnd) && !bStart.isAfter(aEnd);
}

/// "Oct 05, 14:30" from a server timestamp.
String _processedAt(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${formatMMM(d)} ${two(d.day)}, ${two(d.hour)}:${two(d.minute)}';
}

String _sentenceCase(String s) {
  final t = s.replaceAll('_', ' ').trim().toLowerCase();
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

// ── Page ────────────────────────────────────────────────────────────────────

class TeamLeaveRequestsPage extends StatefulWidget {
  const TeamLeaveRequestsPage({super.key});

  @override
  State<TeamLeaveRequestsPage> createState() => _TeamLeaveRequestsPageState();
}

class _TeamLeaveRequestsPageState extends State<TeamLeaveRequestsPage> {
  List<TeamLeaveRequest> _leaves = const [];
  bool _loading = true;
  bool _loadedOnce = false;
  String? _error;
  int? _processing;
  bool _processingApprove = true;
  bool _showHistory = false;
  String _historyFilter = 'ALL';

  /// One comment box per request (on the web all cards share one box).
  final Map<int, TextEditingController> _comments = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _comments.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _commentFor(int id) => _comments.putIfAbsent(id, TextEditingController.new);

  Future<void> _load() async {
    try {
      final data = await teamLeadService.fetchTeamLeaves();
      if (mounted) {
        setState(() {
          _leaves = data;
          _loadedOnce = true;
          _error = null;
        });
      }
    } catch (_) {
      // Keep what's shown; the banner offers a retry.
      if (mounted) setState(() => _error = 'Could not load leave requests.');
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  void _retryFromScratch() {
    setState(() => _loading = true);
    _load();
  }

  Future<void> _act(TeamLeaveRequest leave, {required bool approve}) async {
    final id = leave.id;
    final comment = _commentFor(id).text;
    setState(() {
      _processing = id;
      _processingApprove = approve;
    });
    try {
      if (approve) {
        await teamLeadService.approveLeave(id, comment);
      } else {
        await teamLeadService.declineLeave(id, comment);
      }
      _comments.remove(id)?.dispose();
      if (mounted) {
        showToast(
          context,
          approve
              ? "${leave.employeeName}'s leave approved and sent to HR"
              : "${leave.employeeName}'s leave declined",
        );
      }
      await _load();
      notificationEvents.countsChanged();
    } catch (_) {
      if (mounted) showToast(context, 'Action failed. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _processing = null);
    }
  }

  /// Declining can't be undone here, so confirm first and offer a comment.
  Future<void> _confirmDecline(TeamLeaveRequest leave) async {
    final comment = _commentFor(leave.id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          "Decline ${leave.employeeName}'s leave?",
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${leave.leaveTypeName}, ${_period(leave.startDate, leave.endDate)}. '
              'The employee will see your comment.',
              style: const TextStyle(fontSize: 13, height: 1.45, color: _K.gray600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: comment,
              autofocus: comment.text.isEmpty,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 13),
              decoration: _inputDecoration(hint: 'Reason for declining (recommended)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _K.gray600),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _K.rose600,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Decline leave'),
          ),
        ],
      ),
    );
    if (ok == true) _act(leave, approve: false);
  }

  void _showDetails(TeamLeaveRequest leave) {
    showDialog<void>(context: context, builder: (_) => _DetailsDialog(leave: leave));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _PageSkeleton();
    if (!_loadedOnce) return _ErrorState(onRetry: _retryFromScratch, onRefresh: _load);

    final pending = _leaves.where((l) => l.tlStatus == 'PENDING').toList();
    final history = _leaves.where((l) => l.tlStatus != 'PENDING').toList();
    final approvedByMe = _leaves.where((l) => l.tlStatus == 'APPROVED').toList();

    return RefreshIndicator(
      color: _K.indigo600,
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sm = width >= 640;
          final lg = width >= 1024;
          final gap = sm ? 20.0 : 16.0;

          final sections = <Widget>[
            _Header(wide: sm, pending: pending.length),
            if (_error != null)
              _Banner(
                tone: const _Tone(_K.rose50, _K.rose100, _K.rose700),
                icon: Icons.error_outline_rounded,
                actionLabel: 'Retry',
                onAction: _load,
                child: Text('${_error!} Showing the last update.'),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: _Tabs(
                  showHistory: _showHistory,
                  pending: pending.length,
                  decided: history.length,
                  onChanged: (v) => setState(() => _showHistory = v),
                ),
              ),
            ),
            if (!_showHistory) _pendingSection(pending, approvedByMe, wide: lg) else _historyCard(history),
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

  Widget _pendingSection(
    List<TeamLeaveRequest> pending,
    List<TeamLeaveRequest> approvedByMe, {
    required bool wide,
  }) {
    if (pending.isEmpty) {
      return _EmptyState(
          icon: Icons.task_alt_rounded,
          success: true,
          title: 'No requests waiting for you',
          message: 'New leave requests from your team will appear here.',
          action: _leaves.any((l) => l.tlStatus != 'PENDING')
              ? _LinkButton(label: 'View decided requests', onTap: () => setState(() => _showHistory = true))
              : null,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, leave) in pending.indexed) ...[
          if (i > 0) const SizedBox(height: 12),
          _PendingCard(
          key: ValueKey(leave.id),
          leave: leave,
          alsoOff: [
            for (final o in approvedByMe)
              if (o.employeeName != leave.employeeName && _overlaps(o, leave)) o.employeeName,
          ].toSet().toList(),
          comment: _commentFor(leave.id),
          busy: _processing != null,
          approving: _processing == leave.id && _processingApprove,
          declining: _processing == leave.id && !_processingApprove,
          wide: wide,
          onApprove: () => _act(leave, approve: true),
          onDecline: () => _confirmDecline(leave),
        ),
        ],
      ],
    );
  }

  Widget _historyCard(List<TeamLeaveRequest> history) {
    const filters = [('ALL', 'All'), ('APPROVED', 'Approved'), ('DECLINED', 'Declined')];
    final counts = {
      'ALL': history.length,
      'APPROVED': history.where((l) => l.tlStatus == 'APPROVED').length,
      'DECLINED': history.where((l) => l.tlStatus == 'DECLINED').length,
    };
    final visible = _historyFilter == 'ALL' ? history : history.where((l) => l.tlStatus == _historyFilter).toList();

    return _Surface(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _CardHeader(
                  icon: Icons.history_rounded,
                  tone: _gray,
                  title: 'Your decisions',
                  subtitle: 'Tap a request to see the details',
                ),
                if (history.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (i, (value, label)) in filters.indexed) ...[
                          if (i > 0) const SizedBox(width: 6),
                          _FilterChip(
                            label: label,
                            count: counts[value] ?? 0,
                            selected: _historyFilter == value,
                            onTap: () => setState(() => _historyFilter = value),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          _divider,
          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: _EmptyState(
                icon: Icons.history_rounded,
                title: 'No decisions yet',
                message: 'Requests you approve or decline are listed here.',
              ),
            )
          else if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No ${_sentenceCase(_historyFilter).toLowerCase()} requests.',
                textAlign: TextAlign.center,
                style: _T.subtitle,
              ),
            )
          else
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0) _divider,
              _HistoryRow(leave: visible[i], onView: () => _showDetails(visible[i])),
            ],
        ],
      ),
    );
  }
}

// ── Header and tabs ─────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.wide, required this.pending});

  final bool wide;
  final int pending;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _IconBox(icon: Icons.event_available_outlined, tone: _indigo, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Team leave requests',
                      style: TextStyle(
                        fontSize: wide ? 22 : 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        height: 1.25,
                        color: _K.gray900,
                      ),
                    ),
                  ),
                  if (pending > 0) _Tag(text: '$pending to review', tone: _amber),
                ],
              ),
              const SizedBox(height: 3),
              const Text(
                'Approve or decline requests from your team. HR makes the final decision.',
                style: _T.subtitle,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.showHistory, required this.pending, required this.decided, required this.onChanged});

  final bool showHistory;
  final int pending;
  final int decided;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(bool value, String label, int count) {
      final selected = showHistory == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: Material(
            color: selected ? Colors.white : Colors.transparent,
            elevation: selected ? 1 : 0,
            shadowColor: const Color(0x33000000),
            borderRadius: BorderRadius.circular(7),
            child: InkWell(
              borderRadius: BorderRadius.circular(7),
              onTap: () => onChanged(value),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? _K.indigo600 : _K.gray500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: selected ? _K.indigo50 : _K.gray200,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: selected ? _K.indigo600 : _K.gray600,
                          fontFeatures: _T.tabular,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _K.gray100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _K.gray200),
      ),
      child: Row(children: [tab(false, 'To review', pending), tab(true, 'Decided', decided)]),
    );
  }
}

// ── Pending requests ────────────────────────────────────────────────────────

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    super.key,
    required this.leave,
    required this.alsoOff,
    required this.comment,
    required this.busy,
    required this.approving,
    required this.declining,
    required this.wide,
    required this.onApprove,
    required this.onDecline,
  });

  final TeamLeaveRequest leave;

  /// Other team members whose approved leave overlaps this one.
  final List<String> alsoOff;
  final TextEditingController comment;
  final bool busy;
  final bool approving;
  final bool declining;
  final bool wide;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final days = _days(leave.startDate, leave.endDate);

    final who = Row(
      children: [
        _Avatar(name: leave.employeeName, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                leave.employeeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _K.gray900),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _MiniChip(text: leave.leaveTypeName, tone: _purple),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 12, color: _K.gray400),
                      const SizedBox(width: 5),
                      Text(
                        _period(leave.startDate, leave.endDate),
                        style: const TextStyle(fontSize: 12, color: _K.gray700, fontFeatures: _T.tabular),
                      ),
                    ],
                  ),
                  if (days != null)
                    Text(_daysLabel(days),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.gray500)),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final reason = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _K.gray50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _K.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Reason', style: _T.label),
          const SizedBox(height: 2),
          Text(
            leave.reason.isNotEmpty ? leave.reason : 'No reason given.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: leave.reason.isNotEmpty ? _K.gray700 : _K.gray400,
            ),
          ),
        ],
      ),
    );

    final overlap = alsoOff.isEmpty
        ? null
        : Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _K.amber50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _K.amber100),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.groups_outlined, size: 14, color: _K.amber700),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Also off on these dates (approved by you): ${alsoOff.join(', ')}',
                    style: const TextStyle(fontSize: 12, height: 1.35, color: _K.amber700),
                  ),
                ),
              ],
            ),
          );

    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: comment,
          enabled: !busy,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 13),
          decoration: _inputDecoration(hint: 'Comment (optional)', icon: Icons.chat_bubble_outline_rounded),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: _K.rose50,
                  foregroundColor: _K.rose600,
                  side: const BorderSide(color: _K.rose100),
                  minimumSize: const Size.fromHeight(40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                onPressed: busy ? null : onDecline,
                icon: declining
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _K.rose600))
                    : const Icon(Icons.close_rounded, size: 16),
                label: Text(declining ? 'Declining…' : 'Decline'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _K.emerald600,
                  minimumSize: const Size.fromHeight(40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                onPressed: busy ? null : onApprove,
                icon: approving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_rounded, size: 16),
                label: Text(approving ? 'Approving…' : 'Approve'),
              ),
            ),
          ],
        ),
      ],
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        who,
        const SizedBox(height: 12),
        reason,
        if (overlap != null) ...[const SizedBox(height: 8), overlap],
      ],
    );

    return _Surface(
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: info),
                const SizedBox(width: 20),
                SizedBox(width: 300, child: actions),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [info, const SizedBox(height: 12), actions],
            ),
    );
  }
}

// ── History ─────────────────────────────────────────────────────────────────

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.leave, required this.onView});

  final TeamLeaveRequest leave;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final hasComment = leave.tlComment.isNotEmpty;

    return Semantics(
      button: true,
      hint: 'View details',
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: onView,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Row(
              children: [
                _Avatar(name: leave.employeeName, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              leave.employeeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray800),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusBadge(status: leave.tlStatus),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${leave.leaveTypeName}, ${_period(leave.startDate, leave.endDate, withYear: false)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: _K.gray500, fontFeatures: _T.tabular),
                      ),
                      if (hasComment) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.chat_bubble_outline_rounded, size: 11, color: _K.gray400),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                leave.tlComment,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: _K.gray600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _processedAt(leave.tlProcessedAt),
                  style: const TextStyle(fontSize: 11, color: _K.gray400, fontFeatures: _T.tabular),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18, color: _K.gray300),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailsDialog extends StatelessWidget {
  const _DetailsDialog({required this.leave});

  final TeamLeaveRequest leave;

  @override
  Widget build(BuildContext context) {
    final days = _days(leave.startDate, leave.endDate);
    final tone = _decisionTone(leave.tlStatus);

    Widget info(String label, Widget child) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(label, style: _T.label), const SizedBox(height: 3), child],
        );

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 14),
              child: Row(
                children: [
                  _Avatar(name: leave.employeeName, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          leave.employeeName,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900),
                        ),
                        const Text('Leave request', style: _T.subtitle),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20, color: _K.gray400),
                  ),
                ],
              ),
            ),
            _divider,
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _K.gray50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _K.gray100),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: info(
                              'Leave type',
                              Text(leave.leaveTypeName,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.purple600)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: info(
                              'Dates',
                              Text(
                                '${_period(leave.startDate, leave.endDate)}${days != null ? '\n${_daysLabel(days)}' : ''}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                  color: _K.gray800,
                                  fontFeatures: _T.tabular,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    info(
                      'Employee reason',
                      Text(
                        leave.reason.isNotEmpty ? leave.reason : 'No reason given.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: leave.reason.isNotEmpty ? _K.gray700 : _K.gray400,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: tone.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: tone.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text('Your decision',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.gray700)),
                              ),
                              _StatusBadge(status: leave.tlStatus),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Decided ${_processedAt(leave.tlProcessedAt)}',
                            style: const TextStyle(fontSize: 11, color: _K.gray500, fontFeatures: _T.tabular),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            leave.tlComment.isNotEmpty ? leave.tlComment : 'No comment added.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: leave.tlComment.isNotEmpty ? _K.indigo900 : _K.gray400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 13, color: _K.gray400),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text('HR makes the final decision on this request.',
                              style: TextStyle(fontSize: 11, color: _K.gray400)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.gray100))),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _K.slate900,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── First-load failure ──────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry, required this.onRefresh});

  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: _K.indigo600,
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, c) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: _EmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Could not load leave requests',
                      message: 'Check your connection, then retry or pull down to refresh.',
                      action: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _K.indigo600,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry'),
                      ),
                    ),
                  ),
                ),
              ),
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
      label: 'Loading leave requests',
      child: Column(
        children: [
          const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final sm = c.maxWidth >= 640;
                return ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.all(sm ? 24 : 16),
                  children: const [
                    Row(
                      children: [
                        _Bone(width: 44, height: 44, radius: 13),
                        SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Bone(width: 200, height: 18),
                            SizedBox(height: 8),
                            _Bone(width: 260, height: 12),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                    Align(alignment: Alignment.centerLeft, child: _Bone(width: 280, height: 40, radius: 10)),
                    SizedBox(height: 16),
                    _Bone(height: 220),
                    SizedBox(height: 12),
                    _Bone(height: 220),
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

InputDecoration _inputDecoration({String? hint, IconData? icon}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: _K.gray400),
    prefixIcon: icon == null ? null : Icon(icon, size: 16, color: _K.gray400),
    prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 20),
    filled: true,
    fillColor: _K.gray50,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: border(_K.gray200),
    enabledBorder: border(_K.gray200),
    disabledBorder: border(_K.gray100),
    focusedBorder: border(_K.indigo300, 1.5),
  );
}

/// White card with a hairline border.
class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.padding = const EdgeInsets.all(16), this.clip = false});

  final Widget child;
  final EdgeInsets padding;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.size = 36});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _K.indigo50,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: _K.indigo100),
      ),
      child: Text(
        _initials(name),
        style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w700, color: _K.indigo600),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final tone = _decisionTone(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tone.border),
      ),
      child: Text(
        _sentenceCase(status),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tone.fg),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.tone});

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
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tone.fg)),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.text, required this.tone});

  final String text;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tone.border),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tone.fg)),
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
    final fg = selected ? _K.indigo600 : _K.gray600;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? _K.indigo50 : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? _K.indigo100 : _K.gray200)),
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
                    color: selected ? _K.indigo500 : _K.gray400,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.success = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: success ? _K.emerald50.withValues(alpha: 0.5) : _K.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: success ? _K.emerald100 : _K.gray200),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: success ? _K.emerald100 : _K.gray100, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: success ? _K.emerald600 : _K.gray400),
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
          if (action != null) ...[const SizedBox(height: 10), action!],
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.indigo600)),
        ),
      ),
    );
  }
}