import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show immutable;

import 'model.dart';

/// Which piece of text is being measured, so the measurer can apply the
/// matching style and wrapping width.
enum FlowTextRole {
  /// A node label.
  node,

  /// An edge label.
  edgeLabel,

  /// A subgraph title.
  clusterTitle,
}

/// Returns the size [text] takes when painted in the style of [role].
typedef FlowTextMeasurer = Size Function(String text, FlowTextRole role);

/// Spacing used by [FlowchartLayout], in logical pixels.
@immutable
class FlowLayoutConfig {
  /// Creates a spacing configuration. The defaults suit 12–13 px text.
  const FlowLayoutConfig({
    this.nodeMinWidth = 120,
    this.nodeMinHeight = 34,
    this.nodePaddingX = 10,
    this.nodePaddingY = 9,
    this.cylinderCap = 11,
    this.rankSeparation = 50,
    this.nodeSeparation = 35,
    this.edgeSeparation = 8,
    this.edgeNodeSeparation = 15,
    this.clusterPadding = 20,
    this.clusterTitleGap = 6,
    this.clusterTitleMarginX = 12,
    this.trackSeparation = 10,
    this.trackMargin = 20,
    this.portSeparation = 8,
    this.labelPaddingX = 4,
    this.labelPaddingY = 1,
    this.diagramPadding = 8,
  });

  /// Minimum width of rectangular nodes.
  final double nodeMinWidth;

  /// Minimum height of rectangular nodes.
  final double nodeMinHeight;

  /// Horizontal space between a node's outline and its label.
  final double nodePaddingX;

  /// Vertical space between a node's outline and its label.
  final double nodePaddingY;

  /// Vertical radius of a cylinder's elliptical caps.
  final double cylinderCap;

  /// Minimum gap between two ranks (columns in LR, rows in TB).
  final double rankSeparation;

  /// Gap between neighbouring nodes inside a rank.
  final double nodeSeparation;

  /// Gap between two edges running side by side through a rank.
  final double edgeSeparation;

  /// Gap between an edge running through a rank and a node.
  final double edgeNodeSeparation;

  /// Space between a subgraph's border and its content.
  final double clusterPadding;

  /// Space above and below a subgraph's title.
  final double clusterTitleGap;

  /// Minimum space between a subgraph's title and its side borders.
  final double clusterTitleMarginX;

  /// Distance between parallel vertical edge segments in a gap.
  final double trackSeparation;

  /// Minimum distance between a gap's edge segments and its borders.
  final double trackMargin;

  /// Distance between edges that leave or enter the same side of a node.
  final double portSeparation;

  /// Horizontal space between an edge label and its chip's border.
  final double labelPaddingX;

  /// Vertical space between an edge label and its chip's border.
  final double labelPaddingY;

  /// Empty space around the whole diagram.
  final double diagramPadding;

  @override
  bool operator ==(Object other) =>
      other is FlowLayoutConfig &&
      other.nodeMinWidth == nodeMinWidth &&
      other.nodeMinHeight == nodeMinHeight &&
      other.nodePaddingX == nodePaddingX &&
      other.nodePaddingY == nodePaddingY &&
      other.cylinderCap == cylinderCap &&
      other.rankSeparation == rankSeparation &&
      other.nodeSeparation == nodeSeparation &&
      other.edgeSeparation == edgeSeparation &&
      other.edgeNodeSeparation == edgeNodeSeparation &&
      other.clusterPadding == clusterPadding &&
      other.clusterTitleGap == clusterTitleGap &&
      other.clusterTitleMarginX == clusterTitleMarginX &&
      other.trackSeparation == trackSeparation &&
      other.trackMargin == trackMargin &&
      other.portSeparation == portSeparation &&
      other.labelPaddingX == labelPaddingX &&
      other.labelPaddingY == labelPaddingY &&
      other.diagramPadding == diagramPadding;

  @override
  int get hashCode => Object.hashAll([
        nodeMinWidth,
        nodeMinHeight,
        nodePaddingX,
        nodePaddingY,
        cylinderCap,
        rankSeparation,
        nodeSeparation,
        edgeSeparation,
        edgeNodeSeparation,
        clusterPadding,
        clusterTitleGap,
        clusterTitleMarginX,
        trackSeparation,
        trackMargin,
        portSeparation,
        labelPaddingX,
        labelPaddingY,
        diagramPadding,
      ]);
}

/// Where a subgraph's box is drawn.
class FlowClusterBox {
  /// Creates a positioned subgraph box.
  const FlowClusterBox({
    required this.subgraph,
    required this.rect,
    required this.depth,
    required this.index,
  });

  /// The subgraph the box belongs to.
  final FlowSubgraph subgraph;

  /// The box, title band included.
  final Rect rect;

  /// Nesting depth: 0 for a top-level subgraph.
  final int depth;

  /// Position among the chart's subgraphs, used to pick a palette color.
  final int index;
}

/// The path of an edge.
class FlowEdgeRoute {
  /// Creates a routed edge.
  const FlowEdgeRoute({
    required this.edge,
    required this.points,
    this.labelRect,
  });

  /// The edge being routed.
  final FlowEdge edge;

  /// Orthogonal polyline from `edge.from` to `edge.to`. The first and last
  /// points lie on the outlines of the endpoints.
  final List<Offset> points;

  /// Where the edge's label chip goes, if the edge has a label.
  final Rect? labelRect;
}

/// Positions of every node, subgraph box and edge of a [Flowchart].
///
/// A layered (Sugiyama-style) layout in the spirit of Mermaid's dagre:
///
/// 1. **Ranks.** Longest-path layering over the edges. Subgraphs are kept
///    contiguous: an edge leaving a subgraph places its target after the
///    whole subgraph and an edge entering one places the whole subgraph after
///    the source, so external nodes never land inside a subgraph's columns.
/// 2. **Dummies.** Edges spanning several ranks get one dummy per crossed
///    rank, which reserves a lane for the edge. Labelled edges span at least
///    two ranks so the label gets a lane of its own.
/// 3. **Blocks.** Each subgraph is laid out on its own (innermost first) and
///    then moved as a rigid block inside its parent, which keeps members
///    together and non-members out of the box.
/// 4. **Order and position.** Barycenter sweeps order each rank; positions
///    come from repeated median-like pulls solved with isotonic regression.
/// 5. **Routing.** Edges are orthogonal: straight through their lanes, with
///    vertical segments in per-gap tracks ordered to avoid crossings.
class FlowchartLayout {
  /// Creates a layout from precomputed positions. Use
  /// [FlowchartLayout.compute] to lay a chart out.
  const FlowchartLayout({
    required this.size,
    required this.nodeRects,
    required this.clusters,
    required this.edges,
  });

  /// Lays [chart] out, measuring its text with [measure] (for example
  /// `FlowchartTextStyles.measure`).
  factory FlowchartLayout.compute(
    Flowchart chart,
    FlowTextMeasurer measure, {
    FlowLayoutConfig config = const FlowLayoutConfig(),
  }) =>
      _LayoutBuilder(chart, measure, config).build();

  /// Size of the whole diagram, padding included.
  final Size size;

  /// Bounds of every node, by node id.
  final Map<String, Rect> nodeRects;

  /// Subgraph boxes, outermost first so they can be painted in order.
  final List<FlowClusterBox> clusters;

  /// Every edge, in the order of [Flowchart.edges]. Edges whose endpoints
  /// do not exist are left out.
  final List<FlowEdgeRoute> edges;
}

// ---------------------------------------------------------------------------
// Internal model
// ---------------------------------------------------------------------------

class _Node {
  _Node(this.node, this.index);

  final FlowNode node;
  final int index;
  _Cluster? cluster;
  Size size = Size.zero;
  int rank = 0;
  late final _NodeItem item;

  /// Hops leaving through the side facing higher ranks.
  final List<_Hop> exits = [];

  /// Hops arriving through the side facing lower ranks.
  final List<_Hop> entries = [];
}

class _Cluster {
  _Cluster(this.subgraph, this.index);

  final FlowSubgraph subgraph;
  final int index;
  _Cluster? parent;
  final List<_Cluster> children = [];

  /// Every node inside the subgraph, nested ones included.
  final List<_Node> members = [];
  int depth = 0;
  int minRank = 1 << 30;
  int maxRank = -1;
  Size titleSize = Size.zero;
  late final _BlockItem item;
  late final _Level level;
  int openDepth = 1;
  int closeDepth = 1;
  double mainStart = 0;
  double mainEnd = 0;
  double startPad = 0;
  double endPad = 0;

  bool contains(_Cluster? other) {
    for (var c = other; c != null; c = c.parent) {
      if (c == this) return true;
    }
    return false;
  }
}

/// Something that occupies cross-axis space in one or more ranks of a level.
abstract class _Item {
  _Item(this.minRank, this.maxRank, this.container, this.key);

  final int minRank;
  final int maxRank;

  /// The subgraph whose level lays this item out (`null` for the root).
  final _Cluster? container;

  /// Initial ordering key.
  final double key;

  double crossSize = 0;

  /// Cross position of the item's start, relative to its level.
  double pos = 0;

  /// Absolute cross position of the item's start.
  double abs = 0;
}

class _NodeItem extends _Item {
  _NodeItem(this.node)
      : super(node.rank, node.rank, node.cluster, node.index.toDouble());

  final _Node node;
}

class _BlockItem extends _Item {
  _BlockItem(this.cluster, double key)
      : super(cluster.minRank, cluster.maxRank, cluster.parent, key);

  final _Cluster cluster;
}

class _DummyItem extends _Item {
  _DummyItem(this.chain, int rank, _Cluster? home, double key)
      : super(rank, rank, home, key);

  final _Chain chain;
  Size? label;
}

enum _PointKind { node, cluster, dummy }

/// A point of an edge chain: an endpoint node, the border of an endpoint
/// subgraph, or a dummy lane.
class _Point {
  _Point(this.item, this.rank, this.kind);

  final _Item item;
  final int rank;
  final _PointKind kind;

  /// Cross offset of the edge's port from the node's center.
  double port = 0;

  /// Cross offset of the point from the start of its own item.
  double get offset => item.crossSize / 2 + port;

  double get absCenter => item.abs + offset;
}

class _End {
  _End.node(_Node this.node) : cluster = null;
  _End.cluster(_Cluster this.cluster) : node = null;

  final _Node? node;
  final _Cluster? cluster;

  List<_Cluster> get clusters => [
        for (var c = cluster ?? node!.cluster; c != null; c = c.parent) c,
      ];
}

class _Chain {
  _Chain(this.edge, this.index, this.from, this.to);

  final FlowEdge edge;
  final int index;
  final _End from;
  final _End to;
  bool reversed = false;
  bool sameRank = false;
  bool selfLoop = false;
  int minLength = 1;

  /// Points in increasing rank order (from the lower-ranked endpoint).
  List<_Point> points = [];
  _DummyItem? labelDummy;
  Size? labelSize;
}

class _Hop {
  _Hop(this.chain, this.point, this.other);

  final _Chain chain;

  /// The node's own point.
  final _Point point;

  /// The neighbouring point along the chain.
  final _Point other;
}

class _Conn {
  _Conn(this.a, this.pa, this.b, this.pb, this.weight);

  final _Item a;
  final _Point pa;
  final _Item b;
  final _Point pb;
  final double weight;
}

class _Level {
  _Level(this.cluster, this.minRank, this.maxRank);

  final _Cluster? cluster;
  final int minRank;
  final int maxRank;
  final List<_Item> items = [];
  late List<List<_Item>> rows;
  final List<_Conn> conns = [];
  final Map<_Item, List<_Conn>> connsOf = {};

  List<_Item> row(int rank) => rows[rank - minRank];
}

/// A crossing of the gap between two consecutive ranks by an edge chain.
class _Segment {
  _Segment(this.chain, this.from, this.to, this.gap);

  final _Chain chain;
  final _Point from;
  final _Point to;
  final int gap;
  double exitCross = 0;
  double entryCross = 0;
  double track = 0;

  bool get needsTrack => (exitCross - entryCross).abs() > 0.5;
}

enum _Sweep { down, up, both }

// ---------------------------------------------------------------------------
// Builder
// ---------------------------------------------------------------------------

class _LayoutBuilder {
  _LayoutBuilder(this.chart, this.measure, this.config)
      : horizontal = chart.direction == FlowDirection.leftRight ||
            chart.direction == FlowDirection.rightLeft;

  final Flowchart chart;
  final FlowTextMeasurer measure;
  final FlowLayoutConfig config;
  final bool horizontal;

  final List<_Node> nodes = [];
  final Map<String, _Node> nodeById = {};
  final List<_Cluster> clusters = [];
  final Map<String, _Cluster> clusterById = {};
  final List<_Chain> chains = [];
  final Map<_Cluster?, _Level> levels = {};
  int maxRank = 0;

  double mainOf(Size size) => horizontal ? size.width : size.height;
  double crossOf(Size size) => horizontal ? size.height : size.width;

  double get titleBand => config.clusterTitleGap * 2;

  FlowchartLayout build() {
    _createNodes();
    _createClusters();
    _createChains();
    _assignRanks();
    _createItems();
    _orientChains();
    _layoutLevels();
    _assignAbsolute(levels[null]!, 0);
    _assignPorts(final_: true);
    _straighten();
    return _route();
  }

  // -- Model -----------------------------------------------------------------

  void _createNodes() {
    for (final node in chart.nodes.values) {
      final info = _Node(node, nodes.length);
      final text = measure(node.label, FlowTextRole.node);
      info.size = _nodeSize(node.shape, text);
      nodes.add(info);
      nodeById[node.id] = info;
    }
  }

  Size _nodeSize(FlowNodeShape shape, Size text) {
    final width = text.width + config.nodePaddingX * 2;
    final height = text.height + config.nodePaddingY * 2;
    final minWidth = config.nodeMinWidth;
    final minHeight = config.nodeMinHeight;
    switch (shape) {
      case FlowNodeShape.circle:
      case FlowNodeShape.doubleCircle:
        final extra = shape == FlowNodeShape.doubleCircle ? 10 : 0;
        final diameter =
            math.max(text.width, text.height) + config.nodePaddingX * 2 + extra;
        return Size(diameter, diameter);
      case FlowNodeShape.rhombus:
        final side = math.max(width + height, 60.0);
        return Size(side, side);
      case FlowNodeShape.hexagon:
      case FlowNodeShape.stadium:
        return Size(
          math.max(minWidth, width + height / 2),
          math.max(minHeight, height),
        );
      case FlowNodeShape.parallelogram:
      case FlowNodeShape.parallelogramAlt:
      case FlowNodeShape.trapezoid:
      case FlowNodeShape.trapezoidAlt:
        return Size(
          math.max(minWidth, width + height * 0.6),
          math.max(minHeight, height),
        );
      case FlowNodeShape.asymmetric:
        return Size(
          math.max(minWidth, width + height / 3),
          math.max(minHeight, height),
        );
      case FlowNodeShape.subroutine:
        return Size(
            math.max(minWidth, width + 16), math.max(minHeight, height));
      case FlowNodeShape.cylinder:
        return Size(
          math.max(minWidth, width),
          math.max(minHeight, height) + config.cylinderCap * 2,
        );
      case FlowNodeShape.rectangle:
      case FlowNodeShape.rounded:
        return Size(math.max(minWidth, width), math.max(minHeight, height));
    }
  }

  void _createClusters() {
    final all = <_Cluster>[];
    for (final subgraph in chart.subgraphs.values) {
      final cluster = _Cluster(subgraph, all.length);
      all.add(cluster);
      clusterById[subgraph.id] = cluster;
    }
    for (final cluster in all) {
      cluster.parent = clusterById[cluster.subgraph.parent];
    }
    for (final node in nodes) {
      node.cluster = clusterById[node.node.subgraph];
      for (var c = node.cluster; c != null; c = c.parent) {
        c.members.add(node);
      }
    }
    // Subgraphs without nodes have nothing to draw around.
    for (final cluster in all) {
      if (cluster.members.isEmpty) clusterById.remove(cluster.subgraph.id);
    }
    for (final cluster in all) {
      if (cluster.members.isEmpty) continue;
      clusters.add(cluster);
      cluster.parent?.children.add(cluster);
      for (var c = cluster.parent; c != null; c = c.parent) {
        cluster.depth++;
      }
      if (cluster.subgraph.title.isNotEmpty) {
        cluster.titleSize =
            measure(cluster.subgraph.title, FlowTextRole.clusterTitle);
      }
    }
  }

  _End? _end(String id) {
    final node = nodeById[id];
    if (node != null) return _End.node(node);
    final cluster = clusterById[id];
    if (cluster != null) return _End.cluster(cluster);
    return null;
  }

  void _createChains() {
    for (final edge in chart.edges) {
      final from = _end(edge.from);
      final to = _end(edge.to);
      if (from == null || to == null) continue;
      final chain = _Chain(edge, chains.length, from, to);
      chain.selfLoop = from.node != null && from.node == to.node;
      final label = edge.label;
      if (label != null && label.isNotEmpty) {
        final text = measure(label, FlowTextRole.edgeLabel);
        chain.labelSize = Size(
          text.width + config.labelPaddingX * 2,
          text.height + config.labelPaddingY * 2,
        );
      }
      chains.add(chain);
    }
  }

  // -- Ranks -----------------------------------------------------------------

  void _assignRanks() {
    final n = nodes.length;
    int start(_Cluster c) => n + 2 * c.index;
    int end(_Cluster c) => n + 2 * c.index + 1;
    final total = n + 2 * chart.subgraphs.length;

    final out = List.generate(total, (_) => <(int, int)>[]);
    final hasPredecessor = List.filled(n, false);

    bool reaches(int from, int target) {
      final seen = <int>{from};
      final stack = [from];
      while (stack.isNotEmpty) {
        final v = stack.removeLast();
        if (v == target) return true;
        for (final (next, _) in out[v]) {
          if (seen.add(next)) stack.add(next);
        }
      }
      return false;
    }

    // Constraints that would close a cycle are dropped: earlier ones win,
    // which is how back edges of cyclic charts are found.
    void constrain(int a, int b, int length) {
      if (a == b || reaches(b, a)) return;
      out[a].add((b, length));
      if (b < n) hasPredecessor[b] = true;
    }

    for (final cluster in clusters) {
      for (final member in cluster.members) {
        if (!reaches(member.index, start(cluster))) {
          out[start(cluster)].add((member.index, 0));
        }
        if (!reaches(end(cluster), member.index)) {
          out[member.index].add((end(cluster), 0));
        }
      }
    }

    final active = chains.where((chain) => !chain.selfLoop).toList();
    int source(_Chain chain) =>
        chain.from.node?.index ?? end(chain.from.cluster!);
    int target(_Chain chain) =>
        chain.to.node?.index ?? start(chain.to.cluster!);

    for (final chain in active) {
      var length = chain.edge.length;
      // The border of a subgraph endpoint takes a rank of its own.
      if (chain.from.cluster != null || chain.to.cluster != null) length++;
      if (chain.labelSize != null) length = math.max(length, 2);
      chain.minLength = length;
      constrain(source(chain), target(chain), length);
    }

    for (final chain in active) {
      final fromClusters = chain.from.clusters;
      final toClusters = chain.to.clusters;
      final leaving = fromClusters.where((c) => !toClusters.contains(c));
      final entering = toClusters.where((c) => !fromClusters.contains(c));
      for (final left in leaving) {
        constrain(end(left), target(chain), chain.minLength);
      }
      for (final entered in entering) {
        constrain(source(chain), start(entered), chain.minLength);
      }
      for (final left in leaving) {
        for (final entered in entering) {
          constrain(end(left), start(entered), chain.minLength);
        }
      }
    }

    // Longest path over the constraint DAG.
    final inDegree = List.filled(total, 0);
    for (final edges in out) {
      for (final (next, _) in edges) {
        inDegree[next]++;
      }
    }
    final rank = List.filled(total, 0);
    final order = <int>[];
    final queue = [
      for (var v = 0; v < total; v++)
        if (inDegree[v] == 0) v
    ];
    while (queue.isNotEmpty) {
      final v = queue.removeAt(0);
      order.add(v);
      for (final (next, length) in out[v]) {
        rank[next] = math.max(rank[next], rank[v] + length);
        if (--inDegree[next] == 0) queue.add(next);
      }
    }

    // Pull free-standing sources next to their successors, as dagre's
    // network simplex would, instead of leaving them at rank 0.
    for (final v in order.reversed) {
      if (v >= n || hasPredecessor[v] || nodes[v].cluster != null) continue;
      if (out[v].isEmpty) continue;
      final latest = out[v].map((e) => rank[e.$1] - e.$2).reduce(math.min);
      if (latest > rank[v]) rank[v] = latest;
    }

    final lowest = nodes.isEmpty
        ? 0
        : nodes.map((node) => rank[node.index]).reduce(math.min);
    for (final node in nodes) {
      node.rank = rank[node.index] - lowest;
      maxRank = math.max(maxRank, node.rank);
    }
    for (final cluster in clusters) {
      for (final member in cluster.members) {
        cluster.minRank = math.min(cluster.minRank, member.rank);
        cluster.maxRank = math.max(cluster.maxRank, member.rank);
      }
    }
  }

  // -- Items and chains ------------------------------------------------------

  void _createItems() {
    levels[null] = _Level(null, 0, maxRank);
    for (final cluster in clusters) {
      cluster.level = _Level(cluster, cluster.minRank, cluster.maxRank);
      levels[cluster] = cluster.level;
    }
    for (final cluster in clusters) {
      cluster.item = _BlockItem(
        cluster,
        cluster.members.map((m) => m.index).reduce(math.min).toDouble(),
      );
      levels[cluster.parent]!.items.add(cluster.item);
    }
    for (final node in nodes) {
      node.item = _NodeItem(node)..crossSize = crossOf(node.size);
      levels[node.cluster]!.items.add(node.item);
    }
  }

  _Point _endPoint(_End end, {required bool low}) {
    final node = end.node;
    if (node != null) return _Point(node.item, node.rank, _PointKind.node);
    final cluster = end.cluster!;
    return _Point(
      cluster.item,
      low ? cluster.maxRank : cluster.minRank,
      _PointKind.cluster,
    );
  }

  int _lowRank(_End end) => end.node?.rank ?? end.cluster!.maxRank;
  int _highRank(_End end) => end.node?.rank ?? end.cluster!.minRank;

  void _orientChains() {
    for (final chain in chains) {
      if (chain.selfLoop) {
        chain.points = [_endPoint(chain.from, low: true)];
        continue;
      }
      _End low = chain.from;
      _End high = chain.to;
      if (_lowRank(chain.from) < _highRank(chain.to)) {
        // Forward edge.
      } else if (_lowRank(chain.to) < _highRank(chain.from)) {
        chain.reversed = true;
        low = chain.to;
        high = chain.from;
      } else {
        chain.sameRank = true;
      }

      final first = _endPoint(low, low: true);
      final last = _endPoint(high, low: chain.sameRank);
      final points = <_Point>[first];
      final candidates = {...low.clusters, ...high.clusters};
      for (var r = first.rank + 1; r < last.rank; r++) {
        _Cluster? home;
        for (final cluster in candidates) {
          if (cluster.minRank <= r &&
              r <= cluster.maxRank &&
              (home == null || cluster.depth > home.depth)) {
            home = cluster;
          }
        }
        // Lanes go before nodes when nothing else tells them apart.
        final dummy = _DummyItem(chain, r, home, -1e6 + chain.index);
        levels[home]!.items.add(dummy);
        points.add(_Point(dummy, r, _PointKind.dummy));
      }
      points.add(last);
      chain.points = points;

      final dummies = points.where((p) => p.kind == _PointKind.dummy).toList();
      final label = chain.labelSize;
      if (label != null && dummies.isNotEmpty) {
        final dummy = dummies[(dummies.length - 1) ~/ 2].item as _DummyItem;
        dummy
          ..label = label
          ..crossSize = crossOf(label);
        chain.labelDummy = dummy;
      }

      if (chain.sameRank) {
        if (first.kind == _PointKind.node) {
          (first.item as _NodeItem).node.exits.add(_Hop(chain, first, last));
        }
        if (last.kind == _PointKind.node) {
          (last.item as _NodeItem).node.exits.add(_Hop(chain, last, first));
        }
      } else {
        if (first.kind == _PointKind.node) {
          (first.item as _NodeItem)
              .node
              .exits
              .add(_Hop(chain, first, points[1]));
        }
        if (last.kind == _PointKind.node) {
          (last.item as _NodeItem)
              .node
              .entries
              .add(_Hop(chain, last, points[points.length - 2]));
        }
      }
    }
  }

  /// The item representing [point] at the level of [cluster]: the point's
  /// own item, the block of the subgraph containing it, or `null` when the
  /// point is outside [cluster].
  _Item? _itemAt(_Point point, _Cluster? cluster) {
    if (point.item.container == cluster) return point.item;
    for (var c = point.item.container; c != null; c = c.parent) {
      if (c.parent == cluster) return c.item;
    }
    return null;
  }

  /// Cross offset of [point] from the start of [item], which is the point's
  /// own item or the block of a subgraph containing it.
  double _offsetIn(_Point point, _Item item) {
    var offset = point.offset;
    var current = point.item;
    while (current != item) {
      offset += current.pos;
      current = current.container!.item;
    }
    return offset;
  }

  // -- Levels ----------------------------------------------------------------

  void _layoutLevels() {
    final ordered = [...clusters]..sort((a, b) => b.depth.compareTo(a.depth));
    for (final cluster in ordered) {
      _layoutLevel(cluster.level);
    }
    _layoutLevel(levels[null]!);
  }

  void _layoutLevel(_Level level) {
    level.rows = List.generate(
      level.maxRank - level.minRank + 1,
      (_) => <_Item>[],
    );
    for (final item in level.items) {
      for (var r = item.minRank; r <= item.maxRank; r++) {
        level.row(r).add(item);
      }
    }

    for (final chain in chains) {
      if (chain.selfLoop || chain.sameRank) continue;
      final points = chain.points;
      for (var k = 0; k + 1 < points.length; k++) {
        final a = _itemAt(points[k], level.cluster);
        final b = _itemAt(points[k + 1], level.cluster);
        if (a == null || b == null || a == b) continue;
        // Long edges pull hard on their lanes so they run straight; nodes
        // give way instead, as in dagre's alignment priorities.
        final dummies = (points[k].kind == _PointKind.dummy ? 1 : 0) +
            (points[k + 1].kind == _PointKind.dummy ? 1 : 0);
        final weight = const [1.0, 8.0, 16.0][dummies];
        final conn = _Conn(a, points[k], b, points[k + 1], weight);
        level.conns.add(conn);
        level.connsOf.putIfAbsent(a, () => []).add(conn);
        level.connsOf.putIfAbsent(b, () => []).add(conn);
      }
    }

    _order(level);
    _assignPorts(level: level);
    _position(level);
    _finish(level);
  }

  // -- Ordering --------------------------------------------------------------

  double _fraction(_Item item, _Point point) => item is _BlockItem
      ? (_offsetIn(point, item) / math.max(item.crossSize, 1)).clamp(0.0, 1.0)
      : 0.5;

  void _order(_Level level) {
    for (final row in level.rows) {
      _stableSort(row, (item) => item.key);
    }
    _fixBlockOrder(level);
    if (level.rows.length < 2) return;

    var best = [
      for (final row in level.rows) [...row]
    ];
    var bestCrossings = _crossings(level);
    for (var iteration = 0; iteration < 8 && bestCrossings > 0; iteration++) {
      final down = iteration.isEven;
      if (down) {
        for (var r = level.minRank + 1; r <= level.maxRank; r++) {
          _sortRow(level, r, r - 1);
        }
      } else {
        for (var r = level.maxRank - 1; r >= level.minRank; r--) {
          _sortRow(level, r, r + 1);
        }
      }
      _fixBlockOrder(level);
      final crossings = _crossings(level);
      if (crossings < bestCrossings) {
        bestCrossings = crossings;
        best = [
          for (final row in level.rows) [...row]
        ];
      }
    }
    level.rows = best;
  }

  void _sortRow(_Level level, int rank, int adjacent) {
    final row = level.row(rank);
    final adjacentIndex = {
      for (final (i, item) in level.row(adjacent).indexed) item: i,
    };
    final barycenter = <_Item, double>{};
    for (final (i, item) in row.indexed) {
      // A block present in both rows is one rigid box: it keeps its place
      // relative to the adjacent row, so lanes passing beside it stay on
      // the same side instead of cutting through it.
      final spanned = adjacentIndex[item];
      if (spanned != null) {
        barycenter[item] = spanned + 0.5;
        continue;
      }
      var sum = 0.0;
      var count = 0;
      for (final conn in level.connsOf[item] ?? const <_Conn>[]) {
        final (own, other, otherPoint) = conn.a == item
            ? (conn.pa, conn.b, conn.pb)
            : (conn.pb, conn.a, conn.pa);
        if (own.rank != rank || otherPoint.rank != adjacent) continue;
        final index = adjacentIndex[other];
        if (index == null) continue;
        sum += index + _fraction(other, otherPoint);
        count++;
      }
      barycenter[item] = count > 0 ? sum / count : i + 0.5;
    }
    _stableSort(row, (item) => barycenter[item]!);
  }

  /// Subgraph blocks span several ranks, so their relative order has to be
  /// the same in every rank they share.
  void _fixBlockOrder(_Level level) {
    final blocks = level.items.whereType<_BlockItem>().toList();
    if (blocks.length < 2) return;
    final average = <_Item, double>{};
    for (final block in blocks) {
      var sum = 0.0;
      for (var r = block.minRank; r <= block.maxRank; r++) {
        final row = level.row(r);
        sum += row.indexOf(block) / math.max(row.length - 1, 1);
      }
      average[block] = sum / (block.maxRank - block.minRank + 1);
    }
    _stableSort(blocks, (block) => average[block]!);
    for (final row in level.rows) {
      final slots = [
        for (final (i, item) in row.indexed)
          if (item is _BlockItem) i,
      ];
      final inRow = blocks.where(row.contains).toList();
      for (final (k, slot) in slots.indexed) {
        row[slot] = inRow[k];
      }
    }
  }

  int _crossings(_Level level) {
    var total = 0;
    for (var r = level.minRank; r < level.maxRank; r++) {
      final upper = {for (final (i, it) in level.row(r).indexed) it: i};
      final lower = {for (final (i, it) in level.row(r + 1).indexed) it: i};
      final pairs = <(double, double)>[];
      for (final conn in level.conns) {
        final (top, topPoint, bottom, bottomPoint) = conn.pa.rank < conn.pb.rank
            ? (conn.a, conn.pa, conn.b, conn.pb)
            : (conn.b, conn.pb, conn.a, conn.pa);
        if (topPoint.rank != r || bottomPoint.rank != r + 1) continue;
        final u = upper[top];
        final v = lower[bottom];
        if (u == null || v == null) continue;
        pairs.add(
          (u + _fraction(top, topPoint), v + _fraction(bottom, bottomPoint)),
        );
      }
      for (var i = 0; i < pairs.length; i++) {
        for (var j = i + 1; j < pairs.length; j++) {
          if ((pairs[i].$1 - pairs[j].$1) * (pairs[i].$2 - pairs[j].$2) < 0) {
            total++;
          }
        }
      }
    }
    return total;
  }

  // -- Ports -----------------------------------------------------------------

  /// Spreads the edges leaving or entering the same side of a node so they
  /// do not overlap, ordered like their other ends to avoid crossings.
  ///
  /// Before positions are known ([level] given) the other ends are compared
  /// by their order in the node's level; afterwards by their real position.
  void _assignPorts({_Level? level, bool final_ = false}) {
    final targets = level == null
        ? nodes
        : level.items.whereType<_NodeItem>().map((item) => item.node);
    for (final node in targets) {
      for (final hops in [node.exits, node.entries]) {
        if (hops.isEmpty) continue;
        double estimate(_Hop hop) {
          final other = hop.other;
          if (final_) return other.item.abs + other.item.crossSize / 2;
          final item = _itemAt(other, level!.cluster);
          if (item == null) return 1000.0 + hop.chain.index;
          final index = level.row(other.rank).indexOf(item);
          return index + _fraction(item, other);
        }

        final sorted = [...hops];
        _stableSort(sorted, estimate);
        final span = switch (node.node.shape) {
          FlowNodeShape.rhombus ||
          FlowNodeShape.circle ||
          FlowNodeShape.doubleCircle =>
            node.item.crossSize * 0.35,
          _ => math.max(node.item.crossSize - 12, 0.0),
        };
        final count = sorted.length;
        final spacing = count > 1
            ? math.min(config.portSeparation, span / (count - 1))
            : 0.0;
        for (final (i, hop) in sorted.indexed) {
          hop.point.port = (i - (count - 1) / 2) * spacing;
        }
      }
    }
  }

  // -- Positions -------------------------------------------------------------

  double _separation(_Item a, _Item b) {
    final dummies = (a is _DummyItem ? 1 : 0) + (b is _DummyItem ? 1 : 0);
    if (dummies == 2 &&
        (a as _DummyItem).label == null &&
        (b as _DummyItem).label == null) {
      return config.edgeSeparation;
    }
    if (dummies > 0) return config.edgeNodeSeparation;
    return config.nodeSeparation;
  }

  void _position(_Level level) {
    if (level.items.isEmpty) return;

    // Consecutive items of every row form a DAG of "a before b" constraints.
    final successors = <_Item, List<(_Item, double)>>{};
    final inDegree = <_Item, int>{for (final item in level.items) item: 0};
    for (final row in level.rows) {
      for (var i = 0; i + 1 < row.length; i++) {
        final gap = row[i].crossSize + _separation(row[i], row[i + 1]);
        successors.putIfAbsent(row[i], () => []).add((row[i + 1], gap));
        inDegree[row[i + 1]] = inDegree[row[i + 1]]! + 1;
      }
    }
    final topological = <_Item>[];
    final queue = [
      for (final item in level.items)
        if (inDegree[item] == 0) item,
    ];
    while (queue.isNotEmpty) {
      final item = queue.removeAt(0);
      topological.add(item);
      for (final (next, _) in successors[item] ?? const <(_Item, double)>[]) {
        inDegree[next] = inDegree[next]! - 1;
        if (inDegree[next] == 0) queue.add(next);
      }
    }

    void legalize() {
      for (final item in topological) {
        for (final (next, gap)
            in successors[item] ?? const <(_Item, double)>[]) {
          next.pos = math.max(next.pos, item.pos + gap);
        }
      }
    }

    for (final item in level.items) {
      item.pos = 0;
    }
    legalize();

    const alternating = 12;
    const balanced = 6;
    for (var iteration = 0; iteration < alternating + balanced; iteration++) {
      final sweep = iteration >= alternating
          ? _Sweep.both
          : iteration.isEven
              ? _Sweep.down
              : _Sweep.up;
      // Blocks move first so the rows end up solved against their final
      // positions.
      _moveBlocks(level);
      legalize();
      final ranks = [for (var r = level.minRank; r <= level.maxRank; r++) r];
      for (final r in sweep == _Sweep.up ? ranks.reversed : ranks) {
        _solveRow(level, r, sweep);
      }
      legalize();
    }
  }

  /// The position [item] would like, given the items it connects to.
  (double?, double) _desire(_Level level, _Item item, _Sweep sweep) {
    var sum = 0.0;
    var weights = 0.0;
    for (final conn in level.connsOf[item] ?? const <_Conn>[]) {
      final (own, other, otherPoint) = conn.a == item
          ? (conn.pa, conn.b, conn.pb)
          : (conn.pb, conn.a, conn.pa);
      if (sweep == _Sweep.down && otherPoint.rank >= own.rank) continue;
      if (sweep == _Sweep.up && otherPoint.rank <= own.rank) continue;
      final target =
          other.pos + _offsetIn(otherPoint, other) - _offsetIn(own, item);
      sum += target * conn.weight;
      weights += conn.weight;
    }
    return weights > 0 ? (sum / weights, weights) : (null, 0);
  }

  /// Moves the items of one row towards their desired positions while
  /// keeping their order and spacing. Blocks act as fixed obstacles here.
  void _solveRow(_Level level, int rank, _Sweep sweep) {
    final row = level.row(rank);
    var segment = <_Item>[];
    _Item? previousBlock;

    void solve(_Item? nextBlock) {
      if (segment.isEmpty) return;
      final offsets = <double>[0];
      for (var i = 0; i + 1 < segment.length; i++) {
        offsets.add(
          offsets[i] +
              segment[i].crossSize +
              _separation(segment[i], segment[i + 1]),
        );
      }
      final targets = <double>[];
      final weights = <double>[];
      for (final (i, item) in segment.indexed) {
        final (desired, weight) = _desire(level, item, sweep);
        targets.add((desired ?? item.pos) - offsets[i]);
        weights.add(desired == null ? 0.01 : weight);
      }
      final values = _isotonic(targets, weights);

      var lower = double.negativeInfinity;
      final previous = previousBlock;
      if (previous != null) {
        lower = previous.pos +
            previous.crossSize +
            _separation(previous, segment.first);
      }
      var upper = double.infinity;
      if (nextBlock != null) {
        upper = nextBlock.pos -
            _separation(segment.last, nextBlock) -
            segment.last.crossSize -
            offsets.last;
      }
      for (final (i, item) in segment.indexed) {
        final value =
            lower > upper ? lower : values[i].clamp(lower, upper).toDouble();
        item.pos = value + offsets[i];
      }
    }

    for (final item in row) {
      if (item is _BlockItem) {
        solve(item);
        previousBlock = item;
        segment = [];
      } else {
        segment.add(item);
      }
    }
    solve(null);
  }

  void _moveBlocks(_Level level) {
    for (final block in level.items.whereType<_BlockItem>()) {
      final (desired, _) = _desire(level, block, _Sweep.both);
      if (desired == null) continue;
      var lower = double.negativeInfinity;
      var upper = double.infinity;
      for (var r = block.minRank; r <= block.maxRank; r++) {
        final row = level.row(r);
        final i = row.indexOf(block);
        if (i > 0) {
          final previous = row[i - 1];
          lower = math.max(
            lower,
            previous.pos + previous.crossSize + _separation(previous, block),
          );
        }
        if (i + 1 < row.length) {
          final next = row[i + 1];
          upper = math.min(
            upper,
            next.pos - _separation(block, next) - block.crossSize,
          );
        }
      }
      block.pos =
          lower > upper ? lower : desired.clamp(lower, upper).toDouble();
    }
  }

  /// Weighted L1 isotonic regression (pool adjacent violators with weighted
  /// medians): the non-decreasing sequence closest to [targets].
  ///
  /// Medians rather than means keep a heavy group (the lanes of a long
  /// edge) exactly where it wants to be while a light item that cannot get
  /// its way (a node blocked by its neighbours) is simply pushed aside.
  static List<double> _isotonic(List<double> targets, List<double> weights) {
    final pools = <List<(double, double)>>[];
    final values = <double>[];
    for (var i = 0; i < targets.length; i++) {
      pools.add([(targets[i], weights[i])]);
      values.add(targets[i]);
      while (values.length > 1 && values[values.length - 2] > values.last) {
        final merged = [...pools[pools.length - 2], ...pools.last];
        pools
          ..removeLast()
          ..removeLast()
          ..add(merged);
        values
          ..removeLast()
          ..removeLast()
          ..add(_weightedMedian(merged));
      }
    }
    return [
      for (final (i, pool) in pools.indexed)
        for (var k = 0; k < pool.length; k++) values[i],
    ];
  }

  static double _weightedMedian(List<(double, double)> entries) {
    final sorted = [...entries]..sort((a, b) => a.$1.compareTo(b.$1));
    final total = sorted.fold(0.0, (sum, entry) => sum + entry.$2);
    var cumulative = 0.0;
    for (var i = 0; i < sorted.length; i++) {
      cumulative += sorted[i].$2;
      if ((cumulative - total / 2).abs() < 1e-9 && i + 1 < sorted.length) {
        // Exactly half the weight on each side: any value in between is
        // optimal, take the middle to stay balanced.
        return (sorted[i].$1 + sorted[i + 1].$1) / 2;
      }
      if (cumulative > total / 2) return sorted[i].$1;
    }
    return sorted.last.$1;
  }

  /// Normalizes a level's positions and, for a subgraph, sizes its block.
  void _finish(_Level level) {
    final cluster = level.cluster;
    var top = 0.0;
    var bottom = 0.0;
    if (level.items.isNotEmpty) {
      top = level.items.map((item) => item.pos).reduce(math.min);
      bottom =
          level.items.map((item) => item.pos + item.crossSize).reduce(math.max);
    }
    if (cluster == null) {
      for (final item in level.items) {
        item.pos -= top;
      }
      return;
    }

    final hasTitle = cluster.titleSize != Size.zero;
    cluster.startPad = config.clusterPadding +
        (horizontal && hasTitle ? cluster.titleSize.height + titleBand : 0);
    cluster.endPad = config.clusterPadding;
    var size = cluster.startPad + (bottom - top) + cluster.endPad;
    var shift = cluster.startPad - top;
    if (!horizontal && hasTitle) {
      final titleWidth =
          cluster.titleSize.width + config.clusterTitleMarginX * 2;
      if (size < titleWidth) {
        shift += (titleWidth - size) / 2;
        size = titleWidth;
      }
    }
    for (final item in level.items) {
      item.pos += shift;
    }
    cluster.item.crossSize = size;
  }

  void _assignAbsolute(_Level level, double origin) {
    for (final item in level.items) {
      item.abs = origin + item.pos;
      if (item is _BlockItem) _assignAbsolute(item.cluster.level, item.abs);
    }
  }

  /// Lines a long edge's lanes up with the port it leaves from, so it runs
  /// straight for as long as its neighbours allow.
  void _straighten() {
    for (final chain in chains) {
      if (chain.selfLoop || chain.sameRank || chain.points.length < 3) {
        continue;
      }
      final points = chain.points;
      var moved = _align(points.sublist(1, points.length - 1), points.first);
      if (!moved) {
        _align(
          points.sublist(1, points.length - 1).reversed.toList(),
          points.last,
        );
      }
    }
  }

  bool _align(List<_Point> lanes, _Point anchor) {
    if (anchor.kind == _PointKind.cluster) return false;
    var cross = anchor.absCenter;
    var movedFirst = false;
    for (final (i, lane) in lanes.indexed) {
      final item = lane.item;
      final (lower, upper) = _laneBounds(item);
      final target = cross - item.crossSize / 2;
      if (target >= lower - 0.01 && target <= upper + 0.01) {
        item.abs = target;
        if (i == 0) movedFirst = true;
      } else {
        break;
      }
      cross = item.abs + item.crossSize / 2;
    }
    return movedFirst;
  }

  (double, double) _laneBounds(_Item item) {
    final level = levels[item.container]!;
    final row = level.row(item.minRank);
    final i = row.indexOf(item);
    var lower = double.negativeInfinity;
    var upper = double.infinity;
    if (i > 0) {
      final previous = row[i - 1];
      lower = previous.abs + previous.crossSize + _separation(previous, item);
    }
    if (i + 1 < row.length) {
      final next = row[i + 1];
      upper = next.abs - _separation(item, next) - item.crossSize;
    }
    final cluster = item.container;
    if (cluster != null) {
      lower = math.max(lower, cluster.item.abs + cluster.startPad);
      upper = math.min(
        upper,
        cluster.item.abs +
            cluster.item.crossSize -
            cluster.endPad -
            item.crossSize,
      );
    }
    return (lower, upper);
  }

  // -- Main axis and routing -------------------------------------------------

  /// Distance from a node's center to its outline along the main axis, at
  /// [cross] from its center across it.
  double _mainExtent(_Node node, double cross) {
    final halfMain = mainOf(node.size) / 2;
    final halfCross = crossOf(node.size) / 2;
    final ratio =
        halfCross == 0 ? 0.0 : (cross.abs() / halfCross).clamp(0.0, 1.0);
    switch (node.node.shape) {
      case FlowNodeShape.rhombus:
        return halfMain * (1 - ratio);
      case FlowNodeShape.circle:
      case FlowNodeShape.doubleCircle:
        return halfMain * math.sqrt(1 - ratio * ratio);
      case FlowNodeShape.stadium when horizontal:
        final radius = halfCross;
        final dy = cross.abs().clamp(0.0, radius);
        return halfMain - radius + math.sqrt(radius * radius - dy * dy);
      case FlowNodeShape.hexagon when horizontal:
        return halfMain - (halfCross / 2) * ratio;
      case FlowNodeShape.cylinder when !horizontal:
        final cap = config.cylinderCap;
        return halfMain - cap + cap * math.sqrt(1 - ratio * ratio);
      default:
        return halfMain;
    }
  }

  double _clampToBox(_Item block, double cross) {
    const margin = 8.0;
    final low = block.abs + margin;
    final high = block.abs + block.crossSize - margin;
    return low > high
        ? block.abs + block.crossSize / 2
        : cross.clamp(low, high);
  }

  double _pointCross(_Point point) => point.absCenter;

  FlowchartLayout _route() {
    // Cross positions where each segment leaves and enters its gap.
    final segments = <_Segment>[];
    final segmentsOf = <_Chain, List<_Segment>>{};
    for (final chain in chains) {
      if (chain.selfLoop) continue;
      final points = chain.points;
      final list = <_Segment>[];
      if (chain.sameRank) {
        final segment =
            _Segment(chain, points.first, points.last, points.first.rank)
              ..exitCross = _pointCross(points.first)
              ..entryCross = _pointCross(points.last);
        list.add(segment);
      } else {
        for (var k = 0; k + 1 < points.length; k++) {
          final from = points[k];
          final to = points[k + 1];
          final segment = _Segment(chain, from, to, from.rank);
          final fromCluster = from.kind == _PointKind.cluster;
          final toCluster = to.kind == _PointKind.cluster;
          if (fromCluster && toCluster) {
            final low = math.max(from.item.abs, to.item.abs);
            final high = math.min(
              from.item.abs + from.item.crossSize,
              to.item.abs + to.item.crossSize,
            );
            final shared = low <= high
                ? (low + high) / 2
                : to.item.abs + to.item.crossSize / 2;
            segment
              ..exitCross = _clampToBox(from.item, shared)
              ..entryCross = _clampToBox(to.item, shared);
          } else if (fromCluster) {
            segment.entryCross = _pointCross(to);
            segment.exitCross = _clampToBox(from.item, segment.entryCross);
          } else if (toCluster) {
            segment.exitCross = _pointCross(from);
            segment.entryCross = _clampToBox(to.item, segment.exitCross);
          } else {
            segment
              ..exitCross = _pointCross(from)
              ..entryCross = _pointCross(to);
          }
          list.add(segment);
        }
      }
      segmentsOf[chain] = list;
      segments.addAll(list);
    }

    // Tracks: per gap, upward segments first (highest exit first), then
    // downward ones (lowest exit first), which avoids crossings between
    // segments that fan out from the same area. Same-rank loops go last.
    final tracksOf = List.generate(maxRank + 1, (_) => <_Segment>[]);
    for (final segment in segments) {
      if (segment.needsTrack || segment.chain.sameRank) {
        tracksOf[segment.gap].add(segment);
      }
    }
    for (final list in tracksOf) {
      final up = list
          .where((s) => !s.chain.sameRank && s.entryCross < s.exitCross)
          .toList()
        ..sort((a, b) => a.exitCross.compareTo(b.exitCross));
      final down = list
          .where((s) => !s.chain.sameRank && s.entryCross > s.exitCross)
          .toList()
        ..sort((a, b) => b.exitCross.compareTo(a.exitCross));
      final loops = list.where((s) => s.chain.sameRank).toList();
      list
        ..clear()
        ..addAll([...up, ...down, ...loops]);
    }

    // Column extents along the main axis.
    final columnSize = List.filled(maxRank + 1, 0.0);
    for (final node in nodes) {
      columnSize[node.rank] =
          math.max(columnSize[node.rank], mainOf(node.size));
    }
    for (final chain in chains) {
      final dummy = chain.labelDummy;
      if (dummy != null) {
        columnSize[dummy.minRank] =
            math.max(columnSize[dummy.minRank], mainOf(dummy.label!));
      }
    }

    final titleOnOpen = chart.direction == FlowDirection.topDown;
    final titleOnClose = chart.direction == FlowDirection.bottomUp;
    double band(_Cluster c) =>
        c.titleSize == Size.zero ? 0 : c.titleSize.height + titleBand;
    for (final cluster in [...clusters]
      ..sort((a, b) => b.depth.compareTo(a.depth))) {
      for (final child in cluster.children) {
        if (child.minRank == cluster.minRank) {
          cluster.openDepth = math.max(cluster.openDepth, child.openDepth + 1);
        }
        if (child.maxRank == cluster.maxRank) {
          cluster.closeDepth =
              math.max(cluster.closeDepth, child.closeDepth + 1);
        }
      }
    }
    double openExtra(_Cluster c) =>
        config.clusterPadding * c.openDepth +
        (titleOnOpen ? band(c) * c.openDepth : 0);
    double closeExtra(_Cluster c) =>
        config.clusterPadding * c.closeDepth +
        (titleOnClose ? band(c) * c.closeDepth : 0);

    final columnStart = List.filled(maxRank + 1, 0.0);
    final columnEnd = List.filled(maxRank + 1, 0.0);
    var cursor = 0.0;
    for (var r = 0; r <= maxRank; r++) {
      var opening = 0.0;
      for (final cluster in clusters) {
        if (cluster.minRank == r) {
          opening = math.max(opening, openExtra(cluster));
        }
      }
      columnStart[r] = cursor + opening;
      columnEnd[r] = columnStart[r] + columnSize[r];
      for (final cluster in clusters) {
        if (cluster.minRank == r) {
          cluster.mainStart = columnStart[r] - openExtra(cluster);
        }
      }

      var channelStart = columnEnd[r];
      final closing = clusters.where((c) => c.maxRank == r).toList()
        ..sort((a, b) => a.closeDepth.compareTo(b.closeDepth));
      for (final cluster in closing) {
        var border = columnEnd[r] + closeExtra(cluster);
        for (final child in cluster.children) {
          if (child.maxRank == r) {
            border = math.max(
              border,
              child.mainEnd +
                  config.clusterPadding +
                  (titleOnClose ? band(cluster) : 0),
            );
          }
        }
        if (horizontal && cluster.titleSize != Size.zero) {
          border = math.max(
            border,
            cluster.mainStart +
                cluster.titleSize.width +
                config.clusterTitleMarginX * 2,
          );
        }
        cluster.mainEnd = border;
        channelStart = math.max(channelStart, border);
      }

      final tracks = tracksOf[r];
      final width = tracks.isEmpty
          ? config.rankSeparation
          : math.max(
              config.rankSeparation,
              (tracks.length - 1) * config.trackSeparation +
                  config.trackMargin * 2,
            );
      final center = channelStart + width / 2;
      for (final (i, segment) in tracks.indexed) {
        segment.track =
            center + (i - (tracks.length - 1) / 2) * config.trackSeparation;
      }
      cursor = r == maxRank ? channelStart : channelStart + width;
    }
    final totalMain = cursor;

    Offset toScreen(double main, double cross) {
      switch (chart.direction) {
        case FlowDirection.leftRight:
          return Offset(main, cross);
        case FlowDirection.rightLeft:
          return Offset(totalMain - main, cross);
        case FlowDirection.topDown:
          return Offset(cross, main);
        case FlowDirection.bottomUp:
          return Offset(cross, totalMain - main);
      }
    }

    Rect rectToScreen(
            double main, double cross, double mainSize, double crossSize) =>
        Rect.fromPoints(
          toScreen(main, cross),
          toScreen(main + mainSize, cross + crossSize),
        );

    double nodeMainCenter(_Node node) =>
        columnStart[node.rank] + columnSize[node.rank] / 2;

    final nodeRects = <String, Rect>{};
    for (final node in nodes) {
      final main = nodeMainCenter(node) - mainOf(node.size) / 2;
      nodeRects[node.node.id] = rectToScreen(
        main,
        node.item.abs,
        mainOf(node.size),
        node.item.crossSize,
      );
    }

    final clusterBoxes = <FlowClusterBox>[
      for (final cluster in [
        ...clusters
      ]..sort((a, b) => a.depth.compareTo(b.depth)))
        FlowClusterBox(
          subgraph: cluster.subgraph,
          rect: rectToScreen(
            cluster.mainStart,
            cluster.item.abs,
            cluster.mainEnd - cluster.mainStart,
            cluster.item.crossSize,
          ),
          depth: cluster.depth,
          index: cluster.index,
        ),
    ];

    // Where a point is left from (exit) or arrived at (entry).
    double exitMain(_Point point) {
      switch (point.kind) {
        case _PointKind.node:
          final node = (point.item as _NodeItem).node;
          return nodeMainCenter(node) + _mainExtent(node, point.port);
        case _PointKind.cluster:
          return (point.item as _BlockItem).cluster.mainEnd;
        case _PointKind.dummy:
          return columnEnd[point.rank];
      }
    }

    double entryMain(_Point point) {
      switch (point.kind) {
        case _PointKind.node:
          final node = (point.item as _NodeItem).node;
          return nodeMainCenter(node) - _mainExtent(node, point.port);
        case _PointKind.cluster:
          return (point.item as _BlockItem).cluster.mainStart;
        case _PointKind.dummy:
          return columnStart[point.rank];
      }
    }

    final routes = <FlowEdgeRoute>[];
    for (final chain in chains) {
      final abstract = <(double, double)>[];
      Rect? labelRect;
      if (chain.selfLoop) {
        final node = chain.from.node!;
        final top = node.item.abs;
        final center = nodeMainCenter(node);
        final halfMain = mainOf(node.size) / 2;
        abstract.addAll([
          (center + halfMain * 0.4, top),
          (center + halfMain * 0.4, top - 16),
          (center + halfMain + 16, top - 16),
          (center + halfMain + 16, top + node.item.crossSize / 2),
          (center + _mainExtent(node, 0), top + node.item.crossSize / 2),
        ]);
      } else if (chain.sameRank) {
        final segment = segmentsOf[chain]!.single;
        abstract.addAll([
          (exitMain(segment.from), segment.exitCross),
          (segment.track, segment.exitCross),
          (segment.track, segment.entryCross),
          (exitMain(segment.to), segment.entryCross),
        ]);
      } else {
        final list = segmentsOf[chain]!;
        // Follow the line's current cross position so segments that need
        // no track stay perfectly straight despite sub-pixel differences.
        var cross = list.first.exitCross;
        abstract.add((exitMain(list.first.from), cross));
        for (final segment in list) {
          var entry = cross;
          if (segment.needsTrack) {
            entry = segment.entryCross;
            abstract
              ..add((segment.track, cross))
              ..add((segment.track, entry));
          }
          abstract.add((entryMain(segment.to), entry));
          if (segment.to.kind == _PointKind.dummy) {
            abstract.add((exitMain(segment.to), entry));
          }
          cross = entry;
        }
        final dummy = chain.labelDummy;
        if (dummy != null) {
          final main =
              columnStart[dummy.minRank] + columnSize[dummy.minRank] / 2;
          final label = dummy.label!;
          labelRect = rectToScreen(
            main - mainOf(label) / 2,
            dummy.abs,
            mainOf(label),
            dummy.crossSize,
          );
        }
      }

      var points = [for (final (m, c) in abstract) toScreen(m, c)];
      if (chain.reversed) points = points.reversed.toList();
      points = _simplify(points);

      final labelSize = chain.labelSize;
      if (labelRect == null && labelSize != null && points.length > 1) {
        labelRect = Rect.fromCenter(
          center: _longestSegmentMiddle(points),
          width: labelSize.width,
          height: labelSize.height,
        );
      }
      routes.add(
        FlowEdgeRoute(edge: chain.edge, points: points, labelRect: labelRect),
      );
    }

    // Shift everything so the drawing starts at the padding.
    var bounds = Rect.zero;
    var first = true;
    void include(Rect rect) {
      bounds = first ? rect : bounds.expandToInclude(rect);
      first = false;
    }

    nodeRects.values.forEach(include);
    for (final box in clusterBoxes) {
      include(box.rect);
    }
    for (final route in routes) {
      for (final point in route.points) {
        include(Rect.fromLTWH(point.dx, point.dy, 0, 0));
      }
      if (route.labelRect != null) include(route.labelRect!);
    }
    final shift = Offset(
      config.diagramPadding - bounds.left,
      config.diagramPadding - bounds.top,
    );

    return FlowchartLayout(
      size: Size(
        bounds.width + config.diagramPadding * 2,
        bounds.height + config.diagramPadding * 2,
      ),
      nodeRects: {
        for (final entry in nodeRects.entries)
          entry.key: entry.value.shift(shift),
      },
      clusters: [
        for (final box in clusterBoxes)
          FlowClusterBox(
            subgraph: box.subgraph,
            rect: box.rect.shift(shift),
            depth: box.depth,
            index: box.index,
          ),
      ],
      edges: [
        for (final route in routes)
          FlowEdgeRoute(
            edge: route.edge,
            points: [for (final point in route.points) point + shift],
            labelRect: route.labelRect?.shift(shift),
          ),
      ],
    );
  }

  /// Drops repeated points and the middle of three collinear points.
  static List<Offset> _simplify(List<Offset> points) {
    final result = <Offset>[];
    for (final point in points) {
      if (result.isNotEmpty && (result.last - point).distance < 0.01) continue;
      if (result.length >= 2) {
        final a = result[result.length - 2];
        final b = result.last;
        final collinear =
            ((a.dx - b.dx).abs() < 0.01 && (b.dx - point.dx).abs() < 0.01) ||
                ((a.dy - b.dy).abs() < 0.01 && (b.dy - point.dy).abs() < 0.01);
        if (collinear) result.removeLast();
      }
      result.add(point);
    }
    return result;
  }

  static Offset _longestSegmentMiddle(List<Offset> points) {
    var best = 0;
    var bestLength = -1.0;
    for (var i = 0; i + 1 < points.length; i++) {
      final length = (points[i + 1] - points[i]).distance;
      if (length > bestLength) {
        bestLength = length;
        best = i;
      }
    }
    return (points[best] + points[best + 1]) / 2;
  }
}

/// Stable in-place sort by a numeric key (Dart's `List.sort` is not stable).
void _stableSort<T>(List<T> list, double Function(T) keyOf) {
  final keyed = [
    for (final (i, item) in list.indexed) (keyOf(item), i, item),
  ]..sort((a, b) {
      final byKey = a.$1.compareTo(b.$1);
      return byKey != 0 ? byKey : a.$2.compareTo(b.$2);
    });
  for (final (i, entry) in keyed.indexed) {
    list[i] = entry.$3;
  }
}
