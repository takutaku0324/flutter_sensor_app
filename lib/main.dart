import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const EspMonitorApp());
}

class EspMonitorApp extends StatelessWidget {
  const EspMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,  
      title: 'ESP Monitor',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF58A6FF),
          surface: Color(0xFF161B22),
        ),
      ),
      home: const MonitorPage(),
    );
  }
}

// ================================================================
// SensorFrame: 各チャンネル16サンプルの配列を保持
// ESP32から:
//   d0.R_R / R_L / R_B → List<int> (16要素)
//   d1.L_R / L_L / L_B → List<int> (16要素)
// ================================================================
class SensorFrame {
  final bool conn0;
  final bool conn1;
  // 各チャンネルの16サンプル（正規化前の生値）
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

  // JSON値が配列なら配列として、単値なら[単値]として返す（後方互換）
  static List<int> _parseIntArray(dynamic v) {
    if (v == null) return [];
    if (v is List) return v.map((e) => (e as num).toInt()).toList();
    return [(v as num).toInt()]; // 旧フォーマット互換（単値）
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

  // 表示用: 最後のサンプル値（単値アクセスが必要な箇所用）
  int? get rRLast => rR.isNotEmpty ? rR.last : null;
  int? get rLLast => rL.isNotEmpty ? rL.last : null;
  int? get rBLast => rB.isNotEmpty ? rB.last : null;
  int? get lRLast => lR.isNotEmpty ? lR.last : null;
  int? get lLLast => lL.isNotEmpty ? lL.last : null;
  int? get lBLast => lB.isNotEmpty ? lB.last : null;
}

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});
  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  // グラフに保持するサンプル数 (16サンプル/パケット × 表示パケット数)
  static const int maxPoints = 600;
  static const wsUrl = 'ws://192.168.4.1:81';
  static const double _adcFullScale = 8388607.0; // 24bit符号付き最大値

  static const List<String> _chLabels = ['R_R', 'R_L', 'R_B', 'L_R', 'L_L', 'L_B'];
  static const List<Color> _chColors = [
    Color(0xFFFF6B6B),
    Color(0xFFFFA94D),
    Color(0xFFFFD43B),
    Color(0xFF4ECDC4),
    Color(0xFF45B7D1),
    Color(0xFFA88BFA),
  ];

  WebSocketChannel? _channel;
  bool _connected = false;
  String _status = '未接続';
  SensorFrame? _latest;

  int? _lastSeq0;
  int? _lastSeq1;
  // 6ch × maxPoints のグラフデータ（正規化済み: -1.0〜1.0）
  final List<List<FlSpot>> _series = List.generate(6, (_) => []);
  final List<double> _lastValue = List.filled(6, 0.0);
  int _tick = 0; // サンプル単位のカウンタ（パケット単位ではない）

  final _urlController = TextEditingController(text: wsUrl);

  void _connect() {
    final url = _urlController.text.trim();
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      setState(() {
        _connected = true;
        _status = '接続中: $url';
      });
      channel.stream.listen(
        (msg) {
          Map<String, dynamic> raw;
          try {
            raw = jsonDecode(msg as String) as Map<String, dynamic>;
          } catch (_) {
            return;
          }
          final frame = SensorFrame.fromJson(raw);
          _pushFrame(frame);
        },
        onError: (_) => setState(() {
          _status = '接続エラー';
          _connected = false;
        }),
        onDone: () => setState(() {
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

  // ================================================================
  // フレームを受け取り、16サンプルを順にグラフへ追加
  // ================================================================
  void _pushFrame(SensorFrame frame) {
  // ① 重複パケット除去（seq が前回と同じなら捨てる）
  final seq0Changed = frame.seq0 != null && frame.seq0 != _lastSeq0;
  final seq1Changed = frame.seq1 != null && frame.seq1 != _lastSeq1;
  if (!seq0Changed && !seq1Changed) return;
  _lastSeq0 = frame.seq0;
  _lastSeq1 = frame.seq1;

  final rawArrays = <List<int>?>[
    frame.conn0 ? frame.rR : null,
    frame.conn0 ? frame.rL : null,
    frame.conn0 ? frame.rB : null,
    frame.conn1 ? frame.lR : null,
    frame.conn1 ? frame.lL : null,
    frame.conn1 ? frame.lB : null,
  ];

  final sampleCount = rawArrays
      .whereType<List<int>>()
      .fold(0, (mx, a) => max(mx, a.length));
  if (sampleCount == 0) return;

  setState(() {
    _latest = frame;

    for (int s = 0; s < sampleCount; s++) {
      for (int ch = 0; ch < 6; ch++) {
        final arr = rawArrays[ch];
        if (arr == null || s >= arr.length) continue;

        final normalized = arr[s] / _adcFullScale;


        _lastValue[ch] = normalized;
        _series[ch].add(FlSpot(_tick.toDouble(), _lastValue[ch]));
        if (_series[ch].length > maxPoints) _series[ch].removeAt(0);
      }
      _tick++;
    }
  });
}

  void _disconnect() {
    _channel?.sink.close();
    setState(() {
      _connected = false;
      _status = '未接続';
    });
  }

  void _clearGraph() {
    setState(() {
      for (final s in _series) s.clear();
      _tick = 0;
    });
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _latest;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('ESP Monitor',
            style: TextStyle(color: Color(0xFF58A6FF), fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              _connected ? Icons.circle : Icons.circle_outlined,
              color: _connected ? Colors.greenAccent : Colors.redAccent,
              size: 14,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
                child: Text(_status,
                    style: const TextStyle(fontSize: 12, color: Colors.white54))),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 接続バー
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                  decoration: InputDecoration(
                    labelText: 'WebSocket URL',
                    labelStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF161B22),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _connected ? _disconnect : _connect,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _connected ? Colors.redAccent : const Color(0xFF58A6FF),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                ),
                child: Text(_connected ? '切断' : '接続'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'グラフをクリア',
                onPressed: _clearGraph,
                icon: const Icon(Icons.refresh, color: Colors.white54),
              ),
            ]),
            const SizedBox(height: 12),

            // デバイス接続状態
            Row(children: [
              _deviceChip('Dev1 (右足)', frame?.conn0 ?? false,
                  frame?.seq0, frame?.nf0, frame?.bo0),
              const SizedBox(width: 8),
              _deviceChip('Dev2 (左足)', frame?.conn1 ?? false,
                  frame?.seq1, frame?.nf1, frame?.bo1),
            ]),
            const SizedBox(height: 12),

            // グラフ + 推論パネル
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 1, child: _buildCombinedChart()),
                  const SizedBox(width: 12),
                  Expanded(flex: 1, child: _buildInferencePanel(frame)),
                ],
              ),
            ),
          ],
        ),
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
          color: ready
              ? fillColor.withOpacity(0.4)
              : const Color(0xFF58A6FF).withOpacity(0.2),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ready
                  ? _buildScoreGauge(score, fillColor)
                  : const Center(
                      child: Text('推論待機中',
                          style: TextStyle(color: Colors.white24, fontSize: 13)),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            ready ? score.toStringAsFixed(4) : '-',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          const Text('anomaly score',
              style: TextStyle(color: Colors.white24, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildScoreGauge(double score, Color fillColor) {
    final v = score.clamp(0.0, 1.0);
    return CustomPaint(
      painter: _GaugePainter(value: v, fillColor: fillColor),
      child: Center(
        child: Text(
          '${(v * 100).toStringAsFixed(1)}%',
          style: const TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
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
        child: Row(
          children: [
            Icon(conn ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                size: 16, color: conn ? Colors.greenAccent : Colors.redAccent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                conn
                    ? '$name  seq:${seq ?? '-'} nf:${nf ?? '-'} bo:${bo ?? '-'}'
                    : '$name  未接続',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCombinedChart() {
    // グラフのY軸範囲: 正規化値は-1.0〜+1.0
    // ただし実データが小さい場合に備えてautoScaleも考慮
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
            spacing: 12,
            runSpacing: 4,
            children: List.generate(6, (i) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 10, height: 10,
                    color: _chColors[i],
                    margin: const EdgeInsets.only(right: 4)),
                Text(_chLabels[i],
                    style: TextStyle(color: _chColors[i], fontSize: 11)),
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
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: Colors.white10, strokeWidth: 0.5),
                    getDrawingVerticalLine: (_) =>
                        FlLine(color: Colors.white10, strokeWidth: 0.5),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        interval: 0.5,
                        getTitlesWidget: (v, _) => Text(
                          v.toStringAsFixed(1),
                          style: const TextStyle(color: Colors.white38, fontSize: 9),
                        ),
                      ),
                    ),
                    bottomTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  minX: _tick > maxPoints ? (_tick - maxPoints).toDouble() : 0,
                  maxX: _tick > 0 ? (_tick - 1).toDouble() : (maxPoints - 1).toDouble(),
                  minY: 0.0, // 符号付き24bit → -1.0〜+1.0
                  maxY: 1.0,
                  borderData: FlBorderData(show: false),
                  lineBarsData: List.generate(6, (i) => LineChartBarData(
                    spots: _series[i].isEmpty ? [const FlSpot(0, 0)] : _series[i],
                    color: _chColors[i],
                    isCurved: false,
                    barWidth: 1.2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  )),
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF0D1117),
                      getTooltipItems: (spots) => spots.map((s) {
                        final idx = s.barIndex;
                        return LineTooltipItem(
                          '${_chLabels[idx]}: ${s.y.toStringAsFixed(4)}',
                          TextStyle(color: _chColors[idx], fontSize: 11),
                        );
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
      center, radius,
      Paint()
        ..color = Colors.white10
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

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
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.fillColor != fillColor;
}