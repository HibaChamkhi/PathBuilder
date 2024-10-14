import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gallery_saver/gallery_saver.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Path Builder',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const Scaffold(body: PathBuilderWidget()),
    );
  }
}

class PathBuilderWidget extends StatefulWidget {
  const PathBuilderWidget({super.key});

  @override
  _PathBuilderWidgetState createState() => _PathBuilderWidgetState();
}

class _PathBuilderWidgetState extends State<PathBuilderWidget> {
  List<Offset> points = [];
  List<Offset?> controlPointsIn = [];
  List<Offset?> controlPointsOut = [];
  List<bool> isControlPointModified = [];
  List<bool> isVisible = [];
  int? selectedPointIndex;
  int? selectedControlPointIndex;
  bool isOutwardControl = true;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTapDown: (TapDownDetails details) {
            final tapPosition = details.localPosition;
            _selectPointOrAddNew(tapPosition);
          },
          onPanUpdate: (DragUpdateDetails details) {
            _updateSelectedPoint(details.delta);
          },
          onPanEnd: (_) {
            _clearSelection();
          },
          onDoubleTap: () {
            _removeSelectedPoint();
          },
          child: MouseRegion(
            onHover: (PointerHoverEvent event) {
              final hoverPosition = event.localPosition;
              _toggleLineVisibility(hoverPosition, true);
            },
            onExit: (PointerExitEvent event) {
              _toggleLineVisibility(event.localPosition, false);
            },
            child: CustomPaint(
              painter: PathPainter(points, controlPointsIn, controlPointsOut, isControlPointModified, isVisible),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        Positioned(
          bottom: 16.0,
          right: 16.0,
          child: FloatingActionButton(
            onPressed: _exportPath,
            tooltip: 'Export',
            child: const Icon(Icons.save_alt),
          ),
        ),
      ],
    );
  }

  Future<void> _exportPath() async {
    // Create an image recorder and canvas to draw the path
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Draw the path onto the canvas, but hide the control points
    final pathPainter = PathPainter(points, controlPointsIn, controlPointsOut, isControlPointModified, isVisible, showControlPoints: false);
    pathPainter.paint(canvas, Size(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height));

    // End recording and create an image
    final picture = recorder.endRecording();
    final img = await picture.toImage(800, 600); // Specify the desired resolution

    // Convert image to byte data
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    // Get the directory to save the image
    final directory = await getApplicationDocumentsDirectory();
    final imagePath = '${directory.path}/exported_shape.png';

    // Write the image to a file
    final file = await File(imagePath).writeAsBytes(pngBytes);

    // Save the image to the gallery
    await GallerySaver.saveImage(file.path);

    // Display a message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Shape exported to ${file.path} and saved to gallery')),
    );
  }



  void _selectPointOrAddNew(Offset position) {
    const double proximityThreshold = 10.0;

    for (int i = 0; i < points.length; i++) {
      if (_isWithinProximity(points[i], position, proximityThreshold)) {
        _selectPoint(i);
        return;
      }
      if (_isWithinProximity(controlPointsOut[i], position, proximityThreshold)) {
        _selectControlPoint(i, isOutward: true);
        return;
      }
      if (_isWithinProximity(controlPointsIn[i], position, proximityThreshold)) {
        _selectControlPoint(i, isOutward: false);
        return;
      }
    }

    _addNewPoint(position);
  }

  void _selectPoint(int index) {
    setState(() {
      selectedPointIndex = index;
      selectedControlPointIndex = null;
    });
  }

  void _selectControlPoint(int index, {required bool isOutward}) {
    setState(() {
      selectedPointIndex = null;
      selectedControlPointIndex = index;
      isOutwardControl = isOutward;
    });
  }

  void _addNewPoint(Offset position) {
    setState(() {
      points.add(position);
      controlPointsIn.add(position - const Offset(30, 0));
      controlPointsOut.add(position + const Offset(30, 0));
      isControlPointModified.add(false);
      isVisible.add(true); // New lines start as visible
    });
  }

  bool _isWithinProximity(Offset? point, Offset position, double threshold) {
    return point != null && (point - position).distance < threshold;
  }

  void _updateSelectedPoint(Offset delta) {
    if (selectedPointIndex != null) {
      _movePointAndControlPoints(selectedPointIndex!, delta);
    } else if (selectedControlPointIndex != null) {
      _moveControlPoint(selectedControlPointIndex!, delta);
    }
  }

  void _movePointAndControlPoints(int index, Offset delta) {
    setState(() {
      points[index] += delta;
      controlPointsIn[index] = controlPointsIn[index]! + delta;
      controlPointsOut[index] = controlPointsOut[index]! + delta;
    });
  }

  void _moveControlPoint(int index, Offset delta) {
    setState(() {
      if (isOutwardControl) {
        controlPointsOut[index] = controlPointsOut[index]! + delta;
      } else {
        controlPointsIn[index] = controlPointsIn[index]! - delta;
      }
      isControlPointModified[index] = true;
    });
  }

  void _clearSelection() {
    setState(() {
      selectedPointIndex = null;
      selectedControlPointIndex = null;
    });
  }

  void _removeSelectedPoint() {
    if (selectedPointIndex != null) {
      setState(() {
        points.removeAt(selectedPointIndex!);
        controlPointsIn.removeAt(selectedPointIndex!);
        controlPointsOut.removeAt(selectedPointIndex!);
        isControlPointModified.removeAt(selectedPointIndex!);
        isVisible.removeAt(selectedPointIndex!);
        selectedPointIndex = null;
      });
    }
  }

  void _toggleLineVisibility(Offset hoverPosition, bool visible) {
    const double proximityThreshold = 10.0;
    for (int i = 0; i < points.length; i++) {
      if (_isWithinProximity(points[i], hoverPosition, proximityThreshold)) {
        setState(() {
          isVisible[i] = visible;
        });
        return;
      }
    }
  }
}


class PathPainter extends CustomPainter {
  final List<Offset> points;
  final List<Offset?> controlPointsIn;
  final List<Offset?> controlPointsOut;
  final List<bool> isControlPointModified;
  final List<bool> isVisible;
  final bool showControlPoints;

  PathPainter(this.points, this.controlPointsIn, this.controlPointsOut, this.isControlPointModified, this.isVisible, {this.showControlPoints = true});

  @override
  void paint(Canvas canvas, Size size) {
    _drawPath(canvas);

    if (showControlPoints) {
      _drawControlPoints(canvas);
      _drawPoints(canvas);
    }
  }

  void _drawPath(Canvas canvas) {
    Paint pathPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    if (points.isNotEmpty) {
      Path path = Path()..moveTo(points.first.dx, points.first.dy);

      for (int i = 0; i < points.length - 1; i++) {
        if (isControlPointModified[i] && isVisible[i]) {
          Offset controlIn = controlPointsIn[i] ?? points[i];
          Offset controlOut = controlPointsOut[i] ?? points[i + 1];
          path.cubicTo(controlOut.dx, controlOut.dy, controlIn.dx, controlIn.dy, points[i + 1].dx, points[i + 1].dy);
        } else if (isVisible[i]) {
          path.lineTo(points[i + 1].dx, points[i + 1].dy);
        }
      }
      canvas.drawPath(path, pathPaint);
    }
  }

  void _drawControlPoints(Canvas canvas) {
    Paint controlPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (int i = 0; i < points.length; i++) {
      if (isVisible[i]) {
        if (controlPointsIn[i] != null) {
          canvas.drawLine(points[i], controlPointsIn[i]!, controlPaint);
        }
        if (controlPointsOut[i] != null) {
          canvas.drawLine(points[i], controlPointsOut[i]!, controlPaint);
        }
      }
    }
  }

  void _drawPoints(Canvas canvas) {
    Paint pointPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    for (Offset point in points) {
      canvas.drawCircle(point, 5.0, pointPaint);
    }

    Paint controlPointPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (Offset? controlPoint in controlPointsIn) {
      if (controlPoint != null) {
        canvas.drawCircle(controlPoint, 4.0, controlPointPaint);
      }
    }

    for (Offset? controlPoint in controlPointsOut) {
      if (controlPoint != null) {
        canvas.drawCircle(controlPoint, 4.0, controlPointPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

