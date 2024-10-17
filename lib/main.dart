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
        // GestureDetector widget allows for interaction with the canvas (tap, drag, double-tap).
        GestureDetector(
          // Detects when the user taps down on the canvas
          onTapDown: (TapDownDetails details) {
            if (!isDrawingFinished) {
              final tapPosition = details.localPosition;
              // Selects an existing point or adds a new point at the tap position
              _selectPointOrAddNew(tapPosition);
            }
          },
          // Detects when the user drags their finger or mouse across the canvas
          onPanUpdate: (DragUpdateDetails details) {
            if (!isDrawingFinished) {
              // If no point or control point is selected, move the entire path
              if (selectedPointIndex == null && selectedControlPointIndex == null) {
                _movePath(details.delta);
              } else {
                // Otherwise, update the selected point's position
                _updateSelectedPoint(details.delta);
              }
            }
          },
          // Detects when the user lifts their finger or releases the mouse
          onPanEnd: (_) {
            if (!isDrawingFinished) {
              // Clears selection of points or control points after dragging ends
              _clearSelection();
            }
          },
          // Detects when the user double-taps on the canvas
          onDoubleTap: () {
            if (!isDrawingFinished) {
              // Removes the selected point on double tap
              _removeSelectedPoint();
            }
          },
          // MouseRegion widget to handle mouse hovering
          child: MouseRegion(
            // Detects when the mouse hovers over the canvas
            onHover: (PointerHoverEvent event) {
              print("onhover");
              if (!isDrawingFinished) {
                final hoverPosition = event.localPosition;
                // Toggles the visibility of control lines while hovering
                _toggleLineVisibility(hoverPosition, true);
              }
            },
            // Detects when the mouse leaves the canvas area
            onExit: (PointerExitEvent event) {
              if (!isDrawingFinished) {
                // Hides control lines when the mouse leaves the canvas area
                _toggleLineVisibility(event.localPosition, false);
              }
            },
            // RepaintBoundary widget helps with performance by limiting repainting
            child: RepaintBoundary(
              key: _globalKey, // Used to capture the current state of the canvas for exporting
              child: Stack(
                children: [
                  // If an SVG path has been imported, display it as an image
                  if (importedSvgPath != null)
                    SvgPicture.file(
                      File(importedSvgPath!),
                      width: 800, // Set the width of the SVG image
                      height: 600, // Set the height of the SVG image
                    ),
                  // CustomPaint widget draws the path and control points
                  CustomPaint(
                    painter: PathPainter(
                      points.map((point) => point + offset).toList(), // Offset points for proper alignment
                      controlPointsIn.map((cp) => cp != null ? cp + offset : null).toList(), // Offset control points (in)
                      controlPointsOut.map((cp) => cp != null ? cp + offset : null).toList(), // Offset control points (out)
                      isControlPointModified, // Tracks if control points have been modified
                      isVisible, // Tracks visibility of control lines
                      showControlPoints: !isDrawingFinished, // Hide control points when drawing is finished
                      isExporting: false, // Not in exporting mode
                    ),
                    child: const SizedBox.expand(), // Canvas expands to fill available space
                  ),
                ],
              ),
            ),
          ),
        ),
        // Floating action buttons for different functionalities

        // Button to import an SVG file
        _buildFloatingActionButton(Icons.file_upload, _importSvg, 16.0),

        // Button to export the current path as an SVG file
        _buildFloatingActionButton(Icons.save_alt, _exportPathAsSvg, 100.0),

        // Button to clear all points and start over
        _buildFloatingActionButton(Icons.clear, _clearAll, 200.0),

        // Toggle button that switches between "Finish" and "Edit" modes
        _buildFloatingActionButton(
          isDrawingFinished ? Icons.edit : Icons.check, // Icon changes based on mode
          _toggleDrawingMode, // Call toggle function to switch between modes
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



  ///

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

  ///

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

  ///


// Selects a point or control point within a certain proximity or adds a new point if none are selected
  void _selectPointOrAddNew(Offset position) {
    const double proximityThreshold = 10.0; // Threshold distance for proximity selection

    for (int i = 0; i < points.length; i++) {
      // Check if a point is within proximity
      if (_isWithinProximity(points[i] + offset, position, proximityThreshold)) {
        _selectPoint(i);
        return;
      }
      // Check if an outward control point is within proximity
      if (_isWithinProximity(controlPointsOut[i] != null ? controlPointsOut[i]! + offset : null, position, proximityThreshold)) {
        _selectControlPoint(i, isOutward: true);
        return;
      }
      // Check if an inward control point is within proximity
      if (_isWithinProximity(controlPointsIn[i] != null ? controlPointsIn[i]! + offset : null, position, proximityThreshold)) {
        _selectControlPoint(i, isOutward: false);
        return;
      }
    }

    _addNewPoint(position); // Add a new point if no proximity match is found
  }

// Selects a point by index, deselecting any control point
  void _selectPoint(int index) {
    setState(() {
      selectedPointIndex = index; // Set the selected point index
      selectedControlPointIndex = null; // Deselect any control points
    });
  }

// Selects a control point by index and specifies if it’s an outward control point
  void _selectControlPoint(int index, {required bool isOutward}) {
    setState(() {
      selectedPointIndex = null; // Deselect the main point
      selectedControlPointIndex = index; // Set the selected control point index
      isOutwardControl = isOutward; // Flag whether it's the outward control point
    });
  }

// Adds a new point along with its associated control points and initializes its properties
  void _addNewPoint(Offset position) {
    setState(() {
      points.add(position); // Add new point
      controlPointsIn.add(position - const Offset(30, 0)); // Add corresponding inward control point
      controlPointsOut.add(position + const Offset(30, 0)); // Add corresponding outward control point
      isControlPointModified.add(false); // Control points are not modified initially
      isVisible.add(true); // Point is visible by default
    });
  }

// Checks if a given point is within a certain proximity to the position
  bool _isWithinProximity(Offset? point, Offset position, double threshold) {
    return point != null && (point - position).distance < threshold; // Returns true if within threshold distance
  }

// Updates the position of the selected point or control point by a given delta (dragging)
  void _updateSelectedPoint(Offset delta) {
    if (selectedPointIndex != null) {
      _movePointAndControlPoints(selectedPointIndex!, delta); // Move the point and its control points
    } else if (selectedControlPointIndex != null) {
      _moveControlPoint(selectedControlPointIndex!, delta); // Move the selected control point
    }
  }

// Moves the selected point and both its control points by a given delta (translation)
  void _movePointAndControlPoints(int index, Offset delta) {
    setState(() {
      points[index] += delta; // Move the main point
      controlPointsIn[index] = controlPointsIn[index]! + delta; // Move the inward control point
      controlPointsOut[index] = controlPointsOut[index]! + delta; // Move the outward control point
    });
  }

// Moves either the inward or outward control point of the selected point by a given delta
  void _moveControlPoint(int index, Offset delta) {
    setState(() {
      if (isOutwardControl) {
        controlPointsOut[index] = controlPointsOut[index]! + delta; // Move outward control point
      } else {
        controlPointsIn[index] = controlPointsIn[index]! + delta; // Move inward control point
      }
      isControlPointModified[index] = true; // Mark the control point as modified
    });
  }

// Moves the entire path (including points and control points) by a given delta
  void _movePath(Offset delta) {
    setState(() {
      offset += delta; // Translate the entire path by delta
    });
  }

// Clears the current selection of points or control points
  void _clearSelection() {
    setState(() {
      selectedPointIndex = null; // Deselect point
      selectedControlPointIndex = null; // Deselect control point
    });
  }

// Toggles the visibility of a line based on proximity to a point
  void _toggleLineVisibility(Offset position, bool visible) {
    const double proximityThreshold = 10.0; // Threshold distance for proximity selection

    for (int i = 0; i < points.length; i++) {
      if (_isWithinProximity(points[i] + offset, position, proximityThreshold)) {
        setState(() {
          isVisible[i] = visible; // Set visibility of the point/line
        });
        return;
      }
    }
  }

// Removes the currently selected point along with its control points, and clears the selection
  void _removeSelectedPoint() {
    if (selectedPointIndex != null) {
      setState(() {
        points.removeAt(selectedPointIndex!); // Remove selected point
        controlPointsIn.removeAt(selectedPointIndex!); // Remove corresponding inward control point
        controlPointsOut.removeAt(selectedPointIndex!); // Remove corresponding outward control point
        isControlPointModified.removeAt(selectedPointIndex!); // Remove control modification flag
        isVisible.removeAt(selectedPointIndex!); // Remove visibility flag
      });
      _clearSelection(); // Clear any selections after removal
    }
  }

// Clears all points, control points, and path information, resetting the state
  void _clearAll() {
    setState(() {
      points.clear(); // Clear all points
      controlPointsIn.clear(); // Clear all inward control points
      controlPointsOut.clear(); // Clear all outward control points
      isControlPointModified.clear(); // Clear all control point modification flags
      isVisible.clear(); // Clear visibility flags
      selectedPointIndex = null; // Deselect any selected points
      selectedControlPointIndex = null; // Deselect any selected control points
      offset = Offset.zero; // Reset path offset
      importedSvgPath = null; // Clear any imported SVG paths
    });
  }




}

class PathPainter extends CustomPainter {
  final List<Offset> points; // List of main points for the path
  final List<Offset?> controlPointsIn; // List of 'in' control points for Bezier curves
  final List<Offset?> controlPointsOut; // List of 'out' control points for Bezier curves
  final List<bool> isControlPointModified; // List tracking if control points are modified
  final List<bool> isVisible; // List tracking visibility of the points
  final bool showControlPoints; // Flag to show/hide control points (optional)
  final bool isExporting; // Flag to toggle between export mode and edit mode

  PathPainter(
      this.points,
      this.controlPointsIn,
      this.controlPointsOut,
      this.isControlPointModified,
      this.isVisible, {
        this.showControlPoints = true, // Default value for showing control points
        required this.isExporting, // Make sure this flag is provided when creating the object
      });

  @override
  void paint(Canvas canvas, Size size) {
    _drawPath(canvas); // Draws the main path based on points and control points

    // Draw control points and additional markers only if it's not exporting
    if (!isExporting) {
      // Draw control points (optional based on flag)
      _drawControlPoints(canvas);
      // Draw points themselves as blue circles
      _drawPoints(canvas);
    }
  }

  // Function to draw the main path between the points and optionally curve them
  void _drawPath(Canvas canvas) {
    Paint pathPaint = Paint()
      ..color = Colors.black // Black color for the path
      ..style = PaintingStyle.stroke // Stroke style for outline
      ..strokeWidth = 4.0; // Set line thickness

    if (points.isNotEmpty) {
      Path path = Path()..moveTo(points.first.dx, points.first.dy); // Move to the first point

      // Loop through all points and draw lines/curves between them
      for (int i = 0; i < points.length - 1; i++) {
        if (isControlPointModified[i] && isVisible[i]) {
          // Use Bezier curve if control points are modified
          Offset controlIn = controlPointsIn[i] ?? points[i];
          Offset controlOut = controlPointsOut[i] ?? points[i + 1];
          path.cubicTo(controlOut.dx, controlOut.dy, controlIn.dx, controlIn.dy, points[i + 1].dx, points[i + 1].dy);
        } else if (isVisible[i]) {
          // Draw straight line if no control points are modified
          path.lineTo(points[i + 1].dx, points[i + 1].dy);
        }
      }
      canvas.drawPath(path, pathPaint); // Draw the final path on the canvas
    }
  }

  // Function to draw lines connecting control points and the main points
  void _drawControlPoints(Canvas canvas) {
    Paint controlPaint = Paint()
      ..color = Colors.green // Green color for control point lines
      ..style = PaintingStyle.stroke // Stroke style for lines
      ..strokeWidth = 2.0; // Line thickness

    // Loop through all points and draw lines to control points if available
    for (int i = 0; i < points.length; i++) {
      if (isVisible[i]) {
        if (controlPointsIn[i] != null) {
          canvas.drawLine(points[i], controlPointsIn[i]!, controlPaint); // Draw line to 'in' control point
        }
        if (controlPointsOut[i] != null) {
          canvas.drawLine(points[i], controlPointsOut[i]!, controlPaint); // Draw line to 'out' control point
        }
      }
    }
  }

  // Function to draw main points as blue circles and control points as green circles
  void _drawPoints(Canvas canvas) {
    // Paint configuration for drawing blue main points
    Paint pointPaint = Paint()
      ..color = Colors.blue // Blue color for main points
      ..style = PaintingStyle.fill; // Fill style for circles

    // Draw all main points as blue circles
    for (Offset point in points) {
      canvas.drawCircle(point, 5.0, pointPaint); // Circle radius of 5.0
    }

    // Paint configuration for green control points
    Paint controlPointPaint = Paint()
      ..color = Colors.green // Green color for control points
      ..style = PaintingStyle.fill; // Fill style for circles

    // Draw 'in' control points as green circles if available
    for (Offset? controlPoint in controlPointsIn) {
      if (controlPoint != null) {
        canvas.drawCircle(controlPoint, 4.0, controlPointPaint); // Circle radius of 4.0
      }
    }

    // Draw 'out' control points as green circles if available
    for (Offset? controlPoint in controlPointsOut) {
      if (controlPoint != null) {
        canvas.drawCircle(controlPoint, 4.0, controlPointPaint); // Circle radius of 4.0
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // Always repaint to reflect changes
  }
}



