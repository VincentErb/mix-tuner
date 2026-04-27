import 'package:flutter/material.dart';
import 'common/app_colors.dart';

/// Guitar Tuna-style horizontal cents strip.
///
/// Layout:
///
///   ┌────────────────────────────────────────────────┐
///   │ ♭                       │                    ♯ │   (♭ ♯ markers)
///   │                       ╭──╮                     │
///   │             ┌─────────│-3│─────────┐           │   (sliding pill)
///   │             │         ╰─┬╯         │           │
///   │             │           │          │           │   (tail line)
///   │ ─────────────────────── │ ──────────────────── │   (axis with center)
///   │      TOO LOW           │          TOO HIGH    │   (status)
///   └────────────────────────────────────────────────┘
///
/// The pill slides horizontally based on [centsOff] (clamped to ±50).
/// Color zones: green ≤ ±10¢, amber ≤ ±25¢, red beyond.
class TuningStrip extends StatelessWidget {
  /// Cents off target. Positive = sharp (right), negative = flat (left).
  final double centsOff;

  /// Whether a pitch is currently detected. When false the pill is hidden
  /// and the axis dims.
  final bool pitched;

  /// Optional translucent "ghost" pill drawn beneath the live one — useful
  /// for rendering held/uncertain frames. Pass null to disable.
  final double? ghostCentsOff;

  /// Range of the strip in cents. Anything beyond this clamps to the edge.
  final double rangeCents;

  /// In-tune tolerance (green zone half-width).
  final double inTuneCents;

  /// Almost-in-tune tolerance (amber zone half-width).
  final double closeCents;

  const TuningStrip({
    super.key,
    required this.centsOff,
    required this.pitched,
    this.ghostCentsOff,
    this.rangeCents = 50,
    this.inTuneCents = 10,
    this.closeCents = 25,
  });

  Color _colorForCents(double cents) {
    final a = cents.abs();
    if (a <= inTuneCents) return AppColors.inTune;
    if (a <= closeCents) return AppColors.close;
    return AppColors.outOfTune;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _StripPainter(
            centsOff: centsOff.clamp(-rangeCents, rangeCents).toDouble(),
            ghostCentsOff: ghostCentsOff?.clamp(-rangeCents, rangeCents).toDouble(),
            pitched: pitched,
            rangeCents: rangeCents,
            inTuneCents: inTuneCents,
            closeCents: closeCents,
            pillColor: _colorForCents(centsOff),
            ghostColor: ghostCentsOff != null
                ? _colorForCents(ghostCentsOff!).withValues(alpha: 0.25)
                : null,
          ),
        );
      },
    );
  }
}

class _StripPainter extends CustomPainter {
  final double centsOff;
  final double? ghostCentsOff;
  final bool pitched;
  final double rangeCents;
  final double inTuneCents;
  final double closeCents;
  final Color pillColor;
  final Color? ghostColor;

  _StripPainter({
    required this.centsOff,
    required this.ghostCentsOff,
    required this.pitched,
    required this.rangeCents,
    required this.inTuneCents,
    required this.closeCents,
    required this.pillColor,
    required this.ghostColor,
  });

  // Layout: top section is the pill area, bottom section is the axis line.
  static const double _axisFromBottom = 28;
  static const double _pillRadius = 18;
  static const double _pillStrokeWidth = 2.5;
  static const double _tailWidth = 2.0;

  double _xForCents(double cents, double width) {
    final t = (cents + rangeCents) / (2 * rangeCents); // 0..1
    final pad = _pillRadius + 8;
    return pad + t * (width - 2 * pad);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final axisY = h - _axisFromBottom;
    final dim = pitched ? 1.0 : 0.4;

    // ── Background grid (subtle horizontal lines) ───────────────────
    final gridPaint = Paint()
      ..color = AppColors.divider.withValues(alpha: 0.6 * dim)
      ..strokeWidth = 0.6;
    for (int i = 0; i <= 4; i++) {
      final y = (axisY) * (i / 4) + 4;
      canvas.drawLine(Offset(8, y), Offset(w - 8, y), gridPaint);
    }

    // ── Color zones on the axis ─────────────────────────────────────
    // Three bands: red (full strip), amber inside ±closeCents, green inside
    // ±inTuneCents. Drawn as thin rounded rectangles centered on axisY.
    const zoneHeight = 4.0;
    final zoneY = axisY - zoneHeight / 2;

    void drawZone(double centsHalfWidth, Color color) {
      final left = _xForCents(-centsHalfWidth, w);
      final right = _xForCents(centsHalfWidth, w);
      final paint = Paint()
        ..color = color.withValues(alpha: 0.55 * dim)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, zoneY, right, zoneY + zoneHeight),
          const Radius.circular(2),
        ),
        paint,
      );
    }

    // Outer red strip across the whole range
    drawZone(rangeCents, AppColors.outOfTune);
    drawZone(closeCents, AppColors.close);
    drawZone(inTuneCents, AppColors.inTune);

    // ── Center reference tick ───────────────────────────────────────
    final centerX = _xForCents(0, w);
    final tickPaint = Paint()
      ..color = AppColors.textPrimary.withValues(alpha: 0.55 * dim)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(centerX, axisY - 14),
      Offset(centerX, axisY + 14),
      tickPaint,
    );

    // ── Side tick marks at ±closeCents (subtle reference) ───────────
    final sideTick = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: 0.5 * dim)
      ..strokeWidth = 1.0;
    for (final c in [-closeCents, closeCents]) {
      final x = _xForCents(c, w);
      canvas.drawLine(Offset(x, axisY - 6), Offset(x, axisY + 6), sideTick);
    }

    // ── ♭ / ♯ glyphs at the edges ───────────────────────────────────
    _drawGlyph(canvas, '♭', Offset(14, axisY), dim);
    _drawGlyph(canvas, '♯', Offset(w - 14, axisY), dim);

    if (!pitched) return;

    // ── Ghost pill (held / uncertain) ───────────────────────────────
    if (ghostCentsOff != null && ghostColor != null) {
      _drawPill(
        canvas,
        x: _xForCents(ghostCentsOff!, w),
        axisY: axisY,
        cents: ghostCentsOff!,
        color: ghostColor!,
        textColor: ghostColor!,
        showTail: false,
      );
    }

    // ── Live pill ────────────────────────────────────────────────────
    final pillX = _xForCents(centsOff, w);

    // Tail line — from below the pill down to the axis, in the pill color.
    final tailPaint = Paint()
      ..color = pillColor.withValues(alpha: 0.85)
      ..strokeWidth = _tailWidth;
    canvas.drawLine(
      Offset(pillX, _pillRadius * 2 + 6),
      Offset(pillX, axisY - 3),
      tailPaint,
    );

    _drawPill(
      canvas,
      x: pillX,
      axisY: axisY,
      cents: centsOff,
      color: pillColor,
      textColor: AppColors.background,
      showTail: false, // already drawn above
    );
  }

  void _drawPill(
    Canvas canvas, {
    required double x,
    required double axisY,
    required double cents,
    required Color color,
    required Color textColor,
    required bool showTail,
  }) {
    final pillCenter = Offset(x, _pillRadius + 4);

    // Filled circle
    final fillPaint = Paint()..color = color;
    canvas.drawCircle(pillCenter, _pillRadius, fillPaint);

    // Subtle outline ring
    final ringPaint = Paint()
      ..color = color.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _pillStrokeWidth;
    canvas.drawCircle(pillCenter, _pillRadius + 1.5, ringPaint);

    // Cents text
    final centsText = cents.abs() < 1
        ? '0'
        : '${cents >= 0 ? '+' : ''}${cents.toStringAsFixed(0)}';
    final tp = TextPainter(
      text: TextSpan(
        text: centsText,
        style: TextStyle(
          color: textColor,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      pillCenter - Offset(tp.width / 2, tp.height / 2),
    );
  }

  void _drawGlyph(Canvas canvas, String glyph, Offset center, double dim) {
    final tp = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          color: AppColors.textSecondary.withValues(alpha: dim),
          fontSize: 22,
          fontWeight: FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.centsOff != centsOff ||
      old.ghostCentsOff != ghostCentsOff ||
      old.pitched != pitched ||
      old.pillColor != pillColor;
}
