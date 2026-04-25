import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animated loading indicator with a cosmic feel:
///   - Outer ring: slow rotating dashed arc (CCW)
///   - Middle ring: faster rotating arc (CW)
///   - Center: pulsing glowing sparkle
///
/// Drop-in replacement for CircularProgressIndicator in loading states.
class CosmicLoader extends StatefulWidget {
  final double size;
  final Color color;
  final String? message;

  const CosmicLoader({
    super.key,
    this.size = 64,
    this.color = const Color(0xFF7C4DFF),
    this.message,
  });

  @override
  State<CosmicLoader> createState() => _CosmicLoaderState();
}

class _CosmicLoaderState extends State<CosmicLoader>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: s,
          height: s,
          child: AnimatedBuilder(
            animation: Listenable.merge([_spin, _pulse]),
            builder: (context, _) {
              return CustomPaint(
                painter: _CosmicLoaderPainter(
                  spinProgress: _spin.value,
                  pulseProgress: _pulse.value,
                  color: widget.color,
                ),
              );
            },
          ),
        ),
        if (widget.message != null) ...[
          const SizedBox(height: 14),
          Text(
            widget.message!,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ],
    );
  }
}

class _CosmicLoaderPainter extends CustomPainter {
  final double spinProgress; // 0..1, looping
  final double pulseProgress; // 0..1, mirrored
  final Color color;

  _CosmicLoaderPainter({
    required this.spinProgress,
    required this.pulseProgress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Outer rotating arc (slow, counter-clockwise)
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.8);
    final outerStart = -spinProgress * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r - 2),
      outerStart,
      math.pi * 1.2, // 216° sweep
      false,
      outerPaint,
    );

    // Outer faint background ring
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = color.withValues(alpha: 0.15);
    canvas.drawCircle(center, r - 2, bgPaint);

    // Middle rotating arc (faster, clockwise)
    final middlePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.9);
    final middleStart = spinProgress * 2 * math.pi * 2.2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r * 0.65),
      middleStart,
      math.pi * 0.75, // 135° sweep
      false,
      middlePaint,
    );

    // Orbit dot on outer ring
    final dotAngle = outerStart + math.pi * 1.2;
    final dotCenter = Offset(
      center.dx + (r - 2) * math.cos(dotAngle),
      center.dy + (r - 2) * math.sin(dotAngle),
    );
    final dotPaint = Paint()..color = color;
    canvas.drawCircle(dotCenter, 3.0, dotPaint);
    // Soft glow around the dot
    final dotGlow = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(dotCenter, 5.0, dotGlow);

    // Pulsing center sparkle
    final pulseScale = 0.65 + pulseProgress * 0.45; // 0.65..1.10
    final coreRadius = (r * 0.22) * pulseScale;
    final haloPaint = Paint()
      ..color = color.withValues(alpha: 0.25 + (1 - pulseProgress) * 0.2)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 * pulseScale);
    canvas.drawCircle(center, coreRadius + 4, haloPaint);

    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.95),
          color.withValues(alpha: 0.85),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius));
    canvas.drawCircle(center, coreRadius, corePaint);

    // 4-pointed star rays from center (subtle)
    final rayPaint = Paint()
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.55 * (1 - pulseProgress));
    final rayLen = coreRadius * 1.8;
    for (int i = 0; i < 4; i++) {
      final a = (i * math.pi / 2) + spinProgress * 2 * math.pi;
      canvas.drawLine(
        center,
        Offset(center.dx + math.cos(a) * rayLen,
            center.dy + math.sin(a) * rayLen),
        rayPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CosmicLoaderPainter oldDelegate) =>
      oldDelegate.spinProgress != spinProgress ||
      oldDelegate.pulseProgress != pulseProgress ||
      oldDelegate.color != color;
}
