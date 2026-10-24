// Port of features/admin/alerts/AlertsPage.tsx: the notifications feed
// ("Alerts & Messages" in the employee portal, "Alerts" for staff).
//
// Included: the feed with its "unread only" filter, paging, mark read / mark
// all read, the notification detail and the leave request detail.
// Still to come with the admin screens: sending broadcasts, broadcast history
// with read receipts, and the HR "Direct Leaves" approval queue.
//
// Layout (compact):
//   Dark header: title · reload · mark all read
//   [load-error banner]
//   Activity card: All / Unread toggle · grouped inbox rows (Today, Yesterday,
//   This week, Earlier) · pagination

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:hrm_app/services/leave_service.dart';
import 'package:hrm_app/services/notification_service.dart';
import 'package:hrm_app/utils/toast.dart';

const _pageSize = 10;

// ── Design tokens ───────────────────────────────────────────────────────────

class _K {
  static const gray100 = Color(0xFFF3F4F6);
  static const gray200 = Color(0xFFE5E7EB);
  static const gray400 = Color(0xFF9CA3AF);
  static const gray500 = Color(0xFF6B7280);
  static const gray600 = Color(0xFF4B5563);
  static const gray700 = Color(0xFF374151);
  static const gray800 = Color(0xFF1F2937);
  static const gray900 = Color(0xFF111827);
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo200 = Color(0xFFC7D2FE);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const indigo950 = Color(0xFF1E1B4B);
  static const purple600 = Color(0xFF9333EA);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald600 = Color(0xFF059669);
  static const emerald800 = Color(0xFF065F46);
  static const rose50 = Color(0xFFFFF1F2);
  static const rose200 = Color(0xFFFECDD3);
  static const rose600 = Color(0xFFE11D48);
  static const rose800 = Color(0xFF9F1239);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber200 = Color(0xFFFDE68A);
  static const amber800 = Color(0xFF92400E);
}

/// A tinted color set: soft background, border, and foreground.
class _Tone {
  const _Tone(this.bg, this.border, this.fg);

  final Color bg;
  final Color border;
  final Color fg;
}

const _indigo = _Tone(_K.indigo50, _K.indigo200, _K.indigo600);
const _emerald = _Tone(_K.emerald50, _K.emerald200, _K.emerald600);
const _rose = _Tone(_K.rose50, _K.rose200, _K.rose600);
const _gray = _Tone(_K.slate100, _K.slate200, _K.gray500);

/// Decision badges (leave status).
_Tone _statusTone(String? s) => switch (s) {
      'APPROVED' => const _Tone(_K.emerald50, _K.emerald200, _K.emerald800),
      'DECLINED' => const _Tone(_K.rose50, _K.rose200, _K.rose800),
      _ => const _Tone(_K.amber50, _K.amber200, _K.amber800),
    };

class _T {
  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3, color: _K.gray900);
  static const subtitle = TextStyle(fontSize: 12, height: 1.3, color: _K.gray500);
  static const label = TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _K.gray500);
  static const caption = TextStyle(fontSize: 11, height: 1.3, color: _K.gray400);
}

const _cardRadius = 16.0;
const _divider = Divider(height: 1, thickness: 1, color: _K.gray100);

// ── Date formatting (server times are UTC; show local time) ─────────────────

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsFull = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

DateTime? _local(String iso) => DateTime.tryParse(iso)?.toLocal();
String _two(int n) => n.toString().padLeft(2, '0');
String _hhmm(DateTime d) => '${_two(d.hour % 12 == 0 ? 12 : d.hour % 12)}:${_two(d.minute)} ${d.hour >= 12 ? 'PM' : 'AM'}';
DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// "09 Oct 2026, 02:30 PM"
String _fullDateTime(String iso) {
  final d = _local(iso);
  return d == null ? iso : '${_two(d.day)} ${_months[d.month - 1]} ${d.year}, ${_hhmm(d)}';
}

/// "October 9, 2026"
String _longDate(String iso) {
  final d = _local(iso);
  return d == null ? iso : '${_monthsFull[d.month - 1]} ${d.day}, ${d.year}';
}

/// "12 Mar 2026" from a date-only value like "2026-03-12".
String _dateOnly(String raw) {
  final d = DateTime.tryParse(raw);
  return d == null ? raw : '${_two(d.day)} ${_months[d.month - 1]} ${d.year}';
}

/// Inclusive calendar days between two date-only values (DST-safe).
int? _dayCount(String start, String end) {
  final s = DateTime.tryParse(start);
  final e = DateTime.tryParse(end.isEmpty ? start : end);
  if (s == null || e == null) return null;
  return DateTime.utc(e.year, e.month, e.day).difference(DateTime.utc(s.year, s.month, s.day)).inDays + 1;
}

/// "Just now", "5m ago", "3h ago", "Yesterday, 02:30 PM", "Oct 9, 02:30 PM".
String _relative(String iso) {
  final d = _local(iso);
  if (d == null) return iso;
  final now = DateTime.now();
  final diff = now.difference(d);
  final today = _dayOf(now);
  final day = _dayOf(d);
  if (!diff.isNegative && diff.inMinutes < 1) return 'Just now';
  if (!diff.isNegative && diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (day == today) return diff.isNegative ? _hhmm(d) : '${diff.inHours}h ago';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday, ${_hhmm(d)}';
  final year = d.year == now.year ? '' : ' ${d.year}';
  return '${_months[d.month - 1]} ${d.day}$year, ${_hhmm(d)}';
}

/// Inbox section a notification falls under.
String _dayGroup(String iso) {
  final d = _local(iso);
  if (d == null) return 'Earlier';
  final today = _dayOf(DateTime.now());
  final day = _dayOf(d);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  if (day.isAfter(today.subtract(const Duration(days: 7)))) return 'This week';
  return 'Earlier';
}

/// Leave request id from a notification link like "/alerts?id=12".
int? _leaveIdFromLink(String? link) {
  if (link == null) return null;
  final m = RegExp(r'[?&]id=(\d+)').firstMatch(link);
  return m == null ? null : int.parse(m.group(1)!);
}

/// Color and icon by what the title says (approved / declined / other).
({_Tone tone, IconData icon}) _noteStyle(String title) {
  final t = title.toLowerCase();
  if (t.contains('approved') || t.contains('accept')) {
    return (tone: _emerald, icon: Icons.check_circle_outline_rounded);
  }
  if (t.contains('decline') || t.contains('reject') || t.contains('late') || t.contains('missing') || t.contains('no show')) {
    return (tone: _rose, icon: Icons.error_outline_rounded);
  }
  return (tone: _indigo, icon: Icons.notifications_none_rounded);
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

// ═════════════════════════════════════════════════════════════════════════════

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  List<AppNotification> _notes = const [];
  int _total = 0;
  int _page = 1;
  bool _unreadOnly = false;
  bool _loading = true;
  bool _busy = false;
  bool _markingAll = false;
  int? _openingLeaveId;
  String? _error;
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    if (!_loading) setState(() => _busy = true);
    try {
      final res = await notificationService.fetchNotifications(page: _page, unreadOnly: _unreadOnly);
      if (!mounted || id != _loadId) return;
      setState(() {
        _notes = res.results;
        _total = res.count;
        _error = null;
      });
    } catch (_) {
      // Keep what's shown; the banner offers a retry.
      if (mounted && id == _loadId) setState(() => _error = 'Could not load your alerts.');
    } finally {
      if (mounted && id == _loadId) {
        setState(() {
          _loading = false;
          _busy = false;
        });
      }
    }
  }

  Future<void> _markRead(int id) async {
    try {
      await notificationService.markAsRead(id);
      if (!mounted) return;
      setState(() => _notes = [for (final n in _notes) n.id == id ? n.copyWith(isRead: true) : n]);
      notificationEvents.countsChanged();
      _load();
    } catch (_) {
      if (mounted) showToast(context, 'Could not mark this alert as read.', error: true);
    }
  }

  Future<void> _markAllRead() async {
    setState(() => _markingAll = true);
    try {
      await Future.wait([for (final n in _notes.where((n) => !n.isRead)) notificationService.markAsRead(n.id)]);
      notificationEvents.countsChanged();
      await _load();
    } catch (_) {
      // Whatever was marked stays marked; reload shows the rest.
      if (mounted) showToast(context, 'Some alerts could not be marked as read.', error: true);
      _load();
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  void _setPage(int page) {
    setState(() => _page = page);
    _load();
  }

  void _setUnreadOnly(bool v) {
    if (v == _unreadOnly) return;
    setState(() {
      _unreadOnly = v;
      _page = 1;
    });
    _load();
  }

  void _openNotification(AppNotification note) {
    if (!note.isRead) _markRead(note.id);
    final leaveId = _leaveIdFromLink(note.link);
    showDialog<void>(
      context: context,
      builder: (_) => _NotificationDialog(
        note: note,
        onViewLeave: leaveId == null ? null : () => _openLeave(leaveId),
      ),
    );
  }

  Future<void> _openLeave(int id) async {
    if (_openingLeaveId != null) return;
    setState(() => _openingLeaveId = id);
    try {
      final detail = await leaveService.fetchLeaveRequestDetail(id);
      if (!mounted) return;
      showDialog<void>(context: context, builder: (_) => _LeaveDetailDialog(request: detail));
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          'Could not load leave request details. It may have been deleted or is inaccessible.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _openingLeaveId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _PageSkeleton();

    final unreadOnPage = _notes.where((n) => !n.isRead).length;

    return RefreshIndicator(
      color: _K.indigo600,
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final sm = width >= 640;
          final gap = sm ? 20.0 : 16.0;

          final sections = <Widget>[
            _Header(
              wide: sm,
              busy: _busy,
              markingAll: _markingAll,
              unreadOnPage: unreadOnPage,
              moreThanOnePage: _total > _notes.length,
              onReload: _load,
              onMarkAll: _markAllRead,
            ),
            if (_error != null)
              _Banner(
                tone: const _Tone(_K.rose50, _K.rose200, _K.rose800),
                icon: Icons.error_outline_rounded,
                actionLabel: 'Retry',
                onAction: _load,
                child: Text('${_error!} Check your connection and try again.'),
              ),
            _feedCard(wide: sm),
          ];

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(sm ? 24 : 16),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
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

  Widget _feedCard({required bool wide}) {
    final header = _CardHeader(
      icon: Icons.inbox_outlined,
      tone: _indigo,
      title: 'Activity',
      subtitle: _unreadOnly ? '$_total unread' : '$_total alert${_total == 1 ? '' : 's'}',
    );
    final toggle = _Segmented<bool>(
      value: _unreadOnly,
      options: const [(false, 'All'), (true, 'Unread')],
      onChanged: _setUnreadOnly,
    );

    // Rows with a section label whenever the day group changes.
    final rows = <Widget>[];
    String? group;
    for (final note in _notes) {
      final g = _dayGroup(note.createdAt);
      if (g != group) {
        group = g;
        rows.add(_GroupLabel(g));
      } else {
        rows.add(_divider);
      }
      final leaveId = _leaveIdFromLink(note.link);
      rows.add(_NotificationRow(
        note: note,
        openingLeave: leaveId != null && _openingLeaveId == leaveId,
        onOpen: () => _openNotification(note),
        onMarkRead: () => _markRead(note.id),
        onViewLeave: leaveId == null ? null : () => _openLeave(leaveId),
      ));
    }

    return _Surface(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: wide
                ? Row(
                    children: [
                      Expanded(child: header),
                      const SizedBox(width: 12),
                      SizedBox(width: 180, child: toggle),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [header, const SizedBox(height: 10), toggle],
                  ),
          ),
          SizedBox(
            height: 2,
            child: _busy
                ? const LinearProgressIndicator(minHeight: 2, color: _K.indigo500, backgroundColor: _K.indigo50)
                : const ColoredBox(color: _K.gray100),
          ),
          if (_notes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: _unreadOnly
                  ? _EmptyState(
                      icon: Icons.mark_email_read_outlined,
                      title: "You're all caught up",
                      message: 'No unread alerts. Switch to All to see earlier ones.',
                      action: _LinkButton(label: 'Show all alerts', onTap: () => _setUnreadOnly(false)),
                    )
                  : const _EmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: 'No alerts yet',
                      message: 'Leave decisions, attendance events and announcements will appear here.',
                    ),
            )
          else
            AnimatedOpacity(
              opacity: _busy ? 0.6 : 1,
              duration: const Duration(milliseconds: 150),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
            ),
          if (_total > 0)
            Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _K.gray100))),
              child: _Pagination(page: _page, total: _total, onPage: _setPage),
            ),
        ],
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.wide,
    required this.busy,
    required this.markingAll,
    required this.unreadOnPage,
    required this.moreThanOnePage,
    required this.onReload,
    required this.onMarkAll,
  });

  final bool wide;
  final bool busy;
  final bool markingAll;
  final int unreadOnPage;
  final bool moreThanOnePage;
  final VoidCallback onReload;
  final VoidCallback onMarkAll;

  @override
  Widget build(BuildContext context) {
    final canMarkAll = unreadOnPage > 0 && !markingAll;

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
          child: const Icon(Icons.notifications_active_outlined, size: 22, color: _K.indigo200),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Alerts',
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
              Text(
                unreadOnPage > 0
                    ? '$unreadOnPage unread on this page. Leave decisions, attendance events and announcements.'
                    : 'Leave decisions, attendance events and announcements.',
                style: const TextStyle(fontSize: 12, height: 1.35, color: _K.slate300),
              ),
            ],
          ),
        ),
      ],
    );

    final markLabel = markingAll ? 'Marking…' : (moreThanOnePage ? 'Mark page read' : 'Mark all read');

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Reload alerts',
          child: Material(
            color: Colors.white.withValues(alpha: 0.06),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: InkWell(
              customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onTap: busy ? null : onReload,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: busy
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
        Tooltip(
          message: moreThanOnePage ? 'Marks the unread alerts on this page' : 'Marks every unread alert as read',
          child: Opacity(
            opacity: canMarkAll || markingAll ? 1 : 0.4,
            child: Semantics(
              button: true,
              enabled: canMarkAll,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(colors: [_K.indigo500, _K.purple600]),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: canMarkAll ? onMarkAll : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (markingAll)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          else
                            const Icon(Icons.done_all_rounded, size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            markLabel,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return Container(
      padding: EdgeInsets.all(wide ? 20 : 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: _K.slate700.withValues(alpha: 0.5)),
        gradient: const LinearGradient(colors: [_K.gray900, _K.slate800, _K.indigo950]),
      ),
      child: wide
          ? Row(children: [Expanded(child: title), const SizedBox(width: 16), actions])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 14), actions],
            ),
    );
  }
}

// ── Feed ────────────────────────────────────────────────────────────────────

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _K.slate50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Semantics(
        header: true,
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.gray500)),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.note,
    required this.openingLeave,
    required this.onOpen,
    required this.onMarkRead,
    required this.onViewLeave,
  });

  final AppNotification note;
  final bool openingLeave;
  final VoidCallback onOpen;
  final VoidCallback onMarkRead;
  final VoidCallback? onViewLeave;

  @override
  Widget build(BuildContext context) {
    final style = _noteStyle(note.title);
    final unread = !note.isRead;

    return Semantics(
      button: true,
      label: '${unread ? 'Unread. ' : ''}${note.title}. ${_relative(note.createdAt)}',
      child: Material(
        color: unread ? _K.indigo50.withValues(alpha: 0.45) : Colors.white,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Unread marker
                SizedBox(
                  width: 12,
                  child: unread
                      ? Padding(
                          padding: const EdgeInsets.only(top: 15),
                          child: Center(
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(color: _K.indigo600, shape: BoxShape.circle),
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 4),
                _IconBox(icon: style.icon, tone: style.tone, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              note.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                                color: unread ? _K.gray900 : _K.gray700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: _fullDateTime(note.createdAt),
                            child: Text(
                              _relative(note.createdAt),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                                color: unread ? _K.indigo600 : _K.gray400,
                                fontFeatures: _T.tabular,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        note.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, height: 1.4, color: _K.gray500),
                      ),
                      if (onViewLeave != null) ...[
                        const SizedBox(height: 8),
                        _ChipButton(
                          icon: Icons.description_outlined,
                          label: 'View leave request',
                          tone: _emerald,
                          loading: openingLeave,
                          onTap: onViewLeave!,
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: unread
                      ? IconButton(
                          tooltip: 'Mark as read',
                          onPressed: onMarkRead,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.mark_email_read_outlined, size: 18, color: _K.gray400),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({
    required this.icon,
    required this.label,
    required this.tone,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final _Tone tone;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: tone.border),
    );
    return Material(
      color: tone.bg,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.8, color: tone.fg))
              else
                Icon(icon, size: 14, color: tone.fg),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tone.fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination({required this.page, required this.total, required this.onPage});

  final int page;
  final int total;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final pages = math.max(1, (total / _pageSize).ceil());
    final from = (page - 1) * _pageSize + 1;
    final to = math.min(page * _pageSize, total);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Showing $from–$to of $total',
              style: const TextStyle(fontSize: 12, color: _K.gray500, fontFeatures: _T.tabular),
            ),
          ),
          IconButton(
            tooltip: 'Previous page',
            visualDensity: VisualDensity.compact,
            onPressed: page > 1 ? () => onPage(page - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Text(
            '$page / $pages',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.gray700, fontFeatures: _T.tabular),
          ),
          IconButton(
            tooltip: 'Next page',
            visualDensity: VisualDensity.compact,
            onPressed: page < pages ? () => onPage(page + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

// ── Notification detail ─────────────────────────────────────────────────────

class _NotificationDialog extends StatelessWidget {
  const _NotificationDialog({required this.note, required this.onViewLeave});

  final AppNotification note;

  /// Set when the notification links to a leave request.
  final VoidCallback? onViewLeave;

  @override
  Widget build(BuildContext context) {
    final style = _noteStyle(note.title);

    return _DialogFrame(
      icon: style.icon,
      tone: style.tone,
      title: 'Notification',
      subtitle: 'Received ${_fullDateTime(note.createdAt)}',
      footer: Row(
        children: [
          if (onViewLeave != null)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _K.emerald600,
                side: const BorderSide(color: _K.emerald200),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                onViewLeave!();
              },
              icon: const Icon(Icons.description_outlined, size: 16),
              label: const Text('View leave request'),
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
      body: [
        SelectableText(
          note.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.35, color: _K.gray900),
        ),
        const SizedBox(height: 10),
        SelectableText(
          note.message,
          style: const TextStyle(fontSize: 14, height: 1.6, color: _K.gray700),
        ),
      ],
    );
  }
}

// ── Leave request detail (read-only) ────────────────────────────────────────

class _LeaveDetailDialog extends StatelessWidget {
  const _LeaveDetailDialog({required this.request});

  final LeaveRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final wide = MediaQuery.sizeOf(context).width >= 640;
    final days = _dayCount(r.startDate, r.endDate);
    final sameDay = r.endDate.isEmpty || r.startDate == r.endDate;
    final dates = sameDay ? _dateOnly(r.startDate) : '${_dateOnly(r.startDate)} – ${_dateOnly(r.endDate)}';
    final tlComment = (r.tlComment != null && r.tlComment!.isNotEmpty) ? r.tlComment : null;

    final type = _Info(
      label: 'Leave type',
      child: Text(
        r.leaveTypeName,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _K.indigo600),
      ),
    );
    final when = _Info(
      label: 'Dates',
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: dates),
          if (days != null)
            TextSpan(
              text: '  ${days == 1 ? '1 day' : '$days days'}',
              style: const TextStyle(fontWeight: FontWeight.w500, color: _K.gray500),
            ),
        ]),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _K.gray800, fontFeatures: _T.tabular),
      ),
    );

    return _DialogFrame(
      icon: Icons.description_outlined,
      tone: _indigo,
      title: 'Leave request',
      subtitle: 'Request #${r.id}',
      body: [
        // Applicant
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _K.slate900, borderRadius: BorderRadius.circular(10)),
              child: Text(
                _initials(r.employeeName),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.employeeName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _K.gray900),
                  ),
                  Text('Applied ${_longDate(r.createdAt)}', style: _T.subtitle),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _StatusBadge(status: r.status),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _K.slate50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _K.slate100),
          ),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: type), const SizedBox(width: 16), Expanded(child: when)],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [type, const SizedBox(height: 12), when],
                ),
        ),
        const SizedBox(height: 14),
        _Info(
          label: 'Reason',
          child: Text(
            r.reason.isNotEmpty ? r.reason : 'No reason given.',
            style: TextStyle(fontSize: 14, height: 1.5, color: r.reason.isNotEmpty ? _K.gray700 : _K.gray400),
          ),
        ),
        const SizedBox(height: 18),
        const Text('Approval trail', style: _T.title),
        const SizedBox(height: 10),
        _TrailStep(
          icon: Icons.how_to_reg_outlined,
          title: 'Team lead',
          who: r.hasTeamLead
              ? (r.teamLeadName ?? 'Assigned team lead')
              : 'No team lead. The request went directly to HR.',
          status: r.hasTeamLead ? (r.tlStatus ?? 'PENDING') : null,
          remarks: r.hasTeamLead ? (tlComment ?? '') : null,
          emptyRemarks: 'No remarks from the team lead.',
        ),
        _TrailStep(
          icon: Icons.verified_user_outlined,
          title: 'HR decision',
          who: r.status != 'PENDING' ? 'Processed by HR' : 'Awaiting HR review',
          status: r.status,
          remarks: r.hrComment,
          emptyRemarks: 'No remarks from HR.',
          last: true,
        ),
      ],
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
                decoration: BoxDecoration(
                  color: tone.bg,
                  shape: BoxShape.circle,
                  border: Border.all(color: tone.border),
                ),
                child: Icon(icon, size: 14, color: tone.fg),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: _K.gray200,
                  ),
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
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(title, style: _T.title),
                        ),
                      ),
                      if (status != null) _StatusBadge(status: status!),
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final tone = _statusTone(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

// ── Dialog building blocks ──────────────────────────────────────────────────

class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.body,
    this.footer,
  });

  final IconData icon;
  final _Tone tone;
  final String title;
  final String subtitle;
  final List<Widget> body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 14),
              child: Row(
                children: [
                  _IconBox(icon: icon, tone: tone, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _K.gray900)),
                        const SizedBox(height: 2),
                        Text(subtitle, style: const TextStyle(fontSize: 12, color: _K.gray500, fontFeatures: _T.tabular)),
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

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _T.label),
        const SizedBox(height: 3),
        child,
      ],
    );
  }
}

// ── Loading skeleton ────────────────────────────────────────────────────────

class _PageSkeleton extends StatelessWidget {
  const _PageSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading alerts',
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
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _Bone(height: 84),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(_cardRadius),
                                border: Border.all(color: _K.gray100),
                              ),
                              child: Column(
                                children: [
                                  for (var i = 0; i < 5; i++) ...[
                                    if (i > 0) const SizedBox(height: 18),
                                    const Row(
                                      children: [
                                        _Bone(width: 36, height: 36, radius: 11),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              FractionallySizedBox(widthFactor: 0.45, child: _Bone(height: 12, radius: 4)),
                                              SizedBox(height: 8),
                                              FractionallySizedBox(widthFactor: 0.85, child: _Bone(height: 10, radius: 4)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
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

/// Two-option toggle (All / Unread).
class _Segmented<T> extends StatelessWidget {
  const _Segmented({required this.value, required this.options, required this.onChanged});

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _K.slate100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _K.slate200),
      ),
      child: Row(
        children: [
          for (final (v, label) in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: v == value,
                child: Material(
                  color: v == value ? Colors.white : Colors.transparent,
                  elevation: v == value ? 1 : 0,
                  shadowColor: const Color(0x33000000),
                  borderRadius: BorderRadius.circular(7),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(7),
                    onTap: () => onChanged(v),
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: v == value ? FontWeight.w600 : FontWeight.w500,
                          color: v == value ? _K.indigo600 : _K.gray500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
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
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: _K.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _K.slate200),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: _K.slate100, shape: BoxShape.circle),
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.indigo600)),
        ),
      ),
    );
  }
}