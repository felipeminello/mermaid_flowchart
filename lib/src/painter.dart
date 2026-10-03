import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'layout.dart';
import 'model.dart';
import 'theme.dart';

/// Paints a [FlowchartLayout]: subgraph boxes, then edges, then nodes and
/// finally edge labels on top.
///
/// `MermaidFlowchart` wraps this painter; use it directly to draw a
/// flowchart on your own canvas. [styles] and [config] must be the ones the
/// [layout] was computed with.
class FlowchartPainter extends CustomPainter {
  /// Creates a painter for [chart] positioned by [layout].
  FlowchartPainter({
    required this.chart,
    required this.layout,
    required this.styles,
    required this.palette,
    this.config = const FlowLayoutConfig(),
  });

  /// The parsed diagram.
  final Flowchart chart;

  /// Positions computed by [FlowchartLayout.compute].
  final FlowchartLayout layout;

  /// Text styles the layout was measured with.
  final FlowchartTextStyles styles;

  /// Colors.
  final FlowchartPalette palette;

  /// Spacing the layout was computed with.
  final FlowLayoutConfig config;

  static const double _arrowLength = 8;
  static const double _arrowHalfWidth = 4.5;

  /// Space left between an arrow's tip and the node it points at.
  static const double _arrowGap = 1.5;
  static const double _cornerRadius = 6;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.background);
    for (final box in layout.clusters) {
      _paintCluster(canvas, box);
    }
    for (final route in layout.edges) {
      _paintEdge(canvas, route);
    }
    for (final node in chart.nodes.values) {
      final rect = layout.nodeRects[node.id];
      if (rect != null) _paintNode(canvas, node, rect);
    }
    for (final route in layout.edges) {
      _paintLabel(canvas, route);
    }
  }

  void _paintCluster(Canvas canvas, FlowClusterBox box) {
    final style = chart.subgraphStyle(box.subgraph);
    final fills = palette.clusterFills;
    final strokes = palette.clusterStrokes;
    canvas.drawRect(
      box.rect,
      Paint()
        ..color = style.fill ??
            (fills.isEmpty
                ? palette.background
                : fills[box.index % fills.length]),
    );
    _strokeRect(
      canvas,
      box.rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.strokeWidth ?? 1.5
        ..color = style.stroke ??
            (strokes.isEmpty
                ? palette.nodeStroke
                : strokes[box.index % strokes.length]),
      style.dashArray,
    );

    final title = box.subgraph.title;
    if (title.isEmpty) return;
    final painter = styles.layout(
      title,
      FlowTextRole.clusterTitle,
      overrides: TextStyle(
        color: style.color ?? palette.text,
        fontWeight: style.fontWeight,
        fontStyle: style.fontStyle,
      ),
    );
    painter.paint(
      canvas,
      Offset(
        box.rect.center.dx - painter.width / 2,
        box.rect.top + config.clusterTitleGap,
      ),
    );
    painter.dispose();
  }

  void _paintNode(Canvas canvas, FlowNode node, Rect rect) {
    final style = chart.nodeStyle(node);
    final fill = Paint()..color = style.fill ?? palette.nodeFill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.strokeWidth ?? 1.5
      ..color = style.stroke ?? palette.nodeStroke;

    void drawPath(Path path) {
      canvas.drawPath(path, fill);
      _strokePath(canvas, path, stroke, style.dashArray);
    }

    final l = rect.left;
    final t = rect.top;
    final r = rect.right;
    final b = rect.bottom;
    final c = rect.center;
    final h = rect.height;
    var textCenter = c;

    switch (node.shape) {
      case FlowNodeShape.rectangle:
        drawPath(Path()..addRect(rect));
      case FlowNodeShape.rounded:
        drawPath(
          Path()
            ..addRRect(
                RRect.fromRectAndRadius(rect, const Radius.circular(10))),
        );
      case FlowNodeShape.stadium:
        drawPath(
          Path()
            ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(h / 2))),
        );
      case FlowNodeShape.subroutine:
        drawPath(Path()..addRect(rect));
        canvas
          ..drawLine(Offset(l + 8, t), Offset(l + 8, b), stroke)
          ..drawLine(Offset(r - 8, t), Offset(r - 8, b), stroke);
      case FlowNodeShape.cylinder:
        final cap = config.cylinderCap;
        final body = Path()
          ..moveTo(l, t + cap)
          ..arcTo(
              Rect.fromLTWH(l, t, rect.width, cap * 2), math.pi, math.pi, false)
          ..lineTo(r, b - cap)
          ..arcTo(Rect.fromLTWH(l, b - cap * 2, rect.width, cap * 2), 0,
              math.pi, false)
          ..close();
        drawPath(body);
        _strokePath(
          canvas,
          Path()..addArc(Rect.fromLTWH(l, t, rect.width, cap * 2), 0, math.pi),
          stroke,
          style.dashArray,
        );
        textCenter = c.translate(0, cap / 2);
      case FlowNodeShape.circle:
        drawPath(Path()..addOval(rect));
      case FlowNodeShape.doubleCircle:
        drawPath(Path()..addOval(rect));
        _strokePath(
            canvas, Path()..addOval(rect.deflate(5)), stroke, style.dashArray);
      case FlowNodeShape.asymmetric:
        drawPath(_polygon([
          Offset(l, t),
          Offset(r, t),
          Offset(r, b),
          Offset(l, b),
          Offset(l + h / 4, c.dy),
        ]));
        textCenter = c.translate(h / 8, 0);
      case FlowNodeShape.rhombus:
        drawPath(_polygon([
          Offset(c.dx, t),
          Offset(r, c.dy),
          Offset(c.dx, b),
          Offset(l, c.dy),
        ]));
      case FlowNodeShape.hexagon:
        final inset = h / 4;
        drawPath(_polygon([
          Offset(l + inset, t),
          Offset(r - inset, t),
          Offset(r, c.dy),
          Offset(r - inset, b),
          Offset(l + inset, b),
          Offset(l, c.dy),
        ]));
      case FlowNodeShape.parallelogram:
        final skew = h * 0.3;
        drawPath(_polygon([
          Offset(l + skew, t),
          Offset(r, t),
          Offset(r - skew, b),
          Offset(l, b),
        ]));
      case FlowNodeShape.parallelogramAlt:
        final skew = h * 0.3;
        drawPath(_polygon([
          Offset(l, t),
          Offset(r - skew, t),
          Offset(r, b),
          Offset(l + skew, b),
        ]));
      case FlowNodeShape.trapezoid:
        final skew = h * 0.3;
        drawPath(_polygon([
          Offset(l + skew, t),
          Offset(r - skew, t),
          Offset(r, b),
          Offset(l, b),
        ]));
      case FlowNodeShape.trapezoidAlt:
        final skew = h * 0.3;
        drawPath(_polygon([
          Offset(l, t),
          Offset(r, t),
          Offset(r - skew, b),
          Offset(l + skew, b),
        ]));
    }

    final painter = styles.layout(
      node.label,
      FlowTextRole.node,
      overrides: TextStyle(
        color: style.color ?? palette.text,
        fontWeight: style.fontWeight,
        fontStyle: style.fontStyle,
      ),
    );
    painter.paint(
      canvas,
      textCenter - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  void _paintEdge(Canvas canvas, FlowEdgeRoute route) {
    final edge = route.edge;
    if (edge.line == FlowLineStyle.invisible || route.points.length < 2) {
      return;
    }
    final color = edge.style.stroke ?? palette.edge;
    final width = edge.style.strokeWidth ??
        (edge.line == FlowLineStyle.thick ? 3.0 : 1.5);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    final fill = Paint()..color = color;

    // Pull both ends back so the line stops where the heads begin.
    final points = [...route.points];
    final endTip = _trim(points, atEnd: true, head: edge.endHead);
    final startTip = _trim(points, atEnd: false, head: edge.startHead);

    final dash = edge.style.dashArray ??
        (edge.line == FlowLineStyle.dotted ? const [2.0, 2.0] : null);
    _strokePath(canvas, _roundedPath(points), stroke, dash);

    if (endTip != null) {
      _paintHead(canvas, endTip.$1, endTip.$2, edge.endHead, fill, stroke);
    }
    if (startTip != null) {
      _paintHead(
          canvas, startTip.$1, startTip.$2, edge.startHead, fill, stroke);
    }
  }

  /// Shortens the polyline at one end to make room for an arrow head.
  /// Returns the head's tip and the direction it points to.
  (Offset, Offset)? _trim(
    List<Offset> points, {
    required bool atEnd,
    required FlowArrowHead head,
  }) {
    if (head == FlowArrowHead.none) return null;
    final tipIndex = atEnd ? points.length - 1 : 0;
    final previousIndex = atEnd ? points.length - 2 : 1;
    final tip = points[tipIndex];
    final previous = points[previousIndex];
    final length = (tip - previous).distance;
    if (length == 0) return null;
    final direction = (tip - previous) / length;
    final adjustedTip = tip - direction * _arrowGap;
    final headLength =
        head == FlowArrowHead.arrow ? _arrowLength : _arrowHalfWidth * 2;
    final cut = math.min(_arrowGap + headLength, length);
    points[tipIndex] = tip - direction * cut;
    return (adjustedTip, direction);
  }

  void _paintHead(
    Canvas canvas,
    Offset tip,
    Offset direction,
    FlowArrowHead head,
    Paint fill,
    Paint stroke,
  ) {
    final normal = Offset(-direction.dy, direction.dx);
    switch (head) {
      case FlowArrowHead.arrow:
        final base = tip - direction * _arrowLength;
        canvas.drawPath(
          _polygon([
            tip,
            base + normal * _arrowHalfWidth,
            base - normal * _arrowHalfWidth,
          ]),
          fill,
        );
      case FlowArrowHead.circle:
        canvas.drawCircle(
            tip - direction * _arrowHalfWidth, _arrowHalfWidth, fill);
      case FlowArrowHead.cross:
        final center = tip - direction * _arrowHalfWidth;
        const size = _arrowHalfWidth;
        final a = (direction + normal) * size * 0.7;
        final b = (direction - normal) * size * 0.7;
        canvas
          ..drawLine(center - a, center + a, stroke)
          ..drawLine(center - b, center + b, stroke);
      case FlowArrowHead.none:
        break;
    }
  }

  void _paintLabel(Canvas canvas, FlowEdgeRoute route) {
    final rect = route.labelRect;
    final label = route.edge.label;
    if (rect == null ||
        label == null ||
        route.edge.line == FlowLineStyle.invisible) {
      return;
    }
    canvas.drawRect(rect, Paint()..color = palette.labelBackground);
    final painter = styles.layout(
      label,
      FlowTextRole.edgeLabel,
      overrides: TextStyle(color: route.edge.style.color ?? palette.text),
    );
    painter.paint(
      canvas,
      rect.center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  static Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);

  /// An orthogonal polyline with its corners rounded off.
  static Path _roundedPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i + 1 < points.length; i++) {
      final previous = points[i - 1];
      final corner = points[i];
      final next = points[i + 1];
      final before = (corner - previous).distance;
      final after = (next - corner).distance;
      final radius = math.min(_cornerRadius, math.min(before, after) / 2);
      if (radius < 0.5) {
        path.lineTo(corner.dx, corner.dy);
        continue;
      }
      final entry = corner - (corner - previous) / before * radius;
      final exit = corner + (next - corner) / after * radius;
      path
        ..lineTo(entry.dx, entry.dy)
        ..quadraticBezierTo(corner.dx, corner.dy, exit.dx, exit.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  static void _strokeRect(
    Canvas canvas,
    Rect rect,
    Paint paint,
    List<double>? dash,
  ) =>
      _strokePath(canvas, Path()..addRect(rect), paint, dash);

  static void _strokePath(
    Canvas canvas,
    Path path,
    Paint paint,
    List<double>? dash,
  ) {
    if (dash == null || dash.isEmpty || dash.every((d) => d <= 0)) {
      canvas.drawPath(path, paint);
      return;
    }
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      var index = 0;
      var draw = true;
      while (distance < metric.length) {
        final length = math.max(dash[index % dash.length], 0.5);
        if (draw) {
          dashed.addPath(
            metric.extractPath(
                distance, math.min(distance + length, metric.length)),
            Offset.zero,
          );
        }
        distance += length;
        draw = !draw;
        index++;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(FlowchartPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.styles != styles ||
      oldDelegate.palette != palette ||
      oldDelegate.config != config;
}
