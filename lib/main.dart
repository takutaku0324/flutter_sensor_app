// 非同期処理のライブラリ
import 'dart:async';
// JSON変換のライブラリ
import 'dart:convert';
// 数学関数（min/maxなど）のライブラリ
import 'dart:math';
// バイト列操作
import 'dart:typed_data';
// FlutterのUIライブラリ
import 'package:flutter/material.dart';
// WebSocket通信のライブラリ
import 'package:web_socket_channel/web_socket_channel.dart';
// グラフ描画のライブラリ
import 'package:fl_chart/fl_chart.dart';
// 音声再生ライブラリ
import 'package:audioplayers/audioplayers.dart';

import 'package:flutter_svg/flutter_svg.dart';

import 'dart:ui';

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
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF58A6FF),
          surface: Color(0xFF161B22),
        ),
        textTheme: Typography.material2021().white.apply(
          fontFamily: 'sans-serif',
        ),
      ),
      home: const MonitorPage(),
    );
  }
}

// ================================================================
// IconViewPage
// ================================================================
class IconViewPage extends StatelessWidget {
  const IconViewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('アイコン表示',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
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
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image_not_supported_outlined,
                            size: 64, color: Colors.white24),
                        SizedBox(height: 12),
                        Text('assets/icon.png\nが見つかりません',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('アイコン画像',
                style: TextStyle(color: Colors.white54, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// 異常セッションを記録するクラス
// ================================================================
class AnomalySession {
  final DateTime start;
  DateTime end;
  AnomalySession({required this.start, required this.end});
  Duration get duration => end.difference(start);
}

// ================================================================
// SensorFrame
// ================================================================
class SensorFrame {
  final bool conn0;
  final bool conn1;
  final List<int> rR, rL, rB;
  final List<int> lR, lL, lB;
  final int? seq0, seq1;
  final int? nf0, bo0, nf1, bo1;
  final bool inferReady;
  final double score;
  final bool anomaly;
  final String label;

  SensorFrame({
    required this.conn0,
    required this.conn1,
    required this.rR, required this.rL, required this.rB,
    required this.lR, required this.lL, required this.lB,
    this.seq0, this.seq1,
    this.nf0, this.bo0, this.nf1, this.bo1,
    required this.inferReady,
    required this.score,
    required this.anomaly,
    required this.label,
  });

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
      seq0: _i(d0['seq']), seq1: _i(d1['seq']),
      nf0: _i(d0['nf']),  bo0: _i(d0['bo']),
      nf1: _i(d1['nf']),  bo1: _i(d1['bo']),
      inferReady: infer['ready'] == true,
      score: (infer['score'] ?? 0).toDouble(),
      anomaly: infer['anomaly'] == true,
      label: infer['label']?.toString() ?? '-',
    );
  }
}

// ================================================================
// HeatmapPoint: ヒートマップの各センサー点の設定
// ================================================================
class HeatmapPoint {
  /// 足画像上の相対座標 (0.0~1.0)
  double x;
  double y;
  /// ガウス分布の広がり (sigma, 0.0~1.0の正規化座標上)
  double sigma;
  /// 強度の倍率
  double weightMul;
  /// 表示名
  final String name;
  /// 色
  final Color color;
  final double sigmaY;
  final bool visible;  

  HeatmapPoint({
    required this.x,
    required this.y,
    required this.sigma,
    this.sigmaY = 0.3,
    required this.weightMul,
    required this.name,
    required this.color,
    this.visible = false,
  });

  HeatmapPoint copyWith({double? x, double? y, double? sigma, double? sigmaY, double? weightMul,Color? color,
 bool? visible}) =>
      HeatmapPoint(
        x: x ?? this.x,
        y: y ?? this.y,
        sigma: sigma ?? this.sigma,
        sigmaY: sigmaY ?? this.sigmaY,
        weightMul: weightMul ?? this.weightMul,
        name: name,
        color: color ?? this.color,
        visible: visible ?? this.visible,
      );
}

/// デフォルトのヒートマップ設定を返す。
/// 足画像は縦長のfoot.svgを想定。
/// Dev1 右足: ch0(R_R)=外側前, ch1(R_L)=内側前, ch2(R_B)=踵
/// Dev2 左足: ch3(L_R)=外側前, ch4(L_L)=内側前, ch5(L_B)=踵
List<HeatmapPoint> defaultHeatmapPoints() => [
  // Dev1 右足 (画像左側に表示)
  HeatmapPoint(x: 0.65, y: 0.46, sigma: 0.27, weightMul: 1.0,
      name: 'R_R (内前)', color: const Color(0xFFFF6B6B)),
  HeatmapPoint(x: 0.29, y: 0.46, sigma: 0.27, weightMul: 1.0,
      name: 'R_L (外前)', color: const Color(0xFFFFA94D)),
  HeatmapPoint(x: 0.47, y: 0.68, sigma: 0.27, weightMul: 1.0,
      name: 'R_B (踵)', color: const Color(0xFFFFD43B)),
  // Dev2 左足 (画像右側に表示)
  HeatmapPoint(x: 0.69, y: 0.46, sigma: 0.27, weightMul: 1.0,
      name: 'L_R (外前)', color: const Color(0xFF4ECDC4)),
  HeatmapPoint(x: 0.32, y: 0.46, sigma: 0.27, weightMul: 1.0,
      name: 'L_L (内前)', color: const Color(0xFF45B7D1)),
  HeatmapPoint(x: 0.51, y: 0.68, sigma: 0.27, weightMul: 1.0,
      name: 'L_B (踵)', color: const Color(0xFFA88BFA)),
];

// ================================================================
// FootHeatmapPainter: 足の上にガウスヒートマップを描画するCustomPainter
// ================================================================
class FootHeatmapPainter extends CustomPainter {
  final List<double> values; // 正規化済み 0~1, 長さ3 (ch0/1/2 or ch3/4/5)
  final List<HeatmapPoint> points;
  final Color baseColor;

  FootHeatmapPainter({
    required this.values,
    required this.points,
    required this.baseColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 解像度を下げてパフォーマンスを確保 (ステップ4px)
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
          final sigmaX = p.sigma.clamp(0.01, 1.0);
          final sigmaY = (p.sigma * p.sigmaY).clamp(0.01, 1.0);
          final gauss = exp(
            -(
              (dx * dx) / (2 * sigmaX * sigmaX) +
              (dy * dy) / (2 * sigmaY * sigmaY)
            ),
          );
          intensity += v * gauss;
        }
        intensity = intensity.clamp(0.0, 1.0);
        if (intensity < 0.01) continue;

        final paint = Paint()
          ..color = _intensityColor(intensity, baseColor)
          ..style = PaintingStyle.fill;
        canvas.drawRect(
          Rect.fromLTWH(px - step / 2, py - step / 2, step.toDouble(), step.toDouble()),
          paint,
        );
      }
    }
  }

  Color _intensityColor(double t, Color base) {
    // 青(冷)→緑→黄→赤(熱) のカラーマップ
    if (t < 0.25) {
      return Color.lerp(
        Colors.blue.withOpacity(0.0),
        Colors.cyan.withOpacity(0.5),
        t / 0.25,
      )!;
    } else if (t < 0.5) {
      return Color.lerp(
        Colors.cyan.withOpacity(0.5),
        Colors.green.withOpacity(0.65),
        (t - 0.25) / 0.25,
      )!;
    } else if (t < 0.75) {
      return Color.lerp(
        Colors.green.withOpacity(0.65),
        Colors.yellow.withOpacity(0.75),
        (t - 0.5) / 0.25,
      )!;
    } else {
      return Color.lerp(
        Colors.yellow.withOpacity(0.75),
        Colors.red.withOpacity(0.88),
        (t - 0.75) / 0.25,
      )!;
    }
  }

  @override
  bool shouldRepaint(FootHeatmapPainter old) =>
      old.values != values || old.points != points;
}

// ================================================================
// FootHeatmapView: foot.svg + ヒートマップ + センサー点マーカー
// ================================================================
class FootHeatmapView extends StatelessWidget {
  /// ch0-2 (右足) または ch3-5 (左足) の正規化値
  final List<double> values;
  final List<HeatmapPoint> points;
  final String label;
  final bool connected;
  final bool mirror;

  const FootHeatmapView({
    super.key,
    required this.values,
    required this.points,
    required this.label,
    required this.connected,
    this.mirror = false,
  });


  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LayoutBuilder(
              builder: (_, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // 背景: 足のSVG画像
                    Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..scale(mirror ? -1.0 : 1.0, 1.0),
                      child: SvgPicture.asset(
                        'assets/foot.svg',
                        fit: BoxFit.contain,
                      ),
                    ),
                    // ヒートマップレイヤー
                    if (connected)
                      CustomPaint(
                        painter: FootHeatmapPainter(
                          values: values,
                          points: points,
                          baseColor: const Color(0xFFFF4444),
                        ),
                      ),
                    // センサー点マーカー
                    if (connected)
                      ...List.generate(points.length, (i) {
                        final p = points[i];
                        if (!p.visible) return const SizedBox.shrink();
                        final v = i < values.length ? values[i] : 0.0;
                        return Positioned(
                          left: p.x * w - 6,
                          top: p.y * h - 6,
                          child: _SensorDot(
                              color: p.color, value: v, name: p.name),
                        );
                      }),
                    // 未接続オーバーレイ
                    if (!connected)
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: Text('未接続',
                              style: TextStyle(color: Colors.white38, fontSize: 12)),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        // 凡例
        const SizedBox(height: 4),
        if (connected)
          Wrap(
            spacing: 6,
            children: List.generate(points.length, (i) {
              final p = points[i];
              final v = i < values.length ? values[i] : 0.0;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8,
                      decoration: BoxDecoration(
                          color: p.color, shape: BoxShape.circle)),
                  const SizedBox(width: 2),
                  Text('${(v * 100).toStringAsFixed(0)}%',
                      style: TextStyle(color: p.color,
                          fontSize: 9, fontWeight: FontWeight.bold,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              );
            }),
          ),
      ],
    );
  }

  Widget _placeholderFoot() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: CustomPaint(painter: _FootOutlinePainter()),
    );
  }
}

// ================================================================
// _SensorDot: センサー位置のマーカー
// ================================================================
class _SensorDot extends StatelessWidget {
  final Color color;
  final double value;
  final String name;
  const _SensorDot({required this.color, required this.value, required this.name});

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
          boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 6)],
        ),
      ),
    );
  }
}

// ================================================================
// _FootOutlinePainter: foot.svg が読み込めない場合の代替描画
// ================================================================
class _FootOutlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final w = size.width;
    final h = size.height;

    // 簡易足型アウトライン (足底を模した楕円+指)
    final path = Path();
    // 足底
    path.addOval(Rect.fromLTWH(w * 0.15, h * 0.15, w * 0.70, h * 0.65));
    // 踵をやや尖らせる
    path.moveTo(w * 0.35, h * 0.78);
    path.quadraticBezierTo(w * 0.50, h * 0.92, w * 0.65, h * 0.78);

    canvas.drawPath(path, paint);

    // 5本指
    final toePaint = Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.fill;
    final toePositions = [0.20, 0.32, 0.44, 0.57, 0.70];
    for (int i = 0; i < 5; i++) {
      final tx = w * toePositions[i];
      final ty = h * 0.10;
      canvas.drawOval(
          Rect.fromCenter(center: Offset(tx, ty),
              width: w * 0.09, height: h * 0.10),
          toePaint);
    }

    // プレースホルダーテキスト
    final tp = TextPainter(
      text: const TextSpan(
        text: 'assets/foot.svg\nが見つかりません',
        style: TextStyle(color: Colors.white24, fontSize: 10),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: w);
    tp.paint(canvas, Offset((w - tp.width) / 2, h * 0.40));
  }

  @override
  bool shouldRepaint(_FootOutlinePainter _) => false;
}

// ================================================================
// AlarmSoundController
// ================================================================
class AlarmSoundController {
  static const int _sampleRate = 44100;
  static const double _freqStart = 400.0;
  static const double _freqEnd = 1200.0;
  static const int _sweepMs = 300;
  static const int _silenceMs = 100;
  static const double _amplitude = 0.7;

  AudioPlayer? _player;
  Uint8List? _wavBytes;
  bool _isPlaying = false;
  bool _initialized = false;

  Uint8List _buildWavHeader(int dataSize) {
    final byteRate = _sampleRate * 1 * 16 ~/ 8;
    final blockAlign = 1 * 16 ~/ 8;
    final buf = ByteData(44);
    buf.setUint8(0,  0x52); buf.setUint8(1,  0x49);
    buf.setUint8(2,  0x46); buf.setUint8(3,  0x46);
    buf.setUint32(4, 36 + dataSize, Endian.little);
    buf.setUint8(8,  0x57); buf.setUint8(9,  0x41);
    buf.setUint8(10, 0x56); buf.setUint8(11, 0x45);
    buf.setUint8(12, 0x66); buf.setUint8(13, 0x6D);
    buf.setUint8(14, 0x74); buf.setUint8(15, 0x20);
    buf.setUint32(16, 16, Endian.little);
    buf.setUint16(20, 1, Endian.little);
    buf.setUint16(22, 1, Endian.little);
    buf.setUint32(24, _sampleRate, Endian.little);
    buf.setUint32(28, byteRate, Endian.little);
    buf.setUint16(32, blockAlign, Endian.little);
    buf.setUint16(34, 16, Endian.little);
    buf.setUint8(36, 0x64); buf.setUint8(37, 0x61);
    buf.setUint8(38, 0x74); buf.setUint8(39, 0x61);
    buf.setUint32(40, dataSize, Endian.little);
    return buf.buffer.asUint8List();
  }

  Uint8List _buildSweepSilencePcm() {
    final sweepSamples = (_sampleRate * _sweepMs / 1000).round();
    final silenceSamples = (_sampleRate * _silenceMs / 1000).round();
    final totalSamples = sweepSamples + silenceSamples;
    final pcm = ByteData(totalSamples * 2);
    final sweepDuration = _sweepMs / 1000.0;
    for (int i = 0; i < sweepSamples; i++) {
      final t = i / _sampleRate;
      final phase = 2 * pi * (_freqStart * t +
          (_freqEnd - _freqStart) / (2 * sweepDuration) * t * t);
      final sample = (sin(phase) * _amplitude * 32767).round().clamp(-32768, 32767);
      pcm.setInt16(i * 2, sample, Endian.little);
    }
    return pcm.buffer.asUint8List();
  }

  Future<void> init() async {
    try {
      _player = AudioPlayer();
      await _player!.setReleaseMode(ReleaseMode.loop);
      final pcmData = _buildSweepSilencePcm();
      final header = _buildWavHeader(pcmData.length);
      final wav = Uint8List(header.length + pcmData.length);
      wav.setRange(0, header.length, header);
      wav.setRange(header.length, wav.length, pcmData);
      _wavBytes = wav;
      _initialized = true;
    } catch (e) {
      debugPrint('AlarmSoundController init error: $e');
    }
  }

  Future<void> startAlarm() async {
    if (_isPlaying || !_initialized || _wavBytes == null) return;
    _isPlaying = true;
    try {
      await _player!.play(BytesSource(_wavBytes!));
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
    _wavBytes = null;
  }
}

// ================================================================
// NfBoStatusWidget
// ================================================================
class NfBoStatusWidget extends StatefulWidget {
  final String label;
  final int? nf;
  final int? bo;
  const NfBoStatusWidget({super.key, required this.label, required this.nf, required this.bo});

  @override
  State<NfBoStatusWidget> createState() => _NfBoStatusWidgetState();
}

class _NfBoStatusWidgetState extends State<NfBoStatusWidget> {
  int? _prevNf;
  int? _prevBo;
  bool _nfAlert = false;
  bool _boAlert = false;
  Timer? _nfTimer;
  Timer? _boTimer;

  @override
  void didUpdateWidget(NfBoStatusWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newNf = widget.nf;
    if (newNf != null && _prevNf != null && newNf > _prevNf!) {
      _nfTimer?.cancel();
      setState(() => _nfAlert = true);
      _nfTimer = Timer(const Duration(seconds: 1), () {
        if (mounted) setState(() => _nfAlert = false);
      });
    }
    if (newNf != null) _prevNf = newNf;

    final newBo = widget.bo;
    if (newBo != null && _prevBo != null && newBo > _prevBo!) {
      _boTimer?.cancel();
      setState(() => _boAlert = true);
      _boTimer = Timer(const Duration(seconds: 1), () {
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
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withOpacity(0.5), width: 1),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8,
                  height: 1.0,
                  color: color.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                val != null ? '$val' : '-',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8,
                  height: 1.0,
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
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
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 8,
                color: Colors.white38,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: Row(
                children: [
                  _statCell('Notify Fail', widget.nf, _nfAlert),
                  _statCell('Buffer Overflow', widget.bo, _boAlert),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  }

// ================================================================
// AnomalyHistoryWidget
// ================================================================
class AnomalyHistoryWidget extends StatelessWidget {
  final List<AnomalySession> sessions;
  final DateTime? monitoringStart;
  const AnomalyHistoryWidget({super.key, required this.sessions, required this.monitoringStart});

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';

  String _dur(Duration d) => d.inSeconds < 60
      ? '${d.inSeconds}秒'
      : '${d.inMinutes}分${d.inSeconds % 60}秒';

  void _showPopup(BuildContext context) {
    final now = DateTime.now();
    final rangeStart = monitoringStart ??
        (sessions.isNotEmpty ? sessions.first.start : now.subtract(const Duration(minutes: 1)));
    final totalMs = now.difference(rangeStart).inMilliseconds.toDouble();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(sessions.isNotEmpty ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                    size: 18,
                    color: sessions.isNotEmpty ? const Color(0xFFFF4444) : const Color(0xFF00C853)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('異常履歴: ${sessions.length}回',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, height: 1.0,fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                GestureDetector(onTap: () => Navigator.of(ctx).pop(),
                    child: const Icon(Icons.close, size: 10, color: Colors.white38)),
              ]),
              const SizedBox(height: 16),
              if (totalMs > 0) ...[
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(_fmt(rangeStart), style: const TextStyle(fontSize: 9, color: Colors.white38)),
                  Text(_fmt(now), style: const TextStyle(fontSize: 9, color: Colors.white38)),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LayoutBuilder(builder: (_, constraints) {
                    final bw = constraints.maxWidth;
                    return SizedBox(
                      height: 16,
                      child: Stack(children: [
                        Container(width: bw, height: 16, color: Colors.white.withOpacity(0.07)),
                        for (final s in sessions)
                          Positioned(
                            left: ((s.start.difference(rangeStart).inMilliseconds / totalMs) * bw).clamp(0.0, bw),
                            child: Container(
                              width: ((s.end.difference(s.start).inMilliseconds / totalMs) * bw).clamp(1.0, bw),
                              height: 16,
                              color: const Color(0xFFFF4444).withOpacity(0.85),
                            ),
                          ),
                      ]),
                    );
                  }),
                ),
                const SizedBox(height: 14),
              ],
              if (sessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: Text('異常なし',
                      style: TextStyle(color: Color(0xFF00C853), fontSize: 13))),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    child: Column(
                      children: sessions.reversed.map((s) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF4444).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: const Color(0xFFFF4444).withOpacity(0.25)),
                        ),
                        child: Row(children: [
                          Container(width: 7, height: 7, margin: const EdgeInsets.only(right: 8),
                              decoration: const BoxDecoration(color: Color(0xFFFF4444), shape: BoxShape.circle)),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${_fmt(s.start)}  ～  ${_fmt(s.end)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text('継続時間: ${_dur(s.duration)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10, color: Colors.white38)),
                          ])),
                        ]),
                      )).toList(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = sessions.length;
    return GestureDetector(
      onTap: () => _showPopup(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: count > 0 ? const Color(0xFFFF4444).withOpacity(0.5) : Colors.white10,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('異常履歴',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    height: 1.0,
                    color: (count > 0 ? const Color(0xFFFF4444) : Colors.white38).withOpacity(0.7),
                    fontWeight: FontWeight.w600, letterSpacing: 0.8)),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(count > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  size: 15, color: count > 0 ? const Color(0xFFFF4444) : const Color(0xFF00C853)),
              const SizedBox(width: 4),
              Flexible(
                child: Text('$count 回',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15, height: 1.0, fontWeight: FontWeight.bold,
                        color: count > 0 ? const Color(0xFFFF4444) : const Color(0xFF00C853),
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// MiniStatCard
// ================================================================
class MiniStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const MiniStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
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
                  style: const TextStyle(fontSize: 10, color: Colors.white38,
                      fontWeight: FontWeight.w600, letterSpacing: 0.4)),
              const SizedBox(height: 4),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: color, fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// AppSettings
// ================================================================
class AppSettings {
  final String wsUrl;
  final double stdThreshold;
  final int stdWindowSize;
  final bool alarmEnabled;
  final bool? connectAction;
  final List<HeatmapPoint> heatmapPoints;

  const AppSettings({
    required this.wsUrl,
    required this.stdThreshold,
    required this.stdWindowSize,
    required this.alarmEnabled,
    required this.heatmapPoints,
    this.connectAction,
  });
}

// ================================================================
// HeatmapSettingsPage: 各センサー点のX/Y/Sigma/WeightMul を編集
// ================================================================
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
    // ディープコピー
    _points = widget.points.map((p) => p.copyWith()).toList();
  }

  Widget _slider(String label, double value, double min, double max,
      int divisions, void Function(double) onChanged, Color color) {
    return Row(children: [
      SizedBox(
        width: 68,
        child: Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min, max: max, divisions: divisions,
          activeColor: color,
          inactiveColor: Colors.white10,
          onChanged: onChanged,
        ),
      ),
      SizedBox(
        width: 40,
        child: Text(value.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: TextStyle(color: color, fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('ヒートマップ 設定',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_points),
            child: const Text('保存',
                style: TextStyle(color: Color(0xFF58A6FF), fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                final def = defaultHeatmapPoints();
                for (int i = 0; i < _points.length && i < def.length; i++) {
                  _points[i] = def[i];
                }
              });
            },
            child: const Text('リセット',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ),
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
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.color.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: p.color,
                        shape: BoxShape.circle,
                      ),
                    ),

                    Expanded(
                      child: Text(
                        p.name,
                        style: TextStyle(
                          color: p.color,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                   IconButton(
                      icon: Icon(
                        p.visible ? Icons.visibility : Icons.visibility_off,
                        size: 18,
                        color: p.visible ? Colors.white70 : Colors.white24,
                      ),
                      onPressed: () {
                        setState(() => _points[idx] = p.copyWith(visible: !p.visible));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _slider('X 位置', p.x, 0.0, 1.0, 100,
                    (v) => setState(() => _points[idx] = p.copyWith(x: v)), p.color),
                _slider('Y 位置', p.y, 0.0, 1.0, 100,
                    (v) => setState(() => _points[idx] = p.copyWith(y: v)), p.color),
                _slider('広がり (σ)', p.sigma, 0.02, 0.5, 48,
                    (v) => setState(() => _points[idx] = p.copyWith(sigma: v)), p.color),
                _slider('縦倍率',  p.sigmaY,  0.1, 3.0, 58,  (v) => setState(  () => _points[idx] = p.copyWith(sigmaY: v),),  p.color,),
                _slider('強度倍率', p.weightMul, 0.0, 2.0, 40,
                    (v) => setState(() => _points[idx] = p.copyWith(weightMul: v)), p.color),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ================================================================
// SettingsPage
// ================================================================
class SettingsPage extends StatefulWidget {
  final String initialUrl;
  final double initialThreshold;
  final int initialWindowSize;
  final bool initialAlarmEnabled;
  final bool isConnected;
  final List<HeatmapPoint> heatmapPoints;

  const SettingsPage({
    super.key,
    required this.initialUrl,
    required this.initialThreshold,
    required this.initialWindowSize,
    required this.initialAlarmEnabled,
    required this.isConnected,
    required this.heatmapPoints,
  });

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
    connectAction: connectAction,
  );

  void _save() => Navigator.of(context).pop(_buildSettings());
  void _connect() => Navigator.of(context).pop(_buildSettings(connectAction: true));
  void _disconnect() => Navigator.of(context).pop(_buildSettings(connectAction: false));

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
    child: Text(text, style: const TextStyle(
        color: Color(0xFF58A6FF), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
  );

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF161B22),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white10),
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final connected = widget.isConnected;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('設定', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存',
                style: TextStyle(color: Color(0xFF58A6FF), fontWeight: FontWeight.bold)),
          ),
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
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                  decoration: InputDecoration(
                    labelText: 'WebSocket URL',
                    labelStyle: const TextStyle(color: Colors.white38),
                    filled: true, fillColor: const Color(0xFF0D1117),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Icon(
                    connected ? Icons.circle : Icons.circle_outlined,
                    size: 10,
                    color: connected ? Colors.greenAccent : Colors.redAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    connected ? '接続中' : '未接続',
                    style: TextStyle(
                      fontSize: 12,
                      color: connected ? Colors.greenAccent : Colors.redAccent,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: connected ? _disconnect : _connect,
                    icon: Icon(connected ? Icons.link_off : Icons.link, size: 18),
                    label: Text(
                      connected ? '切断する' : '接続する',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: connected
                          ? Colors.redAccent.withOpacity(0.85)
                          : const Color(0xFF3AB449),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          _sectionTitle('静止／運動 判定'),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('標準偏差しきい値', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text(_threshold.toStringAsFixed(2),
                      style: const TextStyle(color: Color(0xFF58A6FF), fontWeight: FontWeight.bold)),
                ]),
                Slider(
                  value: _threshold,
                  min: 0.01, max: 1.0, divisions: 99,
                  activeColor: const Color(0xFF58A6FF),
                  inactiveColor: Colors.white10,
                  onChanged: (v) => setState(() => _threshold = v),
                ),
                const SizedBox(height: 4),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('判定ウィンドウ（サンプル数）', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text('$_windowSize',
                      style: const TextStyle(color: Color(0xFF58A6FF), fontWeight: FontWeight.bold)),
                ]),
                Slider(
                  value: _windowSize.toDouble(),
                  min: 20, max: 600, divisions: 58,
                  activeColor: const Color(0xFF58A6FF),
                  inactiveColor: Colors.white10,
                  onChanged: (v) => setState(() => _windowSize = v.round()),
                ),
                Text(
                  '62.5Hzサンプリングのため約 ${(_windowSize * 16 / 1000).toStringAsFixed(2)} 秒分の窓',
                  style: const TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ],
            ),
          ),

          _sectionTitle('アラーム'),
          _card(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('異常検知時にアラーム音を再生',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              value: _alarmEnabled,
              activeColor: const Color(0xFF58A6FF),
              onChanged: (v) => setState(() => _alarmEnabled = v),
            ),
          ),

          _sectionTitle('ヒートマップ'),
          _card(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.thermostat_outlined, color: Color(0xFF58A6FF)),
              title: const Text('センサー点の位置・強度を編集',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              subtitle: const Text('各チャンネルの X/Y 位置・ガウス幅・強度倍率を設定',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: () async {
                final result = await Navigator.of(context).push<List<HeatmapPoint>>(
                  MaterialPageRoute(
                    builder: (_) => HeatmapSettingsPage(points: _heatmapPoints),
                  ),
                );
                if (result != null) setState(() => _heatmapPoints = result);
              },
            ),
          ),

          _sectionTitle('画面'),
          _card(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.image_outlined, color: Color(0xFF58A6FF)),
              title: const Text('アイコン表示',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              subtitle: const Text('PNG アイコンを表示する画面を開く',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const IconViewPage()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// MonitorPage
// ================================================================
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
    Color(0xFFFF6B6B), Color(0xFFFFA94D), Color(0xFFFFD43B),
    Color(0xFF4ECDC4), Color(0xFF45B7D1), Color(0xFFA88BFA),
  ];

  int _stdWindowSize = 300;
  double _stdThreshold = 0.1;
  static const int _sampleIntervalMs = 16;

  WebSocketChannel? _channel;
  bool _connected = false;
  String _status = '未接続';
  SensorFrame? _latest;

  // ── ちらつき防止: 表示用の前回値を保持 ────────────────────────
  int? _dispSeq0;
  int? _dispSeq1;
  int? _dispNf0;
  int? _dispBo0;
  int? _dispNf1;
  int? _dispBo1;

  int? _lastSeq0;
  int? _lastSeq1;

  final List<List<FlSpot>> _series = List.generate(6, (_) => []);
  final List<double> _lastValue = List.filled(6, 0.0);
  int _tick = 0;

  final _urlController = TextEditingController(text: _defaultWsUrl);

  DateTime? _monitoringStart;
  final List<AnomalySession> _anomalySessions = [];
  AnomalySession? _currentAnomalySession;
  DateTime? _lastAnomalyTime;

  final AlarmSoundController _alarm = AlarmSoundController();
  bool _alarmPlaying = false;
  bool _alarmEnabled = true;

  final List<List<double>> _stdBuffer = List.generate(6, (_) => []);
  int _stationaryMs = 0;
  int _movementMs = 0;

  // ヒートマップ設定
  List<HeatmapPoint> _heatmapPoints = defaultHeatmapPoints();

  // ── 歩数・ケイデンス ─────────────────────────────────────────
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

  (bool, int, int, int?) _detectStep(
      double val, bool above, int windowCount, int belowCount) {
    if (val > _stepThreshold) {
      if (!above) {
        return (true, 1, 0, null);
      } else {
        final newCount = windowCount + 1;
        if (newCount >= _stepMaxWindow) {
          return (false, 0, 0, null);
        }
        return (true, newCount, 0, null);
      }
    } else {
      final newBelowCount = belowCount + 1;
      if (above) {
        if (windowCount >= _stepMaxWindow) {
          return (false, 0, newBelowCount, null);
        }
        final cad = (60.0 / (windowCount * 0.016)).round();
        if (cad >= _cadenceMaxSpm) {
          return (false, 0, newBelowCount, null);
        }
        return (false, 0, newBelowCount, cad);
      }
      return (false, 0, newBelowCount, null);
    }
  }

  void _updateStepCounts(int s) {
    if (_series[2].isNotEmpty) {
      final valR = _lastValue[2];
      final (newAboveR, newCountR, newBelowR, cadR) =
          _detectStep(valR, _stepAboveR, _stepWindowCountR, _cadenceBelowCountR);
      _stepAboveR = newAboveR;
      _stepWindowCountR = newCountR;
      _cadenceBelowCountR = newBelowR;
      if (cadR != null) {
        _stepCountR++;
        _cadenceR = cadR;
      }
      if (_cadenceBelowCountR >= _cadenceTimeoutSamples) {
        _cadenceR = null;
      }
    }
    if (_series[5].isNotEmpty) {
      final valL = _lastValue[5];
      final (newAboveL, newCountL, newBelowL, cadL) =
          _detectStep(valL, _stepAboveL, _stepWindowCountL, _cadenceBelowCountL);
      _stepAboveL = newAboveL;
      _stepWindowCountL = newCountL;
      _cadenceBelowCountL = newBelowL;
      if (cadL != null) {
        _stepCountL++;
        _cadenceL = cadL;
      }
      if (_cadenceBelowCountL >= _cadenceTimeoutSamples) {
        _cadenceL = null;
      }
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
    final variance = data.fold(0.0, (sum, v) => sum + (v - mean) * (v - mean)) / n;
    return sqrt(variance);
  }

  void _updateMotionState() {
    if (_stdBuffer.any((b) => b.length < _stdWindowSize)) return;
    final allStationary = _stdBuffer.every((b) => _calcStd(b) <= _stdThreshold);
    if (allStationary) {
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
        _currentAnomalySession = AnomalySession(start: now, end: now);
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
      setState(() { _connected = true; _status = '接続中'; });
      channel.stream.listen(
        (msg) {
          Map<String, dynamic> raw;
          try { raw = jsonDecode(msg as String) as Map<String, dynamic>; }
          catch (_) { return; }
          _pushFrame(SensorFrame.fromJson(raw));
        },
        onError: (_) => setState(() { _status = '接続エラー'; _connected = false; }),
        onDone: () => setState(() { _status = '切断されました'; _connected = false; }),
      );
    } catch (e) {
      setState(() { _status = 'エラー: $e'; _connected = false; });
    }
  }

  void _pushFrame(SensorFrame frame) {
    final seq0Changed = frame.seq0 != null && frame.seq0 != _lastSeq0;
    final seq1Changed = frame.seq1 != null && frame.seq1 != _lastSeq1;
    if (!seq0Changed && !seq1Changed) return;
    _lastSeq0 = frame.seq0;
    _lastSeq1 = frame.seq1;

    final rawArrays = <List<int>?>[
      frame.conn0 ? frame.rR : null, frame.conn0 ? frame.rL : null, frame.conn0 ? frame.rB : null,
      frame.conn1 ? frame.lR : null, frame.conn1 ? frame.lL : null, frame.conn1 ? frame.lB : null,
    ];

    final sampleCount = rawArrays.whereType<List<int>>().fold(0, (mx, a) => max(mx, a.length));
    if (sampleCount == 0) return;

    setState(() {
      _latest = frame;

      // ── ちらつき防止: null でない値のみ表示用変数を更新 ──────
      if (frame.seq0 != null) _dispSeq0 = frame.seq0;
      if (frame.seq1 != null) _dispSeq1 = frame.seq1;
      if (frame.nf0 != null)  _dispNf0  = frame.nf0;
      if (frame.bo0 != null)  _dispBo0  = frame.bo0;
      if (frame.nf1 != null)  _dispNf1  = frame.nf1;
      if (frame.bo1 != null)  _dispBo1  = frame.bo1;

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
          if (_stdBuffer[ch].length > _stdWindowSize) _stdBuffer[ch].removeAt(0);
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
    setState(() { _connected = false; _status = '未接続'; });
  }

  void _clearGraph() => setState(() {
    for (final s in _series) s.clear();
    _tick = 0;
    for (final b in _stdBuffer) b.clear();
    _stationaryMs = 0;
    _movementMs = 0;
    _stepCountR = 0; _stepAboveR = false; _stepWindowCountR = 0; _cadenceR = null;
    _stepCountL = 0; _stepAboveL = false; _stepWindowCountL = 0; _cadenceL = null;
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
          heatmapPoints: _heatmapPoints,
        ),
      ),
    );
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

    if (result.connectAction == true) {
      _connect();
    } else if (result.connectAction == false) {
      _disconnect();
    }
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

  @override
  Widget build(BuildContext context) {
    final frame = _latest;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Firefighter Device Monitor',
            style: TextStyle(color: Color(0xFFFF4848), fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(
              _connected ? Icons.circle : Icons.circle_outlined,
              color: _connected ? Colors.greenAccent : Colors.redAccent,
              size: 12,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 4),
            child: Center(
              child: Text(
                _status,
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ),
          ),
          IconButton(
            tooltip: '設定・接続',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings, color: Colors.white54),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              tooltip: 'グラフをリセット',
              onPressed: _clearGraph,
              icon: const Icon(Icons.refresh, color: Colors.white54),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // デバイス接続状態チップ (ちらつき防止: _disp* 変数を使用)
          Row(children: [
            _deviceChip('Dev1 (右足)', frame?.conn0 ?? false,
                _dispSeq0, _dispNf0, _dispBo0),
            const SizedBox(width: 8),
            _deviceChip('Dev2 (左足)', frame?.conn1 ?? false,
                _dispSeq1, _dispNf1, _dispBo1),
          ]),
          const SizedBox(height: 12),

          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 左カラム: グラフ ＋ グラフ下ウィジェット ──
                Expanded(
                  flex: 1,
                  child: Column(children: [
                    Expanded(child: _buildCombinedChart()),
                    const SizedBox(height: 8),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: NfBoStatusWidget(
                              label: 'Dev1 右足',
                              nf: _dispNf0, bo: _dispBo0)),
                          const SizedBox(width: 6),
                          Expanded(child: NfBoStatusWidget(
                              label: 'Dev2 左足',
                              nf: _dispNf1, bo: _dispBo1)),
                          const SizedBox(width: 6),
                          Expanded(child: AnomalyHistoryWidget(
                              sessions: _anomalySessions,
                              monitoringStart: _monitoringStart)),
                        ],
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                // ── 右カラム: ミニ統計 ＋ ヒートマップ＋推論パネル ──
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ミニ統計カード
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            MiniStatCard(
                              icon: Icons.pause_circle_outline,
                              label: '静止時間',
                              value: _fmtDurationShort(_stationaryMs),
                              color: const Color(0xFF45B7D1),
                            ),
                            const SizedBox(width: 6),
                            MiniStatCard(
                              icon: Icons.directions_run,
                              label: '運動時間',
                              value: _fmtDurationShort(_movementMs),
                              color: const Color(0xFFFFA94D),
                            ),
                            const SizedBox(width: 6),
                            MiniStatCard(
                              icon: Icons.directions_walk,
                              label: '歩数',
                              value: '${_stepCountR + _stepCountL}',
                              color: const Color(0xFF58A6FF),
                            ),
                            const SizedBox(width: 6),
                            MiniStatCard(
                              icon: Icons.speed,
                              label: 'ケイデンス 右',
                              value: _cadenceR != null ? '$_cadenceR spm' : '-',
                              color: const Color(0xFFA88BFA),
                            ),
                            const SizedBox(width: 6),
                            MiniStatCard(
                              icon: Icons.speed,
                              label: 'ケイデンス 左',
                              value: _cadenceL != null ? '$_cadenceL spm' : '-',
                              color: const Color(0xFFA88BFA),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // ヒートマップ (左) + 推論パネル (右) を横並び
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── ヒートマップ ──
                            Expanded(
                              flex: 1,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF161B22),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Column(
                                  children: [
                                    const Text('圧力ヒートマップ',
                                        style: TextStyle(
                                            color: Colors.white38,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.6)),
                                    const SizedBox(height: 6),
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: FootHeatmapView(
                                              values: [
                                                _lastValue[0],
                                                _lastValue[1],
                                                _lastValue[2],
                                              ],
                                              points: _heatmapPoints.sublist(0, 3),
                                              label: 'Dev1 右足',
                                              connected: frame?.conn0 ?? false,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: FootHeatmapView(
                                              values: [
                                                _lastValue[3],
                                                _lastValue[4],
                                                _lastValue[5],
                                              ],
                                              points: _heatmapPoints.sublist(3, 6),
                                              label: 'Dev2 左足',
                                              connected: frame?.conn1 ?? false,
                                              mirror: true,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // ── 推論パネル ──
                            Expanded(
                              flex: 1,
                              child: _buildInferencePanel(frame),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildInferencePanel(SensorFrame? frame) {
    final ready = frame?.inferReady ?? false;
    final score = frame?.score ?? 0.0;
    final anomaly = frame?.anomaly ?? false;
    const dangerColor = Color(0xFFFF4444);
    const normalColor = Color(0xFF00C853);
    final fillColor = anomaly ? dangerColor : normalColor;
    final statusText = !ready ? '収集中...' : (anomaly ? 'DANGER' : 'NORMAL');
    final statusColor = !ready ? Colors.white38 : (anomaly ? dangerColor : normalColor);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ready ? fillColor.withOpacity(0.4) : const Color(0xFF58A6FF).withOpacity(0.2),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(statusText, style: TextStyle(
              color: statusColor, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 3)),
          const SizedBox(height: 20),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ready
                  ? _buildScoreGauge(score, fillColor)
                  : const Center(child: Text('推論待機中',
                      style: TextStyle(color: Colors.white24, fontSize: 13))),
            ),
          ),
          const SizedBox(height: 12),
          Text(ready ? score.toStringAsFixed(4) : '-',
              style: const TextStyle(color: Colors.white70, fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 4),
          const Text('anomaly score', style: TextStyle(color: Colors.white24, fontSize: 11)),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildScoreGauge(double score, Color fillColor) {
    final v = score.clamp(0.0, 1.0);
    return CustomPaint(
      painter: _GaugePainter(value: v, fillColor: fillColor),
      child: Center(child: Text('${(v * 100).toStringAsFixed(1)}%',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
    );
  }

  Widget _deviceChip(String name, bool conn, int? seq, int? nf, int? bo) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: (conn ? Colors.greenAccent : Colors.redAccent).withOpacity(0.4)),
        ),
        child: Row(children: [
          Icon(conn ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              size: 16, color: conn ? Colors.greenAccent : Colors.redAccent),
          const SizedBox(width: 6),
          Expanded(child: Text(
            conn
                ? '$name  seq:${seq ?? '-'} nf:${nf ?? '-'} bo:${bo ?? '-'}'
                : '$name  未接続',
            style: const TextStyle(fontSize: 11, color: Colors.white70),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )),
        ]),
      ),
    );
  }

  Widget _buildCombinedChart() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12, runSpacing: 4,
            children: List.generate(6, (i) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 10, height: 10, color: _chColors[i],
                    margin: const EdgeInsets.only(right: 4)),
                Text(_chLabels[i], style: TextStyle(color: _chColors[i], fontSize: 11)),
              ],
            )),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: RepaintBoundary(
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 0.5),
                    getDrawingVerticalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 0.5),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true, reservedSize: 44, interval: 0.5,
                      getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1),
                          style: const TextStyle(color: Colors.white38, fontSize: 9)),
                    )),
                    bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  minX: _tick > maxPoints ? (_tick - maxPoints).toDouble() : 0,
                  maxX: _tick > 0 ? (_tick - 1).toDouble() : (maxPoints - 1).toDouble(),
                  minY: 0.0, maxY: 1.0,
                  borderData: FlBorderData(show: false),
                  lineBarsData: List.generate(6, (i) => LineChartBarData(
                    spots: _series[i].isEmpty ? [const FlSpot(0, 0)] : _series[i],
                    color: _chColors[i], isCurved: false, barWidth: 1.2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  )),
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF0D1117),
                      getTooltipItems: (spots) => spots.map((s) {
                        final idx = s.barIndex;
                        return LineTooltipItem('${_chLabels[idx]}: ${s.y.toStringAsFixed(4)}',
                            TextStyle(color: _chColors[idx], fontSize: 11));
                      }).toList(),
                    ),
                  ),
                ),
                duration: Duration.zero,
                curve: Curves.linear,
              ),
            ),
          ),
        ],
      ),
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
    canvas.drawCircle(center, radius,
        Paint()..color = Colors.white10..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth..strokeCap = StrokeCap.round);
    if (value > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2, 2 * pi * value, false,
        Paint()..color = fillColor..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.fillColor != fillColor;
}