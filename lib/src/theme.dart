import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'layout.dart';

/// Text styles and wrapping widths of a flowchart.
///
/// The same instance is used to measure the text during layout and to paint
/// it, so labels are painted exactly as they were measured.
@immutable
class FlowchartTextStyles {
  /// Creates text styles from explicit [TextStyle]s.
  const FlowchartTextStyles({
    required this.node,
    required this.edgeLabel,
    required this.clusterTitle,
    this.nodeWrapWidth = 100,
    this.edgeLabelWrapWidth = 160,
  });

  /// Default styles in the font family of [base], usually the surrounding
  /// text style: 13 px node labels, 12 px edge labels and subgraph titles.
  factory FlowchartTextStyles.from(
    TextStyle base, {
    double nodeFontSize = 13,
    double labelFontSize = 12,
    double nodeWrapWidth = 100,
    double edgeLabelWrapWidth = 160,
  }) {
    final family = TextStyle(
      fontFamily: base.fontFamily,
      fontFamilyFallback: base.fontFamilyFallback,
      height: 1.3,
      leadingDistribution: TextLeadingDistribution.even,
    );
    return FlowchartTextStyles(
      node: family.copyWith(fontSize: nodeFontSize),
      edgeLabel: family.copyWith(fontSize: labelFontSize),
      clusterTitle: family.copyWith(fontSize: labelFontSize),
      nodeWrapWidth: nodeWrapWidth,
      edgeLabelWrapWidth: edgeLabelWrapWidth,
    );
  }

  /// Style of node labels.
  final TextStyle node;

  /// Style of edge labels.
  final TextStyle edgeLabel;

  /// Style of subgraph titles.
  final TextStyle clusterTitle;

  /// Node labels wrap at this width, like Mermaid's `wrappingWidth`.
  final double nodeWrapWidth;

  /// Edge labels wrap at this width.
  final double edgeLabelWrapWidth;

  /// Lays [text] out in the style of [role]. The caller owns the returned
  /// painter and should dispose it.
  TextPainter layout(String text, FlowTextRole role, {TextStyle? overrides}) {
    final (style, maxWidth) = switch (role) {
      FlowTextRole.node => (node, nodeWrapWidth),
      FlowTextRole.edgeLabel => (edgeLabel, edgeLabelWrapWidth),
      FlowTextRole.clusterTitle => (clusterTitle, double.infinity),
    };
    return TextPainter(
      text: TextSpan(text: text, style: style.merge(overrides)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textWidthBasis: TextWidthBasis.longestLine,
    )..layout(maxWidth: maxWidth);
  }

  /// The size [text] takes in the style of [role]. Matches
  /// [FlowTextMeasurer], so it can be handed to [FlowchartLayout.compute].
  Size measure(String text, FlowTextRole role) {
    final painter = layout(text, role);
    final size = painter.size;
    painter.dispose();
    return size;
  }

  @override
  bool operator ==(Object other) =>
      other is FlowchartTextStyles &&
      other.node == node &&
      other.edgeLabel == edgeLabel &&
      other.clusterTitle == clusterTitle &&
      other.nodeWrapWidth == nodeWrapWidth &&
      other.edgeLabelWrapWidth == edgeLabelWrapWidth;

  @override
  int get hashCode => Object.hash(
        node,
        edgeLabel,
        clusterTitle,
        nodeWrapWidth,
        edgeLabelWrapWidth,
      );
}

/// Colors of a flowchart.
///
/// The defaults give a clean whiteboard look: white nodes with dark
/// outlines, black edges, grey edge-label chips and pastel subgraph boxes.
/// [FlowchartPalette.dark] is the same design for dark backgrounds.
///
/// `style`, `classDef` and `linkStyle` statements in the diagram override
/// these colors for the elements they target.
@immutable
class FlowchartPalette {
  /// Creates a palette from explicit colors.
  const FlowchartPalette({
    required this.background,
    required this.nodeFill,
    required this.nodeStroke,
    required this.text,
    required this.edge,
    required this.labelBackground,
    required this.clusterFills,
    required this.clusterStrokes,
  });

  /// The default palette for light backgrounds.
  const FlowchartPalette.light()
      : this(
          background: const Color(0xFFFFFFFF),
          nodeFill: const Color(0xFFFFFFFF),
          nodeStroke: const Color(0xFF333346),
          text: const Color(0xFF161516),
          edge: const Color(0xFF000000),
          labelBackground: const Color(0xFFCCCCCC),
          clusterFills: _lightFills,
          clusterStrokes: _strokes,
        );

  /// The default palette for dark backgrounds.
  const FlowchartPalette.dark()
      : this(
          background: const Color(0xFF1B1B22),
          nodeFill: const Color(0xFF26262F),
          nodeStroke: const Color(0xFFC9C9D6),
          text: const Color(0xFFE8E8EE),
          edge: const Color(0xFFD4D4DC),
          labelBackground: const Color(0xFF4A4A55),
          clusterFills: _darkFills,
          clusterStrokes: _darkStrokes,
        );

  /// [FlowchartPalette.light] or [FlowchartPalette.dark].
  factory FlowchartPalette.of(Brightness brightness) =>
      brightness == Brightness.light
          ? const FlowchartPalette.light()
          : const FlowchartPalette.dark();

  // Fuchsia, teal, amber, sky, lime, rose, violet and orange.
  static const List<Color> _lightFills = [
    Color(0xFFFDF4FF),
    Color(0xFFF0FDFA),
    Color(0xFFFFFBEB),
    Color(0xFFF0F9FF),
    Color(0xFFF7FEE7),
    Color(0xFFFFF1F2),
    Color(0xFFF5F3FF),
    Color(0xFFFFF7ED),
  ];
  static const List<Color> _strokes = [
    Color(0xFFEFACF8),
    Color(0xFFA2ECE2),
    Color(0xFFFCD34D),
    Color(0xFF7DD3FC),
    Color(0xFFBEF264),
    Color(0xFFFDA4AF),
    Color(0xFFC4B5FD),
    Color(0xFFFDBA74),
  ];
  // The light strokes at 12 % (fills) and 75 % (strokes) opacity.
  static const List<Color> _darkFills = [
    Color(0x1FEFACF8),
    Color(0x1FA2ECE2),
    Color(0x1FFCD34D),
    Color(0x1F7DD3FC),
    Color(0x1FBEF264),
    Color(0x1FFDA4AF),
    Color(0x1FC4B5FD),
    Color(0x1FFDBA74),
  ];
  static const List<Color> _darkStrokes = [
    Color(0xBFEFACF8),
    Color(0xBFA2ECE2),
    Color(0xBFFCD34D),
    Color(0xBF7DD3FC),
    Color(0xBFBEF264),
    Color(0xBFFDA4AF),
    Color(0xBFC4B5FD),
    Color(0xBFFDBA74),
  ];

  /// Painted behind the whole diagram. Use a transparent color to let the
  /// surroundings show through.
  final Color background;

  /// Fill of nodes.
  final Color nodeFill;

  /// Outline of nodes.
  final Color nodeStroke;

  /// Color of every label: nodes, edges and subgraph titles.
  final Color text;

  /// Color of edges and arrow heads.
  final Color edge;

  /// Background of the chips behind edge labels.
  final Color labelBackground;

  /// Subgraph fills, used in order and cycled. Must not be empty.
  final List<Color> clusterFills;

  /// Subgraph outlines, paired with [clusterFills]. Must not be empty.
  final List<Color> clusterStrokes;

  @override
  bool operator ==(Object other) =>
      other is FlowchartPalette &&
      other.background == background &&
      other.nodeFill == nodeFill &&
      other.nodeStroke == nodeStroke &&
      other.text == text &&
      other.edge == edge &&
      other.labelBackground == labelBackground &&
      listEquals(other.clusterFills, clusterFills) &&
      listEquals(other.clusterStrokes, clusterStrokes);

  @override
  int get hashCode => Object.hash(
        background,
        nodeFill,
        nodeStroke,
        text,
        edge,
        labelBackground,
        Object.hashAll(clusterFills),
        Object.hashAll(clusterStrokes),
      );
}
