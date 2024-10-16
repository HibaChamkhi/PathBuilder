import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  final GlobalKey _globalKey = GlobalKey();

  List<Offset> points = [];
  List<Offset?> controlPointsIn = [];
  List<Offset?> controlPointsOut = [];
  List<bool> isControlPointModified = [];
  List<bool> isVisible = [];

  int? selectedPointIndex;
  int? selectedControlPointIndex;
  bool isOutwardControl = true;

  String? importedSvgPath;

  Offset offset = Offset.zero;
  bool isExporting = false;
  bool isDrawingFinished = false; // New state variable


  List<Offset> savedControlPointsIn = [];
  List<Offset> savedControlPointsOut = [];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTapDown: (TapDownDetails details) {
            if (!isDrawingFinished) {
              final tapPosition = details.localPosition;
              _selectPointOrAddNew(tapPosition);
            }
          },
          onPanUpdate: (DragUpdateDetails details) {
            if (!isDrawingFinished) {
              if (selectedPointIndex == null && selectedControlPointIndex == null) {
                _movePath(details.delta);
              } else {
                _updateSelectedPoint(details.delta);
              }
            }
          },
          onPanEnd: (_) {
            if (!isDrawingFinished) {
              _clearSelection();
            }
          },
          onDoubleTap: () {
            if (!isDrawingFinished) {
              _removeSelectedPoint();
            }
          },
          child: MouseRegion(
            onHover: (PointerHoverEvent event) {
              if (!isDrawingFinished) {
                final hoverPosition = event.localPosition;
                _toggleLineVisibility(hoverPosition, true);
              }
            },
            onExit: (PointerExitEvent event) {
              if (!isDrawingFinished) {
                _toggleLineVisibility(event.localPosition, false);
              }
            },
            child: RepaintBoundary(
              key: _globalKey,
              child: Stack(
                children: [
                  if (importedSvgPath != null)
                    SvgPicture.file(
                      File(importedSvgPath!),
                      width: 800,
                      height: 600,
                    ),
                  CustomPaint(
                    painter: PathPainter(
                      points.map((point) => point + offset).toList(),
                      controlPointsIn.map((cp) => cp != null ? cp + offset : null).toList(),
                      controlPointsOut.map((cp) => cp != null ? cp + offset : null).toList(),
                      isControlPointModified,
                      isVisible,
                      showControlPoints: !isDrawingFinished, // Control points hidden when drawing is finished
                      isExporting: false,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ],
              ),
            ),
          ),
        ),
        _buildFloatingActionButton(Icons.file_upload, _importSvg, 16.0),
        _buildFloatingActionButton(Icons.save_alt, _exportPathAsSvg, 100.0),
        _buildFloatingActionButton(Icons.clear, _clearAll, 200.0),
        // Toggle button that switches between "Finish" and "Edit" modes
        _buildFloatingActionButton(
          isDrawingFinished ? Icons.edit : Icons.check, // Icon changes based on mode
          _toggleDrawingMode, // Call toggle function
          300.0,
        ),
      ],
    );
  }

  Positioned _buildFloatingActionButton(IconData icon, VoidCallback onPressed, double rightPosition) {
    return Positioned(
      bottom: 16.0,
      right: rightPosition,
      child: FloatingActionButton(
        onPressed: onPressed,
        tooltip: icon == Icons.file_upload
            ? 'Import SVG'
            : icon == Icons.save_alt
            ? 'Export'
            : icon == Icons.clear
            ? 'Clear'
            : 'Finish Drawing',
        child: Icon(icon),
      ),
    );
  }

  Future<void> _importSvg() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['svg']);
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        importedSvgPath = result.files.first.path;
        print("importSvg $importedSvgPath");
      });
    }
  }

  Future<void> _exportPathAsSvg() async {
    // Call the _finishDrawing method first and await its completion
    await _finishDrawing(); // Ensure that this completes all drawing clearing

    // Now proceed to export the image
    setState(() {
      // Set isExporting to true temporarily for the export
      isExporting = true;
    });

    RenderRepaintBoundary boundary = _globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

    // Capture the image
    ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    Uint8List pngBytes = byteData!.buffer.asUint8List();

    final directory = await getApplicationDocumentsDirectory();
    final pngPathFile = '${directory.path}/exported_shape.png';

    // Write the image to a file
    final file = await File(pngPathFile).writeAsBytes(pngBytes);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Shape exported to ${file.path}')),
    );

    print('PNG file saved at: ${file.path}');

    // Reset the export state
    setState(() {
      isExporting = false; // Reset exporting state
    });
  }
  Future<void> _finishDrawing() async {
    // This method clears the drawing state
    setState(() {
      print("Finishing drawing...");
      // Save the current control points
      savedControlPointsIn = List.from(controlPointsIn);
      savedControlPointsOut = List.from(controlPointsOut);

      // Clear the control points and any other necessary states
      controlPointsIn.clear();
      controlPointsOut.clear();
      isDrawingFinished = true; // Update the drawing state
    });

    // Optionally, you can add a small delay if needed to ensure the UI updates before exporting
    await Future.delayed(Duration(milliseconds: 100));
  }

  void _restoreDrawing() {
    // This method restores the saved control points
    setState(() {
      print("Restoring drawing...");
      controlPointsIn = List.from(savedControlPointsIn);
      controlPointsOut = List.from(savedControlPointsOut);
      isDrawingFinished = false; // Reset the drawing state
    });
  }
  void _toggleDrawingMode() {
    setState(() {
      if (!isDrawingFinished) {
        // If we are switching from edit mode to drawing finished mode, call _finishDrawing()
        _finishDrawing();
      } else {
        _restoreDrawing();
        // Just toggle the mode back to edit mode
        isDrawingFinished = false;
      }
    });
  }

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
      isVisible.add(true);
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
        controlPointsIn[index] = controlPointsIn[index]! + delta;
      }
      isControlPointModified[index] = true;
    });
  }

  void _movePath(Offset delta) {
    setState(() {
      offset += delta;
    });
  }

  void _clearSelection() {
    setState(() {
      selectedPointIndex = null;
      selectedControlPointIndex = null;
    });
  }

  void _toggleLineVisibility(Offset position, bool visible) {
    const double proximityThreshold = 10.0;

    for (int i = 0; i < points.length; i++) {
      if (_isWithinProximity(points[i] + offset, position, proximityThreshold)) {
        setState(() {
          isVisible[i] = visible;
        });
        return;
      }
    }
  }

  void _removeSelectedPoint() {
    if (selectedPointIndex != null) {
      setState(() {
        points.removeAt(selectedPointIndex!);
        controlPointsIn.removeAt(selectedPointIndex!);
        controlPointsOut.removeAt(selectedPointIndex!);
        isControlPointModified.removeAt(selectedPointIndex!);
        isVisible.removeAt(selectedPointIndex!);
      });
      _clearSelection();
    }
  }

  void _clearAll() {
    setState(() {
      points.clear();
      controlPointsIn.clear();
      controlPointsOut.clear();
      isControlPointModified.clear();
      isVisible.clear();
      selectedPointIndex = null;
      selectedControlPointIndex = null;
      offset = Offset.zero;
      importedSvgPath = null;
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
  final bool isExporting;

  PathPainter(
      this.points,
      this.controlPointsIn,
      this.controlPointsOut,
      this.isControlPointModified,
      this.isVisible, {
        this.showControlPoints = true,
        required this.isExporting, // Make sure this is required
      });

  @override
  void paint(Canvas canvas, Size size) {
    _drawPath(canvas);

    // Draw control points and lines only if not exporting
    if (!isExporting) {

      // if (showControlPoints) {
      _drawControlPoints(canvas);
      // }
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
    //  the blue points drawing code
    Paint pointPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    for (Offset point in points) {
      canvas.drawCircle(point, 5.0, pointPaint);
    }

    Paint controlPointPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.fill;

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


