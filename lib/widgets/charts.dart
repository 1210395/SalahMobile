// سكن برو — chart primitives (Ring, BarChart, Donut). Ported from ui2.jsx.

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../data/sample_data.dart';

/// Circular progress ring with a centered child.
class Ring extends StatelessWidget {
  const Ring({
    super.key,
    required this.value,
    this.size = 96,
    this.stroke = 9,
    this.color,
    this.track,
    this.child,
  });
  final double value; // 0..100
  final double size;
  final double stroke;
  final Color? color;
  final Color? track;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
                value / 100, stroke, color ?? AppColors.ok, track ?? AppColors.brand50),
          ),
          ?child,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.frac, this.stroke, this.color, this.track);
  final double frac;
  final double stroke;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = (size.width - stroke) / 2;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(c, r, trackPaint);
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * frac.clamp(0, 1),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.frac != frac || old.color != color;
}

/// Vertical bar chart.
class BarChart extends StatelessWidget {
  const BarChart({super.key, required this.data, this.height = 120, this.max});
  final List<ChartDatum> data;
  final double height;
  final num? max;

  @override
  Widget build(BuildContext context) {
    final m = (max ?? data.map((d) => d.value).fold<num>(1, math.max)).toDouble();
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < data.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (data[i].label2 != null)
                      Text(data[i].label2!,
                          style: AppType.num(
                              size: 10, weight: FontWeight.w700, color: AppColors.ink500)),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: (data[i].value / m).clamp(0.03, 1).toDouble(),
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 30),
                            decoration: BoxDecoration(
                              color: data[i].color,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(7), bottom: Radius.circular(3)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(data[i].label,
                        style: AppType.base(
                            size: 11, weight: FontWeight.w600, color: AppColors.ink500)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Donut chart (segments only — overlay your own center label).
class Donut extends StatelessWidget {
  const Donut({super.key, required this.data, this.size = 120, this.stroke = 18});
  final List<ChartDatum> data;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(size, size), painter: _DonutPainter(data, stroke));
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.data, this.stroke);
  final List<ChartDatum> data;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = (size.width - stroke) / 2;
    final total = data.fold<num>(0, (s, d) => s + d.value).toDouble();
    final track = Paint()
      ..color = AppColors.brand50
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(c, r, track);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (final d in data) {
      final sweep = (d.value / total) * 2 * math.pi;
      final p = Paint()
        ..color = d.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep, false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.data != data;
}
