import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Animated metaballs background rendered entirely on the GPU.
///
/// Blob positions are computed once per frame on the CPU (12 cheap sin/cos
/// calls) and passed as uniforms. The fragment shader only does arithmetic
/// per pixel, so GPU load is minimal. The [Ticker] syncs to vsync and never
/// fires faster than the display refresh rate.
class MetaballsBackground extends StatefulWidget {
  const MetaballsBackground({super.key, this.child});
  final Widget? child;

  @override
  State<MetaballsBackground> createState() => _MetaballsBackgroundState();
}

class _MetaballsBackgroundState extends State<MetaballsBackground>
    with SingleTickerProviderStateMixin {
  // Shader is cached across instances — loaded only once.
  static FragmentShader? _shader;
  static bool _loading = false;

  late final Ticker _ticker;
  double _time = 0;
  Duration? _last;

  // Fallback colour while shader loads (matches the shader's bg colour).
  static const _bg = Color(0xFF0D071E);

  // Each blob: [xAmp, yAmp, xFreq, yFreq, xPhase, yPhase]
  // Amplitudes are fractions of screen height so layout is aspect-agnostic.
  // Frequencies are scaled by _speed in the painter for global speed control.
  static const _speed = 0.45;
  static const _blobs = <List<double>>[
    [0.30, 0.32, 0.610, 0.430, 0.00, 0.00],
    [0.36, 0.28, 0.530, 0.710, 0.00, 0.00],
    [0.24, 0.26, 0.970, 0.790, 1.00, 0.00],
    [0.26, 0.28, 0.410, 0.670, 2.00, 1.00],
    [0.20, 0.32, 0.830, 1.130, 3.00, 0.00],
    [0.24, 0.24, 0.730, 0.890, 1.50, 2.00],
  ];

  @override
  void initState() {
    super.initState();
    if (_shader == null && !_loading) _loadShader();
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _loadShader() async {
    _loading = true;
    try {
      final program =
          await FragmentProgram.fromAsset('assets/shader/metaballs.frag');
      _shader = program.fragmentShader();
      if (mounted) setState(() {});
    } finally {
      _loading = false;
    }
  }

  void _onTick(Duration elapsed) {
    if (_last != null) {
      _time += (elapsed - _last!).inMicroseconds / 1e6;
    }
    _last = elapsed;
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_shader == null) {
      return ColoredBox(color: _bg, child: widget.child);
    }
    return CustomPaint(
      painter: _MetaballsPainter(_shader!, _time * _speed, _blobs),
      child: widget.child,
    );
  }
}

class _MetaballsPainter extends CustomPainter {
  final FragmentShader shader;
  final double time;
  final List<List<double>> blobs;

  const _MetaballsPainter(this.shader, this.time, this.blobs);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final h = size.height;

    // Uniform 0–1: uSize
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);

    // Uniforms 2–13: blob positions in pixel space (uB0..uB5)
    for (var i = 0; i < blobs.length; i++) {
      final b = blobs[i];
      final x = cx + h * b[0] * math.sin(time * b[2] + b[4]);
      final y = cy + h * b[1] * math.cos(time * b[3] + b[5]);
      shader.setFloat(2 + i * 2, x);
      shader.setFloat(2 + i * 2 + 1, y);
    }

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_MetaballsPainter old) => old.time != time;
}
