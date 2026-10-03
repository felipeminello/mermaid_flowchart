import 'dart:ui' show Color, FontStyle, FontWeight;

/// Direction in which the ranks of a flowchart advance.
enum FlowDirection {
  /// `TB` / `TD`: ranks go downwards.
  topDown,

  /// `BT`: ranks go upwards.
  bottomUp,

  /// `LR`: ranks go to the right.
  leftRight,

  /// `RL`: ranks go to the left.
  rightLeft,
}

/// Node shapes of the Mermaid flowchart syntax.
enum FlowNodeShape {
  /// `A[text]`
  rectangle,

  /// `A(text)`
  rounded,

  /// `A([text])`
  stadium,

  /// `A[[text]]`
  subroutine,

  /// `A[(text)]`
  cylinder,

  /// `A((text))`
  circle,

  /// `A(((text)))`
  doubleCircle,

  /// `A>text]`
  asymmetric,

  /// `A{text}`
  rhombus,

  /// `A{{text}}`
  hexagon,

  /// `A[/text/]`
  parallelogram,

  /// `A[\text\]`
  parallelogramAlt,

  /// `A[/text\]`
  trapezoid,

  /// `A[\text/]`
  trapezoidAlt,
}

/// How an edge's line is drawn.
enum FlowLineStyle {
  /// `---`
  solid,

  /// `===`
  thick,

  /// `-.-`
  dotted,

  /// `~~~`: takes part in the layout but is not drawn.
  invisible,
}

/// The marker at one end of an edge.
enum FlowArrowHead {
  /// No marker.
  none,

  /// A filled triangle (`-->`).
  arrow,

  /// A filled circle (`--o`).
  circle,

  /// A cross (`--x`).
  cross,
}

/// The subset of Mermaid's CSS-like style declarations (`style`, `classDef`,
/// `linkStyle`) the renderer understands. `null` means "not set".
class FlowStyle {
  /// Creates a style; unset properties fall back to the palette.
  const FlowStyle({
    this.fill,
    this.stroke,
    this.strokeWidth,
    this.color,
    this.dashArray,
    this.fontWeight,
    this.fontStyle,
  });

  /// `fill`: background of a node or subgraph.
  final Color? fill;

  /// `stroke`: outline of a node or subgraph, or the line of an edge.
  final Color? stroke;

  /// `stroke-width`.
  final double? strokeWidth;

  /// `color`: text color.
  final Color? color;

  /// `stroke-dasharray`.
  final List<double>? dashArray;

  /// `font-weight`.
  final FontWeight? fontWeight;

  /// `font-style`.
  final FontStyle? fontStyle;

  /// Returns a style where every property set in [other] wins over this one.
  FlowStyle merge(FlowStyle other) => FlowStyle(
        fill: other.fill ?? fill,
        stroke: other.stroke ?? stroke,
        strokeWidth: other.strokeWidth ?? strokeWidth,
        color: other.color ?? color,
        dashArray: other.dashArray ?? dashArray,
        fontWeight: other.fontWeight ?? fontWeight,
        fontStyle: other.fontStyle ?? fontStyle,
      );

  /// Parses declarations such as `fill:#f9f,stroke:#333,stroke-width:4px`.
  static FlowStyle parse(String declarations) {
    Color? fill;
    Color? stroke;
    double? strokeWidth;
    Color? color;
    List<double>? dashArray;
    FontWeight? fontWeight;
    FontStyle? fontStyle;

    // Commas separate declarations but also appear inside rgb(...).
    for (final declaration in declarations.split(RegExp(r',(?![^(]*\))|;'))) {
      final colon = declaration.indexOf(':');
      if (colon < 0) continue;
      final key = declaration.substring(0, colon).trim().toLowerCase();
      final value =
          declaration.substring(colon + 1).replaceAll('!important', '').trim();
      switch (key) {
        case 'fill':
        case 'background':
        case 'background-color':
          fill = parseColor(value) ?? fill;
        case 'stroke':
          stroke = parseColor(value) ?? stroke;
        case 'stroke-width':
          strokeWidth = double.tryParse(value.replaceAll('px', '').trim());
        case 'color':
          color = parseColor(value) ?? color;
        case 'stroke-dasharray':
          final parts = value
              .split(RegExp(r'[\s,]+'))
              .map((part) => double.tryParse(part.replaceAll('px', '')))
              .whereType<double>()
              .toList();
          dashArray = parts.isEmpty ? null : parts;
        case 'font-weight':
          fontWeight = value == 'bold' || (int.tryParse(value) ?? 400) >= 600
              ? FontWeight.bold
              : FontWeight.normal;
        case 'font-style':
          fontStyle = value == 'italic' ? FontStyle.italic : FontStyle.normal;
      }
    }

    return FlowStyle(
      fill: fill,
      stroke: stroke,
      strokeWidth: strokeWidth,
      color: color,
      dashArray: dashArray,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
    );
  }

  /// Parses `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()` and a few
  /// common color names. Returns `null` for anything else.
  static Color? parseColor(String value) {
    final text = value.trim().toLowerCase();
    if (text.startsWith('#')) {
      var hex = text.substring(1);
      if (hex.length == 3 || hex.length == 4) {
        hex = hex.split('').map((digit) => '$digit$digit').join();
      }
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed == null) return null;
      if (hex.length == 6) return Color(0xFF000000 | parsed);
      if (hex.length == 8) {
        // CSS puts alpha last; Color wants it first.
        return Color(((parsed & 0xFF) << 24) | (parsed >> 8));
      }
      return null;
    }
    final rgb = RegExp(r'^rgba?\(([^)]*)\)$').firstMatch(text);
    if (rgb != null) {
      final parts = rgb.group(1)!.split(',').map((p) => p.trim()).toList();
      if (parts.length < 3) return null;
      final channels =
          parts.take(3).map((p) => int.tryParse(p)?.clamp(0, 255)).toList();
      if (channels.contains(null)) return null;
      final alpha = parts.length > 3 ? double.tryParse(parts[3]) ?? 1 : 1.0;
      return Color.fromARGB(
        (alpha.clamp(0, 1) * 255).round(),
        channels[0]!,
        channels[1]!,
        channels[2]!,
      );
    }
    final named = _namedColors[text];
    return named == null ? null : Color(named);
  }

  static const Map<String, int> _namedColors = {
    'black': 0xFF000000,
    'white': 0xFFFFFFFF,
    'red': 0xFFFF0000,
    'green': 0xFF008000,
    'lime': 0xFF00FF00,
    'blue': 0xFF0000FF,
    'yellow': 0xFFFFFF00,
    'orange': 0xFFFFA500,
    'purple': 0xFF800080,
    'pink': 0xFFFFC0CB,
    'cyan': 0xFF00FFFF,
    'magenta': 0xFFFF00FF,
    'gray': 0xFF808080,
    'grey': 0xFF808080,
    'lightgray': 0xFFD3D3D3,
    'lightgrey': 0xFFD3D3D3,
    'darkgray': 0xFFA9A9A9,
    'darkgrey': 0xFFA9A9A9,
    'transparent': 0x00000000,
    'none': 0x00000000,
  };
}

/// A node of a flowchart.
class FlowNode {
  /// Creates a node whose label is its [id] until one is set.
  FlowNode(this.id) : label = id;

  /// The id used to reference the node in the source.
  final String id;

  /// Display text; `\n` separates lines.
  String label;

  /// The node's shape.
  FlowNodeShape shape = FlowNodeShape.rectangle;

  /// Whether the node was ever written with a shape/label, as opposed to
  /// only being referenced by its id.
  bool isDefined = false;

  /// Id of the subgraph that directly contains the node, if any.
  String? subgraph;

  /// Classes assigned with `:::` or `class`.
  final List<String> classes = [];

  /// The node's own `style` statement.
  FlowStyle style = const FlowStyle();
}

/// An edge between two nodes or subgraphs.
class FlowEdge {
  /// Creates an edge.
  FlowEdge({
    required this.from,
    required this.to,
    this.label,
    this.line = FlowLineStyle.solid,
    this.startHead = FlowArrowHead.none,
    this.endHead = FlowArrowHead.arrow,
    this.length = 1,
  });

  /// Id of the node or subgraph the edge starts at.
  final String from;

  /// Id of the node or subgraph the edge ends at.
  final String to;

  /// Text shown on the edge.
  final String? label;

  /// How the line is drawn.
  final FlowLineStyle line;

  /// Marker at the [from] end.
  final FlowArrowHead startHead;

  /// Marker at the [to] end.
  final FlowArrowHead endHead;

  /// Minimum number of ranks the edge spans (`-->` is 1, `--->` is 2...).
  final int length;

  /// The edge's `linkStyle`.
  FlowStyle style = const FlowStyle();
}

/// A `subgraph ... end` block.
class FlowSubgraph {
  /// Creates an empty subgraph.
  FlowSubgraph(this.id, this.title);

  /// The id used to reference the subgraph in edges and styles.
  final String id;

  /// Text shown at the top of the box.
  final String title;

  /// Id of the enclosing subgraph, if any.
  String? parent;

  /// Nodes directly inside this subgraph (not inside a nested one).
  final List<String> nodeIds = [];

  /// Subgraphs directly nested in this one.
  final List<String> childIds = [];

  /// Classes assigned with `class`.
  final List<String> classes = [];

  /// The subgraph's own `style` statement.
  FlowStyle style = const FlowStyle();
}

/// A parsed Mermaid flowchart (`flowchart` / `graph`).
class Flowchart {
  /// Creates a flowchart. Usually obtained from `FlowchartParser.parse`
  /// rather than built by hand.
  Flowchart({
    required this.direction,
    required this.nodes,
    required this.edges,
    required this.subgraphs,
    required this.classDefs,
  });

  /// Direction in which ranks advance.
  final FlowDirection direction;

  /// Nodes in order of first appearance.
  final Map<String, FlowNode> nodes;

  /// Edges in source order.
  final List<FlowEdge> edges;

  /// Subgraphs in the order they are closed: nested ones come before the
  /// subgraph that contains them.
  final Map<String, FlowSubgraph> subgraphs;

  /// `classDef` statements by class name.
  final Map<String, FlowStyle> classDefs;

  /// The effective style of [node]: the `default` class, then its classes,
  /// then its own `style` statement.
  FlowStyle nodeStyle(FlowNode node) =>
      _resolve(['default', ...node.classes], node.style);

  /// The effective style of [subgraph]: its classes, then its own `style`.
  FlowStyle subgraphStyle(FlowSubgraph subgraph) =>
      _resolve(subgraph.classes, subgraph.style);

  FlowStyle _resolve(List<String> classes, FlowStyle own) {
    var style = const FlowStyle();
    for (final name in classes) {
      final classStyle = classDefs[name];
      if (classStyle != null) style = style.merge(classStyle);
    }
    return style.merge(own);
  }
}
