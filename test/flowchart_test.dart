// Tests for the parser and the layout. Text is measured by a fake with a
// fixed glyph width, so no fonts are involved.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_flowchart/mermaid_flowchart.dart';

/// A typical architecture diagram: a gateway and services inside an
/// "Application server" subgraph, external services after it and a
/// "Logging" subgraph fed by an edge that leaves the whole subgraph.
const _infra = '''
flowchart LR
  CDN["CDN"] --> GW["Gateway"]
  subgraph APP["Application server (8 GB)"]
    GW --> API["API: 2 workers, cluster mode"]
    GW --> WEB["Web app (Next.js)"]
    API --> SEARCH["Search service<br/>(index per tenant)"]
    API --> JOBS["Job worker<br/>(PDF, exports, retention)<br/>queue in Postgres"]
  end
  subgraph OBS["Logging server (4 GB)"]
    LOGS["Log store<br/>(30-day retention)"]
  end
  APP -.->|log shipper| LOGS
  API --> DB[("Postgres database")]
  API --> STORE[("Object storage<br/>+ lifecycle rules")]
  API --> MAIL["Email API"]
  API --> VISION["Vision API"]
''';

Flowchart _parse(String source) => const FlowchartParser().parse(source)!;

Size _measure(String text, FlowTextRole role) {
  final lines = text.split('\n');
  final longest = lines.map((line) => line.length).reduce(math.max);
  final width = role == FlowTextRole.node
      ? math.min(longest * 7.0, 100.0)
      : longest * 7.0;
  final wrapped = role == FlowTextRole.node
      ? lines
          .map((line) => (line.length * 7 / 100).ceil().clamp(1, 99))
          .reduce((a, b) => a + b)
      : lines.length;
  return Size(width, wrapped * 17.0);
}

FlowchartLayout _layout(String source) =>
    FlowchartLayout.compute(_parse(source), _measure);

/// Asserts that no two node rectangles overlap.
void _expectNoOverlaps(FlowchartLayout layout) {
  final rects = layout.nodeRects.entries.toList();
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      final overlap = rects[i].value.intersect(rects[j].value);
      expect(
        overlap.width > 0.5 && overlap.height > 0.5,
        isFalse,
        reason: '${rects[i].key} overlaps ${rects[j].key}',
      );
    }
  }
}

/// Asserts that every edge is made of horizontal and vertical segments.
void _expectOrthogonal(FlowchartLayout layout) {
  for (final route in layout.edges) {
    for (var i = 0; i + 1 < route.points.length; i++) {
      final a = route.points[i];
      final b = route.points[i + 1];
      expect(
        (a.dx - b.dx).abs() < 0.01 || (a.dy - b.dy).abs() < 0.01,
        isTrue,
        reason: '${route.edge.from} -> ${route.edge.to} has a diagonal',
      );
    }
  }
}

bool _touches(Rect rect, Offset point) => rect.inflate(1).contains(point);

void main() {
  group('FlowchartParser', () {
    test('rejects other diagram types', () {
      expect(
          const FlowchartParser().parse('sequenceDiagram\n A->>B: hi'), isNull);
      expect(const FlowchartParser().parse('pie\n "a" : 1'), isNull);
    });

    test('reads the direction', () {
      expect(_parse('flowchart LR\n A-->B').direction, FlowDirection.leftRight);
      expect(_parse('graph TD\n A-->B').direction, FlowDirection.topDown);
      expect(_parse('graph BT\n A-->B').direction, FlowDirection.bottomUp);
      expect(_parse('flowchart RL\n A-->B').direction, FlowDirection.rightLeft);
      expect(_parse('flowchart\n A-->B').direction, FlowDirection.topDown);
    });

    test('decodes quoted labels, <br/> and entities', () {
      final chart = _parse(_infra);
      expect(chart.nodes['CDN']!.label, 'CDN');
      expect(
          chart.nodes['SEARCH']!.label, 'Search service\n(index per tenant)');
      expect(
        _parse('graph TD\n A["Diz #quot;oi#quot; &amp; tchau"]')
            .nodes['A']!
            .label,
        'Diz "oi" & tchau',
      );
      expect(
        _parse('graph TD\n A["`**Negrito** normal`"]').nodes['A']!.label,
        'Negrito normal',
      );
    });

    test('recognizes every node shape', () {
      final chart = _parse('''
graph LR
  a[r] --> b(r) --> c([s]) --> d[[s]] --> e[(c)] --> f((c)) --> g(((d)))
  h>a] --> i{r} --> j{{h}} --> k[/p/] --> l[\\p\\] --> m[/t\\] --> n[\\t/]
''');
      expect(
        [for (final id in 'abcdefghijklmn'.split('')) chart.nodes[id]!.shape],
        [
          FlowNodeShape.rectangle,
          FlowNodeShape.rounded,
          FlowNodeShape.stadium,
          FlowNodeShape.subroutine,
          FlowNodeShape.cylinder,
          FlowNodeShape.circle,
          FlowNodeShape.doubleCircle,
          FlowNodeShape.asymmetric,
          FlowNodeShape.rhombus,
          FlowNodeShape.hexagon,
          FlowNodeShape.parallelogram,
          FlowNodeShape.parallelogramAlt,
          FlowNodeShape.trapezoid,
          FlowNodeShape.trapezoidAlt,
        ],
      );
    });

    test('reads link styles, heads, lengths and labels', () {
      final chart = _parse('''
graph TD
  A --> B
  A --- C
  A -.-> D
  A ==> E
  A <--> F
  A --o G
  A --x H
  A ~~~ I
  A ---> J
  A -->|pipe| K
  A -- middle text --> L
  A -. dotted text .-> M
  A == thick text ==> N
''');
      final edges = {for (final edge in chart.edges) edge.to: edge};
      expect(edges['B']!.line, FlowLineStyle.solid);
      expect(edges['B']!.endHead, FlowArrowHead.arrow);
      expect(edges['C']!.endHead, FlowArrowHead.none);
      expect(edges['D']!.line, FlowLineStyle.dotted);
      expect(edges['E']!.line, FlowLineStyle.thick);
      expect(edges['F']!.startHead, FlowArrowHead.arrow);
      expect(edges['G']!.endHead, FlowArrowHead.circle);
      expect(edges['H']!.endHead, FlowArrowHead.cross);
      expect(edges['I']!.line, FlowLineStyle.invisible);
      expect(edges['B']!.length, 1);
      expect(edges['J']!.length, 2);
      expect(edges['K']!.label, 'pipe');
      expect(edges['L']!.label, 'middle text');
      expect(edges['M']!.label, 'dotted text');
      expect(edges['M']!.line, FlowLineStyle.dotted);
      expect(edges['N']!.label, 'thick text');
      expect(edges['N']!.line, FlowLineStyle.thick);
    });

    test('expands & groups and chains', () {
      final chart = _parse('graph TD\n A & B --> C --> D & E;F-->A');
      expect(
        [for (final edge in chart.edges) '${edge.from}${edge.to}'],
        ['AC', 'BC', 'CD', 'CE', 'FA'],
      );
    });

    test('assigns nodes to the subgraph that references them', () {
      final chart = _parse(_infra);
      // The gateway is first used outside, then inside the subgraph: it belongs
      // to the subgraph, as in Mermaid.
      expect(chart.subgraphs['APP']!.nodeIds,
          ['GW', 'API', 'WEB', 'SEARCH', 'JOBS']);
      expect(chart.subgraphs['APP']!.title, 'Application server (8 GB)');
      expect(chart.nodes['CDN']!.subgraph, isNull);
      expect(chart.nodes['LOGS']!.subgraph, 'OBS');
    });

    test('treats subgraph ids used in edges as subgraph endpoints', () {
      final chart = _parse(_infra);
      expect(chart.nodes.containsKey('APP'), isFalse);
      final edge = chart.edges.firstWhere((edge) => edge.from == 'APP');
      expect(edge.to, 'LOGS');
      expect(edge.line, FlowLineStyle.dotted);
      expect(edge.label, 'log shipper');
    });

    test('nests subgraphs', () {
      final chart = _parse('''
flowchart TB
  subgraph outer[Outer]
    subgraph inner[Inner]
      a --> b
    end
    c
  end
''');
      expect(chart.subgraphs['inner']!.parent, 'outer');
      expect(chart.subgraphs['outer']!.childIds, ['inner']);
      expect(chart.subgraphs['inner']!.nodeIds, ['a', 'b']);
      expect(chart.subgraphs['outer']!.nodeIds, ['c']);
    });

    test('applies classDef, class, ::: and style', () {
      final chart = _parse('''
graph TD
  A:::warm --> B
  classDef warm fill:#f96,stroke:#333,stroke-width:3px
  classDef cool fill:#9cf
  class B cool
  style B stroke:#ff0000,color:#fff
  %% a comment
  linkStyle 0 stroke:#00f,stroke-width:2px
''');
      final a = chart.nodeStyle(chart.nodes['A']!);
      expect(a.fill, const Color(0xFFFF9966));
      expect(a.strokeWidth, 3);
      final b = chart.nodeStyle(chart.nodes['B']!);
      expect(b.fill, const Color(0xFF99CCFF));
      expect(b.stroke, const Color(0xFFFF0000));
      expect(b.color, const Color(0xFFFFFFFF));
      expect(chart.edges.single.style.stroke, const Color(0xFF0000FF));
    });
  });

  group('FlowchartLayout', () {
    test('lays the infrastructure diagram out like the reference', () {
      final layout = _layout(_infra);
      final nodes = layout.nodeRects;
      final app = layout.clusters.firstWhere((box) => box.subgraph.id == 'APP');
      final obs = layout.clusters.firstWhere((box) => box.subgraph.id == 'OBS');

      // Members inside their boxes, everything else outside.
      for (final id in ['GW', 'API', 'WEB', 'SEARCH', 'JOBS']) {
        expect(app.rect.contains(nodes[id]!.center), isTrue, reason: id);
        expect(app.rect.expandToInclude(nodes[id]!), app.rect, reason: id);
      }
      expect(obs.rect.expandToInclude(nodes['LOGS']!), obs.rect);
      for (final id in ['CDN', 'DB', 'STORE', 'MAIL', 'VISION']) {
        expect(app.rect.overlaps(nodes[id]!), isFalse, reason: id);
        expect(obs.rect.overlaps(nodes[id]!), isFalse, reason: id);
      }

      // Left to right: CDN, gateway, API/web app, search/jobs, then the
      // external services after the box, and the log box after them.
      expect(nodes['CDN']!.right, lessThan(app.rect.left));
      expect(nodes['GW']!.right, lessThan(nodes['API']!.left));
      expect(nodes['API']!.left, nodes['WEB']!.left);
      expect(nodes['API']!.right, lessThan(nodes['SEARCH']!.left));
      for (final id in ['DB', 'STORE', 'MAIL', 'VISION']) {
        expect(nodes[id]!.left, greaterThan(app.rect.right), reason: id);
        expect(nodes[id]!.right, lessThan(obs.rect.left), reason: id);
      }

      // The CDN lines up with the gateway, so their edge is straight.
      expect(nodes['CDN']!.center.dy, closeTo(nodes['GW']!.center.dy, 0.5));

      _expectNoOverlaps(layout);
      _expectOrthogonal(layout);
    });

    test('routes edges between their endpoints', () {
      final layout = _layout(_infra);
      final app = layout.clusters.firstWhere((box) => box.subgraph.id == 'APP');
      for (final route in layout.edges) {
        final from = layout.nodeRects[route.edge.from] ?? app.rect;
        final to = layout.nodeRects[route.edge.to]!;
        expect(_touches(from, route.points.first), isTrue,
            reason: '${route.edge.from} start');
        expect(_touches(to, route.points.last), isTrue,
            reason: '${route.edge.to} end');
      }

      // The subgraph edge leaves from the box's right border and carries
      // its label.
      final logs = layout.edges.firstWhere((route) => route.edge.from == 'APP');
      expect(logs.points.first.dx, closeTo(app.rect.right, 0.5));
      expect(logs.labelRect, isNotNull);
    });

    test('runs the long edges out of API straight through the box', () {
      final layout = _layout(_infra);
      final api = layout.nodeRects['API']!;
      for (final target in ['DB', 'STORE', 'MAIL', 'VISION']) {
        final route = layout.edges.firstWhere(
          (route) => route.edge.from == 'API' && route.edge.to == target,
        );
        // Leaves API horizontally and keeps going past the search service before
        // its first bend.
        expect(route.points[0].dx, closeTo(api.right, 0.5));
        expect(
            route.points[1].dx, greaterThan(layout.nodeRects['SEARCH']!.right));
      }
    });

    test('flows top-down and handles cycles', () {
      final layout = _layout('''
graph TD
  A[Start] --> B{Is it?}
  B -- Yes --> C[OK]
  C --> D[Rethink]
  D --> B
  B -- No ----> E[End]
''');
      final nodes = layout.nodeRects;
      expect(nodes['A']!.bottom, lessThan(nodes['B']!.top));
      expect(nodes['B']!.bottom, lessThan(nodes['C']!.top));
      expect(nodes['C']!.bottom, lessThan(nodes['D']!.top));
      // The back edge still ends at B with its arrow.
      final back = layout.edges.firstWhere((route) => route.edge.from == 'D');
      expect(_touches(nodes['B']!, back.points.last), isTrue);
      _expectNoOverlaps(layout);
      _expectOrthogonal(layout);
    });

    test('mirrors bottom-up and right-left charts', () {
      final up = _layout('graph BT\n A --> B').nodeRects;
      expect(up['A']!.top, greaterThan(up['B']!.bottom));
      final left = _layout('graph RL\n A --> B').nodeRects;
      expect(left['A']!.left, greaterThan(left['B']!.right));
    });

    test('keeps edges out of unrelated subgraph boxes', () {
      final layout = _layout('''
flowchart TB
    c1-->a2
    subgraph one
    a1-->a2
    end
    subgraph two
    b1-->b2
    end
    subgraph three
    c1-->c2
    end
    one --> two
    three --> two
    two --> c2
''');
      final one = layout.clusters.firstWhere((box) => box.subgraph.id == 'one');
      for (final route in layout.edges) {
        final involvesOne = ['a1', 'a2', 'one'].contains(route.edge.from) ||
            ['a1', 'a2', 'one'].contains(route.edge.to);
        if (involvesOne) continue;
        for (var i = 0; i + 1 < route.points.length; i++) {
          final segment = Rect.fromPoints(route.points[i], route.points[i + 1]);
          expect(
            one.rect.deflate(1).overlaps(segment.inflate(0.1)),
            isFalse,
            reason: '${route.edge.from} -> ${route.edge.to} crosses "one"',
          );
        }
      }
      _expectNoOverlaps(layout);
    });

    test('nests subgraph boxes', () {
      final layout = _layout('''
flowchart LR
  subgraph outer[Outer]
    subgraph inner[Inner]
      a --> b
    end
    b --> c
  end
  x --> a
''');
      final outer =
          layout.clusters.firstWhere((box) => box.subgraph.id == 'outer');
      final inner =
          layout.clusters.firstWhere((box) => box.subgraph.id == 'inner');
      expect(outer.depth, 0);
      expect(inner.depth, 1);
      expect(outer.rect.expandToInclude(inner.rect), outer.rect);
      expect(inner.rect.contains(layout.nodeRects['a']!.center), isTrue);
      expect(inner.rect.overlaps(layout.nodeRects['c']!), isFalse);
      expect(outer.rect.overlaps(layout.nodeRects['x']!), isFalse);
      // Outermost boxes come first, so they are painted underneath.
      expect(layout.clusters.first.subgraph.id, 'outer');
    });
  });
}
