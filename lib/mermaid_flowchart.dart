/// Native Mermaid flowchart rendering for Flutter: a parser for the
/// `flowchart` / `graph` syntax, a layered layout with subgraph support and a
/// `CustomPainter`, with no WebView and no JavaScript.
///
/// Most apps only need [MermaidFlowchart]. The lower layers are exported
/// for custom rendering: [FlowchartParser] turns source into a [Flowchart],
/// [FlowchartLayout] positions it and [FlowchartPainter] draws it.
library;

export 'src/layout.dart'
    show
        FlowClusterBox,
        FlowEdgeRoute,
        FlowLayoutConfig,
        FlowTextMeasurer,
        FlowTextRole,
        FlowchartLayout;
export 'src/model.dart';
export 'src/painter.dart' show FlowchartPainter;
export 'src/parser.dart' show FlowchartParser;
export 'src/theme.dart' show FlowchartPalette, FlowchartTextStyles;
export 'src/widget.dart' show MermaidFlowchart;
