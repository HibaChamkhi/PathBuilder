import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'dart:math';

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
      home: Scaffold(body: PathBuilderWidget()),
    );
  }
}

class PathBuilderWidget extends StatefulWidget {
  @override
  _PathBuilderWidgetState createState() => _PathBuilderWidgetState();
}

class _PathBuilderWidgetState extends State<PathBuilderWidget> {
  List<Offset> points = [];
  List<Offset?> controlPoints = [];
  Offset? selectedPoint;
  int? selectedPointIndex;
  Offset? hoveringPoint; // Variable to hold the hovering point

  Offset? _findPointNearby(Offset tapPosition) {
    const double tolerance = 20.0;

    for (int i = 0; i < points.length; i++) {
      if ((points[i] - tapPosition).distance <= tolerance) {
        selectedPointIndex = i;
        return points[i];
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Path Builder')),
      body: GestureDetector(
        onTapDown: (TapDownDetails details) {
          final tapPosition = details.localPosition;

          Offset? nearbyPoint = _findPointNearby(tapPosition);
          if (nearbyPoint != null) {
            setState(() {
              selectedPoint = nearbyPoint;
            });
          } else {
            setState(() {
              points.add(tapPosition);
              controlPoints.add(null);
              hoveringPoint = null; // Reset hovering when adding a point
            });
          }
        },
        onPanUpdate: (DragUpdateDetails details) {
          if (selectedPoint != null && selectedPointIndex != null) {
            setState(() {
              points[selectedPointIndex!] = details.localPosition;

              // Update control point based on dragging
              if (selectedPointIndex! > 0) {
                controlPoints[selectedPointIndex! - 1] = Offset(
                  (points[selectedPointIndex! - 1].dx + details.localPosition.dx) / 2,
                  (points[selectedPointIndex! - 1].dy + details.localPosition.dy) / 2 - 30,
                );
              }
              if (selectedPointIndex! < points.length - 1) {
                controlPoints[selectedPointIndex!] = Offset(
                  (points[selectedPointIndex!].dx + points[selectedPointIndex! + 1].dx) / 2,
                  (points[selectedPointIndex!].dy + points[selectedPointIndex! + 1].dy) / 2 - 30,
                );
              }
            });
          } else {
            // Update the hovering point when no point is selected
            setState(() {
              hoveringPoint = details.localPosition;
            });
          }
        },
        onPanEnd: (DragEndDetails details) {
          setState(() {
            selectedPoint = null;
            selectedPointIndex = null;
            hoveringPoint = null; // Reset hovering when the drag ends
          });
        },
        onLongPress: () {
          // Handle long press to delete a point
          if (selectedPointIndex != null) {
            setState(() {
              points.removeAt(selectedPointIndex!);
              controlPoints.removeAt(selectedPointIndex!);
              selectedPointIndex = null; // Reset selected point index
              selectedPoint = null; // Reset selected point
            });
          }
        },
        child: MouseRegion(
          onEnter: (_) {
            // Optional: You can handle mouse enter if needed
          },
          onExit: (_) {
            // Reset hovering point when the mouse exits the area
            setState(() {
              hoveringPoint = null;
            });
          },
          onHover: (PointerHoverEvent event) {
            // Update the hovering point while the mouse is over the area
            setState(() {
              hoveringPoint = event.localPosition;
            });
          },
          child: CustomPaint(
            painter: PathPainter(points, controlPoints, hoveringPoint),
            child: const SizedBox(
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        ),
      ),
    );
  }
}

class PathPainter extends CustomPainter {
  final List<Offset> points;
  final List<Offset?> controlPoints;
  final Offset? hoveringPoint;

  PathPainter(this.points, this.controlPoints, this.hoveringPoint);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    // Draw the lines between points
    for (int i = 0; i < points.length - 1; i++) {
      Offset start = points[i];
      Offset end = points[i + 1];

      if (controlPoints[i] != null) {
        Offset controlPoint = controlPoints[i]!;
        Path path = Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(controlPoint.dx, controlPoint.dy, end.dx, end.dy);
        canvas.drawPath(path, paint);
      } else {
        canvas.drawLine(start, end, paint);
      }
    }

    // Draw the hovering line if there are points
    if (points.isNotEmpty && hoveringPoint != null) {
      canvas.drawLine(points.last, hoveringPoint!, paint);
    }

    // Draw points
    final pointPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    for (Offset point in points) {
      canvas.drawCircle(point, 5.0, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
