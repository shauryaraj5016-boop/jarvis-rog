import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'jarvis_phase.dart';

class JarvisOrb extends StatefulWidget {
  const JarvisOrb({required this.size, required this.phase, super.key});

  final double size;
  final JarvisPhase phase;

  @override
  State<JarvisOrb> createState() => _JarvisOrbState();
}

class _JarvisOrbState extends State<JarvisOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'JARVIS assistant status: ${widget.phase.label}',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final movement =
              math.sin(_controller.value * math.pi * 2) *
              (widget.phase == JarvisPhase.ready ? 0.006 : 0.018);

          return Transform.scale(scale: 1 + movement, child: child);
        },
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _OrbPainter(phase: widget.phase),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.phase == JarvisPhase.listening
                        ? Icons.graphic_eq_rounded
                        : widget.phase == JarvisPhase.thinking
                        ? Icons.bolt_rounded
                        : Icons.memory_rounded,
                    color: const Color(0xFFFF5360),
                    size: widget.size * 0.105,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.phase.orbLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.size * 0.052,
                      height: 1.18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 34,
                    height: 2,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3344),
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: const [
                        BoxShadow(color: Color(0xAAFF3344), blurRadius: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter({required this.phase});

  final JarvisPhase phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final active = phase != JarvisPhase.ready;

    final glowPaint = Paint()
      ..color = const Color(0xFFFF2638).withValues(alpha: active ? 0.22 : 0.11)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 36);
    canvas.drawCircle(center, radius * 0.67, glowPaint);

    final orbRect = Rect.fromCircle(center: center, radius: radius * 0.72);
    final corePaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.22, -0.3),
        colors: [Color(0xFF451318), Color(0xFF1D0D10), Color(0xFF0C0B0D)],
        stops: [0, 0.5, 1],
      ).createShader(orbRect);
    canvas.drawCircle(center, radius * 0.72, corePaint);

    final coreStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFFF4553).withValues(alpha: active ? 0.55 : 0.28);
    canvas.drawCircle(center, radius * 0.72, coreStroke);

    final ticks = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = radius * 0.009;
    for (var i = 0; i < 72; i++) {
      final angle = i * math.pi * 2 / 72 - math.pi / 2;
      final major = i % 6 == 0;
      final innerRadius = radius * (major ? 0.87 : 0.9);
      final outerRadius = radius * 0.94;
      final opacity = major ? (active ? 0.9 : 0.58) : (active ? 0.42 : 0.22);
      ticks.color = const Color(0xFFFF4654).withValues(alpha: opacity);
      canvas.drawLine(
        Offset(
          center.dx + math.cos(angle) * innerRadius,
          center.dy + math.sin(angle) * innerRadius,
        ),
        Offset(
          center.dx + math.cos(angle) * outerRadius,
          center.dy + math.sin(angle) * outerRadius,
        ),
        ticks,
      );
    }

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.018
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFF4351).withValues(alpha: active ? 0.93 : 0.58);
    final arcRect = Rect.fromCircle(center: center, radius: radius * 0.81);
    canvas.drawArc(arcRect, -math.pi * 0.86, math.pi * 0.48, false, arcPaint);
    canvas.drawArc(arcRect, math.pi * 0.15, math.pi * 0.32, false, arcPaint);

    final innerArcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFFF6570).withValues(alpha: active ? 0.4 : 0.17);
    canvas.drawCircle(center, radius * 0.77, innerArcPaint);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) =>
      oldDelegate.phase != phase;
}
