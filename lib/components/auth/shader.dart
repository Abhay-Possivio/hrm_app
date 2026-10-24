import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Stand-in for the React <ShaderBackground />: slow-moving purple light
/// blobs over the dark base. Swap the painter for a FragmentProgram if you
/// want to port the original GLSL shader 1:1.
class ShaderBackground extends StatefulWidget {
  const ShaderBackground({super.key});

  @override
  State<ShaderBackground> createState() => _ShaderBackgroundState();
}

class _ShaderBackgroundState extends State<ShaderBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect reduced motion: freeze the background.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AuroraPainter(_controller),
        size: Size.infinite,
      ),
    );
  }
}

class _Blob {
  const _Blob(this.color, this.radius, this.phase, this.fx, this.fy);
  final Color color;
  final double radius; // fraction of the longest side
  final double phase;
  final int fx; // integer frequencies keep the loop seamless
  final int fy;
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  static const _base = Color(0xFF0E0818);
  static const _blobs = [
    _Blob(Color(0xFF6A3FC2), 0.60, 0.0, 1, 1),
    _Blob(Color(0xFF8B5CF6), 0.45, 2.1, 2, 1),
    _Blob(Color(0xFF4E2F68), 0.70, 4.2, 1, 2),
    _Blob(Color(0xFFB06AF0), 0.35, 1.3, -1, 2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = _base);

    final t = animation.value * 2 * math.pi;
    for (final b in _blobs) {
      final center = Offset(
        size.width * (0.5 + 0.35 * math.cos(t * b.fx + b.phase)),
        size.height * (0.5 + 0.35 * math.sin(t * b.fy + b.phase)),
      );
      final radius = size.longestSide * b.radius;
      final paint = Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            b.color.withValues(alpha: 0.45),
            b.color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }

    // Soft vignette to keep the card area readable.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.9,
          colors: [Colors.transparent, _base.withValues(alpha: 0.6)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) => false;
}