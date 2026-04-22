import 'dart:math';
import 'package:flutter/material.dart';
import 'common/app_colors.dart';

/// Guitar Tuna-style semi-circular arc meter with animated needle.
/// [centsOff] ranges from -50 (flat) to +50 (sharp).
/// [pitched] controls whether the needle is visible.
class TuningMeter extends StatefulWidget {
  final double centsOff;
  final bool pitched;

  const TuningMeter({
    super.key,
    required this.centsOff,
    required this.pitched,
  });

  @override
  State<TuningMeter> createState() => _TuningMeterState();
}

class _TuningMeterState extends State<TuningMeter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _needleAngle;
  double _previousCents = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _needleAngle = Tween<double>(begin: 0, end: 0).animate(_controller);
  }

  @override
  void didUpdateWidget(TuningMeter old) {
    super.didUpdateWidget(old);
    if (old.centsOff != widget.centsOff) {
      final from = _previousCents;
      final to = widget.centsOff;
      _needleAngle = Tween<double>(begin: from, end: to).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      );
      _previousCents = to;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _needleAngle,
      builder: (context, _) {
        return CustomPaint(
          painter: _MeterPainter(
            centsOff: _needleAngle.value,
            pitched: widget.pitched,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _MeterPainter extends CustomPainter {
  final double centsOff;
  final bool pitched;

  const _MeterPainter({required this.centsOff, required this.pitched});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.95);
    final radius = size.width * 0.42;

    // Draw background arc (dark grey)
    final bgPaint = Paint()
      ..color = AppColors.surfaceVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi, // start at 180° (left)
      pi, // sweep 180° (to right)
      false,
      bgPaint,
    );

    // Draw colored zone arcs on top
    _drawZoneArc(canvas, center, radius, -50, -25, AppColors.outOfTune);
    _drawZoneArc(canvas, center, radius, -25, -5, AppColors.close);
    _drawZoneArc(canvas, center, radius, -5, 5, AppColors.inTune);
    _drawZoneArc(canvas, center, radius, 5, 25, AppColors.close);
    _drawZoneArc(canvas, center, radius, 25, 50, AppColors.outOfTune);

    // Draw tick marks
    _drawTick(canvas, center, radius, -50);
    _drawTick(canvas, center, radius, -25);
    _drawTick(canvas, center, radius, 0);
    _drawTick(canvas, center, radius, 25);
    _drawTick(canvas, center, radius, 50);

    // Draw needle (only when pitched)
    if (pitched) {
      final angle = _centsToAngle(centsOff);
      final needleEnd = Offset(
        center.dx + (radius * 0.85) * cos(angle),
        center.dy + (radius * 0.85) * sin(angle),
      );

      final needlePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(center, needleEnd, needlePaint);

      // Pivot circle
      canvas.drawCircle(
        center,
        8,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        center,
        5,
        Paint()..color = AppColors.surface,
      );
    }
  }

  void _drawZoneArc(
      Canvas canvas, Offset center, double radius, double fromC, double toC, Color color) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.butt;

    final startAngle = _centsToAngle(fromC);
    final endAngle = _centsToAngle(toC);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      endAngle - startAngle,
      false,
      paint,
    );
  }

  void _drawTick(Canvas canvas, Offset center, double radius, double cents) {
    final angle = _centsToAngle(cents);
    final inner = Offset(
      center.dx + (radius - 12) * cos(angle),
      center.dy + (radius - 12) * sin(angle),
    );
    final outer = Offset(
      center.dx + (radius + 4) * cos(angle),
      center.dy + (radius + 4) * sin(angle),
    );
    canvas.drawLine(
      inner,
      outer,
      Paint()
        ..color = Colors.white54
        ..strokeWidth = 2,
    );
  }

  /// Maps cents (-50..+50) to angle in radians on the semi-circle.
  /// -50 cents = π (leftmost), 0 cents = 3π/2 (top), +50 cents = 2π (rightmost)
  double _centsToAngle(double cents) {
    // Semi-circle: starts at π (left), ends at 2π (right), center at 3π/2 (top/up)
    // We want 0 cents → top (3π/2), -50 → left (π), +50 → right (2π=0)
    final normalized = cents.clamp(-50.0, 50.0) / 50.0; // -1 to +1
    return pi + (normalized + 1) / 2 * pi; // π to 2π
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.centsOff != centsOff || old.pitched != pitched;
}
