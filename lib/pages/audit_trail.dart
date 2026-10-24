// Port of features/admin/audit/AuditTrailPage.tsx ("Audit Trail", company
// admins only): who did what, to what, and when. 15 per page.

import 'package:flutter/material.dart';

import 'package:hrm_app/components/ui/pagination_bar.dart';
import 'package:hrm_app/services/attendadmin_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';

const _pageSize = 15;

class _K {
  static const gray50 = Color(0xFFF9FAFB);
  static const gray100 = Color(0xFFF3F4F6);
  static const gray200 = Color(0xFFE5E7EB);
  static const gray400 = Color(0xFF9CA3AF);
  static const gray500 = Color(0xFF6B7280);
  static const gray600 = Color(0xFF4B5563);
  static const gray700 = Color(0xFF374151);
  static const gray900 = Color(0xFF111827);
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo200 = Color(0xFFC7D2FE);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald600 = Color(0xFF059669);
  static const red50 = Color(0xFFFEF2F2);
  static const red200 = Color(0xFFFECACA);
  static const red600 = Color(0xFFDC2626);
}

class _AuditLog {
  const _AuditLog({required this.id, required this.actorName, required this.action, required this.target, required this.createdAt});

  final int id;
  final String actorName;
  final String action;
  final String target;
  final DateTime? createdAt;

  factory _AuditLog.fromJson(Map<String, dynamic> j) => _AuditLog(
        id: j['id'] is num ? (j['id'] as num).toInt() : 0,
        actorName: '${j['actor_name'] ?? ''}',
        action: '${j['action'] ?? ''}',
        target: '${j['target'] ?? ''}',
        createdAt: DateTime.tryParse('${j['created_at'] ?? ''}')?.toLocal(),
      );
}

/// (bg, fg, border) by what the action did.
(Color, Color, Color) _actionColors(String action) {
  if (action.contains('DELETE')) return (_K.red50, _K.red600, _K.red200);
  if (action.contains('CREATE')) return (_K.emerald50, _K.emerald600, _K.emerald200);
  if (action.contains('UPDATE')) return (_K.indigo50, _K.indigo600, _K.indigo200);
  return (_K.gray100, _K.gray400, _K.gray200);
}

String _time(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${two(h)}:${two(d.minute)}:${two(d.second)} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

class AuditTrailPage extends StatefulWidget {
  const AuditTrailPage({super.key});

  @override
  State<AuditTrailPage> createState() => _AuditTrailPageState();
}

class _AuditTrailPageState extends State<AuditTrailPage> {
  List<_AuditLog> _logs = const [];
  int _total = 0;
  int _page = 1;
  bool _loading = true;
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
      final res = await attendanceAdminService.fetchAuditLogs(page: _page);
      if (!mounted || id != _loadId) return;
      setState(() {
        _logs = [for (final r in res.results) _AuditLog.fromJson(r)];
        _total = res.count;
      });
    } catch (_) {
      // Keep what's shown; pull down to retry.
    } finally {
      if (mounted && id == _loadId) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _logs.isEmpty) {
      return const Center(
        child: SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 4, color: _K.indigo500)),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sm = constraints.maxWidth >= 640;
          final md = constraints.maxWidth >= 768;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(sm ? 24 : 16),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _K.red50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _K.red200),
                  ),
                  child: const Text(
                    'SYSTEM SECURITY',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: _K.red600),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Audit Trail',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: _K.gray900),
              ),
              const SizedBox(height: 4),
              const Text(
                'Track all administrative actions and system modifications',
                style: TextStyle(fontSize: 14, color: _K.gray500),
              ),
              const SizedBox(height: 24),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _K.gray100),
                  boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_loading) const LinearProgressIndicator(minHeight: 2),
                    if (md)
                      Container(
                        color: _K.gray50,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: const Row(
                          children: [
                            Expanded(flex: 3, child: _HeaderText('ACTOR')),
                            Expanded(flex: 3, child: _HeaderText('ACTION')),
                            Expanded(flex: 5, child: _HeaderText('TARGET DESCRIPTION')),
                            Expanded(flex: 2, child: _HeaderText('TIMESTAMP', end: true)),
                          ],
                        ),
                      ),
                    if (_logs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 56),
                        child: Column(
                          children: [
                            Icon(Icons.verified_user_outlined, size: 40, color: _K.gray200),
                            SizedBox(height: 12),
                            Text('No audit logs found', style: TextStyle(fontSize: 14, color: _K.gray400)),
                          ],
                        ),
                      )
                    else
                      for (var i = 0; i < _logs.length; i++) _row(_logs[i], wide: md, divider: i < _logs.length - 1),
                    if (_total > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(_AuditLog log, {required bool wide, required bool divider}) {
    final (bg, fg, border) = _actionColors(log.action);
    final d = log.createdAt;

    final actor = Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: _K.gray100, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.person_outline, size: 16, color: _K.gray500),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(log.actorName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _K.gray900)),
        ),
      ],
    );
    final action = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: Border.all(color: border)),
      child: Text(
        log.action.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: fg),
      ),
    );
    final target = Text(log.target, style: const TextStyle(fontSize: 13, height: 1.4, color: _K.gray600));
    final when = Column(
      crossAxisAlignment: wide ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(d != null ? _time(d) : '', style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600, color: _K.gray700)),
        Text(
          d != null ? '${formatMMM(d)} ${formatDD(d)}, ${d.year}' : '',
          style: const TextStyle(fontSize: 11, color: _K.gray400),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(border: divider ? const Border(bottom: BorderSide(color: _K.gray50)) : null),
      child: wide
          ? Row(
              children: [
                Expanded(flex: 3, child: actor),
                Expanded(flex: 3, child: Align(alignment: Alignment.centerLeft, child: action)),
                Expanded(flex: 5, child: target),
                Expanded(flex: 2, child: when),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: actor), when]),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: action),
                const SizedBox(height: 6),
                target,
              ],
            ),
    );
  }
}

class _HeaderText extends StatelessWidget {
  const _HeaderText(this.text, {this.end = false});

  final String text;
  final bool end;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: end ? TextAlign.right : TextAlign.left,
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: _K.gray500),
    );
  }
}