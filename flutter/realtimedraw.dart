import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

// --- 1. 数据接口和实现 ---

abstract class DrawableData<T> {
  final ValueNotifier<T> dataNotifier;
  DrawableData(T initialData) : dataNotifier = ValueNotifier<T>(initialData);
  void updateData(T newData) {
    dataNotifier.value = newData;
  }
  CustomPainter createPainter();
}

abstract class RealtimeDrawingData extends DrawableData<List<List<double>>> {
  final int samplingRate;
  final int windowDurationInSeconds;
  final int _windowSize;

  RealtimeDrawingData({
    required int numberOfChannels,
    required this.samplingRate,
    this.windowDurationInSeconds = 5,
  }) : _windowSize = samplingRate * windowDurationInSeconds,
       super(List.generate(numberOfChannels, (_) => []));

  void addDataPoint(List<double> newData);

  (double, double) getMinMaxAmplitude() {
    double minAmp = double.infinity;
    double maxAmp = double.negativeInfinity;
    
    for (var channelData in dataNotifier.value) {
      if (channelData.isNotEmpty) {
        minAmp = min(minAmp, channelData.reduce(min));
        maxAmp = max(maxAmp, channelData.reduce(max));
      }
    }
    
    if (minAmp.isInfinite || maxAmp.isInfinite) {
      return (-1.0, 1.0); 
    }
    
    if (maxAmp == minAmp) {
      return (minAmp - 1.0, maxAmp + 1.0);
    }
    
    return (minAmp, maxAmp);
  }

  static RealtimeDrawingData create({
    required int numberOfChannels,
    required int samplingRate,
    int windowDurationInSeconds = 5,
  }) {
    return _RealtimeDrawingDataImpl(
      numberOfChannels: numberOfChannels,
      samplingRate: samplingRate,
      windowDurationInSeconds: windowDurationInSeconds,
    );
  }
}

class _RealtimeDrawingDataImpl extends RealtimeDrawingData {
  _RealtimeDrawingDataImpl({
    required super.numberOfChannels,
    required super.samplingRate,
    super.windowDurationInSeconds,
  });

  @override
  void addDataPoint(List<double> newData) {
    if (newData.length != dataNotifier.value.length) {
      throw ArgumentError('通道数不匹配');
    }
    
    for (var i = 0; i < dataNotifier.value.length; i++) {
      dataNotifier.value[i].add(newData[i]);
      if (dataNotifier.value[i].length > _windowSize) {
        dataNotifier.value[i].removeAt(0);
      }
    }
    dataNotifier.notifyListeners();
  }
  
  @override
  CustomPainter createPainter() {
    return _RealtimePainter(this);
  }
}

// --- 2. CustomPainter 实现 ---

class _RealtimePainter extends CustomPainter {
  final RealtimeDrawingData data;
  _RealtimePainter(this.data) : super(repaint: data.dataNotifier);
  @override
  void paint(Canvas canvas, Size size) {
    if (data.dataNotifier.value.isEmpty || data.dataNotifier.value.first.isEmpty) {
      return;
    }
    final (minAmp, maxAmp) = data.getMinMaxAmplitude();
    final ampRange = maxAmp - minAmp;
    // final backgroundPaint = Paint()..color = Colors.black;
    // canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);
    for (var i = 0; i < data.dataNotifier.value.length; i++) {
      final channelData = data.dataNotifier.value[i];
      if (channelData.isEmpty) continue;
      final paint = Paint()
        ..color = _getChannelColor(i)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      final path = Path();
      final x = 0.0;
      final y = size.height - (channelData.first - minAmp) / ampRange * size.height;
      path.moveTo(x, y);
      for (var j = 1; j < channelData.length; j++) {
        final x = j / (data._windowSize - 1) * size.width;
        final y = size.height - (channelData[j] - minAmp) / ampRange * size.height;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }
  }
  Color _getChannelColor(int index) {
    final colors = [Colors.cyan, Colors.yellow, Colors.lightGreen, Colors.pinkAccent, Colors.orange];
    return colors[index % colors.length];
  }
  @override
  bool shouldRepaint(covariant _RealtimePainter oldDelegate) {
    return true;
  }
}

// --- 3. 通用绘图模块 ---

class GenericDrawingCanvas<T> extends StatelessWidget {
  final DrawableData<T> drawableData;
  final Size canvasSize;
  const GenericDrawingCanvas({
    super.key,
    required this.drawableData,
    this.canvasSize = const Size(double.infinity, double.infinity),
  });
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<T>(
        valueListenable: drawableData.dataNotifier,
        builder: (context, value, child) {
          return CustomPaint(
            size: canvasSize,
            painter: drawableData.createPainter(),
          );
        },
      ),
    );
  }
}

// --- 4. 应用程序入口 ---

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final int numberOfChannels = 3;
  final int samplingRate = 256;
  final int windowDurationInSeconds = 5;
  late final RealtimeDrawingData realtimeData;
  late final Timer _timer;
  // 定义一个用来追踪时间的变量
  double _time = 0.0;
  // 定义正弦波的频率和振幅
  final double frequency = 1.0; // 1 Hz
  final double amplitude = 0.5;

  @override
  void initState() {
    super.initState();
    realtimeData = RealtimeDrawingData.create(
      numberOfChannels: numberOfChannels,
      samplingRate: samplingRate,
      windowDurationInSeconds: windowDurationInSeconds,
    );
    _timer = Timer.periodic(Duration(microseconds: 1000000 ~/ samplingRate), (_) {
      // 计算当前时刻的每个通道的数据
      final newData = List.generate(numberOfChannels, (channelIndex) {
        // 为每个通道添加一个相移，使其波形错开
        final phaseShift = channelIndex * (2 * pi / numberOfChannels);
        return amplitude * sin(2 * pi * frequency * _time + phaseShift);
      });
      
      // 更新数据
      realtimeData.addDataPoint(newData);
      
      // 更新时间，为下一个数据点做准备
      _time += 1.0 / samplingRate;
    });
  }
  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('可调大小的绘图区域'),
          backgroundColor: Colors.grey[900],
          foregroundColor: Colors.white,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              SizedBox(
                height: 120,
                width: 600,
                child: Container(
                  color: Colors.white,
                  child: GenericDrawingCanvas(
                    drawableData: realtimeData,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // 使用 SizedBox 给绘图区域一个固定大小
              SizedBox(
                height: 120,
                width: 600,
                child: Container(
                  color: Colors.white,
                  child: GenericDrawingCanvas(
                    drawableData: realtimeData,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // 使用 SizedBox 给绘图区域一个固定大小
              SizedBox(
                height: 120,
                width: 600,
                child: Container(
                  color: Colors.white,
                  child: GenericDrawingCanvas(
                    drawableData: realtimeData,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
