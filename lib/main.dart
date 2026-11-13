// 非同期処理のライブラリ
import 'dart:async';
// 再生キュー (Queue)
import 'dart:collection';
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

import 'package:flutter/gestures.dart';

import 'dart:ui';

// スマホ通知 (nRF Dev1/2 の推論が異常のとき)
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
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
            style:
                TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
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
                            style:
                                TextStyle(color: Colors.white38, fontSize: 12)),
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
// 5クラス行動分類の定義 (M5 / ゲートウェイ側 kClassNames と同じ並びにすること)
//   0:walk 1:stand 2:sit 3:stairs 4:danger
// ================================================================
const int kDangerClass = 4;
const List<String> kClassKeys = ['walk', 'stand', 'sit', 'stairs', 'danger'];
const List<String> kClassJa = ['歩行', '立位', '座位', '階段昇降', '転倒'];
const List<Color> kClassColors = [
  Color(0xFF00C853), // walk
  Color(0xFF45B7D1), // stand
  Color(0xFF58A6FF), // sit
  Color(0xFFFFD43B), // stairs
  Color(0xFFFF4444), // danger
];

// ── 表示用グループ (5クラスと1対1) ──
const List<int> kClassToGroup = [0, 1, 2, 3, 4];
const int kGroupStairs = 3;
const int kGroupFall = 4;
const List<String> kGroupJa = ['歩行', '立位', '座位', '階段昇降', '転倒'];
const List<String> kGroupEn = ['walk', 'stand', 'sit', 'stairs', 'danger'];
const List<Color> kGroupColors = [
  Color(0xFF00C853), // 歩行
  Color(0xFF45B7D1), // 立位
  Color(0xFF58A6FF), // 座位
  Color(0xFFFFD43B), // 階段昇降
  Color(0xFFFF4444), // 転倒
];

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
// ── nRF UART Dev1/Dev2 (d0,d1) のスナップショット (設定画面の数値表示用) ──
class NrfDevSnapshot {
  final bool conn;
  final int? seq, nf, bo;
  final List<int> r, l, b;
  const NrfDevSnapshot({
    this.conn = false,
    this.seq,
    this.nf,
    this.bo,
    this.r = const [],
    this.l = const [],
    this.b = const [],
  });
  factory NrfDevSnapshot.fromJson(Map<String, dynamic> d) => NrfDevSnapshot(
        conn: d['conn'] == true,
        seq: SensorFrame._i(d['seq']),
        nf: SensorFrame._i(d['nf']),
        bo: SensorFrame._i(d['bo']),
        r: SensorFrame._parseIntArray(d['R']),
        l: SensorFrame._parseIntArray(d['L']),
        b: SensorFrame._parseIntArray(d['B']),
      );
}

// ── ゲートウェイ側推論 (nRF Dev1+Dev2) 結果 `nrf_infer` ──
class NrfInferInfo {
  final bool ready;
  final String mode; // "anomaly" | "class" | "none"
  final int count;
  final int us;
  final double score, thr;
  final bool anomaly;
  final int cls;
  final double prob;
  final String label;
  final bool danger;
  final List<double> probs;
  const NrfInferInfo({
    this.ready = false,
    this.mode = 'none',
    this.count = 0,
    this.us = 0,
    this.score = 0,
    this.thr = 0,
    this.anomaly = false,
    this.cls = -1,
    this.prob = 0,
    this.label = '-',
    this.danger = false,
    this.probs = const [],
  });

  /// 異常判定 (anomaly モード: anomaly / class モード: danger クラス)
  bool get abnormal {
    if (!ready) return false;
    if (mode == 'anomaly') return anomaly;
    if (mode == 'class') return danger;
    return false;
  }

  factory NrfInferInfo.fromJson(Map<String, dynamic> j) {
    final cls = SensorFrame._i(j['class']) ?? -1;
    return NrfInferInfo(
      ready: j['ready'] == true,
      mode: j['mode']?.toString() ?? 'none',
      count: SensorFrame._i(j['count']) ?? 0,
      us: SensorFrame._i(j['us']) ?? 0,
      score: ((j['score'] ?? 0) as num).toDouble(),
      thr: ((j['thr'] ?? 0) as num).toDouble(),
      anomaly: j['anomaly'] == true,
      cls: cls,
      prob: ((j['prob'] ?? 0) as num).toDouble(),
      label: j['label']?.toString() ?? '-',
      danger: j['danger'] == true || cls == kDangerClass,
      probs: (j['probs'] is List)
          ? (j['probs'] as List).map((e) => (e as num).toDouble()).toList()
          : const [],
    );
  }
}

class SensorFrame {
  final bool conn0;
  final bool conn1;
  final List<int> rR, rL, rB;
  final List<int> lR, lL, lB;
  final int? seq0, seq1;
  final int? nf0, bo0, nf1, bo1;
  // ── Dev3 / Dev4 (グラフ・ヒートマップ表示のみ、推論には使用しない) ──
  final bool conn2;
  final bool conn3;
  final List<int> d2R, d2L, d2B;
  final List<int> d3R, d3L, d3B;
  final int? seq2, seq3;
  final int? nf2, bo2, nf3, bo3;
  final bool inferReady;
  final double score; // fall クラスの確率
  final bool anomaly; // 予測クラスが fall か
  final String label;
  // ── 7クラス分類結果 ──
  final int predClass; // 0〜6 (-1: 未推論)
  final double prob; // 予測クラスの確率
  final List<double> probs; // 全5クラスの確率
  // ── nRF UART Dev1/Dev2 (設定画面で数値のみ表示) + ゲートウェイ推論 ──
  final NrfDevSnapshot nrf0;
  final NrfDevSnapshot nrf1;
  final NrfInferInfo nrfInfer;

  SensorFrame({
    required this.conn0,
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
    this.conn2 = false,
    this.conn3 = false,
    this.d2R = const [],
    this.d2L = const [],
    this.d2B = const [],
    this.d3R = const [],
    this.d3L = const [],
    this.d3B = const [],
    this.seq2,
    this.seq3,
    this.nf2,
    this.bo2,
    this.nf3,
    this.bo3,
    required this.inferReady,
    required this.score,
    required this.anomaly,
    required this.label,
    this.predClass = -1,
    this.prob = 0.0,
    this.probs = const [],
    this.nrf0 = const NrfDevSnapshot(),
    this.nrf1 = const NrfDevSnapshot(),
    this.nrfInfer = const NrfInferInfo(),
  });

  /// 5クラスの確率 (歩行/立位/座位/階段昇降/転倒)
  List<double> get groupProbs {
    final g = List<double>.filled(kGroupJa.length, 0.0);
    for (int i = 0; i < probs.length && i < kClassToGroup.length; i++) {
      g[kClassToGroup[i]] += probs[i];
    }
    return g;
  }

  /// 転倒スコア = danger クラスの確率
  double get fallGroupScore {
    if (probs.length <= kDangerClass) return score;
    return probs[kDangerClass].clamp(0.0, 1.0);
  }

  /// 5区分のうち最大確率のグループ (-1: 不明)
  int get groupIndex {
    if (probs.length < kClassToGroup.length) return -1;
    final g = groupProbs;
    int best = 0;
    for (int i = 1; i < g.length; i++) {
      if (g[i] > g[best]) best = i;
    }
    return best;
  }

  /// DANGER 判定: 最大確率のクラスが danger
  bool get isDanger {
    final gi = groupIndex;
    return gi < 0 ? anomaly : gi == kGroupFall;
  }

  static int? _i(dynamic v) => v == null ? null : (v as num).toInt();

  static List<int> _parseIntArray(dynamic v) {
    if (v == null) return [];
    if (v is List) return v.map((e) => (e as num).toInt()).toList();
    return [(v as num).toInt()];
  }

  factory SensorFrame.fromJson(Map<String, dynamic> j) {
    // ページ1 (M5): m0 / m1。nRF UART Dev1/2 は d0 / d1 (設定画面のみ)
    final d0 = (j['m0'] as Map<String, dynamic>?) ?? const {};
    final d1 = (j['m1'] as Map<String, dynamic>?) ?? const {};
    final n0 = (j['d0'] as Map<String, dynamic>?) ?? const {};
    final n1 = (j['d1'] as Map<String, dynamic>?) ?? const {};
    final nInf = (j['nrf_infer'] as Map<String, dynamic>?) ?? const {};
    final d2 = (j['d2'] as Map<String, dynamic>?) ?? const {};
    final d3 = (j['d3'] as Map<String, dynamic>?) ?? const {};
    final infer = (j['infer'] as Map<String, dynamic>?) ?? const {};
    return SensorFrame(
      conn0: d0['conn'] == true,
      conn1: d1['conn'] == true,
      rR: _parseIntArray(d0['R']),
      rL: _parseIntArray(d0['L']),
      rB: _parseIntArray(d0['B']),
      lR: _parseIntArray(d1['R']),
      lL: _parseIntArray(d1['L']),
      lB: _parseIntArray(d1['B']),
      seq0: _i(d0['seq']),
      seq1: _i(d1['seq']),
      nf0: _i(d0['nf']),
      bo0: _i(d0['bo']),
      nf1: _i(d1['nf']),
      bo1: _i(d1['bo']),
      conn2: d2['conn'] == true,
      conn3: d3['conn'] == true,
      d2R: _parseIntArray(d2['R']),
      d2L: _parseIntArray(d2['L']),
      d2B: _parseIntArray(d2['B']),
      d3R: _parseIntArray(d3['R']),
      d3L: _parseIntArray(d3['L']),
      d3B: _parseIntArray(d3['B']),
      seq2: _i(d2['seq']),
      seq3: _i(d3['seq']),
      nf2: _i(d2['nf']),
      bo2: _i(d2['bo']),
      nf3: _i(d3['nf']),
      bo3: _i(d3['bo']),
      nrf0: NrfDevSnapshot.fromJson(n0),
      nrf1: NrfDevSnapshot.fromJson(n1),
      nrfInfer: NrfInferInfo.fromJson(nInf),
      inferReady: infer['ready'] == true,
      score: (infer['score'] ?? 0).toDouble(),
      anomaly: infer['anomaly'] == true,
      label: infer['label']?.toString() ?? '-',
      predClass: _i(infer['class']) ?? -1,
      prob: ((infer['prob'] ?? 0) as num).toDouble(),
      probs: (infer['probs'] is List)
          ? (infer['probs'] as List).map((e) => (e as num).toDouble()).toList()
          : const [],
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

  HeatmapPoint copyWith({
    double? x,
    double? y,
    double? sigma,
    double? sigmaY,
    double? weightMul,
    Color? color,
    bool? visible,
  }) =>
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
List<HeatmapPoint> defaultHeatmapPoints() {
  const double sigmaYDev12 = 0.3;  // Dev1,2 用の縦倍率
  const double sigmaYDev34 = 0.45;  // Dev3,4 用の縦倍率

  return [
    // Dev1 右足 (画像左側に表示)
    HeatmapPoint(
        x: 0.65,
        y: 0.46,
        sigma: 0.27,
        sigmaY: sigmaYDev12,
        weightMul: 1.0,
        name: 'R_R (内前)',
        color: const Color(0xFFFF6B6B)),
    HeatmapPoint(
        x: 0.29,
        y: 0.46,
        sigma: 0.27,
        sigmaY: sigmaYDev12,
        weightMul: 1.0,
        name: 'R_L (外前)',
        color: const Color(0xFFFFA94D)),
    HeatmapPoint(
        x: 0.47,
        y: 0.68,
        sigma: 0.27,
        sigmaY: sigmaYDev12,
        weightMul: 1.0,
        name: 'R_B (踵)',
        color: const Color(0xFFFFD43B)),
    // Dev2 左足 (画像右側に表示)
    HeatmapPoint(
        x: 0.69,
        y: 0.46,
        sigma: 0.27,
        sigmaY: sigmaYDev12,
        weightMul: 1.0,
        name: 'L_R (外前)',
        color: const Color(0xFF4ECDC4)),
    HeatmapPoint(
        x: 0.32,
        y: 0.46,
        sigma: 0.27,
        sigmaY: sigmaYDev12,
        weightMul: 1.0,
        name: 'L_L (内前)',
        color: const Color(0xFF45B7D1)),
    HeatmapPoint(
        x: 0.51,
        y: 0.68,
        sigma: 0.27,
        sigmaY: sigmaYDev12,
        weightMul: 1.0,
        name: 'L_B (踵)',
        color: const Color(0xFFA88BFA)),
    // Dev3 (画像左側に表示)
    HeatmapPoint(
        x: 0.65,
        y: 0.41,
        sigma: 0.27,
        sigmaY: sigmaYDev34,
        weightMul: 1.0,
        name: 'D3_R',
        color: const Color(0xFFFF6B6B)),
    HeatmapPoint(
        x: 0.29,
        y: 0.41,
        sigma: 0.27,
        sigmaY: sigmaYDev34,
        weightMul: 1.0,
        name: 'D3_L',
        color: const Color(0xFFFFA94D)),
    HeatmapPoint(
        x: 0.47,
        y: 0.82,
        sigma: 0.27,
        sigmaY: sigmaYDev34,
        weightMul: 1.0,
        name: 'D3_B (踵)',
        color: const Color(0xFFFFD43B)),
    // Dev4 (画像右側に表示)
    HeatmapPoint(
        x: 0.69,
        y: 0.41,
        sigma: 0.27,
        sigmaY: sigmaYDev34,
        weightMul: 1.0,
        name: 'D4_R',
        color: const Color(0xFF4ECDC4)),
    HeatmapPoint(
        x: 0.32,
        y: 0.41,
        sigma: 0.27,
        sigmaY: sigmaYDev34,
        weightMul: 1.0,
        name: 'D4_L',
        color: const Color(0xFF45B7D1)),
    HeatmapPoint(
        x: 0.51,
        y: 0.82,
        sigma: 0.27,
        sigmaY: sigmaYDev34,
        weightMul: 1.0,
        name: 'D4_B (踵)',
        color: const Color(0xFFA88BFA)),
  ];
}
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
    const step = 5;
    final cellPaint = Paint()..style = PaintingStyle.fill;   // 毎セル生成せず使い回す
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
            -((dx * dx) / (2 * sigmaX * sigmaX) +
                (dy * dy) / (2 * sigmaY * sigmaY)),
          );
          intensity += v * gauss;
        }
        intensity = intensity.clamp(0.0, 1.0);
        if (intensity < 0.01) continue;

        cellPaint.color = _intensityColor(intensity, baseColor);
        canvas.drawRect(
          Rect.fromLTWH(
              px - step / 2, py - step / 2, step.toDouble(), step.toDouble()),
          cellPaint,
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
  bool shouldRepaint(FootHeatmapPainter old) {
    // 参照が毎フレーム変わる List でも、内容が同じなら再描画をスキップする
    if (old.baseColor != baseColor) return true;
    if (old.values.length != values.length) return true;
    if (old.points.length != points.length) return true;
    for (int i = 0; i < values.length; i++) {
      if (old.values[i] != values[i]) return true;
    }
    for (int i = 0; i < points.length; i++) {
      final a = old.points[i];
      final b = points[i];
      if (a.x != b.x ||
          a.y != b.y ||
          a.sigma != b.sigma ||
          a.sigmaY != b.sigmaY ||
          a.weightMul != b.weightMul ||
          a.visible != b.visible ||
          a.color != b.color) {
        return true;
      }
    }
    return false;
  }
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
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
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
                          child:
                              _SensorDot(color: p.color, value: v, name: p.name),
                        );
                      }),
                    // 未接続オーバーレイ
                    if (!connected)
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: Text('未接続',
                              style:
                                  TextStyle(color: Colors.white38, fontSize: 12)),
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
          Rect.fromCenter(center: Offset(tx, ty), width: w * 0.09, height: h * 0.10),
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
  AudioPlayer? _player;
  bool _isPlaying = false;

  Future<void> init() async {
    try {
      _player = AudioPlayer();
      await _player!.setReleaseMode(ReleaseMode.loop);
    } catch (e) {
      debugPrint('AlarmSoundController init error: $e');
      _player = null;
    }
  }

  Future<void> startAlarm() async {
    if (_isPlaying) return;
    final player = _player;
    if (player == null) {
      debugPrint('AlarmSoundController startAlarm skipped: player not ready');
      return;
    }
    _isPlaying = true;
    try {
      await player.play(AssetSource('alarm.wav'));
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

// ================================================================
// NfBoStatusWidget
// ================================================================
class NfBoStatusWidget extends StatefulWidget {
  final String label;
  final int? nf;
  final int? bo;
  const NfBoStatusWidget(
      {super.key, required this.label, required this.nf, required this.bo});

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
  const AnomalyHistoryWidget(
      {super.key, required this.sessions, required this.monitoringStart});

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
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                  child: Text('転倒履歴: ${sessions.length}回',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10,
                          height: 1.0,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
                GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    child: const Icon(Icons.close, size: 10, color: Colors.white)),
              ]),
              const SizedBox(height: 16),
              if (totalMs > 0) ...[
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(_fmt(rangeStart),
                      style: const TextStyle(fontSize: 9, color: Colors.white)),
                  Text(_fmt(now),
                      style: const TextStyle(fontSize: 9, color: Colors.white)),
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
                            left: ((s.start.difference(rangeStart).inMilliseconds /
                                        totalMs) *
                                    bw)
                                .clamp(0.0, bw),
                            child: Container(
                              width: ((s.end.difference(s.start).inMilliseconds /
                                          totalMs) *
                                      bw)
                                  .clamp(1.0, bw),
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
                  child: Center(
                      child: Text('転倒なし',
                          style: TextStyle(color: Color(0xFF00C853), fontSize: 13))),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    child: Column(
                      children: sessions.reversed
                          .map((s) => Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF4444).withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                      color: const Color(0xFFFF4444).withOpacity(0.25)),
                                ),
                                child: Row(children: [
                                  Container(
                                      width: 7,
                                      height: 7,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: const BoxDecoration(
                                          color: Color(0xFFFF4444), shape: BoxShape.circle)),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                        Text('${_fmt(s.start)}  ～  ${_fmt(s.end)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.white70,
                                                fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 2),
                                        Text('継続時間: ${_dur(s.duration)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 10, color: Colors.white38)),
                                      ])),
                                ]),
                              ))
                          .toList(),
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
            Text('転倒履歴',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    height: 1.0,
                    color: (count > 0 ? const Color(0xFFFF4444) : Colors.white),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8)),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(count > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  size: 15,
                  color: count > 0 ? const Color(0xFFFF4444) : const Color(0xFF00C853)),
              const SizedBox(width: 4),
              Flexible(
                child: Text('$count 回',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        height: 1.0,
                        fontWeight: FontWeight.bold,
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
                  style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
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
// ================================================================
// NrfLive: nRF Dev1/Dev2 の最新値 (設定画面の数値表示用)
// ================================================================
class NrfLive {
  final List<bool> conn = [false, false];
  final List<int?> seq = [null, null];
  final List<int?> nf = [null, null];
  final List<int?> bo = [null, null];
  final List<int?> r = [null, null];
  final List<int?> l = [null, null];
  final List<int?> b = [null, null];
  NrfInferInfo infer = const NrfInferInfo();
  DateTime? lastRx;

  void update(SensorFrame f) {
    final devs = [f.nrf0, f.nrf1];
    for (int i = 0; i < 2; i++) {
      final d = devs[i];
      conn[i] = d.conn;
      if (d.seq != null) seq[i] = d.seq;
      if (d.nf != null) nf[i] = d.nf;
      if (d.bo != null) bo[i] = d.bo;
      if (d.r.isNotEmpty) r[i] = d.r.last;
      if (d.l.isNotEmpty) l[i] = d.l.last;
      if (d.b.isNotEmpty) b[i] = d.b.last;
    }
    infer = f.nrfInfer;
    lastRx = DateTime.now();
  }
}

// ================================================================
// NrfAlertNotifier: スマホ通知 (flutter_local_notifications)
// ================================================================
class NrfAlertNotifier {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: darwin, macOS: darwin),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      // Web / 未対応プラットフォームでは通知なしで継続
      debugPrint('NrfAlertNotifier init error: $e');
      _ready = false;
    }
  }

  Future<void> show(String title, String body) async {
    if (!_ready) return;
    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'nrf_abnormal',
          'nRF 異常検知',
          channelDescription: 'nRF Dev1/Dev2 の推論異常通知',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
            presentAlert: true, presentSound: true, presentBadge: true),
        macOS: DarwinNotificationDetails(
            presentAlert: true, presentSound: true, presentBadge: true),
      );
      await _plugin.show(1001, title, body, details);
    } catch (e) {
      debugPrint('NrfAlertNotifier show error: $e');
    }
  }
}

class AppSettings {
  final String wsUrl;
  final double stdThreshold;
  final int stdWindowSize;
  final bool alarmEnabled;
  final bool nrfNotifyEnabled;
  final bool? connectAction;
  final List<HeatmapPoint> heatmapPoints;

  const AppSettings({
    required this.wsUrl,
    required this.stdThreshold,
    required this.stdWindowSize,
    required this.alarmEnabled,
    required this.heatmapPoints,
    this.nrfNotifyEnabled = true,
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
        child:
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: color,
          inactiveColor: Colors.white10,
          onChanged: onChanged,
        ),
      ),
      SizedBox(
        width: 40,
        child: Text(value.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: TextStyle(
                color: color,
                fontSize: 11,
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
            style:
                TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_points),
            child: const Text('保存',
                style: TextStyle(
                    color: Color(0xFF58A6FF), fontWeight: FontWeight.bold)),
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
                _slider(
                  '縦倍率',
                  p.sigmaY,
                  0.1,
                  3.0,
                  58,
                  (v) => setState(() => _points[idx] = p.copyWith(sigmaY: v)),
                  p.color,
                ),
                _slider('強度倍率', p.weightMul, 0.0, 2.0, 40,
                    (v) => setState(() => _points[idx] = p.copyWith(weightMul: v)),
                    p.color),
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
  final bool initialNrfNotifyEnabled;
  final NrfLive nrfLive;
  final Listenable nrfListenable;

  const SettingsPage({
    super.key,
    required this.initialUrl,
    required this.initialThreshold,
    required this.initialWindowSize,
    required this.initialAlarmEnabled,
    required this.isConnected,
    required this.heatmapPoints,
    required this.initialNrfNotifyEnabled,
    required this.nrfLive,
    required this.nrfListenable,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _urlController;
  late double _threshold;
  late int _windowSize;
  late bool _alarmEnabled;
  late bool _nrfNotify;
  late List<HeatmapPoint> _heatmapPoints;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
    _threshold = widget.initialThreshold;
    _windowSize = widget.initialWindowSize;
    _alarmEnabled = widget.initialAlarmEnabled;
    _nrfNotify = widget.initialNrfNotifyEnabled;
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
        nrfNotifyEnabled: _nrfNotify,
        connectAction: connectAction,
      );

  void _save() => Navigator.of(context).pop(_buildSettings());
  void _connect() => Navigator.of(context).pop(_buildSettings(connectAction: true));
  void _disconnect() => Navigator.of(context).pop(_buildSettings(connectAction: false));

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFF58A6FF),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8)),
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

  Widget _kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text(v,
              style: TextStyle(
                  color: color ?? Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      );

  String _raw(int? v) => v == null ? '-' : '$v';
  String _volt(int? v) =>
      v == null ? '-' : '${(v / 8388607.0 * 3.3).toStringAsFixed(3)} V';

  Widget _nrfDevCard(String name, int i, NrfLive d) {
    final conn = d.conn[i];
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(conn ? Icons.circle : Icons.circle_outlined,
              size: 10, color: conn ? Colors.greenAccent : Colors.redAccent),
          const SizedBox(width: 6),
          Text(name,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Text(conn ? '接続中' : '未接続',
              style: TextStyle(
                  fontSize: 11,
                  color: conn ? Colors.greenAccent : Colors.redAccent)),
        ]),
        const SizedBox(height: 6),
        _kv('seq', _raw(d.seq[i])),
        _kv('Notify Fail (nf)', _raw(d.nf[i])),
        _kv('Buffer Overflow (bo)', _raw(d.bo[i])),
        const Divider(color: Colors.white10, height: 12),
        _kv('R (raw)', _raw(d.r[i])),
        _kv('R (電圧)', _volt(d.r[i])),
        _kv('L (raw)', _raw(d.l[i])),
        _kv('L (電圧)', _volt(d.l[i])),
        _kv('B (raw)', _raw(d.b[i])),
        _kv('B (電圧)', _volt(d.b[i])),
      ]),
    );
  }

  Widget _nrfInferCard(NrfLive d) {
    final inf = d.infer;
    final abn = inf.abnormal;
    final c = !inf.ready
        ? Colors.white38
        : (abn ? const Color(0xFFFF4444) : const Color(0xFF00C853));
    String status;
    if (!inf.ready) {
      status = '推論待機中';
    } else {
      status = abn ? '異常' : '正常';
    }
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(abn ? Icons.warning_amber_rounded : Icons.check_circle_outline,
              size: 16, color: c),
          const SizedBox(width: 6),
          Text('Dev1+Dev2 推論: $status',
              style: TextStyle(
                  color: c, fontSize: 13, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        _kv('モード', inf.mode),
        _kv('ラベル', inf.label),
        if (inf.mode == 'anomaly') ...[
          _kv('スコア', inf.score.toStringAsFixed(4)),
          _kv('しきい値', inf.thr.toStringAsFixed(4)),
        ],
        if (inf.mode == 'class') ...[
          _kv('確信度', '${(inf.prob * 100).toStringAsFixed(1)} %'),
          if (inf.probs.length == kClassJa.length)
            for (int k = 0; k < kClassJa.length; k++)
              _kv(kClassJa[k], '${(inf.probs[k] * 100).toStringAsFixed(1)} %',
                  color: k == inf.cls ? kClassColors[k] : Colors.white54),
        ],
        _kv('推論回数', '${inf.count}'),
        _kv('推論時間', '${inf.us} us'),
      ]),
    );
  }

  Widget _nrfSection() {
    return AnimatedBuilder(
      animation: widget.nrfListenable,
      builder: (_, __) {
        final d = widget.nrfLive;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _nrfDevCard('nRF UART Dev1', 0, d),
          const SizedBox(height: 8),
          _nrfDevCard('nRF UART Dev2', 1, d),
          const SizedBox(height: 8),
          _nrfInferCard(d),
        ]);
      },
    );
  }

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
                style: TextStyle(
                    color: Color(0xFF58A6FF), fontWeight: FontWeight.bold)),
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
                    filled: true,
                    fillColor: const Color(0xFF0D1117),
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
                      style: const TextStyle(
                          color: Color(0xFF58A6FF), fontWeight: FontWeight.bold)),
                ]),
                Slider(
                  value: _threshold,
                  min: 0.01,
                  max: 1.0,
                  divisions: 99,
                  activeColor: const Color(0xFF58A6FF),
                  inactiveColor: Colors.white10,
                  onChanged: (v) => setState(() => _threshold = v),
                ),
                const SizedBox(height: 4),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('判定ウィンドウ（サンプル数）',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text('$_windowSize',
                      style: const TextStyle(
                          color: Color(0xFF58A6FF), fontWeight: FontWeight.bold)),
                ]),
                Slider(
                  value: _windowSize.toDouble(),
                  min: 20,
                  max: 600,
                  divisions: 58,
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
              title: const Text('転倒検知時にアラーム音を再生',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              value: _alarmEnabled,
              activeColor: const Color(0xFF58A6FF),
              onChanged: (v) => setState(() => _alarmEnabled = v),
            ),
          ),
          _sectionTitle('nRF UART Dev1 / Dev2 (数値確認・異常通知)'),
          _card(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dev1+Dev2 の推論が異常のときスマホ通知',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              value: _nrfNotify,
              activeColor: const Color(0xFF58A6FF),
              onChanged: (v) => setState(() => _nrfNotify = v),
            ),
          ),
          const SizedBox(height: 8),
          _nrfSection(),
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

  static const List<String> _chLabels = [
    '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12',
  ];
  static const List<Color> _chColors = [
    Color(0xFFFF6B6B), Color(0xFFFFA94D), Color(0xFFFFD43B),
    Color(0xFF4ECDC4), Color(0xFF45B7D1), Color(0xFFA88BFA),
    Color(0xFFFF6B6B), Color(0xFFFFA94D), Color(0xFFFFD43B),
    Color(0xFF4ECDC4), Color(0xFF45B7D1), Color(0xFFA88BFA),
  ];

  int _stdWindowSize = 100;
  double _stdThreshold = 0.1;
  static const int _sampleIntervalMs = 16;

  WebSocketChannel? _channel;
  bool _connected = false;
  String _status = '未接続';
  SensorFrame? _latest;
  StreamSubscription? _wsSub;
  Timer? _reconnectTimer;
  bool _manualDisconnect = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectDelayMs = 10000;
  bool _dataReceivedSinceConnect = false;

  Timer? _uiThrottleTimer;
  bool _pendingUiUpdate = false;

  // ── ちらつき防止: 表示用の前回値を保持 ────────────────────────
  int? _dispSeq0;
  int? _dispSeq1;
  int? _dispNf0;
  int? _dispBo0;
  int? _dispNf1;
  int? _dispBo1;

  int? _dispSeq2;
  int? _dispSeq3;
  int? _dispNf2;
  int? _dispBo2;
  int? _dispNf3;
  int? _dispBo3;

  int? _lastSeq0;
  int? _lastSeq1;
  int? _lastSeq2;
  int? _lastSeq3;

  // ch0-2: Dev1, ch3-5: Dev2, ch6-8: Dev3, ch9-11: Dev4
  final List<List<FlSpot>> _series = List.generate(12, (_) => []);
  final List<double> _lastValue = List.filled(12, 0.0);
  int _tick = 0;

  // ページ切り替え (0: Dev1,2 画面 / 1: Dev3,4 画面)
  final PageController _pageController = PageController();
  double _dragAccum = 0;
  bool _dragTriggered = false;
  int _currentPage = 0;

  final _urlController = TextEditingController(text: _defaultWsUrl);

  DateTime? _monitoringStart;
  final List<AnomalySession> _anomalySessions = [];
  AnomalySession? _currentAnomalySession;
  DateTime? _lastAnomalyTime;

  final AlarmSoundController _alarm = AlarmSoundController();

  // ── 再生(プレイアウト)バッファ ───────────────────────────────
  // 1パケット(16サンプル=256ms分)がまとめて届くため、そのまま描画するとグラフ・ヒートマップが
  // 256msごとにカクつく。受信サンプルをグループ別のキューに溜め、62.5Hz(16ms)で1サンプルずつ消費する。
  //   グループ: 0=M5 Dev1(ch0-2) 1=M5 Dev2(ch3-5) 2=nRF Dev3(ch6-8) 3=nRF Dev4(ch9-11)
  static const int _playPrime = 16;    // この数たまってから再生開始 (約256ms遅延で揺らぎを吸収)
  static const int _playCatchup = 48;  // これ以上溜まったら1サンプル余分に進めて遅延を詰める
  static const int _playMax = 96;      // 上限 (超えたら古いものを捨てる)
  final List<Queue<List<double>>> _playQ = List.generate(4, (_) => Queue<List<double>>());
  final List<bool> _playPrimed = List.filled(4, false);
  Timer? _playTimer;
  int _playLastMs = 0;

  // ── nRF UART Dev1/Dev2 (設定画面で数値確認) + 異常通知 ──
  final NrfLive _nrfLive = NrfLive();
  final ValueNotifier<int> _nrfTick = ValueNotifier<int>(0);
  final NrfAlertNotifier _notifier = NrfAlertNotifier();
  bool _nrfNotifyEnabled = true;
  DateTime? _lastNrfNotify;
  static const int _nrfNotifyIntervalSec = 30; // 異常継続中の再通知間隔
  bool _alarmPlaying = false;
  bool _alarmEnabled = true;

  final List<List<double>> _stdBuffer = List.generate(12, (_) => []);
  int _stationaryMs = 0;
  int _movementMs = 0;

  // ヒートマップ設定
  List<HeatmapPoint> _heatmapPoints = defaultHeatmapPoints();
  
  // ── 歩数・ケイデンス ─────────────────────────────────────────
  // 立ち上がりエッジ（しきい値を下から上に超えた瞬間）を1歩として検出し、
  // 直前の立ち上がりエッジからのサンプル間隔でケイデンスを算出する。
  static const double _stepThreshold = 0.35;
  static const int _cadenceTimeoutSamples = 313;
  static const int _cadenceMaxSpm = 180;

  int _stepCountR = 0;
  bool _stepAboveR = false;
  int? _lastStepTickR;
  int? _cadenceR;
  int _cadenceBelowCountR = 0;

  int _stepCountL = 0;
  bool _stepAboveL = false;
  int? _lastStepTickL;
  int? _cadenceL;
  int _cadenceBelowCountL = 0;

  void _updateStepCounts(int s, List<bool> validThisSample) {
    if (validThisSample[2]) {
      final valR = _lastValue[2];
      final isAboveR = valR > _stepThreshold;
      if (isAboveR && !_stepAboveR) {
        // 立ち上がりエッジ = 1歩
        _stepCountR++;
        if (_lastStepTickR != null) {
          final interval = _tick - _lastStepTickR!;
          if (interval > 0) {
            final cad = (60.0 / (interval * 0.016)).round();
            if (cad < _cadenceMaxSpm) {
              _cadenceR = cad;
            }
          }
        }
        _lastStepTickR = _tick;
        _cadenceBelowCountR = 0;
      } else if (!isAboveR) {
        _cadenceBelowCountR++;
        if (_cadenceBelowCountR >= _cadenceTimeoutSamples) {
          _cadenceR = null;
        }
      }
      _stepAboveR = isAboveR;
    }
    if (validThisSample[5]) {
      final valL = _lastValue[5];
      final isAboveL = valL > _stepThreshold;
      if (isAboveL && !_stepAboveL) {
        _stepCountL++;
        if (_lastStepTickL != null) {
          final interval = _tick - _lastStepTickL!;
          if (interval > 0) {
            final cad = (60.0 / (interval * 0.016)).round();
            if (cad < _cadenceMaxSpm) {
              _cadenceL = cad;
            }
          }
        }
        _lastStepTickL = _tick;
        _cadenceBelowCountL = 0;
      } else if (!isAboveL) {
        _cadenceBelowCountL++;
        if (_cadenceBelowCountL >= _cadenceTimeoutSamples) {
          _cadenceL = null;
        }
      }
      _stepAboveL = isAboveL;
    }
  }

  @override
  void initState() {
    super.initState();
    _alarm.init();
    _notifier.init();
    _playLastMs = DateTime.now().millisecondsSinceEpoch;
    _playTimer = Timer.periodic(const Duration(milliseconds: 8), (_) => _playoutTick());
    _uiThrottleTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {   // 画面更新は約12Hz(サンプル消費は16msごとのまま)
      if (_pendingUiUpdate && mounted) {
        _pendingUiUpdate = false;
        setState(() {});
      }
    });
  }

  // フィールドに追加
DateTime? _lastMotionUpdateTime;

double _calcStd(List<double> data) {
  final n = data.length;
  if (n == 0) return 0.0;
  final mean = data.reduce((a, b) => a + b) / n;
  final variance =
      data.fold(0.0, (sum, v) => sum + (v - mean) * (v - mean)) / n;
  return sqrt(variance);
}

void _updateMotionState() {
  final now = DateTime.now();
  final bothConnected = (_latest?.conn0 ?? false) && (_latest?.conn1 ?? false);

  if (!bothConnected) {
    _lastMotionUpdateTime = null; // 次回接続時にリセット
    return;
  }

  final last = _lastMotionUpdateTime;
  _lastMotionUpdateTime = now;
  if (last == null) return; // 初回は経過時間を計算できない

  final elapsedMs = now.difference(last).inMilliseconds;
  // 通信断・バックグラウンド化などで異常に大きい間隔になった場合は積算しない
  if (elapsedMs <= 0 || elapsedMs > 2000) return;

  final targetBuffers = _stdBuffer.sublist(0, 6);
  if (targetBuffers.any((b) => b.length < _stdWindowSize)) return;

  final allStationary = targetBuffers.every((b) => _calcStd(b) <= _stdThreshold);
  if (allStationary) {
    _stationaryMs += elapsedMs;
  } else {
    _movementMs += elapsedMs;
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
          if (_anomalySessions.length > 200) _anomalySessions.removeAt(0);
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
          if (_anomalySessions.length > 200) _anomalySessions.removeAt(0);
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
    _manualDisconnect = false;
    _reconnectTimer?.cancel();

    _wsSub?.cancel();
    _wsSub = null;
    _channel?.sink.close();
    _channel = null;

    final url = _urlController.text.trim();
    _monitoringStart ??= DateTime.now();
    for (final b in _stdBuffer) b.clear();

    // 切断されていたチャンネルの値が固まって std バッファ等を汚染しないよう、
    // 再接続時に前回値と歩数検出の状態をリセットする。
    for (int ch = 0; ch < 12; ch++) {
      _lastValue[ch] = 0.0;
    }
    _stepAboveR = false;
    _stepAboveL = false;
    _lastStepTickR = null;
    _lastStepTickL = null;

    for (final q in _playQ) {
      q.clear();
    }
    for (int g = 0; g < 4; g++) {
      _playPrimed[g] = false;
    }

    _dataReceivedSinceConnect = false;

    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      setState(() {
        _connected = true;
        _status = '接続試行中...';
      });

      _wsSub = channel.stream.listen(
        (msg) {
          if (!_dataReceivedSinceConnect) {
            _dataReceivedSinceConnect = true;
            // 実際にデータを受信できた時点で再接続バックオフをリセットする
            _reconnectAttempts = 0;
            if (mounted) {
              setState(() => _status = '接続中');
            } else {
              _status = '接続中';
            }
          }
          Map<String, dynamic> raw;
          try {
            raw = jsonDecode(msg as String) as Map<String, dynamic>;
          } catch (_) {
            return;
          }
          _pushFrame(SensorFrame.fromJson(raw));
        },
        onError: (_) => _handleDisconnect('接続エラー'),
        onDone: () => _handleDisconnect('切断されました'),
        cancelOnError: true,
      );
    } catch (e) {
      _handleDisconnect('エラー: $e');
    }
  }

  void _handleDisconnect(String status) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _connected = false;
    });
    _wsSub?.cancel();
    _wsSub = null;
    _channel = null;

    if (_manualDisconnect) return;

    final delayMs = min(1000 * (1 << min(_reconnectAttempts, 4)), _maxReconnectDelayMs);
    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted || _manualDisconnect) return;
      setState(() => _status = '再接続中... (${_reconnectAttempts}回目)');
      _connect();
    });
  }

  // 16ms(62.5Hz)ごとに各グループから1サンプルずつ取り出して反映する
  void _playoutTick() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    int due = (nowMs - _playLastMs) ~/ 16;
    if (due <= 0) return;
    if (due > 4) {            // バックグラウンド復帰などで大きく遅れたら追いかけず仕切り直す
      due = 1;
      _playLastMs = nowMs;
    } else {
      _playLastMs += due * 16;
    }
    for (int k = 0; k < due; k++) {
      _playOneSample();
    }
  }

  void _playOneSample() {
    final valid = List<bool>.filled(12, false);
    bool any = false;
    for (int g = 0; g < 4; g++) {
      final q = _playQ[g];
      if (!_playPrimed[g]) {
        if (q.length >= _playPrime) {
          _playPrimed[g] = true;
        } else {
          continue;
        }
      }
      if (q.isEmpty) {        // 枯渇したら再度ためてから再生 (途切れ防止)
        _playPrimed[g] = false;
        continue;
      }
      if (q.length > _playCatchup) q.removeFirst();   // 溜まりすぎ → 遅延を詰める
      final v = q.removeFirst();
      for (int c = 0; c < 3; c++) {
        final ch = g * 3 + c;
        _lastValue[ch] = v[c];
        valid[ch] = true;
        _series[ch].add(FlSpot(_tick.toDouble(), v[c]));
        if (_series[ch].length > maxPoints) _series[ch].removeAt(0);
        _stdBuffer[ch].add(v[c]);
        if (_stdBuffer[ch].length > _stdWindowSize) _stdBuffer[ch].removeAt(0);
      }
      any = true;
    }
    if (!any) return;
    _updateStepCounts(0, valid);
    _tick++;
    _pendingUiUpdate = true;
  }

  void _handleNrf(SensorFrame frame) {
    _nrfLive.update(frame);
    _nrfTick.value++;
    if (!_nrfNotifyEnabled) return;
    if (!frame.nrfInfer.abnormal) return;
    final now = DateTime.now();
    final last = _lastNrfNotify;
    if (last != null && now.difference(last).inSeconds < _nrfNotifyIntervalSec) {
      return;
    }
    _lastNrfNotify = now;
    final inf = frame.nrfInfer;
    final detail = inf.mode == 'class'
        ? '${inf.label} (${(inf.prob * 100).toStringAsFixed(1)}%)'
        : 'ANOMALY (score ${inf.score.toStringAsFixed(3)})';
    _notifier.show('nRF Dev1/Dev2 異常検知', detail);
  }

  void _pushFrame(SensorFrame frame) {
    // nRF Dev1/2 は新しいサンプルの有無に関わらず常に最新値と推論結果を反映
    _handleNrf(frame);
    final seq0Changed = frame.seq0 != null && frame.seq0 != _lastSeq0;
    final seq1Changed = frame.seq1 != null && frame.seq1 != _lastSeq1;
    final seq2Changed = frame.seq2 != null && frame.seq2 != _lastSeq2;
    final seq3Changed = frame.seq3 != null && frame.seq3 != _lastSeq3;
    if (!seq0Changed && !seq1Changed && !seq2Changed && !seq3Changed) return;
    _lastSeq0 = frame.seq0;
    _lastSeq1 = frame.seq1;
    _lastSeq2 = frame.seq2;
    _lastSeq3 = frame.seq3;

     final rawArrays = <List<int>?>[
      (frame.conn0 && seq0Changed) ? frame.rR : null,
      (frame.conn0 && seq0Changed) ? frame.rL : null,
      (frame.conn0 && seq0Changed) ? frame.rB : null,
      (frame.conn1 && seq1Changed) ? frame.lR : null,
      (frame.conn1 && seq1Changed) ? frame.lL : null,
      (frame.conn1 && seq1Changed) ? frame.lB : null,
      (frame.conn2 && seq2Changed) ? frame.d2R : null,
      (frame.conn2 && seq2Changed) ? frame.d2L : null,
      (frame.conn2 && seq2Changed) ? frame.d2B : null,
      (frame.conn3 && seq3Changed) ? frame.d3R : null,
      (frame.conn3 && seq3Changed) ? frame.d3L : null,
      (frame.conn3 && seq3Changed) ? frame.d3B : null,
    ];

    final sampleCount = rawArrays.whereType<List<int>>().fold(0, (mx, a) => max(mx, a.length));
    if (sampleCount == 0) return;

    _latest = frame;

    if (frame.seq0 != null) _dispSeq0 = frame.seq0;
    if (frame.seq1 != null) _dispSeq1 = frame.seq1;
    if (frame.nf0 != null) _dispNf0 = frame.nf0;
    if (frame.bo0 != null) _dispBo0 = frame.bo0;
    if (frame.nf1 != null) _dispNf1 = frame.nf1;
    if (frame.bo1 != null) _dispBo1 = frame.bo1;

    if (frame.seq2 != null) _dispSeq2 = frame.seq2;
    if (frame.seq3 != null) _dispSeq3 = frame.seq3;
    if (frame.nf2 != null) _dispNf2 = frame.nf2;
    if (frame.bo2 != null) _dispBo2 = frame.bo2;
    if (frame.nf3 != null) _dispNf3 = frame.nf3;
    if (frame.bo3 != null) _dispBo3 = frame.bo3;

    if (frame.inferReady) _updateAnomalyHistory(frame.isDanger);

    // 受信サンプルを再生キューへ積む (描画・統計は _playoutTick が16msごとに1サンプルずつ消費)
    for (int g = 0; g < 4; g++) {
      final ra = rawArrays[g * 3];
      final rb = rawArrays[g * 3 + 1];
      final rc = rawArrays[g * 3 + 2];
      if (ra == null || rb == null || rc == null) continue;
      final n = min(ra.length, min(rb.length, rc.length));
      for (int i = 0; i < n; i++) {
        _playQ[g].add([ra[i] / _adcFullScale, rb[i] / _adcFullScale, rc[i] / _adcFullScale]);
      }
      while (_playQ[g].length > _playMax) {
        _playQ[g].removeFirst();
      }
    }

    // Dev1/Dev2 (ch0〜5) に新しいサンプルが1つでもあった場合のみ、
    // フレーム単位で1回、壁時計ベースの経過時間を加算する
    if (seq0Changed || seq1Changed) {
      _updateMotionState();
    }

    _pendingUiUpdate = true;
  }

  void _disconnect() {
    _manualDisconnect = true;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _wsSub?.cancel();
    _wsSub = null;
    _channel?.sink.close();
    _channel = null;
    _alarm.stopAlarm();
    _alarmPlaying = false;
    setState(() {
      _connected = false;
      _status = '未接続';
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
        _lastStepTickR = null;
        _cadenceR = null;
        _cadenceBelowCountR = 0;
        _stepCountL = 0;
        _stepAboveL = false;
        _lastStepTickL = null;
        _cadenceL = null;
        _cadenceBelowCountL = 0;
      });

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<AppSettings>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          initialUrl: _urlController.text,
          initialThreshold: _stdThreshold,
          initialWindowSize: _stdWindowSize,
          initialAlarmEnabled: _alarmEnabled,
          initialNrfNotifyEnabled: _nrfNotifyEnabled,
          nrfLive: _nrfLive,
          nrfListenable: _nrfTick,
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
      _nrfNotifyEnabled = result.nrfNotifyEnabled;
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
    _uiThrottleTimer?.cancel();
    _reconnectTimer?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close();
    _urlController.dispose();
    _alarm.dispose();
    _playTimer?.cancel();
    _nrfTick.dispose();
    _pageController.dispose();
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
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                if (_dragTriggered) return;
                _dragAccum += details.delta.dx;
                const threshold = 30.0; // ← この数値を小さくするほど軽い力で反応する
                if (_dragAccum < -threshold && _currentPage < 1) {
                  _dragTriggered = true;
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
                } else if (_dragAccum > threshold && _currentPage > 0) {
                  _dragTriggered = true;
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
                }
              },
              onHorizontalDragEnd: (_) {
                _dragAccum = 0;
                _dragTriggered = false;
              },
              onHorizontalDragCancel: () {
                _dragAccum = 0;
                _dragTriggered = false;
              },
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  // ══════════════ ページ1: M5 Dev1,2 (m0,m1 + M5推論) ══════════════
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      // デバイス接続状態チップ (ちらつき防止: _disp* 変数を使用)
                      Row(children: [
                        _deviceChip('M5 Dev1 (左足)', frame?.conn0 ?? false, _dispSeq0, _dispNf0, _dispBo0),
                        const SizedBox(width: 8),
                        _deviceChip('M5 Dev2 (右足)', frame?.conn1 ?? false, _dispSeq1, _dispNf1, _dispBo1),
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
                                      Expanded(
                                          child: NfBoStatusWidget(
                                              label: 'M5 Dev1 左足', nf: _dispNf0, bo: _dispBo0)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                          child: NfBoStatusWidget(
                                              label: 'M5 Dev2 右足', nf: _dispNf1, bo: _dispBo1)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                          child: AnomalyHistoryWidget(
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
                                          label: 'ケイデンス 左',
                                          value: _cadenceL != null ? '$_cadenceL spm' : '-',
                                          color: const Color(0xFFA88BFA),
                                        ),
                                        const SizedBox(width: 6),
                                        MiniStatCard(
                                          icon: Icons.speed,
                                          label: 'ケイデンス 右',
                                          value: _cadenceR != null ? '$_cadenceR spm' : '-',
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
                                                        color: Colors.white,
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600,
                                                        letterSpacing: 0.6)),
                                                const SizedBox(height: 6),
                                                Expanded(
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: FootHeatmapView(
                                                          values: [
                                                            _lastValue[3],
                                                            _lastValue[4],
                                                            _lastValue[5],
                                                          ],
                                                          points: _heatmapPoints.sublist(0, 3),
                                                          label: 'Dev1 左足',
                                                          connected: frame?.conn1 ?? false,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: FootHeatmapView(
                                                          values: [
                                                            _lastValue[0],
                                                            _lastValue[1],
                                                            _lastValue[2],
                                                          ],
                                                          points: _heatmapPoints.sublist(3, 6),
                                                          label: 'Dev2 右足',
                                                          connected: frame?.conn0 ?? false,
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
                  // ══════════════ ページ2: nRF UART Dev3,4 (d2,d3: グラフ + 圧力分布) ══════════════
                  _buildDev34Page(frame),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════ Dev3,4 用画面: グラフと圧力分布のみ ══════════════
  Widget _buildDev34Page(SensorFrame? frame) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          _deviceChip('nRF Dev3', frame?.conn2 ?? false, _dispSeq2, _dispNf2, _dispBo2),
          const SizedBox(width: 8),
          _deviceChip('nRF Dev4', frame?.conn3 ?? false, _dispSeq3, _dispNf3, _dispBo3),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 左: グラフ ──
              Expanded(
                flex: 1,
                child: _buildCombinedChart(
                  channels: const [6, 7, 8, 9, 10, 11],
                ),
              ),
              const SizedBox(width: 12),
              // ── 右: 圧力ヒートマップ ──
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
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6)),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: FootHeatmapView(
                                values: [
                                  _lastValue[9],
                                  _lastValue[10],
                                  _lastValue[11],
                                ],
                                points: _heatmapPoints.sublist(6, 9),
                                label: 'Dev3',
                                connected: frame?.conn2 ?? false,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: FootHeatmapView(
                                values: [
                                  _lastValue[6],
                                  _lastValue[7],
                                  _lastValue[8],
                                ],
                                points: _heatmapPoints.sublist(9, 12),
                                label: 'Dev4',
                                connected: frame?.conn3 ?? false,
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
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildInferencePanel(SensorFrame? frame) {
    final ready = frame?.inferReady ?? false;
    final score = frame?.fallGroupScore ?? 0.0; // lie + fall
    final danger = ready && (frame?.isDanger ?? false);
    final gi = frame?.groupIndex ?? -1;
    final gp = frame?.groupProbs ?? List<double>.filled(kGroupJa.length, 0.0);
    final validGroup = ready && gi >= 0 && gi < kGroupJa.length;

    const dangerColor = Color(0xFFFF4444);
    const normalColor = Color(0xFF00C853);
    final fillColor = danger ? dangerColor : normalColor;
    final statusText = !ready ? '収集中...' : (danger ? 'DANGER' : 'NORMAL');
    final statusColor = !ready ? Colors.white38 : fillColor;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ready
              ? fillColor.withOpacity(0.4)
              : const Color(0xFF58A6FF).withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ══ 上半分: NORMAL/DANGER 円ゲージ (スコア = danger 確率) ══
          Expanded(
            flex: 1,
            child: Column(children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: ready
                      ? CustomPaint(
                          painter: _GaugePainter(
                              value: score.clamp(0.0, 1.0),
                              fillColor: fillColor),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(statusText,
                                      style: TextStyle(
                                          color: statusColor,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 2)),
                                  Text(
                                      '${(score.clamp(0.0, 1.0) * 100).toStringAsFixed(1)}%',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(statusText,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 14))),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                  ready
                      ? '転倒スコア(danger) ${score.toStringAsFixed(4)}'
                      : '転倒スコア -',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 10)),
            ]),
          ),
          const Divider(color: Colors.white10, height: 12),
          // ══ 下半分: クラス表示 (5クラス) ══
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      validGroup
                          ? '${kGroupJa[gi]}  ${(gp[gi] * 100).toStringAsFixed(1)}%'
                          : '-',
                      maxLines: 1,
                      style: TextStyle(
                          color: validGroup ? kGroupColors[gi] : Colors.white38,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: ready
                      ? Column(
                          children: List.generate(kGroupJa.length, (i) {
                            final p = gp[i].clamp(0.0, 1.0);
                            final isTop = i == gi;
                            final c = kGroupColors[i];
                            return Expanded(
                              child: Row(children: [
                                SizedBox(
                                  width: 50,
                                  child: Text(kGroupJa[i],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: isTop ? c : Colors.white38,
                                          fontWeight: isTop
                                              ? FontWeight.bold
                                              : FontWeight.normal)),
                                ),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: Stack(children: [
                                      Container(
                                          color: Colors.white.withOpacity(0.07)),
                                      FractionallySizedBox(
                                        widthFactor: p,
                                        child: Container(
                                            color: c.withOpacity(
                                                isTop ? 0.95 : 0.45)),
                                      ),
                                    ]),
                                  ),
                                ),
                                SizedBox(
                                  width: 40,
                                  child: Text('${(p * 100).toStringAsFixed(1)}%',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: isTop ? c : Colors.white38,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures()
                                          ])),
                                ),
                              ]),
                            );
                          }),
                        )
                      : const Center(
                          child: Text('推論待機中',
                              style: TextStyle(
                                  color: Colors.white24, fontSize: 12))),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreGauge(double score, Color fillColor) {
    final v = score.clamp(0.0, 1.0);
    return CustomPaint(
      painter: _GaugePainter(value: v, fillColor: fillColor),
      child: Center(
          child: Text('${(v * 100).toStringAsFixed(1)}%',
              style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
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
          Expanded(
              child: Text(
            conn ? '$name  seq:${seq ?? '-'} nf:${nf ?? '-'} bo:${bo ?? '-'}' : '$name  未接続',
            style: const TextStyle(fontSize: 11, color: Colors.white70),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )),
        ]),
      ),
    );
  }

  Widget _buildCombinedChart({List<int> channels = const [0, 1, 2, 3, 4, 5]}) {
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: channels
                .map((ch) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                            width: 10,
                            height: 10,
                            color: _chColors[ch],
                            margin: const EdgeInsets.only(right: 4)),
                        Text('${ch % 6 + 1}', style: TextStyle(color: _chColors[ch], fontSize: 11)),
                      ],
                    ))
                .toList(),
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
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        interval: 0.5,
                        // 変更: 素のTextではなくSideTitleWidgetでラップする。
                        // これによりfl_chartがラベルをreservedSize領域内・軸の外側に
                        // 正しく配置するようになり、グラフ本体との重なりが解消される。
                        getTitlesWidget: (v, meta) => SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text(
                            v.toStringAsFixed(1),
                            style: const TextStyle(color: Colors.white38, fontSize: 9),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  minX: _tick > maxPoints ? (_tick - maxPoints).toDouble() : 0,
                  maxX: _tick > 0 ? (_tick - 1).toDouble() : (maxPoints - 1).toDouble(),
                  minY: 0.0,
                  maxY: 3.5,
                  clipData: const FlClipData.all(), 
                  borderData: FlBorderData(show: false),
                  lineBarsData: channels
                      .map((ch) => LineChartBarData(
                            spots: _series[ch].isEmpty
                                ? [const FlSpot(0, 0)]
                                : [
                                    // 描画点は1つおきに間引いて軽量化 (見た目はほぼ同じ)
                                    for (int i = 0; i < _series[ch].length; i += 2)
                                      FlSpot(_series[ch][i].x, _series[ch][i].y * 3.3)
                                  ],
                            color: _chColors[ch],
                            isCurved: false,
                            barWidth: 1.2,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(show: false),
                          ))
                      .toList(),
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF0D1117),
                      getTooltipItems: (spots) => spots.map((s) {
                        final ch = channels[s.barIndex];
                        return LineTooltipItem('${_chLabels[ch]}: ${s.y.toStringAsFixed(4)}',
                            TextStyle(color: _chColors[ch], fontSize: 11));
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
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.white10
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
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.fillColor != fillColor;
}