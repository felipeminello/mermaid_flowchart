import 'package:flutter/material.dart';

import 'layout.dart';
import 'model.dart';
import 'painter.dart';
import 'parser.dart';
import 'theme.dart';

/// Renders a Mermaid flowchart (`flowchart` / `graph`) natively, without a
/// WebView.
///
/// ```dart
/// MermaidFlowchart(
///   source: '''
/// flowchart LR
///   A[Start] --> B{Ok?}
///   B -->|yes| C[Done]
/// ''',
/// )
/// ```
///
/// The diagram is drawn at its natural size, which depends on its content.
/// Wrap it in a `FittedBox` to shrink it to the available width, or in an
/// `InteractiveViewer` to pan and zoom.
///
/// Colors default to [FlowchartPalette.light] or [FlowchartPalette.dark]
/// following the ambient [Theme], and text uses the theme's `bodyMedium`
/// font family. Parsing and layout are cached and only redone when the
/// source, the text styles or [layoutConfig] change.
class MermaidFlowchart extends StatefulWidget {
  /// Parses and renders [source]. When it is not a flowchart, or declares no
  /// node, [errorBuilder] is shown instead.
  const MermaidFlowchart({
    super.key,
    required String this.source,
    this.palette,
    this.textStyles,
    this.layoutConfig = const FlowLayoutConfig(),
    this.errorBuilder,
    this.onNodeTap,
    this.semanticLabel,
  }) : chart = null;

  /// Renders a [Flowchart] that was already parsed, for example with
  /// [FlowchartParser] to decide beforehand whether it can be rendered.
  const MermaidFlowchart.chart({
    super.key,
    required Flowchart this.chart,
    this.palette,
    this.textStyles,
    this.layoutConfig = const FlowLayoutConfig(),
    this.onNodeTap,
    this.semanticLabel,
  })  : source = null,
        errorBuilder = null;

  /// Mermaid source, when built with the default constructor.
  final String? source;

  /// Parsed chart, when built with [MermaidFlowchart.chart].
  final Flowchart? chart;

  /// Colors. Defaults to the palette matching the theme's brightness.
  final FlowchartPalette? palette;

  /// Text styles. Defaults to [FlowchartTextStyles.from] the theme's
  /// `bodyMedium` style.
  final FlowchartTextStyles? textStyles;

  /// Spacing of the layout.
  final FlowLayoutConfig layoutConfig;

  /// Shown when [source] cannot be rendered. Defaults to an empty box.
  final WidgetBuilder? errorBuilder;

  /// Called with the node under a tap.
  final ValueChanged<FlowNode>? onNodeTap;

  /// Description for screen readers. Defaults to "Flowchart:" followed by
  /// the node labels.
  final String? semanticLabel;

  @override
  State<MermaidFlowchart> createState() => _MermaidFlowchartState();
}

class _MermaidFlowchartState extends State<MermaidFlowchart> {
  Flowchart? _parsed;
  String? _parsedSource;
  FlowchartLayout? _layout;
  Flowchart? _layoutChart;
  FlowchartTextStyles? _layoutStyles;
  FlowLayoutConfig? _layoutConfig;

  Flowchart? get _chart {
    final chart = widget.chart;
    if (chart != null) return chart;
    final source = widget.source!;
    if (source != _parsedSource) {
      _parsedSource = source;
      _parsed = const FlowchartParser().parse(source);
    }
    return _parsed;
  }

  @override
  Widget build(BuildContext context) {
    final chart = _chart;
    if (chart == null) {
      return widget.errorBuilder?.call(context) ?? const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final styles = widget.textStyles ??
        FlowchartTextStyles.from(
          theme.textTheme.bodyMedium ?? DefaultTextStyle.of(context).style,
        );
    final config = widget.layoutConfig;
    if (_layout == null ||
        _layoutChart != chart ||
        _layoutStyles != styles ||
        _layoutConfig != config) {
      _layout = FlowchartLayout.compute(chart, styles.measure, config: config);
      _layoutChart = chart;
      _layoutStyles = styles;
      _layoutConfig = config;
    }
    final layout = _layout!;

    Widget diagram = CustomPaint(
      size: layout.size,
      painter: FlowchartPainter(
        chart: chart,
        layout: layout,
        styles: styles,
        palette: widget.palette ?? FlowchartPalette.of(theme.brightness),
        config: config,
      ),
    );

    final onNodeTap = widget.onNodeTap;
    if (onNodeTap != null) {
      diagram = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          for (final entry in layout.nodeRects.entries) {
            if (entry.value.contains(details.localPosition)) {
              onNodeTap(chart.nodes[entry.key]!);
              return;
            }
          }
        },
        child: diagram,
      );
    }

    final labels = chart.nodes.values
        .map((node) => node.label.replaceAll('\n', ' '))
        .join(', ');
    return Semantics(
      image: true,
      label: widget.semanticLabel ?? 'Flowchart: $labels',
      child: ExcludeSemantics(child: diagram),
    );
  }
}
