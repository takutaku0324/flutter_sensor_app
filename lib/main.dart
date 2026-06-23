import 'dart:async';
import 'dart:convert';
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

class SensorData {
  final double ax, ay, az, gx, gy, gz;
  final String label;
  final double score;
  SensorData({
    required this.ax, required this.ay, required this.az,
    required this.gx, required this.gy, required this.gz,
    required this.label, required this.score,
  });
  factory SensorData.fromJson(Map<String, dynamic> j) => SensorData(
    ax: (j['ax'] ?? 0).toDouble(), ay: (j['ay'] ?? 0).toDouble(),
    az: (j['az'] ?? 0).toDouble(), gx: (j['gx'] ?? 0).toDouble(),
    gy: (j['gy'] ?? 0).toDouble(), gz: (j['gz'] ?? 0).toDouble(),
    label: j['label'] ?? '-', score: (j['score'] ?? 0).toDouble(),
  );
}

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});
  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  static const int maxPoints = 100;
  static const wsUrl = 'ws://192.168.1.100:81';

  WebSocketChannel? _channel;
  bool _connected = false;
  String _status = '未接続';
  SensorData? _latest;

  // 6ch分のデータバッファ
  final List<List<FlSpot>> _series = List.generate(6, (_) => []);
  int _tick = 0;

  final _urlController = TextEditingController(text: wsUrl);

  void _connect() {
    final url = _urlController.text.trim();
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      setState(() { _connected = true; _status = '接続中: $url'; });
      _channel!.stream.listen(
        (msg) {
          final data = SensorData.fromJson(jsonDecode(msg as String));
          setState(() {
            _latest = data;
            final values = [data.ax, data.ay, data.az, data.gx, data.gy, data.gz];
            for (int i = 0; i < 6; i++) {
              _series[i].add(FlSpot(_tick.toDouble(), values[i]));
              if (_series[i].length > maxPoints) _series[i].removeAt(0);
            }
            _tick++;
          });
        },
        onError: (_) => setState(() { _status = '接続エラー'; _connected = false; }),
        onDone: ()  => setState(() { _status = '切断されました'; _connected = false; }),
      );
    } catch (e) {
      setState(() { _status = 'エラー: $e'; _connected = false; });
    }
  }

  void _disconnect() {
    _channel?.sink.close();
    setState(() { _connected = false; _status = '未接続'; });
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('ESP Monitor', style: TextStyle(color: Color(0xFF58A6FF), fontWeight: FontWeight.bold)),
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
            child: Center(child: Text(_status, style: const TextStyle(fontSize: 12, color: Colors.white54))),
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
                    filled: true, fillColor: const Color(0xFF161B22),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _connected ? _disconnect : _connect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _connected ? Colors.redAccent : const Color(0xFF58A6FF),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                ),
                child: Text(_connected ? '切断' : '接続'),
              ),
            ]),
            const SizedBox(height: 16),

            // 推論結果バナー
            if (_latest != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF58A6FF).withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('推論結果', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    Text(_latest!.label,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    Text('${(_latest!.score * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // グラフ 2段
            Expanded(child: Column(children: [
              Expanded(child: _buildChart('加速度 (m/s²)', 0, [
                const Color(0xFFFF6B6B), const Color(0xFF4ECDC4), const Color(0xFF45B7D1),
              ])),
              const SizedBox(height: 12),
              Expanded(child: _buildChart('ジャイロ (rad/s)', 3, [
                const Color(0xFFFFE66D), const Color(0xFFA8E6CF), const Color(0xFFFF8B94),
              ])),
            ])),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(String title, int startIdx, List<Color> colors) {
    final labels = startIdx == 0
        ? ['ax', 'ay', 'az']
        : ['gx', 'gy', 'gz'];

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 16),
            ...List.generate(3, (i) => Row(children: [
              Container(width: 10, height: 10, color: colors[i], margin: const EdgeInsets.only(right: 4)),
              Text(labels[i], style: TextStyle(color: colors[i], fontSize: 11)),
              const SizedBox(width: 8),
            ])),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(LineChartData(
              gridData: FlGridData(
                show: true,
                getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 0.5),
                getDrawingVerticalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 0.5),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 40,
                  getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1),
                    style: const TextStyle(color: Colors.white38, fontSize: 9)),
                )),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: List.generate(3, (i) => LineChartBarData(
                spots: _series[startIdx + i].isEmpty
                    ? [const FlSpot(0, 0)]
                    : _series[startIdx + i],
                color: colors[i],
                isCurved: true,
                barWidth: 1.5,
                dotData: FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: colors[i].withOpacity(0.05),
                ),
              )),
              lineTouchData: LineTouchData(enabled: false),
            )),
          ),
        ],
      ),
    );
  }
}