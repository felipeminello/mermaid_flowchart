import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_flowchart/mermaid_flowchart.dart';

const _source = '''
flowchart LR
  A[Start] --> B{Ok?}
  B -->|yes| C[Done]
''';

Widget _app(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: Center(child: child)),
    );

FlowchartPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<FlowchartPainter>()
    .single;

void main() {
  group('FlowchartParser.isFlowchart', () {
    test('detects flowchart headers', () {
      expect(FlowchartParser.isFlowchart('flowchart LR\n A-->B'), isTrue);
      expect(FlowchartParser.isFlowchart('graph TD;A-->B'), isTrue);
      expect(FlowchartParser.isFlowchart('%% note\n\ngraph\n A'), isTrue);
      expect(
        FlowchartParser.isFlowchart('---\ntitle: T\n---\nflowchart TB\n A'),
        isTrue,
      );
    });

    test('rejects other diagrams', () {
      expect(
          FlowchartParser.isFlowchart('sequenceDiagram\n A->>B: hi'), isFalse);
      expect(FlowchartParser.isFlowchart('graphic design'), isFalse);
      expect(FlowchartParser.isFlowchart(''), isFalse);
    });
  });

  group('MermaidFlowchart', () {
    testWidgets('paints a flowchart at its natural size', (tester) async {
      await tester.pumpWidget(_app(const MermaidFlowchart(source: _source)));

      final painter = _painter(tester);
      expect(painter.chart.nodes.keys, ['A', 'B', 'C']);
      expect(
        tester.getSize(find.byType(MermaidFlowchart)),
        painter.layout.size,
      );
    });

    testWidgets('shows errorBuilder for sources it cannot render',
        (tester) async {
      await tester.pumpWidget(
        _app(
          MermaidFlowchart(
            source: 'pie\n "a" : 1',
            errorBuilder: (_) => const Text('not a flowchart'),
          ),
        ),
      );

      expect(find.text('not a flowchart'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is FlowchartPainter,
        ),
        findsNothing,
      );
    });

    testWidgets('renders an already parsed chart', (tester) async {
      final chart = const FlowchartParser().parse(_source)!;
      await tester.pumpWidget(_app(MermaidFlowchart.chart(chart: chart)));

      expect(_painter(tester).chart, same(chart));
    });

    testWidgets('follows the theme brightness unless a palette is given',
        (tester) async {
      await tester.pumpWidget(
        _app(const MermaidFlowchart(source: _source),
            brightness: Brightness.dark),
      );
      expect(_painter(tester).palette, const FlowchartPalette.dark());

      const custom = FlowchartPalette(
        background: Colors.transparent,
        nodeFill: Colors.yellow,
        nodeStroke: Colors.black,
        text: Colors.black,
        edge: Colors.blue,
        labelBackground: Colors.white,
        clusterFills: [Colors.white],
        clusterStrokes: [Colors.grey],
      );
      await tester.pumpWidget(
        _app(const MermaidFlowchart(source: _source, palette: custom),
            brightness: Brightness.dark),
      );
      expect(_painter(tester).palette, custom);
    });

    testWidgets('reports taps on nodes', (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(
        _app(
          MermaidFlowchart(
            source: _source,
            onNodeTap: (node) => tapped.add(node.id),
          ),
        ),
      );

      final layout = _painter(tester).layout;
      final origin = tester.getTopLeft(find.byType(MermaidFlowchart));
      await tester.tapAt(origin + layout.nodeRects['C']!.center);
      // Taps between nodes are ignored.
      await tester.tapAt(origin + const Offset(1, 1));

      expect(tapped, ['C']);
    });

    testWidgets('describes itself to screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(const MermaidFlowchart(source: _source)));

      expect(
        find.bySemanticsLabel('Flowchart: Start, Ok?, Done'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
