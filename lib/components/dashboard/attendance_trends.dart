import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:hrm_app/services/hr_service.dart';
import 'package:hrm_app/utils/attendance_format.dart';

const _ranges = [7, 14, 30, 90];
const _refreshEvery = Duration(seconds: 60);
const _ratePanel = 92.0; // height of the attendance % band above the bars
const _rateColor = Color(0xFF6366F1);

enum _Series {
  onTime('On time', Color(0xFF10B981), Color(0xFFD1FAE5)),
  late('Late', Color(0xFFF59E0B), Color(0xFFFEF3C7)),
  absent('Absent', Color(0xFFF43F5E), Color(0xFFFFE4E6)),
  onLeave('On leave', Color(0xFF8B5CF6), Color(0xFFEDE9FE));

  const _Series(this.label, this.color, this.soft);

  final String label;
  final Color color;
  final Color soft;

  int of(TrendPoint p) => switch (this) {
        _Series.onTime => p.onTime,
        _Series.late => p.late,
        _Series.absent => p.absent,
        _Series.onLeave => p.onLeave,
      };
}

/// Tailwind colors used by this component.
class _K {
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
  static const indigo300 = Color(0xFFA5B4FC);
  static const indigo600 = Color(0xFF4F46E5);
  static const indigo700 = Color(0xFF4338CA);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald600 = Color(0xFF059669);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber600 = Color(0xFFD97706);
  static const rose50 = Color(0xFFFFF1F2);
  static const rose600 = Color(0xFFE11D48);
  static const violet50 = Color(0xFFF5F3FF);
  static const violet600 = Color(0xFF7C3AED);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
}

/// Prints numbers the way JavaScript does: 92 → "92", 92.5 → "92.5".
String _num(num v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

String _pct(num? v) => v == null ? '—' : '${_num(v)}%';

const _tabular = [ui.FontFeature.tabularFigures()];

// ── Data-loading wrapper used on the dashboards ─────────────────────────────

/// Attendance trends: daily headcount by status (on time / late / absent /
/// on leave) with the attendance-rate line, a 7/14/30/90-day range and
/// comparison with the previous period. Refreshes silently every minute.
class AttendanceTrendsChart extends StatefulWidget {
  const AttendanceTrendsChart({super.key, this.branchId, this.height = 340});

  final Object? branchId;
  final double height;

  @override
  State<AttendanceTrendsChart> createState() => _AttendanceTrendsChartState();
}

class _AttendanceTrendsChartState extends State<AttendanceTrendsChart> {
  int _days = 7;
  TrendData? _data;
  bool _loading = true;
  bool _error = false;
  int _request = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant AttendanceTrendsChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchId != widget.branchId) _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _load(silent: false);
    _timer = Timer.periodic(_refreshEvery, (_) => _load(silent: true));
  }

  Future<void> _load({required bool silent}) async {
    final id = ++_request;
    if (!silent && !_loading) setState(() => _loading = true);
    try {
      final res = await trendService.get(_days, widget.branchId);
      if (mounted && id == _request) {
        setState(() {
          _data = res;
          _error = false;
        });
      }
    } catch (_) {
      if (mounted && id == _request && !silent) setState(() => _error = true);
    } finally {
      if (mounted && id == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AttendanceTrendsView(
      data: _data,
      days: _days,
      onDaysChange: (d) {
        setState(() => _days = d);
        _start();
      },
      loading: _loading,
      error: _error,
      height: widget.height,
    );
  }
}

// ── View (pure; used by the dashboards and previews) ────────────────────────

class AttendanceTrendsView extends StatefulWidget {
  const AttendanceTrendsView({
    super.key,
    required this.data,
    required this.days,
    required this.onDaysChange,
    this.loading = false,
    this.error = false,
    this.height = 340,
  });

  final TrendData? data;
  final int days;
  final ValueChanged<int> onDaysChange;
  final bool loading;
  final bool error;
  final double height;

  @override
  State<AttendanceTrendsView> createState() => _AttendanceTrendsViewState();
}

class _AttendanceTrendsViewState extends State<AttendanceTrendsView> {
  final Set<_Series> _hidden = {};
  int? _hover;

  void _toggle(_Series s) {
    setState(() {
      if (!_hidden.remove(s)) _hidden.add(s);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final data = widget.data;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headline(lg: width >= 1024, sm: width >= 640),
            const SizedBox(height: 20),
            _controls(sm: width >= 640),
            const SizedBox(height: 20),
            SizedBox(height: widget.height, child: _chartArea(compact: width < 560)),
            if (data != null) ...[
              const SizedBox(height: 20),
              _footer(data),
            ],
          ],
        );
      },
    );
  }

  Widget _headline({required bool lg, required bool sm}) {
    final s = widget.data?.summary;
    final rate = s?.attendanceRate;

    final rateCard = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _K.indigo100.withValues(alpha: 0.7)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_K.indigo50, Colors.white, Colors.white],
        ),
      ),
      child: Row(
        children: [
          _RateRing(value: rate),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attendance rate · last ${widget.days} days',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _K.gray500),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _pct(rate),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: _K.gray900,
                      ),
                    ),
                    _DeltaPill(now: rate, before: s?.previousAttendanceRate),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'vs previous ${widget.days} days',
                  style: const TextStyle(fontSize: 11, color: _K.gray400),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final tiles = _TileGrid(
      columns: sm ? 4 : 2,
      gap: 12,
      children: [
        _StatTile(
          icon: Icons.how_to_reg_outlined,
          label: 'On time',
          value: _pct(s?.punctualityRate),
          background: _K.emerald50,
          foreground: _K.emerald600,
        ),
        _StatTile(
          icon: Icons.alarm,
          label: 'Late',
          value: '${s?.late ?? 0}',
          background: _K.amber50,
          foreground: _K.amber600,
        ),
        _StatTile(
          icon: Icons.person_off_outlined,
          label: 'Absences',
          value: '${s?.absent ?? 0}',
          background: _K.rose50,
          foreground: _K.rose600,
        ),
        _StatTile(
          icon: Icons.event_busy_outlined,
          label: 'On leave',
          value: '${s?.onLeave ?? 0}',
          background: _K.violet50,
          foreground: _K.violet600,
        ),
      ],
    );

    if (!lg) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [rateCard, const SizedBox(height: 12), tiles],
      );
    }
    return Row(
      children: [
        Expanded(flex: 13, child: rateCard),
        const SizedBox(width: 12),
        Expanded(flex: 20, child: tiles),
      ],
    );
  }

  Widget _controls({required bool sm}) {
    final legend = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final s in _Series.values)
          _LegendChip(series: s, off: _hidden.contains(s), onTap: () => _toggle(s)),
      ],
    );
    final range = _RangeSwitch(days: widget.days, onChanged: widget.onDaysChange);

    if (!sm) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [legend, const SizedBox(height: 12), range],
      );
    }
    return Row(
      children: [Expanded(child: legend), const SizedBox(width: 12), range],
    );
  }

  Widget _chartArea({required bool compact}) {
    final data = widget.data;
    if (widget.loading && data == null) return const _Skeleton();
    if (widget.error) {
      return const Center(
        child: Text('Could not load trends.', style: TextStyle(fontSize: 14, color: _K.gray400)),
      );
    }

    final points = data?.series ?? const <TrendPoint>[];
    final hasData = points.any((p) => p.expected > 0 || p.present > 0);
    if (!hasData) return const _EmptyState();

    return _TrendChart(
      points: points,
      days: widget.days,
      visible: [for (final s in _Series.values) if (!_hidden.contains(s)) s],
      hover: _hover,
      onHover: (i) {
        if (i != _hover) setState(() => _hover = i);
      },
      compact: compact,
      height: widget.height,
    );
  }

  Widget _footer(TrendData data) {
    final from = parseDateOnly(data.from);
    final to = parseDateOnly(data.to);
    return Text(
      '${from != null ? formatDDMMM(from) : data.from} – '
      '${to != null ? formatDDMMMYYYY(to) : data.to} · '
      'hatched columns are off days or holidays · tap a legend item to hide it',
      style: const TextStyle(fontSize: 11, color: _K.gray400),
    );
  }
}

// ── Header pieces ───────────────────────────────────────────────────────────

class _RateRing extends StatelessWidget {
  const _RateRing({required this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    final v = (value ?? 0).clamp(0.0, 100.0).toDouble();
    return SizedBox.square(
      dimension: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ExcludeSemantics(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: v),
              duration: const Duration(milliseconds: 600),
              curve: Curves.ease,
              builder: (_, t, __) => CustomPaint(
                size: const Size.square(64),
                painter: _RingPainter(t),
              ),
            ),
          ),
          Text(
            value == null ? '—' : '${value!.round()}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _K.indigo700),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 26.0;
    const stroke = 7.0;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = _K.indigo50,
    );
    if (value <= 0) return;

    canvas.drawArc(
      rect,
      -math.pi / 2,
      value / 100 * 2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF818CF8), Color(0xFF4F46E5)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.value != value;
}

class _DeltaPill extends StatelessWidget {
  const _DeltaPill({required this.now, required this.before});

  final double? now;
  final double? before;

  @override
  Widget build(BuildContext context) {
    final now = this.now;
    final before = this.before;
    if (now == null || before == null) {
      return const Text('no earlier data', style: TextStyle(fontSize: 11, color: _K.gray400));
    }

    final diff = ((now - before) * 10).round() / 10;
    if (diff == 0) {
      return const Text(
        'same as before',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _K.gray400),
      );
    }

    final good = diff > 0;
    final fg = good ? _K.emerald600 : _K.rose600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: good ? _K.emerald50 : _K.rose50,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(diff > 0 ? Icons.north_east : Icons.south_east, size: 12, color: fg),
          const SizedBox(width: 2),
          Text(
            '${_num(diff.abs())} pts',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _K.gray100),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 16, color: foreground),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _K.gray500),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    color: _K.gray900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.columns, required this.gap, required this.children});

  final int columns;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth =
            ((constraints.maxWidth - gap * (columns - 1)) / columns).floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final c in children) SizedBox(width: itemWidth, child: c)],
        );
      },
    );
  }
}

// ── Controls ────────────────────────────────────────────────────────────────

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.series, required this.off, required this.onTap});

  final _Series series;
  final bool off;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(
      side: BorderSide(color: off ? _K.gray200 : Colors.transparent),
    );
    return Semantics(
      button: true,
      toggled: !off,
      child: Material(
        color: off ? Colors.white : series.soft,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: off ? _K.slate300 : series.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  series.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: off ? _K.gray400 : _K.gray700,
                    decoration: off ? TextDecoration.lineThrough : null,
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

class _RangeSwitch extends StatelessWidget {
  const _RangeSwitch({required this.days, required this.onChanged});

  final int days;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Trend range',
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _K.gray100.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in _ranges)
              _RangeButton(
                label: '$r days',
                selected: days == r,
                onTap: () => onChanged(r),
              ),
          ],
        ),
      ),
    );
  }
}

class _RangeButton extends StatelessWidget {
  const _RangeButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: selected
                  ? const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? _K.indigo700 : _K.gray500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Chart ───────────────────────────────────────────────────────────────────

/// Shared layout so painting, hit-testing and the tooltip agree on positions.
class _Geometry {
  _Geometry(this.size, this.count, this.days, this.compact);

  final Size size;
  final int count;
  final int days;
  final bool compact;

  static const axisWidth = 38.0;
  static const rightPad = 8.0;

  double get left => axisWidth;
  double get right => size.width - rightPad;
  double get band => count == 0 ? 0 : (right - left) / count;
  double centerX(int i) => left + band * (i + 0.5);

  double get rateTop => 22;
  double get rateBottom => _ratePanel - 6;

  double get barsTop => _ratePanel + 8;
  double get tickHeight => days <= 30 ? (compact ? 24 : 40) : 28;
  double get barsBottom => size.height - tickHeight;

  double get maxBarWidth => days <= 7 ? 34 : days <= 14 ? 22 : days <= 30 ? 12 : 5;
  double get barWidth => math.min(maxBarWidth, band * 0.8);

  int? indexAt(Offset p) {
    if (count == 0 || p.dx < left || p.dx > right) return null;
    final i = ((p.dx - left) / band).floor();
    return math.min(math.max(i, 0), count - 1);
  }
}

double? _averageRate(List<TrendPoint> points) {
  final vals = [for (final p in points) if (p.attendanceRate != null) p.attendanceRate!];
  if (vals.isEmpty) return null;
  final mean = vals.reduce((a, b) => a + b) / vals.length;
  return (mean * 10).round() / 10;
}

/// The rate band starts a little below the lowest day so small changes stay visible.
double _rateFloor(List<TrendPoint> points) {
  final vals = [for (final p in points) if (p.attendanceRate != null) p.attendanceRate!];
  if (vals.isEmpty) return 0;
  final lowest = vals.reduce(math.min);
  return math.max(0, ((lowest - 5) / 10).floor() * 10).toDouble();
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({
    required this.points,
    required this.days,
    required this.visible,
    required this.hover,
    required this.onHover,
    required this.compact,
    required this.height,
  });

  final List<TrendPoint> points;
  final int days;
  final List<_Series> visible;
  final int? hover;
  final ValueChanged<int?> onHover;
  final bool compact;
  final double height;

  static const _tooltipWidth = 220.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, height);
        final geo = _Geometry(size, points.length, days, compact);
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        final hovered = (hover != null && hover! < points.length) ? hover : null;
        final avg = _averageRate(points);
        final floor = _rateFloor(points);

        return MouseRegion(
          onHover: (e) => onHover(geo.indexAt(e.localPosition)),
          onExit: (_) => onHover(null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Touch: tap a day to show its tooltip, tap it again to hide.
            onTapDown: (d) {
              if (d.kind == PointerDeviceKind.mouse) return;
              final i = geo.indexAt(d.localPosition);
              onHover(i == hovered ? null : i);
            },
            onHorizontalDragUpdate: (d) => onHover(geo.indexAt(d.localPosition)),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                TweenAnimationBuilder<double>(
                  key: ValueKey('${points.first.date}-${points.last.date}-$days'),
                  tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => CustomPaint(
                    size: size,
                    painter: _TrendPainter(
                      geo: geo,
                      points: points,
                      visible: visible,
                      hover: hovered,
                      rateFloor: floor,
                      avgRate: avg,
                      progress: t,
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 8,
                  child: IgnorePointer(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Attendance %',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _K.indigo600,
                          ),
                        ),
                        if (avg != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            'avg ${_num(avg)}%',
                            style: const TextStyle(fontSize: 10, color: _K.indigo300),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (hovered != null) _tooltip(geo, hovered),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tooltip(_Geometry geo, int i) {
    final cx = geo.centerX(i);
    final onLeft = cx > geo.size.width / 2;
    final rawLeft = onLeft ? cx - 14 - _tooltipWidth : cx + 14;
    final left = rawLeft.clamp(0.0, math.max(0.0, geo.size.width - _tooltipWidth)).toDouble();
    return Positioned(
      top: _ratePanel,
      left: left,
      width: _tooltipWidth,
      child: IgnorePointer(child: _TrendTooltip(point: points[i])),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.geo,
    required this.points,
    required this.visible,
    required this.hover,
    required this.rateFloor,
    required this.avgRate,
    required this.progress,
  });

  final _Geometry geo;
  final List<TrendPoint> points;
  final List<_Series> visible;
  final int? hover;
  final double rateFloor;
  final double? avgRate;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || geo.band <= 0) return;
    _paintRatePanel(canvas);
    _paintBars(canvas);
    _paintDateTicks(canvas);
  }

  // Attendance % band ───────────────────────────────────────────────────────

  void _paintRatePanel(Canvas canvas) {
    final top = geo.rateTop;
    final bottom = geo.rateBottom;
    final span = 100 - rateFloor;

    double y(double v, {bool animate = true}) {
      final shown = animate ? rateFloor + (v - rateFloor) * progress : v;
      return bottom - (shown - rateFloor) / span * (bottom - top);
    }

    const axisStyle = TextStyle(fontSize: 10, color: _K.indigo300);
    _text(canvas, '100%', Offset(geo.left - 6, top), axisStyle, align: TextAlign.right, vCenter: true);
    _text(canvas, '${rateFloor.round()}%', Offset(geo.left - 6, bottom), axisStyle,
        align: TextAlign.right, vCenter: true);

    final hover = this.hover;
    if (hover != null) {
      final cx = geo.centerX(hover);
      _dashed(canvas, Offset(cx, top), Offset(cx, bottom),
          Paint()..color = _K.indigo200..strokeWidth = 1, 3, 3);
    }

    final avg = avgRate;
    if (avg != null) {
      final ay = y(avg, animate: false);
      _dashed(canvas, Offset(geo.left, ay), Offset(geo.right, ay),
          Paint()..color = _rateColor.withValues(alpha: 0.3)..strokeWidth = 1, 4, 4);
    }

    // connectNulls: skip days without a rate and join the rest.
    final pts = <Offset>[];
    final indexes = <int>[];
    for (var i = 0; i < points.length; i++) {
      final r = points[i].attendanceRate;
      if (r == null) continue;
      pts.add(Offset(geo.centerX(i), y(r)));
      indexes.add(i);
    }
    if (pts.isEmpty) return;

    final line = _monotonePath(pts);
    final area = Path.from(line)
      ..lineTo(pts.last.dx, bottom)
      ..lineTo(pts.first.dx, bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_rateColor.withValues(alpha: 0.28), _rateColor.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTRB(geo.left, top, geo.right, bottom)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = _rateColor,
    );

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _rateColor;
    if (geo.days <= 30) {
      for (final p in pts) {
        canvas.drawCircle(p, 3, Paint()..color = Colors.white);
        canvas.drawCircle(p, 3, ring);
      }
    }

    if (hover != null) {
      final k = indexes.indexOf(hover);
      if (k >= 0) {
        canvas.drawCircle(pts[k], 5, Paint()..color = _rateColor);
        canvas.drawCircle(
          pts[k],
          5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white,
        );
      }
    }
  }

  // Headcount bars ──────────────────────────────────────────────────────────

  void _paintBars(Canvas canvas) {
    final top = geo.barsTop;
    final bottom = geo.barsBottom;
    if (bottom <= top) return;

    // Off days get a faint hatched column so the gap reads as "off", not missing data.
    final maxStack = math.max(
      1,
      points
          .map((p) => _Series.values.fold<int>(0, (sum, s) => sum + s.of(p)))
          .reduce(math.max),
    );
    final offMarker = maxStack * 0.18;

    var yMax = 0.0;
    for (final p in points) {
      final total = (p.isOffDay ? offMarker : 0) + visible.fold<int>(0, (sum, s) => sum + s.of(p));
      yMax = math.max(yMax, total.toDouble());
    }
    if (yMax <= 0) yMax = 1;

    final (niceMax, ticks) = _niceTicks(yMax);
    final scale = (bottom - top) / niceMax;

    // Grid and Y labels
    final gridPaint = Paint()
      ..color = const Color(0xFFEEF2F7)
      ..strokeWidth = 1;
    const axisStyle = TextStyle(fontSize: 11, color: _K.slate400);
    for (final t in ticks) {
      final ty = bottom - t * scale;
      _dashed(canvas, Offset(geo.left, ty), Offset(geo.right, ty), gridPaint, 4, 4);
      _text(canvas, '$t', Offset(geo.left - 6, ty), axisStyle, align: TextAlign.right, vCenter: true);
    }

    // Hover cursor
    final hover = this.hover;
    if (hover != null) {
      final cx = geo.centerX(hover);
      canvas.drawRect(
        Rect.fromLTRB(cx - geo.band / 2, top, cx + geo.band / 2, bottom),
        Paint()..color = _rateColor.withValues(alpha: 0.06),
      );
    }

    final w = geo.barWidth;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w > 10 ? 1.5 : 0.5
      ..color = Colors.white;

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final x = geo.centerX(i) - w / 2;
      var base = bottom;

      if (p.isOffDay) {
        final h = offMarker * scale * progress;
        if (h > 0) {
          _hatch(
            canvas,
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, base - h, w, h),
              Radius.circular(math.min(8, w / 2)),
            ),
          );
          base -= h;
        }
      }

      // Only the top-most non-empty segment of a stack gets rounded corners.
      final dim = hover != null && hover != i;
      final alpha = dim ? 0.4 : 1.0;
      final segments = [for (final s in visible) if (s.of(p) > 0) s];
      for (final s in segments) {
        final h = s.of(p) * scale * progress;
        if (h <= 0) continue;
        final rect = Rect.fromLTWH(x, base - h, w, h);
        final r = s == segments.last ? math.min(7.0, math.min(w / 2, h)) : 0.0;
        final path = r > 0
            ? (Path()
              ..addRRect(RRect.fromRectAndCorners(
                rect,
                topLeft: Radius.circular(r),
                topRight: Radius.circular(r),
              )))
            : (Path()..addRect(rect));
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                s.color.withValues(alpha: alpha),
                s.color.withValues(alpha: 0.75 * alpha),
              ],
            ).createShader(rect),
        );
        canvas.drawPath(path, outline);
        base -= h;
      }
    }
  }

  // X axis ──────────────────────────────────────────────────────────────────

  bool _showTick(int i) {
    final n = points.length;
    final band = geo.band;
    if (geo.days <= 30) {
      var step = geo.days <= 14 ? 1 : 2;
      while (band * step < 26) {
        step *= 2;
      }
      return i % step == 0;
    }
    if (i == 0 || i == n - 1) return true;
    final step = math.max(1, (56 / band).ceil());
    return i % step == 0 && n - 1 - i >= step;
  }

  void _paintDateTicks(Canvas canvas) {
    final days = geo.days;
    for (var i = 0; i < points.length; i++) {
      if (!_showTick(i)) continue;
      final p = points[i];
      final d = parseDateOnly(p.date);
      if (d == null) continue;
      final cx = geo.centerX(i);

      final topText = p.isToday
          ? 'Today'
          : days <= 14
              ? formatEEE(d)
              : days <= 30
                  ? '${d.day}'
                  : formatDMMM(d);
      _text(
        canvas,
        topText,
        Offset(cx, geo.barsBottom + 8),
        TextStyle(
          fontSize: 11,
          fontWeight: p.isToday ? FontWeight.w700 : FontWeight.w600,
          color: p.isToday ? _rateColor : (p.isOffDay ? _K.slate300 : _K.slate500),
        ),
        align: TextAlign.center,
      );

      // 30 days: the month shows under the first tick and near the 1st only.
      if (days <= 30 && !geo.compact) {
        final bottomText = days <= 14
            ? formatDMMM(d)
            : (i == 0 || d.day <= 2)
                ? formatMMM(d)
                : '';
        if (bottomText.isNotEmpty) {
          _text(
            canvas,
            bottomText,
            Offset(cx, geo.barsBottom + 22),
            TextStyle(fontSize: 10, color: p.isOffDay ? _K.slate300 : _K.slate400),
            align: TextAlign.center,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => true;
}

// ── Painting helpers ────────────────────────────────────────────────────────

/// Whole-number Y ticks with a "nice" step (about 4 intervals).
(double, List<int>) _niceTicks(double max) {
  final raw = max / 4;
  final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final normalized = raw / magnitude;
  final nice = normalized <= 1
      ? 1
      : normalized <= 2
          ? 2
          : normalized <= 5
              ? 5
              : 10;
  final step = math.max(1, (nice * magnitude).ceil());
  final top = (max / step).ceil() * step;
  return (top.toDouble(), [for (var v = 0; v <= top; v += step) v]);
}

/// Monotone cubic curve through the points (same idea as recharts' "monotone").
Path _monotonePath(List<Offset> pts) {
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  final n = pts.length;
  if (n == 1) return path;
  if (n == 2) return path..lineTo(pts[1].dx, pts[1].dy);

  final dx = [for (var i = 0; i < n - 1; i++) pts[i + 1].dx - pts[i].dx];
  final slope = [for (var i = 0; i < n - 1; i++) (pts[i + 1].dy - pts[i].dy) / dx[i]];
  final tangent = List<double>.filled(n, 0);
  tangent[0] = slope[0];
  tangent[n - 1] = slope[n - 2];
  for (var i = 1; i < n - 1; i++) {
    if (slope[i - 1] * slope[i] <= 0) continue;
    final w1 = 2 * dx[i] + dx[i - 1];
    final w2 = dx[i] + 2 * dx[i - 1];
    tangent[i] = (w1 + w2) / (w1 / slope[i - 1] + w2 / slope[i]);
  }
  for (var i = 0; i < n - 1; i++) {
    final h = dx[i] / 3;
    path.cubicTo(
      pts[i].dx + h,
      pts[i].dy + tangent[i] * h,
      pts[i + 1].dx - h,
      pts[i + 1].dy - tangent[i + 1] * h,
      pts[i + 1].dx,
      pts[i + 1].dy,
    );
  }
  return path;
}

void _text(
  Canvas canvas,
  String text,
  Offset anchor,
  TextStyle style, {
  TextAlign align = TextAlign.left,
  bool vCenter = false,
}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  var dx = anchor.dx;
  if (align == TextAlign.center) dx -= tp.width / 2;
  if (align == TextAlign.right) dx -= tp.width;
  tp.paint(canvas, Offset(dx, vCenter ? anchor.dy - tp.height / 2 : anchor.dy));
}

void _dashed(Canvas canvas, Offset a, Offset b, Paint paint, double dash, double gap) {
  final total = (b - a).distance;
  if (total == 0) return;
  final dir = (b - a) / total;
  for (var d = 0.0; d < total; d += dash + gap) {
    canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), paint);
  }
}

/// Diagonal hatch for off days (the SVG pattern in the React version).
void _hatch(Canvas canvas, RRect rrect) {
  canvas.save();
  canvas.clipRRect(rrect);
  canvas.drawRRect(rrect, Paint()..color = const Color(0xFFF8FAFC));
  final line = Paint()
    ..color = const Color(0xFFE2E8F0)
    ..strokeWidth = 3;
  final r = rrect.outerRect;
  for (var x = r.left - r.height; x < r.right; x += 8.5) {
    canvas.drawLine(Offset(x, r.bottom), Offset(x + r.height, r.top), line);
  }
  canvas.restore();
}

// ── Tooltip, loading and empty states ───────────────────────────────────────

class _TrendTooltip extends StatelessWidget {
  const _TrendTooltip({required this.point});

  final TrendPoint point;

  @override
  Widget build(BuildContext context) {
    final p = point;
    final d = parseDateOnly(p.date);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _K.gray100),
        boxShadow: const [
          BoxShadow(color: Color(0x0D1E1B4B), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  d != null ? formatEEEDDMMM(d) : p.date,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _K.gray900),
                ),
              ),
              if (p.isToday)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _K.indigo50,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Today',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _K.indigo600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (p.isOffDay)
            Row(
              children: [
                const Icon(Icons.event_busy_outlined, size: 14, color: _K.gray500),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Off day / holiday${p.present > 0 ? ' · ${p.present} worked' : ''}',
                    style: const TextStyle(fontSize: 12, color: _K.gray500),
                  ),
                ),
              ],
            )
          else ...[
            for (final s in _Series.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(s.label, style: const TextStyle(fontSize: 12, color: _K.gray600)),
                    ),
                    Text(
                      '${s.of(p)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _K.gray900,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _K.indigo50.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Attendance',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _K.indigo700),
                    ),
                  ),
                  Text(
                    _pct(p.attendanceRate),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _K.indigo700,
                      fontFeatures: _tabular,
                    ),
                  ),
                ],
              ),
            ),
            if (p.missingOut > 0) ...[
              const SizedBox(height: 6),
              Text(
                '${p.missingOut} missing clock-out',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _K.rose600),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Skeleton extends StatefulWidget {
  const _Skeleton();

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse
        ..stop()
        ..value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading attendance trends',
      child: FadeTransition(
        opacity: Tween(begin: 0.5, end: 1.0).animate(_pulse),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < 10; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: FractionallySizedBox(
                      alignment: Alignment.bottomCenter,
                      heightFactor: (30 + (i * 37) % 60) / 100,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: _K.gray100,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _DashedBorderPainter(),
      child: SizedBox.expand(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_rounded, size: 32, color: _K.gray300),
            SizedBox(height: 8),
            Text(
              'No attendance recorded in this period.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _K.gray400),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(0.5),
        const Radius.circular(16),
      ));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _K.gray200;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 6, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) => false;
}