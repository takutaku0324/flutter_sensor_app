import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' hide Image;
import 'dart:ui' as ui show Image;
// Flutter Web専用: ブラウザのダウンロード機能
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void main() {
  runApp(const EspMonitorApp());
}

class EspMonitorApp extends StatelessWidget {
  const EspMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Firefighter Device Monitor',
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF1A73E8),
          surface: Color(0xFFFFFFFF),
        ),
        textTheme: Typography.material2021()
            .black
            .apply(fontFamily: 'sans-serif'),
      ),
      home: const MonitorPage(),
    );
  }
}

class IconViewPage extends StatelessWidget {
  const IconViewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFFFF),
        title: const Text('アイコン表示',
            style: TextStyle(
                color: Colors.black87, fontWeight: FontWeight.bold)),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/icon.png',
              width: 200,
              height: 200,
              errorBuilder: (_, __, ___) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                            color: const Color(0xFFFFFFFF),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.black12)),
                        child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.image_not_supported_outlined,
                                  size: 64, color: Colors.black26),
                              SizedBox(height: 12),
                              Text('assets/icon.png\nが見つかりません',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Colors.black38, fontSize: 12)),
                            ])),
                  ]),
            ),
            const SizedBox(height: 24),
            const Text('アイコン画像',
                style: TextStyle(color: Colors.black54, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

class AnomalySession {
  final DateTime start;
  DateTime end;
  AnomalySession({required this.start, required this.end});
  Duration get duration => end.difference(start);
}

class SensorFrame {
  final bool conn0, conn1;
  final List<int> rR, rL, rB, lR, lL, lB;
  final int? seq0, seq1, nf0, bo0, nf1, bo1;
  final bool inferReady;
  final double score;
  final bool anomaly;
  final String label;

  SensorFrame(
      {required this.conn0,
      required this.conn1,
      required this.rR,
      required this.rL,
      required this.rB,
      required this.lR,
      required this.lL,
      required this.lB,
      this.seq0,
      this.seq1,
      this.nf0,
      this.bo0,
      this.nf1,
      this.bo1,
      required this.inferReady,
      required this.score,
      required this.anomaly,
      required this.label});

  static int? _i(dynamic v) => v == null ? null : (v as num).toInt();
  static List<int> _parseIntArray(dynamic v) {
    if (v == null) return [];
    if (v is List) return v.map((e) => (e as num).toInt()).toList();
    return [(v as num).toInt()];
  }

  factory SensorFrame.fromJson(Map<String, dynamic> j) {
    final d0 = (j['d0'] as Map<String, dynamic>?) ?? const {};
    final d1 = (j['d1'] as Map<String, dynamic>?) ?? const {};
    final infer = (j['infer'] as Map<String, dynamic>?) ?? const {};
    return SensorFrame(
      conn0: d0['conn'] == true,
      conn1: d1['conn'] == true,
      rR: _parseIntArray(d0['R_R']),
      rL: _parseIntArray(d0['R_L']),
      rB: _parseIntArray(d0['R_B']),
      lR: _parseIntArray(d1['L_R']),
      lL: _parseIntArray(d1['L_L']),
      lB: _parseIntArray(d1['L_B']),
      seq0: _i(d0['seq']),
      seq1: _i(d1['seq']),
      nf0: _i(d0['nf']),
      bo0: _i(d0['bo']),
      nf1: _i(d1['nf']),
      bo1: _i(d1['bo']),
      inferReady: infer['ready'] == true,
      score: (infer['score'] ?? 0).toDouble(),
      anomaly: infer['anomaly'] == true,
      label: infer['label']?.toString() ?? '-',
    );
  }
}

class HeatmapPoint {
  double x, y, sigma, weightMul;
  final String name;
  final Color color;
  final double sigmaY;
  final bool visible;

  HeatmapPoint(
      {required this.x,
      required this.y,
      required this.sigma,
      this.sigmaY = 0.3,
      required this.weightMul,
      required this.name,
      required this.color,
      this.visible = false});

  HeatmapPoint copyWith(
          {double? x,
          double? y,
          double? sigma,
          double? sigmaY,
          double? weightMul,
          Color? color,
          bool? visible}) =>
      HeatmapPoint(
          x: x ?? this.x,
          y: y ?? this.y,
          sigma: sigma ?? this.sigma,
          sigmaY: sigmaY ?? this.sigmaY,
          weightMul: weightMul ?? this.weightMul,
          name: name,
          color: color ?? this.color,
          visible: visible ?? this.visible);
}

List<HeatmapPoint> defaultHeatmapPoints() => [
      HeatmapPoint(
          x: 0.65,
          y: 0.46,
          sigma: 0.27,
          weightMul: 1.0,
          name: 'R_R (内前)',
          color: const Color(0xFFFF6B6B)),
      HeatmapPoint(
          x: 0.29,
          y: 0.46,
          sigma: 0.27,
          weightMul: 1.0,
          name: 'R_L (外前)',
          color: const Color(0xFFFFA94D)),
      HeatmapPoint(
          x: 0.47,
          y: 0.68,
          sigma: 0.27,
          weightMul: 1.0,
          name: 'R_B (踵)',
          color: const Color(0xFFFFD43B)),
      HeatmapPoint(
          x: 0.69,
          y: 0.46,
          sigma: 0.27,
          weightMul: 1.0,
          name: 'L_R (外前)',
          color: const Color(0xFF4ECDC4)),
      HeatmapPoint(
          x: 0.32,
          y: 0.46,
          sigma: 0.27,
          weightMul: 1.0,
          name: 'L_L (内前)',
          color: const Color(0xFF45B7D1)),
      HeatmapPoint(
          x: 0.51,
          y: 0.68,
          sigma: 0.27,
          weightMul: 1.0,
          name: 'L_B (踵)',
          color: const Color(0xFFA88BFA)),
    ];

class FootHeatmapPainter extends CustomPainter {
  final List<double> values;
  final List<HeatmapPoint> points;
  final Color baseColor;
  FootHeatmapPainter(
      {required this.values, required this.points, required this.baseColor});

  @override
  void paint(Canvas canvas, Size size) {
    const step = 4;
    final cols = (size.width / step).ceil();
    final rows = (size.height / step).ceil();
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final px = col * step + step / 2;
        final py = row * step + step / 2;
        final nx = px / size.width;
        final ny = py / size.height;
        double intensity = 0.0;
        for (int i = 0; i < points.length && i < values.length; i++) {
          final p = points[i];
          final v = (values[i] * p.weightMul).clamp(0.0, 1.0);
          if (v <= 0) continue;
          final dx = nx - p.x;
          final dy = ny - p.y;
          final sx = p.sigma.clamp(0.01, 1.0);
          final sy = (p.sigma * p.sigmaY).clamp(0.01, 1.0);
          intensity += v *
              exp(-((dx * dx) / (2 * sx * sx) + (dy * dy) / (2 * sy * sy)));
        }
        intensity = intensity.clamp(0.0, 1.0);
        if (intensity < 0.01) continue;
        canvas.drawRect(
          Rect.fromLTWH(
              px - step / 2, py - step / 2, step.toDouble(), step.toDouble()),
          Paint()
            ..color = _intensityColor(intensity)
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  Color _intensityColor(double t) {
    if (t < 0.25) {
      return Color.lerp(Colors.blue.withOpacity(0.0),
          Colors.cyan.withOpacity(0.5), t / 0.25)!;
    }
    if (t < 0.5) {
      return Color.lerp(Colors.cyan.withOpacity(0.5),
          Colors.green.withOpacity(0.65), (t - 0.25) / 0.25)!;
    }
    if (t < 0.75) {
      return Color.lerp(Colors.green.withOpacity(0.65),
          Colors.yellow.withOpacity(0.75), (t - 0.5) / 0.25)!;
    }
    return Color.lerp(Colors.yellow.withOpacity(0.75),
        Colors.red.withOpacity(0.88), (t - 0.75) / 0.25)!;
  }

  @override
  bool shouldRepaint(FootHeatmapPainter old) =>
      old.values != values || old.points != points;
}

// ─────────────────────────────────────────────
// FootHeatmapView: repaintKey を追加して PNG 保存に対応
// ─────────────────────────────────────────────
class FootHeatmapView extends StatelessWidget {
  final List<double> values;
  final List<HeatmapPoint> points;
  final String label;
  final bool connected;
  final bool mirror;
  final GlobalKey? repaintKey; // ← 追加

  const FootHeatmapView({
    super.key,
    required this.values,
    required this.points,
    required this.label,
    required this.connected,
    this.mirror = false,
    this.repaintKey, // ← 追加
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label,
          style: const TextStyle(
              color: Colors.black54,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Expanded(
        child: RepaintBoundary(
          // ← key をここに付与（PNG キャプチャ用）
          key: repaintKey,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LayoutBuilder(builder: (_, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              return Stack(fit: StackFit.expand, children: [
                Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..scale(mirror ? -1.0 : 1.0, 1.0),
                    child: SvgPicture.asset('assets/foot.svg',
                        fit: BoxFit.contain)),
                if (connected)
                  CustomPaint(
                      painter: FootHeatmapPainter(
                          values: values,
                          points: points,
                          baseColor: const Color(0xFFFF4444))),
                if (connected)
                  ...List.generate(points.length, (i) {
                    final p = points[i];
                    if (!p.visible) return const SizedBox.shrink();
                    final v = i < values.length ? values[i] : 0.0;
                    return Positioned(
                        left: p.x * w - 6,
                        top: p.y * h - 6,
                        child: _SensorDot(
                            color: p.color, value: v, name: p.name));
                  }),
                if (!connected)
                  Container(
                      color: Colors.black12,
                      child: const Center(
                          child: Text('Not connected',
                              style: TextStyle(
                                  color: Colors.black38, fontSize: 12)))),
              ]);
            }),
          ),
        ),
      ),
      const SizedBox(height: 4),
    ]);
  }
}

class _SensorDot extends StatelessWidget {
  final Color color;
  final double value;
  final String name;
  const _SensorDot(
      {required this.color, required this.value, required this.name});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$name: ${(value * 100).toStringAsFixed(1)}%',
      child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: color.withOpacity(0.9),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.6), blurRadius: 6)
              ])),
    );
  }
}

class AlarmSoundController {
  AudioPlayer? _player;
  bool _isPlaying = false;

  Future<void> init() async {
    try {
      _player = AudioPlayer();
      await _player!.setReleaseMode(ReleaseMode.loop);
    } catch (e) {
      debugPrint('AlarmSoundController init error: $e');
    }
  }

  Future<void> startAlarm() async {
    if (_isPlaying) return;
    _isPlaying = true;
    try {
      await _player!.play(AssetSource('alarm.wav'));
    } catch (e) {
      debugPrint('AlarmSoundController startAlarm error: $e');
      _isPlaying = false;
    }
  }

  Future<void> stopAlarm() async {
    if (!_isPlaying) return;
    _isPlaying = false;
    try {
      await _player?.stop();
    } catch (e) {
      debugPrint('AlarmSoundController stopAlarm error: $e');
    }
  }

  Future<void> dispose() async {
    await stopAlarm();
    await _player?.dispose();
    _player = null;
  }
}

class NfBoStatusWidget extends StatefulWidget {
  final String label;
  final int? nf, bo;
  const NfBoStatusWidget(
      {super.key, required this.label, required this.nf, required this.bo});

  @override
  State<NfBoStatusWidget> createState() => _NfBoStatusWidgetState();
}

class _NfBoStatusWidgetState extends State<NfBoStatusWidget> {
  int? _prevNf, _prevBo;
  bool _nfAlert = false, _boAlert = false;
  Timer? _nfTimer, _boTimer;

  @override
  void didUpdateWidget(NfBoStatusWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newNf = widget.nf;
    if (newNf != null && _prevNf != null && newNf > _prevNf!) {
      _nfTimer?.cancel();
      setState(() => _nfAlert = true);
      _nfTimer = Timer(const Duration(seconds: 1),
          () {
            if (mounted) setState(() => _nfAlert = false);
          });
    }
    if (newNf != null) _prevNf = newNf;
    final newBo = widget.bo;
    if (newBo != null && _prevBo != null && newBo > _prevBo!) {
      _boTimer?.cancel();
      setState(() => _boAlert = true);
      _boTimer = Timer(const Duration(seconds: 1),
          () {
            if (mounted) setState(() => _boAlert = false);
          });
    }
    if (newBo != null) _prevBo = newBo;
  }

  @override
  void dispose() {
    _nfTimer?.cancel();
    _boTimer?.cancel();
    super.dispose();
  }

  Widget _statCell(String key, int? val, bool alert) {
    final color = alert ? const Color(0xFFFF4444) : const Color(0xFF00C853);
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: color.withOpacity(0.4), width: 1)),
        child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(key,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 8,
                  height: 1.0,
                  color: color.withOpacity(0.8),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
          Text(val != null ? '$val' : '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 8,
                  height: 1.0,
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ])),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 8,
                  color: Colors.black38,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8)),
          const SizedBox(height: 2),
          Expanded(
              child: Row(children: [
            _statCell('Notify Fail', widget.nf, _nfAlert),
            _statCell('Buffer Overflow', widget.bo, _boAlert),
          ])),
        ]),
      ),
    );
  }
}

class AnomalyHistoryWidget extends StatelessWidget {
  final List<AnomalySession> sessions;
  final DateTime? monitoringStart;
  const AnomalyHistoryWidget(
      {super.key,
      required this.sessions,
      required this.monitoringStart});

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  String _dur(Duration d) =>
      d.inSeconds < 60 ? '${d.inSeconds}秒' : '${d.inMinutes}分${d.inSeconds % 60}秒';

  void _showPopup(BuildContext context) {
    final now = DateTime.now();
    final rangeStart = monitoringStart ??
        (sessions.isNotEmpty
            ? sessions.first.start
            : now.subtract(const Duration(minutes: 1)));
    final totalMs = now.difference(rangeStart).inMilliseconds.toDouble();
    showDialog(
        context: context,
        builder: (ctx) => Dialog(
              backgroundColor: const Color(0xFFFFFFFF),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(
                            sessions.isNotEmpty
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline,
                            size: 18,
                            color: sessions.isNotEmpty
                                ? const Color(0xFFFF4444)
                                : const Color(0xFF00C853)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text('Anomaly history: ${sessions.length} occurrences',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 10,
                                    height: 1.0,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87))),
                        GestureDetector(
                            onTap: () => Navigator.of(ctx).pop(),
                            child: const Icon(Icons.close,
                                size: 10, color: Colors.black54)),
                      ]),
                      const SizedBox(height: 16),
                      if (totalMs > 0) ...[
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_fmt(rangeStart),
                                  style: const TextStyle(
                                      fontSize: 9, color: Colors.black87)),
                              Text(_fmt(now),
                                  style: const TextStyle(
                                      fontSize: 9, color: Colors.black87)),
                            ]),
                        const SizedBox(height: 4),
                        ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LayoutBuilder(builder: (_, constraints) {
                              final bw = constraints.maxWidth;
                              return SizedBox(
                                  height: 16,
                                  child: Stack(children: [
                                    Container(
                                        width: bw,
                                        height: 16,
                                        color: Colors.black.withOpacity(0.05)),
                                    for (final s in sessions)
                                      Positioned(
                                          left: ((s.start
                                                          .difference(
                                                              rangeStart)
                                                          .inMilliseconds /
                                                      totalMs) *
                                                  bw)
                                              .clamp(0.0, bw),
                                          child: Container(
                                              width: ((s.end
                                                              .difference(
                                                                  s.start)
                                                              .inMilliseconds /
                                                          totalMs) *
                                                      bw)
                                                  .clamp(1.0, bw),
                                              height: 16,
                                              color: const Color(0xFFFF4444)
                                                  .withOpacity(0.85))),
                                  ]));
                            })),
                        const SizedBox(height: 14),
                      ],
                      if (sessions.isEmpty)
                        const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                                child: Text('異常なし',
                                    style: TextStyle(
                                        color: Color(0xFF00C853),
                                        fontSize: 13))))
                      else
                        ConstrainedBox(
                            constraints:
                                const BoxConstraints(maxHeight: 260),
                            child: SingleChildScrollView(
                                child: Column(
                              children: sessions.reversed
                                  .map((s) => Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 6),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 7),
                                        decoration: BoxDecoration(
                                            color: const Color(0xFFFF4444)
                                                .withOpacity(0.06),
                                            borderRadius:
                                                BorderRadius.circular(7),
                                            border: Border.all(
                                                color: const Color(0xFFFF4444)
                                                    .withOpacity(0.25))),
                                        child: Row(children: [
                                          Container(
                                              width: 7,
                                              height: 7,
                                              margin: const EdgeInsets.only(
                                                  right: 8),
                                              decoration: const BoxDecoration(
                                                  color: Color(0xFFFF4444),
                                                  shape: BoxShape.circle)),
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(
                                                    '${_fmt(s.start)}  ～  ${_fmt(s.end)}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.black87,
                                                        fontWeight:
                                                            FontWeight.w600)),
                                                const SizedBox(height: 2),
                                                Text(
                                                    '継続時間: ${_dur(s.duration)}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontSize: 10,
                                                        color:
                                                            Colors.black54)),
                                              ])),
                                        ]),
                                      ))
                                  .toList(),
                            ))),
                    ],
                  )),
            ));
  }

  @override
  Widget build(BuildContext context) {
    final count = sessions.length;
    return GestureDetector(
      onTap: () => _showPopup(context),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: count > 0
                    ? const Color(0xFFFF4444).withOpacity(0.5)
                    : Colors.black12)),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Anomaly history',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.0,
                      color: count > 0
                          ? const Color(0xFFFF4444)
                          : Colors.black87,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8)),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(
                    count > 0
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    size: 15,
                    color: count > 0
                        ? const Color(0xFFFF4444)
                        : const Color(0xFF00C853)),
                const SizedBox(width: 4),
                Flexible(
                    child: Text('$count 回',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15,
                            height: 1.0,
                            fontWeight: FontWeight.bold,
                            color: count > 0
                                ? const Color(0xFFFF4444)
                                : const Color(0xFF00C853),
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ]))),
              ]),
            ]),
      ),
    );
  }
}

class MiniStatCard extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const MiniStatCard(
      {super.key,
      required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
        child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.35))),
      child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(height: 6),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4)),
                const SizedBox(height: 4),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15,
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ])),
    ));
  }
}

class AppSettings {
  final String wsUrl;
  final double stdThreshold;
  final int stdWindowSize;
  final bool alarmEnabled;
  final bool? connectAction;
  final List<HeatmapPoint> heatmapPoints;
  const AppSettings(
      {required this.wsUrl,
      required this.stdThreshold,
      required this.stdWindowSize,
      required this.alarmEnabled,
      required this.heatmapPoints,
      this.connectAction});
}

class HeatmapSettingsPage extends StatefulWidget {
  final List<HeatmapPoint> points;
  const HeatmapSettingsPage({super.key, required this.points});

  @override
  State<HeatmapSettingsPage> createState() => _HeatmapSettingsPageState();
}

class _HeatmapSettingsPageState extends State<HeatmapSettingsPage> {
  late List<HeatmapPoint> _points;

  @override
  void initState() {
    super.initState();
    _points = widget.points.map((p) => p.copyWith()).toList();
  }

  Widget _slider(
      String label,
      double value,
      double min,
      double max,
      int divisions,
      void Function(double) onChanged,
      Color color) {
    return Row(children: [
      SizedBox(
          width: 68,
          child: Text(label,
              style:
                  const TextStyle(color: Colors.black54, fontSize: 11))),
      Expanded(
          child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              activeColor: color,
              inactiveColor: Colors.black12,
              onChanged: onChanged)),
      SizedBox(
          width: 40,
          child: Text(value.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()]))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFFFF),
        title: const Text('ヒートマップ 設定',
            style: TextStyle(
                color: Colors.black87, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(_points),
              child: const Text('保存',
                  style: TextStyle(
                      color: Color(0xFF1A73E8),
                      fontWeight: FontWeight.bold))),
          TextButton(
              onPressed: () {
                setState(() {
                  final def = defaultHeatmapPoints();
                  for (int i = 0;
                      i < _points.length && i < def.length;
                      i++) {
                    _points[i] = def[i];
                  }
                });
              },
              child: const Text('リセット',
                  style: TextStyle(color: Colors.black38, fontSize: 12))),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _points.length,
        itemBuilder: (_, idx) {
          final p = _points[idx];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.color.withOpacity(0.35))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                        color: p.color, shape: BoxShape.circle)),
                Expanded(
                    child: Text(p.name,
                        style: TextStyle(
                            color: p.color,
                            fontSize: 13,
                            fontWeight: FontWeight.bold))),
                IconButton(
                    icon: Icon(
                        p.visible ? Icons.visibility : Icons.visibility_off,
                        size: 18,
                        color: p.visible ? Colors.black54 : Colors.black26),
                    onPressed: () => setState(() =>
                        _points[idx] = p.copyWith(visible: !p.visible))),
              ]),
              const SizedBox(height: 8),
              _slider('X 位置', p.x, 0.0, 1.0, 100,
                  (v) => setState(() => _points[idx] = p.copyWith(x: v)),
                  p.color),
              _slider('Y 位置', p.y, 0.0, 1.0, 100,
                  (v) => setState(() => _points[idx] = p.copyWith(y: v)),
                  p.color),
              _slider('広がり (σ)', p.sigma, 0.02, 0.5, 48,
                  (v) => setState(() => _points[idx] = p.copyWith(sigma: v)),
                  p.color),
              _slider('縦倍率', p.sigmaY, 0.1, 3.0, 58,
                  (v) => setState(() => _points[idx] = p.copyWith(sigmaY: v)),
                  p.color),
              _slider(
                  '強度倍率',
                  p.weightMul,
                  0.0,
                  2.0,
                  40,
                  (v) => setState(
                      () => _points[idx] = p.copyWith(weightMul: v)),
                  p.color),
            ]),
          );
        },
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final String initialUrl;
  final double initialThreshold;
  final int initialWindowSize;
  final bool initialAlarmEnabled, isConnected;
  final List<HeatmapPoint> heatmapPoints;
  const SettingsPage(
      {super.key,
      required this.initialUrl,
      required this.initialThreshold,
      required this.initialWindowSize,
      required this.initialAlarmEnabled,
      required this.isConnected,
      required this.heatmapPoints});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _urlController;
  late double _threshold;
  late int _windowSize;
  late bool _alarmEnabled;
  late List<HeatmapPoint> _heatmapPoints;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
    _threshold = widget.initialThreshold;
    _windowSize = widget.initialWindowSize;
    _alarmEnabled = widget.initialAlarmEnabled;
    _heatmapPoints = widget.heatmapPoints.map((p) => p.copyWith()).toList();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  AppSettings _buildSettings({bool? connectAction}) => AppSettings(
      wsUrl: _urlController.text.trim(),
      stdThreshold: _threshold,
      stdWindowSize: _windowSize,
      alarmEnabled: _alarmEnabled,
      heatmapPoints: _heatmapPoints,
      connectAction: connectAction);

  void _save() => Navigator.of(context).pop(_buildSettings());
  void _connect() =>
      Navigator.of(context).pop(_buildSettings(connectAction: true));
  void _disconnect() =>
      Navigator.of(context).pop(_buildSettings(connectAction: false));

  Widget _sectionTitle(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Text(text,
          style: const TextStyle(
              color: Color(0xFF1A73E8),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8)));

  Widget _card({required Widget child}) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black12)),
      child: child);

  @override
  Widget build(BuildContext context) {
    final connected = widget.isConnected;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFFFF),
        title: const Text('設定',
            style: TextStyle(color: Colors.black87)),
        actions: [
          TextButton(
              onPressed: _save,
              child: const Text('保存',
                  style: TextStyle(
                      color: Color(0xFF1A73E8),
                      fontWeight: FontWeight.bold)))
        ],
      ),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _sectionTitle('接続'),
            _card(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                    decoration: InputDecoration(
                        labelText: 'WebSocket URL',
                        labelStyle: const TextStyle(color: Colors.black38),
                        filled: true,
                        fillColor: const Color(0xFFF5F7FA),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8))),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Icon(connected ? Icons.circle : Icons.circle_outlined,
                        size: 10,
                        color: connected ? Colors.green : Colors.redAccent),
                    const SizedBox(width: 6),
                    Text(connected ? 'Connected' : 'Not connected',
                        style: TextStyle(
                            fontSize: 12,
                            color: connected
                                ? Colors.green
                                : Colors.redAccent)),
                  ]),
                  const SizedBox(height: 12),
                  SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                          onPressed: connected ? _disconnect : _connect,
                          icon: Icon(
                              connected ? Icons.link_off : Icons.link,
                              size: 18),
                          label: Text(
                              connected ? '切断する' : '接続する',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: connected
                                  ? Colors.redAccent.withOpacity(0.85)
                                  : const Color(0xFF3AB449),
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(10))))),
                ])),
            _sectionTitle('静止／運動 判定'),
            _card(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('標準偏差しきい値',
                            style: TextStyle(
                                color: Colors.black87, fontSize: 13)),
                        Text(_threshold.toStringAsFixed(2),
                            style: const TextStyle(
                                color: Color(0xFF1A73E8),
                                fontWeight: FontWeight.bold)),
                      ]),
                  Slider(
                      value: _threshold,
                      min: 0.01,
                      max: 1.0,
                      divisions: 99,
                      activeColor: const Color(0xFF1A73E8),
                      inactiveColor: Colors.black12,
                      onChanged: (v) => setState(() => _threshold = v)),
                  const SizedBox(height: 4),
                  const Divider(color: Colors.black12, height: 1),
                  const SizedBox(height: 12),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('判定ウィンドウ（サンプル数）',
                            style: TextStyle(
                                color: Colors.black87, fontSize: 13)),
                        Text('$_windowSize',
                            style: const TextStyle(
                                color: Color(0xFF1A73E8),
                                fontWeight: FontWeight.bold)),
                      ]),
                  Slider(
                      value: _windowSize.toDouble(),
                      min: 20,
                      max: 600,
                      divisions: 58,
                      activeColor: const Color(0xFF1A73E8),
                      inactiveColor: Colors.black12,
                      onChanged: (v) =>
                          setState(() => _windowSize = v.round())),
                  Text(
                      '62.5Hzサンプリングのため約 ${(_windowSize * 16 / 1000).toStringAsFixed(2)} 秒分の窓',
                      style: const TextStyle(
                          color: Colors.black38, fontSize: 11)),
                ])),
            _sectionTitle('アラーム'),
            _card(
                child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('異常検知時にアラーム音を再生',
                        style: TextStyle(
                            color: Colors.black87, fontSize: 13)),
                    value: _alarmEnabled,
                    activeColor: const Color(0xFF1A73E8),
                    onChanged: (v) =>
                        setState(() => _alarmEnabled = v))),
            _sectionTitle('ヒートマップ'),
            _card(
                child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.thermostat_outlined,
                        color: Color(0xFF1A73E8)),
                    title: const Text('センサー点の位置・強度を編集',
                        style: TextStyle(
                            color: Colors.black87, fontSize: 13)),
                    subtitle: const Text(
                        '各チャンネルの X/Y 位置・ガウス幅・強度倍率を設定',
                        style: TextStyle(
                            color: Colors.black54, fontSize: 11)),
                    trailing: const Icon(Icons.chevron_right,
                        color: Colors.black38),
                    onTap: () async {
                      final result =
                          await Navigator.of(context)
                              .push<List<HeatmapPoint>>(MaterialPageRoute(
                                  builder: (_) => HeatmapSettingsPage(
                                      points: _heatmapPoints)));
                      if (result != null) {
                        setState(() => _heatmapPoints = result);
                      }
                    })),
            _sectionTitle('画面'),
            _card(
                child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.image_outlined,
                        color: Color(0xFF1A73E8)),
                    title: const Text('アイコン表示',
                        style: TextStyle(
                            color: Colors.black87, fontSize: 13)),
                    subtitle: const Text('PNG アイコンを表示する画面を開く',
                        style: TextStyle(
                            color: Colors.black54, fontSize: 11)),
                    trailing: const Icon(Icons.chevron_right,
                        color: Colors.black38),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const IconViewPage())))),
          ]),
    );
  }
}

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  static const int maxPoints = 600;
  static const String _defaultWsUrl = 'ws://192.168.4.1:81';
  static const double _adcFullScale = 8388607.0;
  static const List<String> _chLabels = ['1', '2', '3', '4', '5', '6'];
  static const List<Color> _chColors = [
    Color(0xFFFF6B6B),
    Color(0xFFFFA94D),
    Color(0xFFFFD43B),
    Color(0xFF4ECDC4),
    Color(0xFF45B7D1),
    Color(0xFFA88BFA),
  ];

  int _stdWindowSize = 300;
  double _stdThreshold = 0.1;
  static const int _sampleIntervalMs = 16;

  WebSocketChannel? _channel;
  bool _connected = false;
  String _status = 'Not connected';
  SensorFrame? _latest;

  int? _dispSeq0, _dispSeq1, _dispNf0, _dispBo0, _dispNf1, _dispBo1;
  int? _lastSeq0, _lastSeq1;

  final List<List<FlSpot>> _series = List.generate(6, (_) => []);
  final List<double> _lastValue = List.filled(6, 0.0);
  int _tick = 0;

  final _urlController = TextEditingController(text: _defaultWsUrl);
  DateTime? _monitoringStart;
  final List<AnomalySession> _anomalySessions = [];
  AnomalySession? _currentAnomalySession;
  DateTime? _lastAnomalyTime;

  final AlarmSoundController _alarm = AlarmSoundController();
  bool _alarmPlaying = false, _alarmEnabled = true;

  final List<List<double>> _stdBuffer = List.generate(6, (_) => []);
  int _stationaryMs = 0, _movementMs = 0;

  List<HeatmapPoint> _heatmapPoints = defaultHeatmapPoints();

  static const double _stepThreshold = 0.35;
  static const int _stepMaxWindow = 300;
  static const int _cadenceTimeoutSamples = 313;
  static const int _cadenceMaxSpm = 180;

  int _stepCountR = 0;
  bool _stepAboveR = false;
  int _stepWindowCountR = 0;
  int? _cadenceR;
  int _cadenceBelowCountR = 0;
  int _stepCountL = 0;
  bool _stepAboveL = false;
  int _stepWindowCountL = 0;
  int? _cadenceL;
  int _cadenceBelowCountL = 0;

  // ─── PNG保存用 GlobalKey ───────────────────────────
  final GlobalKey _heatmapKeyL = GlobalKey();
  final GlobalKey _heatmapKeyR = GlobalKey();

  (bool, int, int, int?) _detectStep(
      double val, bool above, int windowCount, int belowCount) {
    if (val > _stepThreshold) {
      if (!above) return (true, 1, 0, null);
      final newCount = windowCount + 1;
      if (newCount >= _stepMaxWindow) return (false, 0, 0, null);
      return (true, newCount, 0, null);
    } else {
      final newBelowCount = belowCount + 1;
      if (above) {
        if (windowCount >= _stepMaxWindow) {
          return (false, 0, newBelowCount, null);
        }
        final cad = (60.0 / (windowCount * 0.016)).round();
        if (cad >= _cadenceMaxSpm) return (false, 0, newBelowCount, null);
        return (false, 0, newBelowCount, cad);
      }
      return (false, 0, newBelowCount, null);
    }
  }

  void _updateStepCounts(int s) {
    if (_series[2].isNotEmpty) {
      final (na, nc, nb, cad) = _detectStep(
          _lastValue[2], _stepAboveR, _stepWindowCountR, _cadenceBelowCountR);
      _stepAboveR = na;
      _stepWindowCountR = nc;
      _cadenceBelowCountR = nb;
      if (cad != null) {
        _stepCountR++;
        _cadenceR = cad;
      }
      if (_cadenceBelowCountR >= _cadenceTimeoutSamples) _cadenceR = null;
    }
    if (_series[5].isNotEmpty) {
      final (na, nc, nb, cad) = _detectStep(
          _lastValue[5], _stepAboveL, _stepWindowCountL, _cadenceBelowCountL);
      _stepAboveL = na;
      _stepWindowCountL = nc;
      _cadenceBelowCountL = nb;
      if (cad != null) {
        _stepCountL++;
        _cadenceL = cad;
      }
      if (_cadenceBelowCountL >= _cadenceTimeoutSamples) _cadenceL = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _alarm.init();
  }

  double _calcStd(List<double> data) {
    final n = data.length;
    if (n == 0) return 0.0;
    final mean = data.reduce((a, b) => a + b) / n;
    return sqrt(
        data.fold(0.0, (sum, v) => sum + (v - mean) * (v - mean)) / n);
  }

  void _updateMotionState() {
    if (_stdBuffer.any((b) => b.length < _stdWindowSize)) return;
    if (_stdBuffer.every((b) => _calcStd(b) <= _stdThreshold)) {
      _stationaryMs += _sampleIntervalMs;
    } else {
      _movementMs += _sampleIntervalMs;
    }
  }

  void _updateAnomalyHistory(bool anomaly) {
    final now = DateTime.now();
    if (anomaly) {
      if (_currentAnomalySession != null &&
          _lastAnomalyTime != null &&
          now.difference(_lastAnomalyTime!).inSeconds <= 5) {
        _currentAnomalySession!.end = now;
      } else {
        if (_currentAnomalySession != null &&
            !_anomalySessions.contains(_currentAnomalySession)) {
          _anomalySessions.add(_currentAnomalySession!);
        }
        _currentAnomalySession =
            AnomalySession(start: now, end: now);
      }
      _lastAnomalyTime = now;
      if (!_alarmPlaying) {
        _alarmPlaying = true;
        if (_alarmEnabled) _alarm.startAlarm();
      }
    } else {
      if (_currentAnomalySession != null) {
        if (!_anomalySessions.contains(_currentAnomalySession)) {
          _anomalySessions.add(_currentAnomalySession!);
        }
        _currentAnomalySession = null;
      }
      if (_alarmPlaying) {
        _alarmPlaying = false;
        _alarm.stopAlarm();
      }
    }
  }

  void _connect() {
    final url = _urlController.text.trim();
    _monitoringStart ??= DateTime.now();
    for (final b in _stdBuffer) b.clear();
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      setState(() {
        _connected = true;
        _status = 'Connected';
      });
      channel.stream.listen(
        (msg) {
          Map<String, dynamic> raw;
          try {
            raw = jsonDecode(msg as String) as Map<String, dynamic>;
          } catch (_) {
            return;
          }
          _pushFrame(SensorFrame.fromJson(raw));
        },
        onError: (_) =>
            setState(() {
              _status = '接続エラー';
              _connected = false;
            }),
        onDone: () =>
            setState(() {
              _status = '切断されました';
              _connected = false;
            }),
      );
    } catch (e) {
      setState(() {
        _status = 'エラー: $e';
        _connected = false;
      });
    }
  }

  void _pushFrame(SensorFrame frame) {
    final seq0Changed =
        frame.seq0 != null && frame.seq0 != _lastSeq0;
    final seq1Changed =
        frame.seq1 != null && frame.seq1 != _lastSeq1;
    if (!seq0Changed && !seq1Changed) return;
    _lastSeq0 = frame.seq0;
    _lastSeq1 = frame.seq1;
    final rawArrays = <List<int>?>[
      frame.conn0 ? frame.lR : null,
      frame.conn0 ? frame.lL : null,
      frame.conn0 ? frame.lB : null,
      frame.conn1 ? frame.rR : null,
      frame.conn1 ? frame.rL : null,
      frame.conn1 ? frame.rB : null,
    ];
    final sampleCount = rawArrays
        .whereType<List<int>>()
        .fold(0, (mx, a) => max(mx, a.length));
    if (sampleCount == 0) return;
    setState(() {
      _latest = frame;
      if (frame.seq0 != null) _dispSeq0 = frame.seq0;
      if (frame.seq1 != null) _dispSeq1 = frame.seq1;
      if (frame.nf0 != null) _dispNf0 = frame.nf0;
      if (frame.bo0 != null) _dispBo0 = frame.bo0;
      if (frame.nf1 != null) _dispNf1 = frame.nf1;
      if (frame.bo1 != null) _dispBo1 = frame.bo1;
      if (frame.inferReady) _updateAnomalyHistory(frame.anomaly);
      for (int s = 0; s < sampleCount; s++) {
        for (int ch = 0; ch < 6; ch++) {
          final arr = rawArrays[ch];
          if (arr == null || s >= arr.length) continue;
          _lastValue[ch] = arr[s] / _adcFullScale;
          _series[ch].add(FlSpot(_tick.toDouble(), _lastValue[ch]));
          if (_series[ch].length > maxPoints) _series[ch].removeAt(0);
        }
        for (int ch = 0; ch < 6; ch++) {
          _stdBuffer[ch].add(_lastValue[ch]);
          if (_stdBuffer[ch].length > _stdWindowSize) {
            _stdBuffer[ch].removeAt(0);
          }
        }
        _updateMotionState();
        _updateStepCounts(s);
        _tick++;
      }
    });
  }

  void _disconnect() {
    _channel?.sink.close();
    _alarm.stopAlarm();
    _alarmPlaying = false;
    setState(() {
      _connected = false;
      _status = 'Not connected';
    });
  }

  void _clearGraph() => setState(() {
        for (final s in _series) s.clear();
        _tick = 0;
        for (final b in _stdBuffer) b.clear();
        _stationaryMs = 0;
        _movementMs = 0;
        _stepCountR = 0;
        _stepAboveR = false;
        _stepWindowCountR = 0;
        _cadenceR = null;
        _stepCountL = 0;
        _stepAboveL = false;
        _stepWindowCountL = 0;
        _cadenceL = null;
      });

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<AppSettings>(
        MaterialPageRoute(
            builder: (_) => SettingsPage(
                initialUrl: _urlController.text,
                initialThreshold: _stdThreshold,
                initialWindowSize: _stdWindowSize,
                initialAlarmEnabled: _alarmEnabled,
                isConnected: _connected,
                heatmapPoints: _heatmapPoints)));
    if (result == null) return;
    setState(() {
      _urlController.text = result.wsUrl;
      _stdThreshold = result.stdThreshold;
      _stdWindowSize = result.stdWindowSize;
      for (final b in _stdBuffer) b.clear();
      _alarmEnabled = result.alarmEnabled;
      _heatmapPoints = result.heatmapPoints;
      if (!_alarmEnabled && _alarmPlaying) {
        _alarmPlaying = false;
        _alarm.stopAlarm();
      }
    });
    if (result.connectAction == true) _connect();
    else if (result.connectAction == false) _disconnect();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _urlController.dispose();
    _alarm.dispose();
    super.dispose();
  }

  String _fmtDurationShort(int ms) {
    final totalSec = ms ~/ 1000;
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return m > 0 ? '${m}分${s}秒' : '${s}秒';
  }


  // ─── ヒートマップ PNG 保存（Flutter Web 専用）─────────────────
// RepaintBoundary をそのままキャプチャするので foot.svg も含まれ、
// 画面表示と同じアスペクト比になる
// ─── ヒートマップ PNG 保存（Flutter Web 専用）─────────────────
  // RepaintBoundary をそのままキャプチャするので foot.svg も含まれ、
  // 画面表示と同じアスペクト比になる。pixelRatio を上げて高画質化。

  Future<ui.Image?> _captureBoundaryImage(GlobalKey key,
      {double pixelRatio = 4.0}) async {
    try {
      final renderObject = key.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) return null;
      if (renderObject.debugNeedsPaint) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      final ui.Image image =
          await renderObject.toImage(pixelRatio: pixelRatio);
      return image;
    } catch (e) {
      debugPrint('capture error: $e');
      return null;
    }
  }

  Future<void> _saveHeatmapPng() async {
    try {
      const double quality = 4.0;
      final ui.Image? imgL =
          await _captureBoundaryImage(_heatmapKeyL, pixelRatio: quality);
      final ui.Image? imgR =
          await _captureBoundaryImage(_heatmapKeyR, pixelRatio: quality);
      if (imgL == null || imgR == null) {
        _showSnack('キャプチャに失敗しました');
        return;
      }

      final int w = imgL.width + imgR.width;
      final int h = max(imgL.height, imgR.height);

      final recorder = PictureRecorder();
      final canvas =
          Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
      canvas.drawColor(Colors.white, BlendMode.src);
      canvas.drawImage(imgL, Offset.zero, Paint());
      canvas.drawImage(imgR, Offset(imgL.width.toDouble(), 0), Paint());
      final picture = recorder.endRecording();
      final ui.Image combined = await picture.toImage(w, h);
      final byteData =
          await combined.toByteData(format: ImageByteFormat.png);
      if (byteData == null) {
        _showSnack('画像変換失敗');
        return;
      }
      final bytes = byteData.buffer.asUint8List();
      final blob = html.Blob([bytes], 'image/png');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download',
            'heatmap_${DateTime.now().millisecondsSinceEpoch}.png')
        ..click();
      html.Url.revokeObjectUrl(url);
      _showSnack('ダウンロードを開始しました (${w}x$h px)');
    } catch (e) {
      _showSnack('エラー: $e');
    }
  }
  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(msg),
            duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    final frame = _latest;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFFFF),
        title: const Text('Firefighter Device Monitor',
            style: TextStyle(
                color: Color(0xFFCC0000),
                fontWeight: FontWeight.bold)),
        actions: [
          Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                  _connected ? Icons.circle : Icons.circle_outlined,
                  color: _connected ? Colors.green : Colors.redAccent,
                  size: 12)),
          Padding(
              padding: const EdgeInsets.only(left: 6, right: 4),
              child: Center(
                  child: Text(_status,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54)))),
          IconButton(
              tooltip: '設定・接続',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings, color: Colors.black54)),
          Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                  tooltip: 'グラフをリセット',
                  onPressed: _clearGraph,
                  icon: const Icon(Icons.refresh, color: Colors.black54))),
        ],
      ),
      body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              _deviceChip('Dev1 (Left foot)', frame?.conn0 ?? false,
                  _dispSeq0, _dispNf0, _dispBo0),
              const SizedBox(width: 8),
              _deviceChip('Dev2 (Right foot)', frame?.conn1 ?? false,
                  _dispSeq1, _dispNf1, _dispBo1),
            ]),
            const SizedBox(height: 12),
            Expanded(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Expanded(
                      flex: 1,
                      child: Column(children: [
                        Expanded(child: _buildCombinedChart()),
                        const SizedBox(height: 8),
                        IntrinsicHeight(
                            child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                              Expanded(
                                  child: NfBoStatusWidget(
                                      label: 'Dev1 Left foot',
                                      nf: _dispNf0,
                                      bo: _dispBo0)),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: NfBoStatusWidget(
                                      label: 'Dev2 Right foot',
                                      nf: _dispNf1,
                                      bo: _dispBo1)),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: AnomalyHistoryWidget(
                                      sessions: _anomalySessions,
                                      monitoringStart:
                                          _monitoringStart)),
                            ])),
                      ])),
                  const SizedBox(width: 12),
                  Expanded(
                      flex: 1,
                      child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                        IntrinsicHeight(
                            child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                              MiniStatCard(
                                  icon: Icons.pause_circle_outline,
                                  label: 'Stationary time',
                                  value: _fmtDurationShort(
                                      _stationaryMs),
                                  color: const Color(0xFF45B7D1)),
                              const SizedBox(width: 6),
                              MiniStatCard(
                                  icon: Icons.directions_run,
                                  label: 'Active time',
                                  value:
                                      _fmtDurationShort(_movementMs),
                                  color: const Color(0xFFFFA94D)),
                              const SizedBox(width: 6),
                              MiniStatCard(
                                  icon: Icons.directions_walk,
                                  label: 'Step Count',
                                  value:
                                      '${_stepCountR + _stepCountL}',
                                  color: const Color(0xFF1A73E8)),
                              const SizedBox(width: 6),
                              MiniStatCard(
                                  icon: Icons.speed,
                                  label: 'Cadence Left',
                                  value: _cadenceR != null
                                      ? '$_cadenceR spm'
                                      : '-',
                                  color: const Color(0xFFA88BFA)),
                              const SizedBox(width: 6),
                              MiniStatCard(
                                  icon: Icons.speed,
                                  label: 'Cadence Right',
                                  value: _cadenceL != null
                                      ? '$_cadenceL spm'
                                      : '-',
                                  color: const Color(0xFFA88BFA)),
                            ])),
                        const SizedBox(height: 8),
                        Expanded(
                            child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                          Expanded(
                              flex: 1,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFFFFFFF),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                    border: Border.all(
                                        color: Colors.black12)),
                                child: Column(children: [
                                  // ─ タイトル行にダウンロードボタンを追加 ─
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Pressure heatmap',
                                          style: TextStyle(
                                              color: Colors.black87,
                                              fontSize: 12,
                                              fontWeight:
                                                  FontWeight.w600,
                                              letterSpacing: 0.6)),
                                      IconButton(
                                        tooltip: 'PNG として保存',
                                        icon: const Icon(
                                            Icons.download,
                                            size: 18,
                                            color:
                                                Color(0xFF1A73E8)),
                                        padding: EdgeInsets.zero,
                                        constraints:
                                            const BoxConstraints(),
                                        onPressed: _saveHeatmapPng,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Expanded(
                                      child: Row(children: [
                                    Expanded(
                                        child: FootHeatmapView(
                                            values: [
                                              _lastValue[3],
                                              _lastValue[4],
                                              _lastValue[5]
                                            ],
                                            points: _heatmapPoints
                                                .sublist(0, 3),
                                            label: 'Dev1 Left foot',
                                            connected:
                                                frame?.conn0 ?? false,
                                            repaintKey:
                                                _heatmapKeyL)), // ← key
                                    const SizedBox(width: 6),
                                    Expanded(
                                        child: FootHeatmapView(
                                            values: [
                                              _lastValue[0],
                                              _lastValue[1],
                                              _lastValue[2]
                                            ],
                                            points: _heatmapPoints
                                                .sublist(3, 6),
                                            label: 'Dev2 Right foot',
                                            connected:
                                                frame?.conn1 ?? false,
                                            mirror: true,
                                            repaintKey:
                                                _heatmapKeyR)), // ← key
                                  ])),
                                ]),
                              )),
                          const SizedBox(width: 8),
                          Expanded(
                              flex: 1,
                              child: _buildInferencePanel(frame)),
                        ])),
                      ])),
                ])),
          ])),
    );
  }

  Widget _buildInferencePanel(SensorFrame? frame) {
    final ready = frame?.inferReady ?? false;
    final score = frame?.score ?? 0.0;
    final anomaly = frame?.anomaly ?? false;
    const dangerColor = Color(0xFFFF4444);
    const normalColor = Color(0xFF00C853);
    final fillColor = anomaly ? dangerColor : normalColor;
    final statusText =
        !ready ? '収集中...' : (anomaly ? 'DANGER' : 'NORMAL');
    final statusColor = !ready
        ? Colors.black38
        : (anomaly ? dangerColor : normalColor);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: ready
                  ? fillColor.withOpacity(0.4)
                  : const Color(0xFF1A73E8).withOpacity(0.2))),
      child:
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(statusText,
            style: TextStyle(
                color: statusColor,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 3)),
        const SizedBox(height: 20),
        Expanded(
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ready
                    ? CustomPaint(
                        painter: _GaugePainter(
                            value: score.clamp(0.0, 1.0),
                            fillColor: fillColor),
                        child: Center(
                            child: Text(
                                '${(score.clamp(0.0, 1.0) * 100).toStringAsFixed(1)}%',
                                style: const TextStyle(
                                    color: Colors.black87,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold))))
                    : const Center(
                        child: Text('推論待機中',
                            style: TextStyle(
                                color: Colors.black26,
                                fontSize: 13))))),
        const SizedBox(height: 12),
        const Text('anomaly score',
            style: TextStyle(color: Colors.black54, fontSize: 13)),
        const SizedBox(height: 2),
        Text(ready ? score.toStringAsFixed(4) : '-',
            style: const TextStyle(
                color: Colors.black87,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()])),
        const SizedBox(height: 12),
      ]),
    );
  }

  Widget _deviceChip(
      String name, bool conn, int? seq, int? nf, int? bo) {
    return Expanded(
        child: Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: (conn ? Colors.green : Colors.redAccent)
                  .withOpacity(0.4))),
      child: Row(children: [
        Icon(
            conn
                ? Icons.bluetooth_connected
                : Icons.bluetooth_disabled,
            size: 16,
            color: conn ? Colors.green : Colors.redAccent),
        const SizedBox(width: 6),
        Expanded(
            child: Text(
          conn
              ? '$name  seq:${seq ?? '-'} nf:${nf ?? '-'} bo:${bo ?? '-'}'
              : '$name  Not connected',
          style: const TextStyle(fontSize: 11, color: Colors.black87),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        )),
      ]),
    ));
  }

  Widget _buildCombinedChart() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Wrap(
            spacing: 12,
            runSpacing: 4,
            children: List.generate(
                6,
                (i) => Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                          width: 10,
                          height: 10,
                          color: _chColors[i],
                          margin: const EdgeInsets.only(right: 4)),
                      Text(_chLabels[i],
                          style: TextStyle(
                              color: _chColors[i], fontSize: 11)),
                    ]))),
        const SizedBox(height: 8),
        Expanded(
            child: RepaintBoundary(
                child: LineChart(
          LineChartData(
              gridData: FlGridData(
                  show: true,
                  getDrawingHorizontalLine: (_) => FlLine(
                      color: Colors.black12, strokeWidth: 0.5),
                  getDrawingVerticalLine: (_) => FlLine(
                      color: Colors.black12, strokeWidth: 0.5)),
              titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 44,
                          interval: 0.5,
                          getTitlesWidget: (v, _) => Text(
                              v.toStringAsFixed(1),
                              style: const TextStyle(
                                  color: Colors.black45,
                                  fontSize: 9)))),
                  bottomTitles: const AxisTitles(
                      sideTitles:
                          SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles:
                          SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles:
                          SideTitles(showTitles: false))),
              minX: _tick > maxPoints
                  ? (_tick - maxPoints).toDouble()
                  : 0,
              maxX: _tick > 0
                  ? (_tick - 1).toDouble()
                  : (maxPoints - 1).toDouble(),
              minY: 0.0,
              maxY: 1.0,
              borderData: FlBorderData(show: false),
              lineBarsData: List.generate(
                  6,
                  (i) => LineChartBarData(
                      spots: _series[i].isEmpty
                          ? [const FlSpot(0, 0)]
                          : _series[i],
                      color: _chColors[i],
                      isCurved: false,
                      barWidth: 1.2,
                      dotData: const FlDotData(show: false),
                      belowBarData:
                          BarAreaData(show: false))),
              lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) =>
                          const Color(0xFFF5F7FA),
                      getTooltipItems: (spots) =>
                          spots.map((s) {
                            final idx = s.barIndex;
                            return LineTooltipItem(
                                '${_chLabels[idx]}: ${s.y.toStringAsFixed(4)}',
                                TextStyle(
                                    color: _chColors[idx],
                                    fontSize: 11));
                          }).toList()))),
          duration: Duration.zero,
          curve: Curves.linear,
        ))),
      ]),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color fillColor;
  _GaugePainter({required this.value, required this.fillColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 8;
    const strokeWidth = 16.0;
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.black12
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round);
    if (value > 0) {
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          -pi / 2,
          2 * pi * value,
          false,
          Paint()
            ..color = fillColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.fillColor != fillColor;
}