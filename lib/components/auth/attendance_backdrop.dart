// Port of components/auth/AttendanceBackdrop.tsx: the login background.
//
// A light lavender canvas with attendance-style chart graphics: heatmap, rate
// ring, mini bars, rising bars, layered area charts and a trend line. Drawn
// once with a CustomPainter: no animation, no images, no packages.
//
// Two layouts:
//   • Wide screens (landscape): the web's 1440 × 900 artwork, scaled to cover
//     the screen and centred, like the SVG's preserveAspectRatio "slice".
//   • Phones / portrait: the same pieces rearranged for a tall screen, so
//     nothing is cropped: heatmap, ring and mini bars across the top (above
//     the sign-in card, below the status bar), bars, area charts and trend
//     line along the bottom (below the card). Each band shrinks to the free
//     space around the card, so small phones still show both.
//
// The "random" values come from a seeded generator (seed 42, like the web),
// so the picture is the same on every launch.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const _brand = Color(0xFF4E2F68);
const _violet = Color(0xFF7E52D9);
const _pink = Color(0xFFD46FC4);
const _canvasTop = Color(0xFFFBF9FE);
const _canvasBottom = Color(0xFFEFE7FA);

class AttendanceBackdrop extends StatelessWidget {
  const AttendanceBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    // Keep the top band clear of the status bar on phones.
    final topInset = MediaQuery.paddingOf(context).top;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(painter: _BackdropPainter(topInset: topInset), size: Size.infinite),
        ),
      ),
    );
  }
}

// ── Shared helpers ──────────────────────────────────────────────────────────

/// Park–Miller generator, same as the web's rng().
class _Rng {
  _Rng(this._s);

  int _s;

  double next() {
    _s = (_s * 16807) % 2147483647;
    return _s / 2147483647;
  }
}

class _Cell {
  const _Cell(this.x, this.y, this.opacity, this.hot);

  final double x;
  final double y;
  final double opacity;
  final bool hot;
}

class _Bar {
  const _Bar(this.x, this.w, this.h);

  final double x;
  final double w;
  final double h;
}

Color _a(Color c, double opacity) => c.withValues(alpha: opacity.clamp(0.0, 1.0).toDouble());

/// Wave points across [width]; same formula as the web.
List<Offset> _wave(double width, double base, double amp, double phase, int steps) => [
      for (var i = 0; i <= steps; i++)
        Offset(
          i / steps * width,
          base + amp * math.sin(i * 0.85 + phase) + amp * 0.35 * math.sin(i * 2.1 + phase * 2),
        ),
    ];

/// Smooth path through points (horizontal bezier easing between neighbours).
Path _smoothPath(List<Offset> pts) {
  final p = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1];
    final b = pts[i];
    final mx = (a.dx + b.dx) / 2;
    p.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
  }
  return p;
}

/// Heatmap cells: weekdays in violet (a few "hot" ones in pink), weekends faint,
/// fading toward the right.
List<_Cell> _heatCells(_Rng r, {required int cols, required double size, required double gap, required Offset origin, required double fadeSpan}) {
  final cells = <_Cell>[];
  for (var c = 0; c < cols; c++) {
    for (var row = 0; row < 7; row++) {
      final fade = 1 - c / fadeSpan;
      final weekend = row >= 5;
      final v = r.next();
      cells.add(_Cell(
        origin.dx + c * (size + gap),
        origin.dy + row * (size + gap),
        weekend ? 0.05 * fade : (0.08 + v * 0.32) * fade,
        !weekend && v > 0.9,
      ));
    }
  }
  return cells;
}

// ── Artwork for each layout (computed once) ─────────────────────────────────

/// The web layout (1440 × 900).
class _WideArt {
  _WideArt._(this.cells, this.backBars, this.miniBars);

  static const w = 1440.0;
  static const h = 900.0;
  static const cellSize = 22.0;

  final List<_Cell> cells;
  final List<_Bar> backBars;
  final List<double> miniBars;

  // Same order of random draws as the web: heatmap, back bars, mini bars.
  static final instance = () {
    final r = _Rng(42);
    final cells = _heatCells(r, cols: 16, size: cellSize, gap: 6, origin: const Offset(70, 80), fadeSpan: 16);
    const bw = w / 22;
    final backBars = [
      for (var i = 0; i < 22; i++) _Bar(i * bw + bw * 0.22, bw * 0.56, 120 + 260 * (i / 22) + 60 * r.next()),
    ];
    final miniBars = [for (var i = 0; i < 7; i++) 26 + r.next() * 60 + i * 4];
    return _WideArt._(cells, backBars, miniBars);
  }();
}

/// The phone layout: 900 units wide; the height follows the screen.
class _TallArt {
  _TallArt._(this.cells, this.backBars, this.miniBars);

  static const w = 900.0;
  static const cellSize = 30.0;
  static const cellGap = 7.0;

  final List<_Cell> cells;
  final List<_Bar> backBars;
  final List<double> miniBars;

  static final instance = () {
    final r = _Rng(42);
    final cells = _heatCells(r, cols: 9, size: cellSize, gap: cellGap, origin: const Offset(50, 0), fadeSpan: 12);
    const bw = w / 12;
    final backBars = [
      for (var i = 0; i < 12; i++) _Bar(i * bw + bw * 0.22, bw * 0.56, 160 + 300 * (i / 12) + 80 * r.next()),
    ];
    final miniBars = [for (var i = 0; i < 7; i++) (26 + r.next() * 60 + i * 4) * 1.5];
    return _TallArt._(cells, backBars, miniBars);
  }();
}

// ── Painter ─────────────────────────────────────────────────────────────────

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({this.topInset = 0});

  /// Status-bar height in logical pixels (tall layout only).
  final double topInset;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (size.width >= size.height) {
      _paintWide(canvas, size);
    } else {
      _paintTall(canvas, size);
    }
    canvas.restore();
  }

  // ── Wide: the web layout ──────────────────────────────────────────────────

  void _paintWide(Canvas canvas, Size size) {
    const w = _WideArt.w, h = _WideArt.h;
    final art = _WideArt.instance;

    // Cover the screen, centred, cropping the overflow.
    final scale = math.max(size.width / w, size.height / h);
    canvas.translate((size.width - w * scale) / 2, (size.height - h * scale) / 2);
    canvas.scale(scale);

    _background(canvas, w, h);
    _ellipseGlow(canvas, w, h, cx: 0.82, cy: 0.18, r: 0.45, color: _violet, opacity: 0.16);
    _ellipseGlow(canvas, w, h, cx: 0.12, cy: 0.85, r: 0.5, color: _pink, opacity: 0.12);
    _grid(canvas, w, h, rowStep: 90, colStep: 120);
    _cells(canvas, art.cells, _WideArt.cellSize, 5);

    _ring(canvas, const Offset(1180, 170), radius: 56, stroke: 14, inner: 30);
    _miniBars(canvas, art.miniBars, origin: const Offset(1080, 330), step: 30, barWidth: 16, base: 110, lineEnd: 212, line: 2);

    _backBars(canvas, art.backBars, h, radius: 10);
    _area(canvas, _wave(w, 640, 34, 0.4, 12), w, h, _a(_violet, 0.20), _a(_violet, 0.04));
    _area(canvas, _wave(w, 700, 28, 1.9, 12), w, h, _a(_pink, 0.16), _a(_pink, 0.03));
    _area(canvas, _wave(w, 770, 22, 3.1, 12), w, h, _a(_violet, 0.26), _a(_brand, 0.14));
    _trend(canvas, _wave(w, 610, 30, 0.9, 12), w, stroke: 3, dot: 7, dotStroke: 2.5);
  }

  // ── Tall: phones ──────────────────────────────────────────────────────────

  void _paintTall(Canvas canvas, Size size) {
    const w = _TallArt.w;
    final art = _TallArt.instance;

    // Fit the width exactly; the canvas is as tall as the screen's shape.
    final scale = size.width / w;
    final h = size.height / scale;
    canvas.scale(scale);

    _background(canvas, w, h);
    _circleGlow(canvas, Offset(w * 0.85, h * 0.10), w * 0.62, _violet, 0.16);
    _circleGlow(canvas, Offset(w * 0.10, h * 0.90), w * 0.70, _pink, 0.12);
    _grid(canvas, w, h, rowStep: 90, colStep: 150);

    // Free space above and below the sign-in card (estimated card height,
    // matching the login page's normal / compact / tiny sizes).
    final cardPx = size.height <= 480 ? 330.0 : (size.height <= 700 ? 430.0 : 500.0);
    final freePx = math.max(0.0, (size.height - cardPx) / 2);

    // Top band (above the card): heatmap · ring · mini bars, just below the
    // status bar, scaled down when there's little room.
    const bandLeft = 50.0, bandWidth = 836.0, bandHeight = 252.0;
    final topRoomPx = freePx - topInset - 20;
    final ft = (topRoomPx / (bandHeight * scale)).clamp(0.45, 1.0).toDouble();
    canvas.save();
    canvas.translate((w - bandWidth * ft) / 2, (topInset + 12) / scale);
    canvas.scale(ft);
    canvas.translate(-bandLeft, 0);
    _cells(canvas, art.cells, _TallArt.cellSize, 7);
    _ring(canvas, const Offset(565, 120), radius: 80, stroke: 20, inner: 44);
    _miniBars(canvas, art.miniBars, origin: const Offset(690, 30), step: 28, barWidth: 18, base: 190, lineEnd: 200, line: 3);
    canvas.restore();

    // Bottom band (below the card): bars · area charts · trend line, shorter
    // when there's little room.
    final fb = (freePx / scale / 380).clamp(0.5, 1.0).toDouble();
    _backBars(canvas, [for (final b in art.backBars) _Bar(b.x, b.w, b.h * fb)], h, radius: 14);
    _area(canvas, _wave(w, h - 300 * fb, 40 * fb, 0.4, 8), w, h, _a(_violet, 0.20), _a(_violet, 0.04));
    _area(canvas, _wave(w, h - 240 * fb, 32 * fb, 1.9, 8), w, h, _a(_pink, 0.16), _a(_pink, 0.03));
    _area(canvas, _wave(w, h - 170 * fb, 26 * fb, 3.1, 8), w, h, _a(_violet, 0.26), _a(_brand, 0.14));
    _trend(canvas, _wave(w, h - 335 * fb, 34 * fb, 0.9, 8), w, stroke: 4, dot: 9, dotStroke: 3);
  }

  // ── Pieces ────────────────────────────────────────────────────────────────

  void _background(Canvas canvas, double w, double h) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, h), const [_canvasTop, _canvasBottom]),
    );
  }

  /// Radial glow relative to the canvas (an ellipse, like the SVG's
  /// objectBoundingBox gradient on the full rect).
  void _ellipseGlow(Canvas canvas, double w, double h,
      {required double cx, required double cy, required double r, required Color color, required double opacity}) {
    canvas.save();
    canvas.scale(w, h); // 0..1 canvas units
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1, 1),
      Paint()..shader = ui.Gradient.radial(Offset(cx, cy), r, [_a(color, opacity), _a(color, 0)]),
    );
    canvas.restore();
  }

  /// Round glow (tall layout, where a canvas-relative ellipse would stretch).
  void _circleGlow(Canvas canvas, Offset center, double radius, Color color, double opacity) {
    canvas.drawCircle(
      center,
      radius,
      Paint()..shader = ui.Gradient.radial(center, radius, [_a(color, opacity), _a(color, 0)]),
    );
  }

  void _grid(Canvas canvas, double w, double h, {required double rowStep, required double colStep}) {
    final paint = Paint()
      ..color = _a(_brand, 0.05)
      ..strokeWidth = 1;
    for (var y = rowStep; y < h; y += rowStep) {
      canvas.drawLine(Offset(0, y), Offset(w, y), paint);
    }
    for (var x = colStep; x < w; x += colStep) {
      for (var y = 0.0; y < h; y += 10) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 2, h)), paint); // dash 2, gap 8
      }
    }
  }

  void _cells(Canvas canvas, List<_Cell> cells, double size, double radius) {
    for (final c in cells) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(c.x, c.y, size, size), Radius.circular(radius)),
        Paint()..color = c.hot ? _a(_pink, c.opacity + 0.15) : _a(_violet, c.opacity),
      );
    }
  }

  /// Attendance-rate ring: track, 92 % arc from the top, soft centre.
  void _ring(Canvas canvas, Offset center, {required double radius, required double stroke, required double inner}) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = _a(_brand, 0.08),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * 0.92,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = _a(_violet, 0.45),
    );
    canvas.drawCircle(center, inner, Paint()..color = _a(_violet, 0.06));
  }

  /// Seven small bars on a baseline; the last one highlighted in pink.
  void _miniBars(Canvas canvas, List<double> bars,
      {required Offset origin,
      required double step,
      required double barWidth,
      required double base,
      required double lineEnd,
      required double line}) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    for (var i = 0; i < bars.length; i++) {
      final h = bars[i];
      final last = i == bars.length - 1;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(i * step, base - h, barWidth, h), Radius.circular(barWidth * 0.3)),
        Paint()..color = last ? _a(_pink, 0.35) : _a(_violet, 0.18),
      );
    }
    canvas.drawLine(
      Offset(-6, base + line),
      Offset(lineEnd, base + line),
      Paint()
        ..color = _a(_brand, 0.12)
        ..strokeWidth = line,
    );
    canvas.restore();
  }

  /// Rising bars standing on the bottom edge, fading upward-to-transparent.
  void _backBars(Canvas canvas, List<_Bar> bars, double h, {required double radius}) {
    for (final b in bars) {
      final rect = Rect.fromLTWH(b.x, h - b.h, b.w, b.h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        Paint()
          ..shader = ui.Gradient.linear(
            rect.topCenter,
            rect.bottomCenter,
            [_a(_violet, 0.10), _a(_violet, 0.03), _a(_violet, 0)],
            const [0, 0.6, 1],
          ),
      );
    }
  }

  /// Area chart: the smooth line closed to the bottom, top-to-bottom gradient.
  void _area(Canvas canvas, List<Offset> pts, double w, double h, Color top, Color bottom) {
    final path = _smoothPath(pts)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    final bounds = path.getBounds();
    canvas.drawPath(path, Paint()..shader = ui.Gradient.linear(bounds.topCenter, bounds.bottomCenter, [top, bottom]));
  }

  /// Trend line (violet → pink) with hollow data points.
  void _trend(Canvas canvas, List<Offset> pts, double w,
      {required double stroke, required double dot, required double dotStroke}) {
    canvas.drawPath(
      _smoothPath(pts),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(w, 0),
          [_a(_violet, 0.15), _a(_violet, 0.75), _a(_pink, 0.8)],
          const [0, 0.5, 1],
        ),
    );
    final points = pts.sublist(1, pts.length - 1);
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], dot, Paint()..color = _canvasTop);
      canvas.drawCircle(
        points[i],
        dot,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = dotStroke
          ..color = _a(_violet, 0.25 + (i / pts.length) * 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) => oldDelegate.topInset != topInset;
}