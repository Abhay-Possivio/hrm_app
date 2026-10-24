// Port of features/admin/corrections/CorrectionsReviewPage.tsx.
//
// Attendance correction (missing punch) requests. Used twice, like the web:
//   CorrectionsReviewPage(scope: 'all')  — HR gives the final approval
//   CorrectionsReviewPage(scope: 'team') — team leads recommend, then HR decides
//
// Wide screens get a table with column headers; on phones each request is a
// compact card with labelled Approve / Decline buttons.
//
// Layout (compact):
//   Header: title · what approving does · refresh
//   [load-error banner]
//   Requests card: status tabs (Open count) · search · table / cards · pagination

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hrm_app/components/attendance/correction_req.dart';
import 'package:hrm_app/components/ui/pagination_bar.dart';
import 'package:hrm_app/services/hr_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';
import 'package:hrm_app/utils/toast.dart';

const _pageSize = 20;
const _tabs = [('OPEN', 'Open'), ('APPROVED', 'Approved'), ('DECLINED', 'Declined'), ('ALL', 'All')];

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
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber100 = Color(0xFFFEF3C7);
  static const amber200 = Color(0xFFFDE68A);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);
  static const red50 = Color(0xFFFEF2F2);
  static const red100 = Color(0xFFFEE2E2);
  static const red200 = Color(0xFFFECACA);
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);
  static const sky50 = Color(0xFFF0F9FF);
  static const sky100 = Color(0xFFE0F2FE);
  static const sky700 = Color(0xFF0369A1);
}

/// A tinted color set: soft background, border, and foreground.
class _Tone {
  const _Tone(this.bg, this.border, this.fg);

  final Color bg;
  final Color border;
  final Color fg;
}

const _indigo = _Tone(_K.indigo50, _K.indigo100, _K.indigo600);
const _inTone = _Tone(_K.emerald50, _K.emerald200, _K.emerald700);
const _outTone = _Tone(_K.amber50, _K.amber200, _K.amber700);
const _amber = _Tone(_K.amber50, _K.amber100, _K.amber600);

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3, color: _K.gray900);
  static const subtitle = TextStyle(fontSize: 12, height: 1.3, color: _K.gray500);
  static const label = TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _K.gray500);
  static const caption = TextStyle(fontSize: 11, height: 1.3, color: _K.gray400);
  static const columnHead = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.gray500);
}

const _cardRadius = 16.0;
const _divider = Divider(height: 1, thickness: 1, color: _K.gray100);

String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

String _dateText(CorrectionRequest r) {
  final d = parseDateOnly(r.date);
  return d != null ? '${formatEEE(d)}, ${formatDDMMMYYYY(d)}' : r.date;
}

/// The requested punch lands on the calendar day after the attendance date.
bool _isNextDay(CorrectionRequest r) => r.timestamp.length >= 10 && r.timestamp.substring(0, 10) != r.date;

// ── Page ────────────────────────────────────────────────────────────────────

class CorrectionsReviewPage extends StatefulWidget {
  const CorrectionsReviewPage({super.key, required this.scope});

  /// "all" = HR / admin review, "team" = team lead review.
  final String scope;

  @override
  State<CorrectionsReviewPage> createState() => _CorrectionsReviewPageState();
}

class _CorrectionsReviewPageState extends State<CorrectionsReviewPage> {
  String _tab = 'OPEN';
  String _query = '';
  int _page = 1;
  CorrectionList? _data;
  bool _loading = true;
  String? _error;
  Timer? _debounce;
  int _loadId = 0;
  final _searchCtrl = TextEditingController();

  bool get _hr => widget.scope == 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    setState(() => _loading = true);
    try {
      final data = await correctionService.list(
        scope: widget.scope,
        status: _tab,
        q: _query,
        page: _page,
        pageSize: _pageSize,
      );
      if (mounted && id == _loadId) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (err) {
      if (mounted && id == _loadId) setState(() => _error = apiError(err, 'Could not load requests'));
    } finally {
      if (mounted && id == _loadId) setState(() => _loading = false);
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = value.trim();
      if (q == _query) return;
      setState(() {
        _query = q;
        _page = 1;
      });
      _load();
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    if (_query.isEmpty) return;
    setState(() {
      _query = '';
      _page = 1;
    });
    _load();
  }

  void _setTab(String tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _page = 1;
    });
    _load();
  }

  bool _canAct(CorrectionRequest r) => _hr ? r.canApproveHr : r.canApproveTl;

  Future<void> _act(CorrectionRequest r, {required bool approve}) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _DecisionDialog(request: r, approve: approve, hr: _hr),
    );
    if (done == true && mounted) {
      showToast(
        context,
        approve
            ? (_hr ? 'Approved. The punch was added and the day recalculated.' : 'Approved and sent to HR')
            : 'Request declined',
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null && _error == null) return const _PageSkeleton();

    final rows = _data?.results ?? const <CorrectionRequest>[];

    return RefreshIndicator(
      color: _K.indigo600,
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sm = width >= 640;
          final md = width >= 768;
          final lg = width >= 1024;
          final gap = sm ? 20.0 : 16.0;

          final sections = <Widget>[
            _Header(hr: _hr, wide: sm, loading: _loading, onRefresh: _load),
            if (_error != null)
              _Banner(
                tone: const _Tone(_K.red50, _K.red200, _K.red700),
                icon: Icons.error_outline_rounded,
                actionLabel: 'Retry',
                onAction: _load,
                child: Text(_error!),
              ),
            _requestsCard(rows: rows, sm: sm, wide: lg || md),
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

  Widget _requestsCard({required List<CorrectionRequest> rows, required bool sm, required bool wide}) {
    final count = _data?.count ?? 0;
    final open = _data?.openCount;

    final tabs = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, (id, label)) in _tabs.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            _TabChip(
              label: label,
              count: id == 'OPEN' && open != null && open > 0 ? open : null,
              selected: _tab == id,
              onTap: () => _setTab(id),
            ),
          ],
        ],
      ),
    );

    final search = ValueListenableBuilder<TextEditingValue>(
      valueListenable: _searchCtrl,
      builder: (context, value, _) => TextField(
        controller: _searchCtrl,
        onChanged: _onSearch,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14, color: _K.gray900),
        decoration: _inputDecoration(
          hint: 'Search employee name or code',
          icon: Icons.search_rounded,
          suffix: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                  onPressed: _clearSearch,
                  icon: const Icon(Icons.close_rounded, size: 16, color: _K.gray400),
                ),
        ),
      ),
    );

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
                if (sm)
                  Row(
                    children: [
                      Expanded(
                        child: _CardHeader(
                          icon: Icons.fact_check_outlined,
                          tone: _indigo,
                          title: 'Requests',
                          subtitle: '$count request${count == 1 ? '' : 's'}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(width: 300, child: search),
                    ],
                  )
                else ...[
                  _CardHeader(
                    icon: Icons.fact_check_outlined,
                    tone: _indigo,
                    title: 'Requests',
                    subtitle: '$count request${count == 1 ? '' : 's'}',
                  ),
                  const SizedBox(height: 12),
                  search,
                ],
                const SizedBox(height: 12),
                tabs,
              ],
            ),
          ),
          SizedBox(
            height: 2,
            child: _loading
                ? const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50)
                : const ColoredBox(color: _K.gray100),
          ),
          if (wide && rows.isNotEmpty)
            Container(
              color: _K.gray50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: _tableRow(
                employee: const Text('Employee', style: _T.columnHead),
                date: const Text('Date', style: _T.columnHead),
                punch: const Text('Requested punch', style: _T.columnHead),
                reason: const Text('Reason and comments', style: _T.columnHead),
                status: const Text('Status', style: _T.columnHead),
                actions: const SizedBox.shrink(),
              ),
            ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Loading requests…', textAlign: TextAlign.center, style: _T.subtitle),
                    )
                  : _tab == 'OPEN' && _query.isEmpty
                      ? _EmptyState(
                          icon: Icons.task_alt_rounded,
                          success: true,
                          title: 'No open requests',
                          message: _hr
                              ? 'Missing-punch requests waiting for HR will appear here.'
                              : 'Missing-punch requests from your team will appear here.',
                        )
                      : _EmptyState(
                          icon: Icons.inbox_outlined,
                          title: 'No requests here',
                          message: _query.isNotEmpty ? 'No matches for "$_query".' : 'Try another status.',
                          action: _query.isNotEmpty ? _LinkButton(label: 'Clear search', onTap: _clearSearch) : null,
                        ),
            )
          else
            AnimatedOpacity(
              opacity: _loading ? 0.55 : 1,
              duration: const Duration(milliseconds: 150),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) _divider,
                    _RequestRow(
                      request: rows[i],
                      hr: _hr,
                      canAct: _canAct(rows[i]),
                      wide: wide,
                      onApprove: () => _act(rows[i], approve: true),
                      onDecline: () => _act(rows[i], approve: false),
                    ),
                  ],
                ],
              ),
            ),
          if (count > _pageSize)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.gray100))),
              child: PaginationBar(
                page: _page,
                total: count,
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
  const _Header({required this.hr, required this.wide, required this.loading, required this.onRefresh});

  final bool hr;
  final bool wide;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _IconBox(icon: Icons.edit_calendar_outlined, tone: _indigo, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  hr ? 'Attendance corrections' : 'Team corrections',
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
              Text(
                hr
                    ? 'Missing-punch requests from employees. Approving adds the punch and recalculates the day.'
                    : 'Missing-punch requests from your team. Your approval sends the request to HR for the final decision.',
                style: const TextStyle(fontSize: 12, height: 1.4, color: _K.gray500),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        wide
            ? OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _K.gray700,
                  side: const BorderSide(color: _K.gray200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                onPressed: loading ? null : onRefresh,
                icon: loading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Refresh'),
              )
            : IconButton(
                tooltip: 'Refresh',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: _K.gray200),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: loading ? null : onRefresh,
                icon: loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, size: 18, color: _K.gray600),
              ),
      ],
    );
  }
}

// ── One request ─────────────────────────────────────────────────────────────

Widget _tableRow({
  required Widget employee,
  required Widget date,
  required Widget punch,
  required Widget reason,
  required Widget status,
  required Widget actions,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(flex: 3, child: employee),
      const SizedBox(width: 12),
      Expanded(flex: 2, child: date),
      const SizedBox(width: 12),
      Expanded(flex: 2, child: punch),
      const SizedBox(width: 12),
      Expanded(flex: 4, child: reason),
      const SizedBox(width: 12),
      Expanded(flex: 2, child: status),
      const SizedBox(width: 12),
      SizedBox(width: 200, child: Align(alignment: Alignment.topRight, child: actions)),
    ],
  );
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.hr,
    required this.canAct,
    required this.wide,
    required this.onApprove,
    required this.onDecline,
  });

  final CorrectionRequest request;
  final bool hr;
  final bool canAct;
  final bool wide;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final r = request;

    final employee = Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: _K.indigo50, shape: BoxShape.circle),
          child: Text(
            _initials(r.employeeName),
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _K.indigo600),
          ),
        ),
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
              Text(
                [r.employeeCode, if (r.branchName.isNotEmpty) r.branchName].join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: _K.gray500, fontFeatures: _T.tabular),
              ),
            ],
          ),
        ),
      ],
    );

    final date = Text(_dateText(r), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray900));
    final punch = _PunchChip(request: r);
    final comments = _Comments(request: r, maxReasonLines: wide ? 2 : 3);
    final status = _StatusCell(request: r, hr: hr);

    if (wide) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: _tableRow(
          employee: employee,
          date: date,
          punch: punch,
          reason: comments,
          status: status,
          actions: canAct
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DeclineButton(onPressed: onDecline),
                    const SizedBox(width: 6),
                    _ApproveButton(onPressed: onApprove),
                  ],
                )
              : const Text('—', style: TextStyle(fontSize: 13, color: _K.gray300)),
        ),
      );
    }

    // Phone card
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: employee), const SizedBox(width: 8), status],
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
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 12, color: _K.gray400),
                        const SizedBox(width: 5),
                        Text(_dateText(r),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.gray700)),
                      ],
                    ),
                    punch,
                  ],
                ),
                const SizedBox(height: 8),
                comments,
              ],
            ),
          ),
          if (canAct) ...[
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
    );
  }
}

class _PunchChip extends StatelessWidget {
  const _PunchChip({required this.request});

  final CorrectionRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final isIn = r.punchType == 'IN';
    final tone = isIn ? _inTone : _outTone;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: tone.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: tone.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isIn ? Icons.login_rounded : Icons.logout_rounded, size: 12, color: tone.fg),
              const SizedBox(width: 4),
              Text(isIn ? 'In' : 'Out', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tone.fg)),
            ],
          ),
        ),
        Text(
          fmtWallTime(r.timestamp),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray800, fontFeatures: _T.tabular),
        ),
        if (_isNextDay(r))
          const Tooltip(
            message: 'This punch falls on the next calendar day',
            child: _MiniChip(text: 'Next day', tone: _amber),
          ),
      ],
    );
  }
}

class _Comments extends StatelessWidget {
  const _Comments({required this.request, required this.maxReasonLines});

  final CorrectionRequest request;
  final int maxReasonLines;

  @override
  Widget build(BuildContext context) {
    final r = request;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: r.reason.length > 80 ? r.reason : '',
          child: Text(
            r.reason.isNotEmpty ? r.reason : 'No reason given.',
            maxLines: maxReasonLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, height: 1.4, color: r.reason.isNotEmpty ? _K.gray700 : _K.gray400),
          ),
        ),
        if (r.tlComment.isNotEmpty)
          _CommentLine(
            icon: Icons.how_to_reg_outlined,
            who: 'Team lead',
            text: r.tlComment,
            tone: const _Tone(_K.sky50, _K.sky100, _K.sky700),
          ),
        if (r.hrComment.isNotEmpty)
          _CommentLine(
            icon: Icons.verified_user_outlined,
            who: 'HR',
            text: r.hrComment,
            tone: const _Tone(_K.gray100, _K.gray200, _K.gray700),
          ),
      ],
    );
  }
}

class _CommentLine extends StatelessWidget {
  const _CommentLine({required this.icon, required this.who, required this.text, required this.tone});

  final IconData icon;
  final String who;
  final String text;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(8)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 12, color: tone.fg),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '$who: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: text),
                ]),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, height: 1.35, color: tone.fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCell extends StatelessWidget {
  const _StatusCell({required this.request, required this.hr});

  final CorrectionRequest request;
  final bool hr;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final style = correctionStatusStyle(r.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: style.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: style.border),
          ),
          child: Text(
            correctionStatusLabel(r.status) ?? r.statusDisplay,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: style.fg),
          ),
        ),
        if (hr && r.tlStatus == 'PENDING' && r.status == 'PENDING')
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Team lead not reviewed yet', style: _T.caption),
          ),
        if (r.tlStatus == 'APPROVED' && r.tlProcessedBy != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Team lead: ${r.tlProcessedBy}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.caption),
          ),
        if (r.processedBy != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('By ${r.processedBy}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _T.caption),
          ),
      ],
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
        backgroundColor: _K.red50,
        foregroundColor: _K.red600,
        side: const BorderSide(color: _K.red100),
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

// ── Decision dialog ─────────────────────────────────────────────────────────

class _DecisionDialog extends StatefulWidget {
  const _DecisionDialog({required this.request, required this.approve, required this.hr});

  final CorrectionRequest request;
  final bool approve;
  final bool hr;

  @override
  State<_DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends State<_DecisionDialog> {
  final _comment = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await correctionService.act(widget.request.id, widget.approve ? 'approve' : 'decline', comment: _comment.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (mounted) setState(() => _error = apiError(err, 'Action failed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final approve = widget.approve;
    final accent = approve ? _K.emerald600 : _K.red600;

    final consequence = approve
        ? (widget.hr
            ? 'A manual punch will be added and the day recalculated.'
            : 'The request goes to HR for the final decision.')
        : 'The employee will see that the request was declined, along with your comment.';

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
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 14),
              child: Row(
                children: [
                  _IconBox(
                    icon: approve ? Icons.check_rounded : Icons.close_rounded,
                    tone: approve
                        ? const _Tone(_K.emerald50, _K.emerald200, _K.emerald600)
                        : const _Tone(_K.red50, _K.red200, _K.red600),
                    size: 36,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      approve ? 'Approve correction' : 'Decline correction',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900),
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

            // Body
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.employeeName,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _K.gray900)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(_dateText(r), style: const TextStyle(fontSize: 12, color: _K.gray600)),
                              _PunchChip(request: r),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text('Reason', style: _T.label),
                          const SizedBox(height: 2),
                          Text(
                            r.reason.isNotEmpty ? r.reason : 'No reason given.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: r.reason.isNotEmpty ? _K.gray700 : _K.gray400,
                            ),
                          ),
                          if (widget.hr && r.tlComment.isNotEmpty)
                            _CommentLine(
                              icon: Icons.how_to_reg_outlined,
                              who: 'Team lead',
                              text: r.tlComment,
                              tone: const _Tone(_K.sky50, _K.sky100, _K.sky700),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(Icons.info_outline_rounded, size: 13, color: _K.gray400),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(consequence, style: const TextStyle(fontSize: 12, height: 1.4, color: _K.gray500)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      approve ? 'Comment (optional)' : 'Reason for declining (recommended)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.gray600),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _comment,
                      maxLength: 1000,
                      minLines: 3,
                      maxLines: 5,
                      autofocus: !approve,
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                      decoration: _inputDecoration(
                        hint: approve ? 'Add a note for the record' : 'Explain why, so the employee can fix it',
                      ).copyWith(contentPadding: const EdgeInsets.all(12)),
                    ),
                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: _K.red50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _K.red200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, size: 15, color: _K.red600),
                            const SizedBox(width: 6),
                            Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12, color: _K.red700))),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.gray100))),
              child: Row(
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
                      backgroundColor: accent,
                      disabledBackgroundColor: accent.withValues(alpha: 0.5),
                      disabledForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(approve ? Icons.check_rounded : Icons.close_rounded, size: 16),
                    label: Text(_saving ? 'Saving…' : (approve ? 'Approve' : 'Decline')),
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

// ── Loading skeleton ────────────────────────────────────────────────────────

class _PageSkeleton extends StatelessWidget {
  const _PageSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading correction requests',
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
                            _Bone(width: 210, height: 18),
                            SizedBox(height: 8),
                            _Bone(width: 260, height: 12),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
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

InputDecoration _inputDecoration({String? hint, IconData? icon, Widget? suffix}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13.5, color: _K.gray400),
    prefixIcon: icon == null ? null : Icon(icon, size: 16, color: _K.gray500),
    prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 20),
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 20),
    filled: true,
    fillColor: _K.gray50,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: border(_K.gray200),
    enabledBorder: border(_K.gray200),
    disabledBorder: border(_K.gray100),
    focusedBorder: border(_K.indigo500, 1.5),
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

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.text, required this.tone});

  final String text;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: tone.fg)),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.selected, required this.onTap, this.count});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(side: BorderSide(color: selected ? _K.gray900 : _K.gray200));
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? _K.gray900 : Colors.white,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : _K.gray600),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white.withValues(alpha: 0.2) : _K.amber100,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : _K.amber600,
                        fontFeatures: _T.tabular,
                      ),
                    ),
                  ),
                ],
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