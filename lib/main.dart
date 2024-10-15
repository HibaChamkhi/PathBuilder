import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

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
  // Store points and control points for the path
  List<Offset> points = [];
  List<Offset?> controlPointsIn = [];
  List<Offset?> controlPointsOut = [];
  List<bool> isControlPointModified = [];
  List<bool> isVisible = [];

  // Track the currently selected point and control point
  int? selectedPointIndex;
  int? selectedControlPointIndex;
  bool isOutwardControl = true;

  // Path to imported SVG file
  String? importedSvgPath;

  // Offset to track movement of the entire path
  Offset offset = Offset.zero;

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
            if (selectedPointIndex == null && selectedControlPointIndex == null) {
              // Move the entire path if no point or control point is selected
              _movePath(details.delta);
            } else {
              _updateSelectedPoint(details.delta);
            }
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
            child: Stack(
              children: [
                // Display the imported SVG first
                if (importedSvgPath != null)
                  SvgPicture.file(
                    File(importedSvgPath!),
                    width: 800, // Set your desired width
                    height: 600, // Set your desired height
                  ),
                // Paint the path on top of the SVG
                CustomPaint(
                  painter: PathPainter(
                    points.map((point) => point + offset).toList(),
                    controlPointsIn.map((cp) => cp != null ? cp + offset : null).toList(),
                    controlPointsOut.map((cp) => cp != null ? cp + offset : null).toList(),
                    isControlPointModified,
                    isVisible,
                  ),
                  child: const SizedBox.expand(),
                ),
              ],
            ),
          ),
        ),
        // Floating Action Buttons for importing, exporting, and clearing paths
        _buildFloatingActionButton(Icons.file_upload, _importSvg, 16.0),
        _buildFloatingActionButton(Icons.save_alt, _exportPathAsSvg, 100.0),
        _buildFloatingActionButton(Icons.clear, _clearAll, 200.0),
      ],
    );
  }

  /// Creates a FloatingActionButton and positions it on the screen.
  Positioned _buildFloatingActionButton(IconData icon, VoidCallback onPressed, double rightPosition) {
    return Positioned(
      bottom: 16.0,
      right: rightPosition,
      child: FloatingActionButton(
        onPressed: onPressed,
        tooltip: icon == Icons.file_upload ? 'Import SVG' : icon == Icons.save_alt ? 'Export' : 'Clear',
        child: Icon(icon),
      ),
    );
  }

  /// Imports an SVG file and updates the state.
  Future<void> _importSvg() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['svg']);
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        importedSvgPath = result.files.first.path; // Store the selected SVG path
      });
    }
  }

  /// Exports the current path as an SVG file.
  Future<void> _exportPathAsSvg() async {
    final svgPath = StringBuffer();
    svgPath.write('<svg xmlns="http://www.w3.org/2000/svg" width="800" height="600">\n');

    if (points.isNotEmpty) {
      svgPath.write('<path d="M${points.first.dx + offset.dx},${points.first.dy + offset.dy} ');

      for (int i = 0; i < points.length - 1; i++) {
        if (isControlPointModified[i] && isVisible[i]) {
          Offset controlIn = (controlPointsIn[i] ?? points[i]) + offset;
          Offset controlOut = (controlPointsOut[i] ?? points[i + 1]) + offset;
          svgPath.write('C${controlOut.dx},${controlOut.dy} ${controlIn.dx},${controlIn.dy} ${points[i + 1].dx + offset.dx},${points[i + 1].dy + offset.dy} ');
        } else if (isVisible[i]) {
          svgPath.write('L${points[i + 1].dx + offset.dx},${points[i + 1].dy + offset.dy} ');
        }
      }

      svgPath.write('" stroke="black" fill="none" stroke-width="4"/>\n');
    }

    svgPath.write('</svg>');

    // Get the directory to save the SVG
    final directory = await getApplicationDocumentsDirectory();
    final svgPathFile = '${directory.path}/exported_shape.svg';

    // Write the SVG to a file
    final file = await File(svgPathFile).writeAsString(svgPath.toString());

    // Display a message and print the file path
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('SVG shape exported to ${file.path}')),
    );

    // Print the path in the console
    print('SVG file saved at: ${file.path}');
  }

  /// Selects an existing point or adds a new one based on tap position.
  void _selectPointOrAddNew(Offset position) {
    const double proximityThreshold = 10.0;

    for (int i = 0; i < points.length; i++) {
      if (_isWithinProximity(points[i] + offset, position, proximityThreshold)) {
        _selectPoint(i);
        return;
      }
      if (_isWithinProximity(controlPointsOut[i] != null ? controlPointsOut[i]! + offset : null, position, proximityThreshold)) {
        _selectControlPoint(i, isOutward: true);
        return;
      }
      if (_isWithinProximity(controlPointsIn[i] != null ? controlPointsIn[i]! + offset : null, position, proximityThreshold)) {
        _selectControlPoint(i, isOutward: false);
        return;
      }
    }

    _addNewPoint(position);
  }

  /// Selects a point at a given index.
  void _selectPoint(int index) {
    setState(() {
      selectedPointIndex = index;
      selectedControlPointIndex = null;
    });
  }

  /// Selects a control point at a given index.
  void _selectControlPoint(int index, {required bool isOutward}) {
    setState(() {
      selectedPointIndex = null;
      selectedControlPointIndex = index;
      isOutwardControl = isOutward;
    });
  }

  /// Adds a new point at the specified position.
  void _addNewPoint(Offset position) {
    setState(() {
      points.add(position);
      controlPointsIn.add(position - const Offset(30, 0));
      controlPointsOut.add(position + const Offset(30, 0));
      isControlPointModified.add(false);
      isVisible.add(true); // New lines start as visible
    });
  }

  /// Checks if a point is within a specified proximity to another position.
  bool _isWithinProximity(Offset? point, Offset position, double threshold) {
    return point != null && (point - position).distance < threshold;
  }

  /// Updates the position of the selected point or control point based on the drag delta.
  void _updateSelectedPoint(Offset delta) {
    if (selectedPointIndex != null) {
      _movePointAndControlPoints(selectedPointIndex!, delta);
    } else if (selectedControlPointIndex != null) {
      _moveControlPoint(selectedControlPointIndex!, delta);
    }
  }

  /// Moves a point and its control points by a given delta.
  void _movePointAndControlPoints(int index, Offset delta) {
    setState(() {
      points[index] += delta;
      controlPointsIn[index] = controlPointsIn[index]! + delta;
      controlPointsOut[index] = controlPointsOut[index]! + delta;
    });
  }

  /// Moves a control point by a given delta.
  void _moveControlPoint(int index, Offset delta) {
    setState(() {
      if (isOutwardControl) {
        controlPointsOut[index] = controlPointsOut[index]! + delta;
      } else {
        controlPointsIn[index] = controlPointsIn[index]! + delta;
      }
      isControlPointModified[index] = true;
    });
  }

  /// Moves the entire path by a given delta.
  void _movePath(Offset delta) {
    setState(() {
      offset += delta;
    });
  }

  /// Clears the selected point and control point.
  void _clearSelection() {
    setState(() {
      selectedPointIndex = null;
      selectedControlPointIndex = null;
    });
  }

  /// Toggles the visibility of the lines when hovering over them.
  void _toggleLineVisibility(Offset position, bool visible) {
    const double proximityThreshold = 10.0;

    for (int i = 0; i < points.length; i++) {
      if (_isWithinProximity(points[i] + offset, position, proximityThreshold)) {
        setState(() {
          isVisible[i] = visible;
        });
      }
    }
  }

  /// Removes the selected point from the path.
  void _removeSelectedPoint() {
    if (selectedPointIndex != null) {
      setState(() {
        points.removeAt(selectedPointIndex!);
        controlPointsIn.removeAt(selectedPointIndex!);
        controlPointsOut.removeAt(selectedPointIndex!);
        isControlPointModified.removeAt(selectedPointIndex!);
        isVisible.removeAt(selectedPointIndex!);
        selectedPointIndex = null; // Clear selection
      });
    }
  }

  /// Clears all points and paths.
  void _clearAll() {
    setState(() {
      points.clear();
      controlPointsIn.clear();
      controlPointsOut.clear();
      isControlPointModified.clear();
      isVisible.clear();
      selectedPointIndex = null; // Clear selection
      selectedControlPointIndex = null;
      offset = Offset.zero; // Reset the offset
    });
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
