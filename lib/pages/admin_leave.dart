// Port of features/admin/leaves/AdminLeavePage.tsx ("Leave Management Hub")
// with RecordLeaveModal.tsx.
//
// HR approves or declines leave requests (after the team lead's
// recommendation, where there is one) and can record an approved leave for
// an employee who didn't apply. Wide screens get a table with column headers;
// on phones each request is a compact card.
//
// Layout (compact):
//   Dark header: title · Record leave · refresh
//   [load-error banner]
//   Requests card: status tabs · table / cards · pagination
//   Dialogs: decision (with the team lead's recommendation), details (approval
//   trail), record-leave sheet (pinned header and footer)

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hrm_app/components/ui/pagination_bar.dart';
import 'package:hrm_app/services/employee_service.dart';
import 'package:hrm_app/services/leave_service.dart';
import 'package:hrm_app/services/notification_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';
import 'package:hrm_app/utils/toast.dart';

const _pageSize = 10;
const _tabs = [('ALL', 'All active'), ('PENDING', 'Pending'), ('APPROVED', 'Approved')];

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
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate700 = Color(0xFF334155);
  static const slate900 = Color(0xFF0F172A);
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo200 = Color(0xFFC7D2FE);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const indigo700 = Color(0xFF4338CA);
  static const indigo900 = Color(0xFF312E81);
  static const indigo950 = Color(0xFF1E1B4B);
  static const purple500 = Color(0xFFA855F7);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber200 = Color(0xFFFDE68A);
  static const amber700 = Color(0xFFB45309);
  static const rose50 = Color(0xFFFFF1F2);
  static const rose100 = Color(0xFFFFE4E6);
  static const rose200 = Color(0xFFFECDD3);
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
const _gray = _Tone(_K.slate100, _K.gray200, _K.gray500);

_Tone _statusTone(String? s) => switch (s) {
      'APPROVED' => const _Tone(_K.emerald50, _K.emerald200, _K.emerald700),
      'DECLINED' => const _Tone(_K.rose50, _K.rose200, _K.rose700),
      _ => const _Tone(_K.amber50, _K.amber200, _K.amber700),
    };

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3, color: _K.gray900);
  static const subtitle = TextStyle(fontSize: 12, height: 1.3, color: _K.gray500);
  static const label = TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _K.gray500);
  static const fieldLabel = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.gray700);
  static const caption = TextStyle(fontSize: 11, height: 1.3, color: _K.gray400);
  static const columnHead = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.gray500);
}

const _cardRadius = 16.0;
const _divider = Divider(height: 1, thickness: 1, color: _K.gray100);

// ── Helpers ─────────────────────────────────────────────────────────────────

String _typeName(LeaveRequest r) => r.leaveTypeName.isNotEmpty ? r.leaveTypeName : (r.leaveTypeDisplay ?? '');

/// "12 Mar 2026 – 14 Mar 2026", or one date for single-day leave.
String _period(String start, String end) {
  final s = parseDateOnly(start);
  final e = parseDateOnly(end);
  final a = s != null ? formatDDMMMYYYY(s) : start;
  final b = e != null ? formatDDMMMYYYY(e) : end;
  return (b.isEmpty || a == b) ? a : '$a – $b';
}

/// Inclusive calendar days (DST-safe).
int? _dayCount(String start, String end) {
  final s = parseDateOnly(start);
  final e = parseDateOnly(end);
  if (s == null || e == null) return null;
  return DateTime.utc(e.year, e.month, e.day).difference(DateTime.utc(s.year, s.month, s.day)).inDays + 1;
}

String _daysLabel(int n) => '$n day${n == 1 ? '' : 's'}';

String _sentenceCase(String s) {
  final t = s.replaceAll('_', ' ').trim().toLowerCase();
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return 'E';
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

// ── Page ────────────────────────────────────────────────────────────────────

class AdminLeavePage extends StatefulWidget {
  const AdminLeavePage({super.key});

  @override
  State<AdminLeavePage> createState() => _AdminLeavePageState();
}

class _AdminLeavePageState extends State<AdminLeavePage> {
  List<LeaveRequest> _requests = const [];
  int _total = 0;
  int _page = 1;
  String _status = 'ALL';
  bool _loading = true;
  bool _loadedOnce = false;
  String? _error;
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    setState(() => _loading = true);
    try {
      final res = await leaveService.fetchLeaveRequestPage(page: _page, status: _status == 'ALL' ? null : _status);
      if (!mounted || id != _loadId) return;
      setState(() {
        _requests = res.results;
        _total = res.count;
        _error = null;
        _loadedOnce = true;
      });
    } catch (err) {
      // Keep what's shown; the banner offers a retry.
      if (mounted && id == _loadId) setState(() => _error = apiError(err, 'Could not load leave requests.'));
    } finally {
      if (mounted && id == _loadId) setState(() => _loading = false);
    }
  }

  void _setStatus(String value) {
    if (value == _status) return;
    setState(() {
      _status = value;
      _page = 1;
    });
    _load();
  }

  Future<void> _decide(LeaveRequest req, String action) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _DecisionDialog(request: req, action: action),
    );
    if (done == true) {
      if (mounted) {
        showToast(
          context,
          action == 'APPROVED' ? "${req.employeeName}'s leave approved" : "${req.employeeName}'s leave declined",
        );
      }
      notificationEvents.countsChanged(); // the bell counts pending leaves for HR
      _load();
    }
  }

  void _details(LeaveRequest req) {
    showDialog<void>(
      context: context,
      builder: (_) => _DetailsDialog(
        request: req,
        onApprove: req.status == 'PENDING' ? () => _decide(req, 'APPROVED') : null,
        onDecline: req.status == 'PENDING' ? () => _decide(req, 'DECLINED') : null,
      ),
    );
  }

  Future<void> _record() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxWidth: 600),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _RecordLeaveForm(),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_loadedOnce && _error == null) return const _PageSkeleton();

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
            _Header(wide: sm, loading: _loading, onRecord: _record, onRefresh: _load),
            if (_error != null)
              _Banner(
                tone: const _Tone(_K.rose50, _K.rose200, _K.rose700),
                icon: Icons.error_outline_rounded,
                actionLabel: 'Retry',
                onAction: _load,
                child: Text(_error!),
              ),
            _requestsCard(wide: lg),
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

  Widget _requestsCard({required bool wide}) {
    final from = _total == 0 ? 0 : (_page - 1) * _pageSize + 1;
    final to = (_page - 1) * _pageSize + _requests.length;

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
                _CardHeader(
                  icon: Icons.event_note_outlined,
                  tone: _indigo,
                  title: 'Leave requests',
                  subtitle: _total == 0 ? 'No records' : 'Showing $from–$to of $_total',
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (i, (value, label)) in _tabs.indexed) ...[
                        if (i > 0) const SizedBox(width: 6),
                        _TabChip(label: label, selected: _status == value, onTap: () => _setStatus(value)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 2,
            child: _loading
                ? const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50)
                : const ColoredBox(color: _K.gray100),
          ),
          if (wide && _requests.isNotEmpty)
            Container(
              color: _K.gray50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: _tableRow(
                employee: const Text('Employee', style: _T.columnHead),
                leave: const Text('Leave', style: _T.columnHead),
                dates: const Text('Dates', style: _T.columnHead),
                teamLead: const Text('Team lead', style: _T.columnHead),
                status: const Text('Status', style: _T.columnHead),
                actions: const SizedBox.shrink(),
              ),
            ),
          if (_requests.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Loading leave requests…', textAlign: TextAlign.center, style: _T.subtitle),
                    )
                  : _status == 'PENDING'
                      ? const _EmptyState(
                          icon: Icons.task_alt_rounded,
                          success: true,
                          title: 'No pending requests',
                          message: 'Leave requests waiting for HR will appear here.',
                        )
                      : _EmptyState(
                          icon: Icons.event_busy_outlined,
                          title: 'No leave requests',
                          message: _status == 'ALL'
                              ? 'There are no active leave requests yet. You can record leave for an employee '
                                  'who told HR directly.'
                              : 'No ${_sentenceCase(_status).toLowerCase()} requests.',
                          action: _status == 'ALL'
                              ? _LinkButton(label: 'Record leave', onTap: _record)
                              : _LinkButton(label: 'Show all', onTap: () => _setStatus('ALL')),
                        ),
            )
          else
            AnimatedOpacity(
              opacity: _loading ? 0.55 : 1,
              duration: const Duration(milliseconds: 150),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _requests.length; i++) ...[
                    if (i > 0) _divider,
                    _RequestRow(
                      request: _requests[i],
                      wide: wide,
                      onView: () => _details(_requests[i]),
                      onApprove: () => _decide(_requests[i], 'APPROVED'),
                      onDecline: () => _decide(_requests[i], 'DECLINED'),
                    ),
                  ],
                ],
              ),
            ),
          if (_total > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.gray100))),
              child: PaginationBar(
                page: _page,
                total: _total,
                pageSize: _pageSize,
                onPage: (p) {
                  setState(() => _page = p);
                  _load();
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.wide, required this.loading, required this.onRecord, required this.onRefresh});

  final bool wide;
  final bool loading;
  final VoidCallback onRecord;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final title = Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: const Icon(Icons.description_outlined, size: 22, color: _K.indigo200),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Leave management',
                  style: TextStyle(
                    fontSize: wide ? 22 : 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.25,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Review leave requests across all departments, or record leave for an employee.',
                style: TextStyle(fontSize: 12, height: 1.35, color: _K.slate300),
              ),
            ],
          ),
        ),
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Refresh',
          child: Material(
            color: Colors.white.withValues(alpha: 0.06),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: InkWell(
              customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onTap: loading ? null : onRefresh,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _K.slate300),
                        )
                      : const Icon(Icons.refresh_rounded, size: 20, color: _K.slate300),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: _K.indigo700,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          onPressed: onRecord,
          icon: const Icon(Icons.edit_calendar_outlined, size: 16),
          label: const Text('Record leave'),
        ),
      ],
    );

    return Container(
      padding: EdgeInsets.all(wide ? 20 : 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: _K.slate700.withValues(alpha: 0.5)),
        gradient: const LinearGradient(colors: [_K.slate900, _K.indigo950, _K.slate900]),
      ),
      child: wide
          ? Row(children: [Expanded(child: title), const SizedBox(width: 16), actions])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 14), actions]),
    );
  }
}

// ── One leave request ───────────────────────────────────────────────────────

Widget _tableRow({
  required Widget employee,
  required Widget leave,
  required Widget dates,
  required Widget teamLead,
  required Widget status,
  required Widget actions,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(flex: 3, child: employee),
      const SizedBox(width: 12),
      Expanded(flex: 3, child: leave),
      const SizedBox(width: 12),
      Expanded(flex: 3, child: dates),
      const SizedBox(width: 12),
      Expanded(flex: 2, child: teamLead),
      const SizedBox(width: 12),
      Expanded(flex: 2, child: status),
      const SizedBox(width: 12),
      SizedBox(width: 230, child: Align(alignment: Alignment.centerRight, child: actions)),
    ],
  );
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.wide,
    required this.onView,
    required this.onApprove,
    required this.onDecline,
  });

  final LeaveRequest request;
  final bool wide;
  final VoidCallback onView;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final pending = r.status == 'PENDING';
    final days = _dayCount(r.startDate, r.endDate);

    final employee = Row(
      children: [
        _Avatar(name: r.employeeName),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.employeeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray900),
              ),
              Text('ID #${r.employee}', style: const TextStyle(fontSize: 11, color: _K.gray500, fontFeatures: _T.tabular)),
            ],
          ),
        ),
      ],
    );

    final leave = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_typeName(r), maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray800)),
        if (r.reason.isNotEmpty)
          Text(r.reason, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _K.gray500)),
      ],
    );

    final dates = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_period(r.startDate, r.endDate),
            style: const TextStyle(fontSize: 13, color: _K.gray800, fontFeatures: _T.tabular)),
        if (days != null) Text(_daysLabel(days), style: _T.caption),
      ],
    );

    final teamLead = _TeamLeadCell(request: r);

    final status = Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        _StatusBadge(status: r.status),
        if (r.recordedByHr) const _MiniChip(text: 'Recorded by HR', tone: _gray),
      ],
    );

    if (wide) {
      return Material(
        color: Colors.white,
        child: InkWell(
          onTap: onView,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _tableRow(
              employee: employee,
              leave: leave,
              dates: dates,
              teamLead: teamLead,
              status: status,
              actions: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (pending) ...[
                    _DeclineButton(onPressed: onDecline),
                    const SizedBox(width: 6),
                    _ApproveButton(onPressed: onApprove),
                    const SizedBox(width: 4),
                  ],
                  IconButton(
                    tooltip: 'View details',
                    visualDensity: VisualDensity.compact,
                    onPressed: onView,
                    icon: const Icon(Icons.chevron_right_rounded, size: 20, color: _K.gray400),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Phone card
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onView,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: employee), const SizedBox(width: 8), _StatusBadge(status: r.status)],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _K.gray50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _K.gray100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _MiniChip(text: _typeName(r), tone: _indigo),
                        Text(_period(r.startDate, r.endDate),
                            style: const TextStyle(fontSize: 12, color: _K.gray700, fontFeatures: _T.tabular)),
                        if (days != null)
                          Text(_daysLabel(days),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.gray500)),
                        if (r.recordedByHr) const _MiniChip(text: 'Recorded by HR', tone: _gray),
                      ],
                    ),
                    if (r.reason.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(r.reason, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, height: 1.4, color: _K.gray700)),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Team lead', style: _T.label),
                        const SizedBox(width: 8),
                        Expanded(child: teamLead),
                      ],
                    ),
                  ],
                ),
              ),
              if (pending) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _DeclineButton(onPressed: onDecline, expand: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _ApproveButton(onPressed: onApprove, expand: true)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamLeadCell extends StatelessWidget {
  const _TeamLeadCell({required this.request});

  final LeaveRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    if (!r.hasTeamLead) {
      return const Text('No team lead', style: TextStyle(fontSize: 12, color: _K.gray400));
    }
    final comment = (r.tlComment != null && r.tlComment!.isNotEmpty) ? r.tlComment! : null;
    return Tooltip(
      message: comment ?? '',
      child: Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _StatusBadge(status: r.tlStatus ?? 'PENDING', small: true),
          if (comment != null) const Icon(Icons.chat_bubble_outline_rounded, size: 12, color: _K.gray400),
        ],
      ),
    );
  }
}

class _ApproveButton extends StatelessWidget {
  const _ApproveButton({required this.onPressed, this.expand = false});

  final VoidCallback onPressed;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: _K.emerald600,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: expand ? const Size.fromHeight(38) : const Size(0, 34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.check_rounded, size: 15),
      label: const Text('Approve'),
    );
  }
}

class _DeclineButton extends StatelessWidget {
  const _DeclineButton({required this.onPressed, this.expand = false});

  final VoidCallback onPressed;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        backgroundColor: _K.rose50,
        foregroundColor: _K.rose600,
        side: const BorderSide(color: _K.rose100),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: expand ? const Size.fromHeight(38) : const Size(0, 34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.close_rounded, size: 15),
      label: const Text('Decline'),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, this.small = false});

  final String status;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final tone = _statusTone(status);
    final icon = switch (status) {
      'APPROVED' => Icons.check_rounded,
      'DECLINED' => Icons.close_rounded,
      _ => Icons.schedule_rounded,
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 1 : 3),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: small ? 11 : 12, color: tone.fg),
          const SizedBox(width: 3),
          Text(
            _sentenceCase(status),
            style: TextStyle(fontSize: small ? 10.5 : 11, fontWeight: FontWeight.w600, color: tone.fg),
          ),
        ],
      ),
    );
  }
}

// ── Approve / decline ───────────────────────────────────────────────────────

class _DecisionDialog extends StatefulWidget {
  const _DecisionDialog({required this.request, required this.action});

  final LeaveRequest request;
  final String action; // APPROVED | DECLINED

  @override
  State<_DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends State<_DecisionDialog> {
  final _comment = TextEditingController();
  bool _processing = false;
  String? _error;

  bool get _approve => widget.action == 'APPROVED';

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      await leaveService.updateLeaveRequestStatus(widget.request.id, widget.action, _comment.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (mounted) setState(() => _error = apiError(err, 'Failed to update leave request. Please try again.'));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final accent = _approve ? _K.emerald600 : _K.rose600;
    final days = _dayCount(r.startDate, r.endDate);
    final tlComment = (r.tlComment != null && r.tlComment!.isNotEmpty) ? r.tlComment! : null;

    return _DialogFrame(
      icon: _approve ? Icons.check_rounded : Icons.close_rounded,
      tone: _approve
          ? const _Tone(_K.emerald50, _K.emerald200, _K.emerald600)
          : const _Tone(_K.rose50, _K.rose200, _K.rose600),
      title: _approve ? 'Approve leave' : 'Decline leave',
      subtitle: r.employeeName,
      closeEnabled: !_processing,
      body: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _K.gray50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _K.gray100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _MiniChip(text: _typeName(r), tone: _indigo),
                  Text(_period(r.startDate, r.endDate),
                      style: const TextStyle(fontSize: 12.5, color: _K.gray800, fontFeatures: _T.tabular)),
                  if (days != null)
                    Text(_daysLabel(days),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.gray500)),
                ],
              ),
              if (r.reason.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Reason', style: _T.label),
                const SizedBox(height: 2),
                Text(r.reason, style: const TextStyle(fontSize: 13, height: 1.45, color: _K.gray700)),
              ],
            ],
          ),
        ),
        if (r.hasTeamLead) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _K.indigo50.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _K.indigo100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.how_to_reg_outlined, size: 14, color: _K.indigo600),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text('Team lead recommendation',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.indigo900)),
                    ),
                    _StatusBadge(status: r.tlStatus ?? 'PENDING', small: true),
                  ],
                ),
                if (tlComment != null) ...[
                  const SizedBox(height: 4),
                  Text(tlComment, style: const TextStyle(fontSize: 12.5, height: 1.4, color: _K.indigo900)),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          _approve ? 'Comment for the employee (optional)' : 'Reason for declining (recommended)',
          style: _T.fieldLabel,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _comment,
          minLines: 3,
          maxLines: 5,
          autofocus: !_approve,
          enabled: !_processing,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 13, height: 1.4),
          decoration: _inputDecoration(
            hint: _approve ? 'e.g. Enjoy your time off' : 'Explain why, so the employee can plan around it',
          ).copyWith(contentPadding: const EdgeInsets.all(12)),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          _InlineNote(icon: Icons.error_outline_rounded, text: _error!, tone: const _Tone(_K.rose50, _K.rose200, _K.rose700)),
        ],
      ],
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: _K.gray600,
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            onPressed: _processing ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              disabledBackgroundColor: accent.withValues(alpha: 0.5),
              disabledForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            onPressed: _processing ? null : _submit,
            icon: _processing
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_approve ? Icons.check_rounded : Icons.close_rounded, size: 16),
            label: Text(_processing ? 'Saving…' : (_approve ? 'Approve leave' : 'Decline leave')),
          ),
        ],
      ),
    );
  }
}

// ── Details ─────────────────────────────────────────────────────────────────

class _DetailsDialog extends StatelessWidget {
  const _DetailsDialog({required this.request, this.onApprove, this.onDecline});

  final LeaveRequest request;

  /// Set when the request is still pending.
  final VoidCallback? onApprove;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final days = _dayCount(r.startDate, r.endDate);
    final tlComment = (r.tlComment != null && r.tlComment!.isNotEmpty) ? r.tlComment! : null;

    Widget info(String label, Widget child) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(label, style: _T.label), const SizedBox(height: 3), child],
        );

    return _DialogFrame(
      leading: _Avatar(name: r.employeeName, size: 36),
      title: r.employeeName,
      subtitle: 'Leave request #${r.id}',
      body: [
        Row(
          children: [
            _StatusBadge(status: r.status),
            if (r.recordedByHr) ...[const SizedBox(width: 6), const _MiniChip(text: 'Recorded by HR', tone: _gray)],
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _K.slate50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _K.slate100),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: info(
                  'Leave type',
                  Text(_typeName(r), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.indigo600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: info(
                  'Dates',
                  Text(
                    '${_period(r.startDate, r.endDate)}${days != null ? '\n${_daysLabel(days)}' : ''}',
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
            r.reason.isNotEmpty ? r.reason : 'No reason given.',
            style: TextStyle(fontSize: 13, height: 1.5, color: r.reason.isNotEmpty ? _K.gray700 : _K.gray400),
          ),
        ),
        const SizedBox(height: 18),
        const Text('Approval trail', style: _T.title),
        const SizedBox(height: 10),
        _TrailStep(
          icon: Icons.how_to_reg_outlined,
          title: 'Team lead',
          who: r.hasTeamLead ? 'Recommendation' : 'No team lead. The request came directly to HR.',
          status: r.hasTeamLead ? (r.tlStatus ?? 'PENDING') : null,
          remarks: r.hasTeamLead ? (tlComment ?? '') : null,
          emptyRemarks: 'No comment from the team lead.',
        ),
        _TrailStep(
          icon: Icons.verified_user_outlined,
          title: 'HR decision',
          who: r.recordedByHr ? 'Recorded directly by HR' : (r.status == 'PENDING' ? 'Waiting for your decision' : 'Final'),
          status: r.status,
          remarks: r.hrComment,
          emptyRemarks: 'No HR remarks.',
          last: true,
        ),
      ],
      footer: Row(
        children: [
          if (onDecline != null) ...[
            _DeclineButton(
              onPressed: () {
                Navigator.of(context).pop();
                onDecline!();
              },
            ),
            const SizedBox(width: 8),
          ],
          if (onApprove != null)
            _ApproveButton(
              onPressed: () {
                Navigator.of(context).pop();
                onApprove!();
              },
            ),
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _K.slate900,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _TrailStep extends StatelessWidget {
  const _TrailStep({
    required this.icon,
    required this.title,
    required this.who,
    required this.status,
    required this.remarks,
    required this.emptyRemarks,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String who;

  /// Null when this step does not apply (no team lead).
  final String? status;

  /// Null hides the remarks; empty shows [emptyRemarks].
  final String? remarks;
  final String emptyRemarks;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final tone = status == null ? _gray : _statusTone(status);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: tone.bg, shape: BoxShape.circle, border: Border.all(color: tone.border)),
                child: Icon(icon, size: 14, color: tone.fg),
              ),
              if (!last)
                Expanded(
                  child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: _K.gray200),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(title, style: _T.title)),
                      ),
                      if (status != null) _StatusBadge(status: status!, small: true),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(who, style: _T.subtitle),
                  if (remarks != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: _K.slate50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _K.slate100),
                      ),
                      child: Text(
                        remarks!.isNotEmpty ? remarks! : emptyRemarks,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: remarks!.isNotEmpty ? _K.gray700 : _K.gray400,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Record leave for an employee ────────────────────────────────────────────

class _RecordLeaveForm extends StatefulWidget {
  const _RecordLeaveForm();

  @override
  State<_RecordLeaveForm> createState() => _RecordLeaveFormState();
}

class _RecordLeaveFormState extends State<_RecordLeaveForm> {
  List<LeaveType> _types = const [];
  List<Employee> _matches = const [];
  Employee? _employee;
  int? _leaveType;
  DateTime _start = _today();
  DateTime _end = _today();
  final _search = TextEditingController();
  final _reason = TextEditingController();
  Timer? _debounce;
  bool _searched = false;
  bool _searching = false;
  bool _saving = false;
  String? _error;
  String? _employeeError;
  String? _typeError;
  String? _reasonError;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  int get _days => _end.isBefore(_start)
      ? 0
      : DateTime.utc(_end.year, _end.month, _end.day).difference(DateTime.utc(_start.year, _start.month, _start.day)).inDays + 1;

  @override
  void initState() {
    super.initState();
    leaveService.fetchLeaveTypes().then((t) {
      if (mounted) setState(() => _types = t);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      setState(() {
        _matches = const [];
        _searched = false;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final res = await employeeService.fetchEmployees(q: q, pageSize: 8);
        if (mounted) {
          setState(() {
            _matches = res.results;
            _searched = true;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _matches = const []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
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
    final employee = _employee;
    setState(() {
      _employeeError = employee == null ? 'Choose an employee.' : null;
      _typeError = _leaveType == null ? 'Choose a leave type.' : null;
      _reasonError = _reason.text.trim().isEmpty ? 'Add a note, e.g. how the employee informed HR.' : null;
      _error = _days == 0 ? 'Choose a valid date range.' : null;
    });
    if (_employeeError != null || _typeError != null || _reasonError != null || _error != null) return;

    setState(() => _saving = true);
    try {
      await leaveService.recordLeave(
        employeeId: employee!.id,
        leaveType: _leaveType!,
        startDate: toDateKey(_start),
        endDate: toDateKey(_end),
        reason: _reason.text.trim(),
      );
      if (!mounted) return;
      showToast(context, 'Leave recorded for ${employee.name}');
      Navigator.of(context).pop(true);
    } catch (err) {
      if (mounted) setState(() => _error = apiError(err, 'Could not record the leave'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final employee = _employee;
    final rangeText = _start == _end
        ? formatDDMMMYYYY(_start)
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
                const _IconBox(icon: Icons.edit_calendar_outlined, tone: _indigo, size: 40),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Record leave',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _K.gray900)),
                      SizedBox(height: 2),
                      Text('Saved as approved for an employee who told HR directly.', style: _T.subtitle),
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _InlineNote(
                    icon: Icons.info_outline_rounded,
                    text: 'Use this when an employee did not apply in time. Those days will show the leave type '
                        'instead of Absent.',
                    tone: _Tone(_K.indigo50, _K.indigo100, _K.indigo900),
                  ),
                  const SizedBox(height: 16),

                  // Employee
                  const Text('Employee', style: _T.fieldLabel),
                  const SizedBox(height: 6),
                  if (employee != null)
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                      decoration: BoxDecoration(
                        color: _K.indigo50.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _K.indigo200),
                      ),
                      child: Row(
                        children: [
                          _Avatar(name: employee.name, size: 32),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(employee.name,
                                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _K.gray900)),
                                Text(
                                  [employee.employeeCode, if (employee.branchName.isNotEmpty) employee.branchName].join(', '),
                                  style: const TextStyle(fontSize: 11, color: _K.gray500, fontFeatures: _T.tabular),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: _K.indigo600,
                              visualDensity: VisualDensity.compact,
                              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            onPressed: () => setState(() {
                              _employee = null;
                              _search.clear();
                              _matches = const [];
                              _searched = false;
                            }),
                            child: const Text('Change'),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    TextField(
                      controller: _search,
                      autofocus: true,
                      onChanged: _onSearch,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(fontSize: 14),
                      decoration: _inputDecoration(
                        hint: 'Search by name or employee code',
                        icon: Icons.search_rounded,
                        error: _employeeError,
                        suffix: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : null,
                      ),
                    ),
                    if (_matches.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _K.gray200),
                          boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, 4))],
                        ),
                        child: Column(
                          children: [
                            for (final (i, m) in _matches.indexed) ...[
                              if (i > 0) _divider,
                              Material(
                                color: Colors.white,
                                child: InkWell(
                                  onTap: () => setState(() {
                                    _employee = m;
                                    _matches = const [];
                                    _employeeError = null;
                                  }),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                    child: Row(
                                      children: [
                                        _Avatar(name: m.name, size: 28),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            m.name,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: _K.gray900),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          [m.employeeCode, if (m.branchName.isNotEmpty) m.branchName].join(', '),
                                          style: const TextStyle(fontSize: 11, color: _K.gray500, fontFeatures: _T.tabular),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    else if (_searched && !_searching)
                      const Padding(
                        padding: EdgeInsets.only(top: 6, left: 4),
                        child: Text('No matching employees.', style: _T.caption),
                      )
                    else if (_search.text.trim().isNotEmpty && _search.text.trim().length < 2)
                      const Padding(
                        padding: EdgeInsets.only(top: 6, left: 4),
                        child: Text('Type at least 2 characters.', style: _T.caption),
                      ),
                  ],
                  const SizedBox(height: 16),

                  // Leave type
                  const Text('Leave type', style: _T.fieldLabel),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    value: _leaveType,
                    isExpanded: true,
                    hint: Text(
                      _types.isEmpty ? 'Loading leave types…' : 'Select a leave type',
                      style: const TextStyle(fontSize: 14, color: _K.gray400),
                    ),
                    icon: const Icon(Icons.expand_more_rounded, size: 20, color: _K.gray500),
                    borderRadius: BorderRadius.circular(10),
                    style: const TextStyle(fontSize: 14, color: _K.gray900),
                    decoration: _inputDecoration(error: _typeError),
                    items: [for (final t in _types) DropdownMenuItem(value: t.id, child: Text(t.name))],
                    onChanged: (v) => setState(() {
                      _leaveType = v;
                      _typeError = null;
                    }),
                  ),
                  const SizedBox(height: 16),

                  // Dates
                  const Text('Dates', style: _T.fieldLabel),
                  const SizedBox(height: 6),
                  Semantics(
                    button: true,
                    label: 'Leave dates, $rangeText',
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
                            if (_days > 0)
                              Text(_daysLabel(_days),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.indigo600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 4),
                    child: Text('Off days and holidays in the range stay off days.', style: _T.caption),
                  ),
                  const SizedBox(height: 16),

                  // Note
                  const Text('Note', style: _T.fieldLabel),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _reason,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 1000,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                    onChanged: (_) {
                      if (_reasonError != null) setState(() => _reasonError = null);
                    },
                    decoration: _inputDecoration(
                      hint: 'e.g. Called in sick on the morning of 24 Sep; medical certificate received',
                      error: _reasonError,
                    ).copyWith(contentPadding: const EdgeInsets.all(12)),
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
                    tone: const _Tone(_K.rose50, _K.rose200, _K.rose700),
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
                          : const Icon(Icons.check_rounded, size: 16),
                      label: Text(_saving ? 'Saving…' : 'Record leave'),
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
                    _Bone(height: 84),
                    SizedBox(height: 16),
                    _Bone(height: 420),
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

InputDecoration _inputDecoration({String? hint, IconData? icon, Widget? suffix, String? error}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13.5, color: _K.gray400),
    errorText: error,
    errorStyle: const TextStyle(fontSize: 12, color: _K.rose600),
    prefixIcon: icon == null ? null : Icon(icon, size: 16, color: _K.gray500),
    prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 20),
    suffixIcon: suffix,
    filled: true,
    fillColor: _K.gray50,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: border(_K.gray200),
    enabledBorder: border(_K.gray200),
    disabledBorder: border(_K.gray100),
    focusedBorder: border(_K.indigo500, 1.5),
    errorBorder: border(_K.rose200),
    focusedErrorBorder: border(_K.rose600, 1.5),
  );
}

class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.title,
    required this.subtitle,
    required this.body,
    this.icon,
    this.tone,
    this.leading,
    this.footer,
    this.closeEnabled = true,
  });

  final IconData? icon;
  final _Tone? tone;
  final Widget? leading;
  final String title;
  final String subtitle;
  final List<Widget> body;
  final Widget? footer;
  final bool closeEnabled;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 14),
              child: Row(
                children: [
                  leading ?? _IconBox(icon: icon ?? Icons.info_outline_rounded, tone: tone ?? _indigo, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900)),
                        const SizedBox(height: 1),
                        Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.subtitle),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: closeEnabled ? () => Navigator.of(context).pop(false) : null,
                    icon: const Icon(Icons.close_rounded, size: 20, color: _K.gray400),
                  ),
                ],
              ),
            ),
            _divider,
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
              ),
            ),
            if (footer != null)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.gray100))),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
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
                Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _K.gray500, fontFeatures: _T.tabular)),
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

/// Initials on the indigo → purple gradient used across the leave screens.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.size = 32});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: const LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [_K.indigo500, _K.purple500],
        ),
      ),
      child: Text(
        _initials(name),
        style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w700, color: Colors.white),
      ),
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

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(side: BorderSide(color: selected ? _K.indigo600 : _K.gray200));
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? _K.indigo600 : Colors.white,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : _K.gray600),
            ),
          ),
        ),
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
        border: Border.all(color: success ? _K.emerald200 : _K.gray200),
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.indigo600)),
        ),
      ),
    );
  }
}