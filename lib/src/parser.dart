import 'dart:collection';

import 'model.dart';

/// Parses the Mermaid flowchart syntax (`flowchart` / `graph`) into a
/// [Flowchart].
///
/// Covers the syntax used in practice: every classic node shape, quoted and
/// Markdown labels with `<br/>`, all link styles (`-->`, `---`, `-.->`,
/// `==>`, `~~~`, `<-->`, `--o`, `--x`, longer links), labels in pipes or in
/// the middle of the link, `&` chaining, nested subgraphs, edges to and from
/// subgraphs, `classDef`, `class`, `:::`, `style` and `linkStyle`. Statements
/// it does not understand (`click`, accessibility metadata...) are skipped.
class FlowchartParser {
  /// Creates a parser. It holds no state and can be reused.
  const FlowchartParser();

  static final RegExp _header = RegExp(
    r'^(?:graph|flowchart(?:-elk)?)(?=\s|;|$)',
    caseSensitive: false,
  );

  /// Whether [source] declares a flowchart (`flowchart` or `graph`), after
  /// any front matter, `%%` comments and directives. Cheap: it only looks at
  /// the header, so other diagram types can be routed elsewhere.
  static bool isFlowchart(String source) {
    final lines = source
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('%%'))
        .toList();
    if (lines.isNotEmpty && lines.first == '---') {
      final close = lines.indexOf('---', 1);
      if (close > 0) lines.removeRange(0, close + 1);
    }
    return lines.isNotEmpty && _header.hasMatch(lines.first);
  }

  /// Parses [source]. Returns `null` when it is not a flowchart or declares
  /// no node. Statements that cannot be understood are skipped.
  Flowchart? parse(String source) => _FlowchartReader().read(source);
}

class _OpenSubgraph {
  _OpenSubgraph(this.id, this.title);

  final String id;
  final String title;

  /// Ids referenced by statements written directly inside the subgraph.
  final LinkedHashSet<String> referenced = LinkedHashSet();
}

class _Link {
  const _Link({
    required this.line,
    required this.startHead,
    required this.endHead,
    required this.length,
    this.label,
  });

  final FlowLineStyle line;
  final FlowArrowHead startHead;
  final FlowArrowHead endHead;
  final int length;
  final String? label;
}

class _Scanner {
  _Scanner(this.text);

  final String text;
  int index = 0;

  bool get done => index >= text.length;
  String get current => index < text.length ? text[index] : '';
  String at(int offset) {
    final i = index + offset;
    return i >= 0 && i < text.length ? text[i] : '';
  }

  bool startsWith(String pattern) => text.startsWith(pattern, index);

  void skipSpaces() {
    while (!done && (current == ' ' || current == '\t' || current == '\r')) {
      index++;
    }
  }
}

final RegExp _idChar = RegExp(r'[\p{L}\p{N}_$]', unicode: true);

bool _isIdChar(String char) => char.isNotEmpty && _idChar.hasMatch(char);

/// Node shape openers, longest first so `((` wins over `(`.
const List<(String, String, FlowNodeShape)> _shapes = [
  ('(((', ')))', FlowNodeShape.doubleCircle),
  ('((', '))', FlowNodeShape.circle),
  ('([', '])', FlowNodeShape.stadium),
  ('[[', ']]', FlowNodeShape.subroutine),
  ('[(', ')]', FlowNodeShape.cylinder),
  ('{{', '}}', FlowNodeShape.hexagon),
  ('[/', '/]', FlowNodeShape.parallelogram),
  ('[\\', '\\]', FlowNodeShape.parallelogramAlt),
  ('(', ')', FlowNodeShape.rounded),
  ('[', ']', FlowNodeShape.rectangle),
  ('{', '}', FlowNodeShape.rhombus),
  ('>', ']', FlowNodeShape.asymmetric),
];

/// `A@{ shape: ... }` names (Mermaid 11) mapped to the classic shapes.
const Map<String, FlowNodeShape> _namedShapes = {
  'rect': FlowNodeShape.rectangle,
  'rectangle': FlowNodeShape.rectangle,
  'proc': FlowNodeShape.rectangle,
  'process': FlowNodeShape.rectangle,
  'rounded': FlowNodeShape.rounded,
  'event': FlowNodeShape.rounded,
  'stadium': FlowNodeShape.stadium,
  'pill': FlowNodeShape.stadium,
  'terminal': FlowNodeShape.stadium,
  'subproc': FlowNodeShape.subroutine,
  'subroutine': FlowNodeShape.subroutine,
  'subprocess': FlowNodeShape.subroutine,
  'cyl': FlowNodeShape.cylinder,
  'cylinder': FlowNodeShape.cylinder,
  'db': FlowNodeShape.cylinder,
  'database': FlowNodeShape.cylinder,
  'circle': FlowNodeShape.circle,
  'circ': FlowNodeShape.circle,
  'dbl-circ': FlowNodeShape.doubleCircle,
  'double-circle': FlowNodeShape.doubleCircle,
  'diam': FlowNodeShape.rhombus,
  'diamond': FlowNodeShape.rhombus,
  'decision': FlowNodeShape.rhombus,
  'question': FlowNodeShape.rhombus,
  'hex': FlowNodeShape.hexagon,
  'hexagon': FlowNodeShape.hexagon,
  'prepare': FlowNodeShape.hexagon,
  'lean-r': FlowNodeShape.parallelogram,
  'lean-right': FlowNodeShape.parallelogram,
  'in-out': FlowNodeShape.parallelogram,
  'lean-l': FlowNodeShape.parallelogramAlt,
  'lean-left': FlowNodeShape.parallelogramAlt,
  'out-in': FlowNodeShape.parallelogramAlt,
  'trap-b': FlowNodeShape.trapezoid,
  'trapezoid': FlowNodeShape.trapezoid,
  'priority': FlowNodeShape.trapezoid,
  'trap-t': FlowNodeShape.trapezoidAlt,
  'inv-trapezoid': FlowNodeShape.trapezoidAlt,
  'manual': FlowNodeShape.trapezoidAlt,
  'odd': FlowNodeShape.asymmetric,
};

class _FlowchartReader {
  final Map<String, FlowNode> _nodes = {};
  final List<FlowEdge> _edges = [];
  final Map<String, FlowSubgraph> _subgraphs = {};
  final Map<String, FlowStyle> _classDefs = {};
  final List<_OpenSubgraph> _open = [];
  final Map<String, String> _owner = {};
  final Map<String, List<String>> _pendingClasses = {};
  final Map<String, FlowStyle> _pendingStyles = {};
  final Map<String, FlowStyle> _linkStyles = {};
  int _anonymousSubgraphs = 0;

  Flowchart? read(String source) {
    final lines = _stripComments(source);
    var first = 0;
    while (first < lines.length && lines[first].trim().isEmpty) {
      first++;
    }
    if (first == lines.length) return null;

    final header = RegExp(
      r'^(?:graph|flowchart(?:-elk)?)(?=\s|;|$)\s*(.*)$',
      caseSensitive: false,
    ).firstMatch(lines[first].trim());
    if (header == null) return null;

    var rest = header.group(1)!;
    var direction = FlowDirection.topDown;
    final directionMatch =
        RegExp(r'^(TB|TD|BT|RL|LR|[<>^v])(?=\s|;|$)', caseSensitive: false)
            .firstMatch(rest);
    if (directionMatch != null) {
      direction = _direction(directionMatch.group(1)!);
      rest = rest.substring(directionMatch.end);
    }

    final body = [rest, ...lines.skip(first + 1)].join('\n');
    for (final statement in _splitStatements(body)) {
      _statement(statement);
    }
    // Unclosed subgraphs are closed at the end, as Mermaid is lenient.
    while (_open.isNotEmpty) {
      _closeSubgraph();
    }

    _resolveSubgraphReferences();
    if (_nodes.isEmpty) return null;
    _applyStyles();

    return Flowchart(
      direction: direction,
      nodes: _nodes,
      edges: _edges,
      subgraphs: _subgraphs,
      classDefs: _classDefs,
    );
  }

  static FlowDirection _direction(String token) {
    switch (token.toUpperCase()) {
      case 'BT':
      case '^':
        return FlowDirection.bottomUp;
      case 'LR':
      case '>':
        return FlowDirection.leftRight;
      case 'RL':
      case '<':
        return FlowDirection.rightLeft;
      default:
        return FlowDirection.topDown;
    }
  }

  /// Drops YAML front matter, `%%` comments and `%%{init}%%` directives.
  static List<String> _stripComments(String source) {
    var lines = source.split('\n');
    final firstContent = lines.indexWhere((line) => line.trim().isNotEmpty);
    if (firstContent >= 0 && lines[firstContent].trim() == '---') {
      final close = lines.indexWhere(
        (line) => line.trim() == '---',
        firstContent + 1,
      );
      if (close > 0) lines = lines.sublist(close + 1);
    }

    return [
      for (final line in lines)
        if (line.trim().startsWith('%%')) '' else _cutComment(line),
    ];
  }

  static String _cutComment(String line) {
    var inQuote = false;
    for (var i = 0; i < line.length - 1; i++) {
      if (line[i] == '"') inQuote = !inQuote;
      if (!inQuote && line[i] == '%' && line[i + 1] == '%') {
        return line.substring(0, i);
      }
    }
    return line;
  }

  /// Splits on newlines and on `;` outside quotes and brackets. A `;` that
  /// ends an entity such as `#59;` or `&amp;` is kept.
  static List<String> _splitStatements(String body) {
    final statements = <String>[];
    final buffer = StringBuffer();
    var inQuote = false;
    var depth = 0;

    void flush() {
      final statement = buffer.toString().trim();
      if (statement.isNotEmpty) statements.add(statement);
      buffer.clear();
    }

    for (var i = 0; i < body.length; i++) {
      final char = body[i];
      if (char == '\n' && !inQuote) {
        flush();
        depth = 0;
        continue;
      }
      if (char == '"') {
        inQuote = !inQuote;
      } else if (!inQuote) {
        if ('[({'.contains(char)) depth++;
        if ('])}'.contains(char) && depth > 0) depth--;
        if (char == ';' &&
            depth == 0 &&
            !RegExp(r'[#&]#?\w+$').hasMatch(buffer.toString())) {
          flush();
          continue;
        }
      }
      buffer.write(char);
    }
    flush();
    return statements;
  }

  void _statement(String statement) {
    final keyword = RegExp(r'^(\w+)').firstMatch(statement)?.group(1);
    switch (keyword) {
      case 'subgraph':
        _openSubgraph(statement.substring('subgraph'.length).trim());
        return;
      case 'end':
        if (statement.trim() == 'end') {
          if (_open.isNotEmpty) _closeSubgraph();
          return;
        }
      case 'direction':
        // Per-subgraph directions are not supported; the chart's own wins.
        if (RegExp(r'^direction\s+\w+$').hasMatch(statement)) return;
      case 'click':
        if (RegExp(r'^click\s+\S+\s').hasMatch(statement)) return;
      case 'accTitle':
      case 'accDescr':
        if (RegExp(r'^acc(?:Title|Descr)\s*[:{]').hasMatch(statement)) return;
      case 'classDef':
        final match =
            RegExp(r'^classDef\s+(\S+)\s+(.*)$').firstMatch(statement);
        if (match != null) {
          final style = FlowStyle.parse(match.group(2)!);
          for (final name in match.group(1)!.split(',')) {
            _classDefs[name.trim()] = style;
          }
        }
        return;
      case 'class':
        final match = RegExp(r'^class\s+(\S+)\s+(\S+)').firstMatch(statement);
        if (match != null) {
          for (final id in match.group(1)!.split(',')) {
            _pendingClasses.putIfAbsent(id.trim(), () => []).add(
                  match.group(2)!,
                );
          }
        }
        return;
      case 'style':
        final match = RegExp(r'^style\s+(\S+)\s+(.*)$').firstMatch(statement);
        if (match != null) {
          final id = match.group(1)!;
          _pendingStyles[id] = (_pendingStyles[id] ?? const FlowStyle())
              .merge(FlowStyle.parse(match.group(2)!));
        }
        return;
      case 'linkStyle':
        final match =
            RegExp(r'^linkStyle\s+(\S+)\s+(.*)$').firstMatch(statement);
        if (match != null) {
          final style = FlowStyle.parse(match.group(2)!);
          for (final index in match.group(1)!.split(',')) {
            _linkStyles[index.trim()] = style;
          }
        }
        return;
    }
    _chain(statement);
  }

  void _openSubgraph(String header) {
    String id;
    String title;
    final withTitle =
        RegExp(r'^([^\s\[]+)\s*\[(.*)\]$', dotAll: true).firstMatch(header);
    if (withTitle != null) {
      id = withTitle.group(1)!;
      title = _decodeText(withTitle.group(2)!);
    } else if (header.startsWith('"')) {
      id = 'subgraph${_anonymousSubgraphs++}';
      title = _decodeText(header);
    } else {
      id = header.isEmpty ? 'subgraph${_anonymousSubgraphs++}' : header;
      title = _decodeText(header);
    }
    _open.add(_OpenSubgraph(id, title));
  }

  void _closeSubgraph() {
    final open = _open.removeLast();
    final subgraph = FlowSubgraph(open.id, open.title);
    for (final id in open.referenced) {
      final nested = _subgraphs[id];
      if (nested != null) {
        if (nested.parent == null && id != open.id) {
          nested.parent = open.id;
          subgraph.childIds.add(id);
        }
        continue;
      }
      // Like Mermaid, a node belongs to the first subgraph that closes
      // after referencing it: nested subgraphs claim their nodes first.
      if (!_owner.containsKey(id)) {
        _owner[id] = open.id;
        subgraph.nodeIds.add(id);
      }
    }
    _subgraphs[open.id] = subgraph;
    if (_open.isNotEmpty) _open.last.referenced.add(open.id);
  }

  /// Ids used as edge endpoints that name a subgraph point at the subgraph,
  /// not at a node, unless a node with that id was explicitly written.
  void _resolveSubgraphReferences() {
    for (final id in _subgraphs.keys) {
      final node = _nodes[id];
      if (node == null || node.isDefined) continue;
      _nodes.remove(id);
      final owner = _owner.remove(id);
      if (owner != null) _subgraphs[owner]?.nodeIds.remove(id);
    }
    for (final entry in _owner.entries) {
      _nodes[entry.key]?.subgraph = entry.value;
    }
  }

  void _applyStyles() {
    for (final entry in _pendingClasses.entries) {
      _nodes[entry.key]?.classes.addAll(entry.value);
      _subgraphs[entry.key]?.classes.addAll(entry.value);
    }
    for (final entry in _pendingStyles.entries) {
      final node = _nodes[entry.key];
      if (node != null) node.style = node.style.merge(entry.value);
      final subgraph = _subgraphs[entry.key];
      if (subgraph != null) {
        subgraph.style = subgraph.style.merge(entry.value);
      }
    }
    final defaultLinkStyle = _linkStyles['default'];
    for (var i = 0; i < _edges.length; i++) {
      var style = defaultLinkStyle ?? const FlowStyle();
      final own = _linkStyles['$i'];
      if (own != null) style = style.merge(own);
      _edges[i].style = style;
    }
  }

  /// A statement made of vertex groups joined by links:
  /// `A[x] & B --> C -.->|label| D`.
  void _chain(String statement) {
    final scanner = _Scanner(statement);
    var previous = _vertexGroup(scanner);
    if (previous.isEmpty) return;

    while (true) {
      final link = _link(scanner);
      if (link == null) return;
      final next = _vertexGroup(scanner);
      if (next.isEmpty) return;
      for (final from in previous) {
        for (final to in next) {
          _edges.add(
            FlowEdge(
              from: from,
              to: to,
              label: link.label,
              line: link.line,
              startHead: link.startHead,
              endHead: link.endHead,
              length: link.length,
            ),
          );
        }
      }
      previous = next;
    }
  }

  List<String> _vertexGroup(_Scanner scanner) {
    final ids = <String>[];
    while (true) {
      final id = _vertex(scanner);
      if (id == null) break;
      ids.add(id);
      scanner.skipSpaces();
      if (scanner.current != '&') break;
      scanner.index++;
    }
    return ids;
  }

  String? _vertex(_Scanner scanner) {
    scanner.skipSpaces();
    final start = scanner.index;
    while (!scanner.done) {
      final char = scanner.current;
      if (_isIdChar(char)) {
        scanner.index++;
        continue;
      }
      // `rag-service` or `api.v1` are ids, but `A-->B` and `A-.->B` are not.
      if ((char == '-' || char == '.') &&
          scanner.index > start &&
          _isIdChar(scanner.at(1))) {
        scanner.index++;
        continue;
      }
      break;
    }
    if (scanner.index == start) return null;
    final id = scanner.text.substring(start, scanner.index);

    String? text;
    FlowNodeShape? shape;
    if (scanner.startsWith('@{')) {
      final close = scanner.text.indexOf('}', scanner.index);
      if (close > 0) {
        final properties =
            _properties(scanner.text.substring(scanner.index + 2, close));
        text = properties['label'];
        shape = _namedShapes[properties['shape']?.toLowerCase()] ??
            FlowNodeShape.rectangle;
        scanner.index = close + 1;
      }
    } else {
      for (final (opener, closer, candidate) in _shapes) {
        if (!scanner.startsWith(opener)) continue;
        scanner.index += opener.length;
        final parsed = _shapeText(scanner, opener, closer, candidate);
        if (parsed != null) {
          (text, shape) = parsed;
        }
        break;
      }
    }

    final classes = <String>[];
    while (scanner.startsWith(':::')) {
      scanner.index += 3;
      final classStart = scanner.index;
      while (!scanner.done &&
          (_isIdChar(scanner.current) || scanner.current == '-')) {
        scanner.index++;
      }
      if (scanner.index > classStart) {
        classes.add(scanner.text.substring(classStart, scanner.index));
      }
    }

    final node = _nodes.putIfAbsent(id, () => FlowNode(id));
    if (text != null) {
      node.label = _decodeText(text);
      node.isDefined = true;
    }
    if (shape != null) {
      node.shape = shape;
      node.isDefined = true;
    }
    node.classes.addAll(classes);
    if (_open.isNotEmpty) _open.last.referenced.add(id);
    return id;
  }

  /// Reads a node's text up to the shape's closer. Trapezoids and
  /// parallelograms share openers and are told apart by the closer.
  (String, FlowNodeShape)? _shapeText(
    _Scanner scanner,
    String opener,
    String closer,
    FlowNodeShape shape,
  ) {
    final closers = <String, FlowNodeShape>{closer: shape};
    if (opener == '[/') closers['\\]'] = FlowNodeShape.trapezoid;
    if (opener == '[\\') closers['/]'] = FlowNodeShape.trapezoidAlt;

    final text = scanner.text;
    var searchFrom = scanner.index;
    String? quoted;
    var lookahead = scanner.index;
    while (lookahead < text.length && text[lookahead] == ' ') {
      lookahead++;
    }
    if (lookahead < text.length && text[lookahead] == '"') {
      final closeQuote = text.indexOf('"', lookahead + 1);
      if (closeQuote > 0) {
        quoted = text.substring(lookahead, closeQuote + 1);
        searchFrom = closeQuote + 1;
      }
    }

    var best = -1;
    String? bestCloser;
    for (final candidate in closers.keys) {
      final at = text.indexOf(candidate, searchFrom);
      if (at >= 0 && (best < 0 || at < best)) {
        best = at;
        bestCloser = candidate;
      }
    }
    if (best < 0) return null;

    final content = quoted ?? text.substring(scanner.index, best);
    scanner.index = best + bestCloser!.length;
    return (content, closers[bestCloser]!);
  }

  static Map<String, String> _properties(String body) {
    final properties = <String, String>{};
    for (final match
        in RegExp(r'(\w+)\s*:\s*("[^"]*"|[^,]+)').allMatches(body)) {
      var value = match.group(2)!.trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      properties[match.group(1)!] = value;
    }
    return properties;
  }

  _Link? _link(_Scanner scanner) {
    final save = scanner.index;
    scanner.skipSpaces();

    var startHead = FlowArrowHead.none;
    final first = scanner.current;
    if (first == '<') {
      startHead = FlowArrowHead.arrow;
      scanner.index++;
    } else if ((first == 'o' || first == 'x') &&
        '-=.'.contains(scanner.at(1)) &&
        scanner.at(1).isNotEmpty) {
      startHead = first == 'o' ? FlowArrowHead.circle : FlowArrowHead.cross;
      scanner.index++;
    }

    if (scanner.startsWith('~~~')) {
      while (scanner.current == '~') {
        scanner.index++;
      }
      return _withPipeLabel(
        scanner,
        const _Link(
          line: FlowLineStyle.invisible,
          startHead: FlowArrowHead.none,
          endHead: FlowArrowHead.none,
          length: 1,
        ),
      );
    }

    final bodyStart = scanner.index;
    while (!scanner.done && '-=.'.contains(scanner.current)) {
      scanner.index++;
    }
    final body = scanner.text.substring(bodyStart, scanner.index);
    if (!RegExp(r'^(?:-{2,}|={2,}|-\.+-?|\.+-)$').hasMatch(body)) {
      scanner.index = save;
      return null;
    }

    final thick = body.contains('=');
    final dotted = body.contains('.');
    final line = thick
        ? FlowLineStyle.thick
        : dotted
            ? FlowLineStyle.dotted
            : FlowLineStyle.solid;

    var endHead = _endHead(scanner);
    String? label;
    var length = _length(body, endHead != FlowArrowHead.none);

    final opensText = endHead == FlowArrowHead.none &&
        (body == '--' || body == '==' || body == '-.') &&
        (scanner.current == ' ' || scanner.current == '"');
    if (opensText) {
      // `A -- text --> B`, `A -. text .-> B`, `A == text ==> B`.
      final end = switch (body) {
        '==' => RegExp(r'={2,}[>ox]|={3,}'),
        '-.' => RegExp(r'-?\.+-[>ox]?'),
        _ => RegExp(r'-{2,}[>ox]|-{3,}'),
      };
      var searchFrom = scanner.index;
      final trimmed = scanner.text.substring(scanner.index).trimLeft();
      if (trimmed.startsWith('"')) {
        final quoteStart = scanner.text.indexOf('"', scanner.index);
        final quoteEnd = scanner.text.indexOf('"', quoteStart + 1);
        if (quoteEnd > 0) searchFrom = quoteEnd + 1;
      }
      final match = end.firstMatch(scanner.text.substring(searchFrom));
      if (match == null) {
        scanner.index = save;
        return null;
      }
      label = _decodeText(
        scanner.text.substring(scanner.index, searchFrom + match.start),
      );
      final token = match.group(0)!;
      endHead = switch (token[token.length - 1]) {
        '>' => FlowArrowHead.arrow,
        'o' => FlowArrowHead.circle,
        'x' => FlowArrowHead.cross,
        _ => FlowArrowHead.none,
      };
      final tokenBody = endHead == FlowArrowHead.none
          ? token
          : token.substring(0, token.length - 1);
      length = _length(tokenBody, endHead != FlowArrowHead.none);
      scanner.index = searchFrom + match.end;
    }

    return _withPipeLabel(
      scanner,
      _Link(
        line: line,
        startHead: startHead,
        endHead: endHead,
        length: length,
        label: label == null || label.isEmpty ? null : label,
      ),
    );
  }

  static FlowArrowHead _endHead(_Scanner scanner) {
    final char = scanner.current;
    if (char == '>') {
      scanner.index++;
      return FlowArrowHead.arrow;
    }
    // `--o B` is a circle head, but in `---oB` the `o` starts the node id.
    if ((char == 'o' || char == 'x') && !_isIdChar(scanner.at(1))) {
      scanner.index++;
      return char == 'o' ? FlowArrowHead.circle : FlowArrowHead.cross;
    }
    return FlowArrowHead.none;
  }

  /// Ranks spanned by a link body: `-->`/`---` span 1, `--->`/`----` 2...
  static int _length(String body, bool hasHead) {
    final dots = '.'.allMatches(body).length;
    if (dots > 0) return dots;
    final dashes = body.length;
    return (hasHead ? dashes - 1 : dashes - 2).clamp(1, 10);
  }

  _Link _withPipeLabel(_Scanner scanner, _Link link) {
    final save = scanner.index;
    scanner.skipSpaces();
    if (scanner.current == '|') {
      final close = scanner.text.indexOf('|', scanner.index + 1);
      if (close > 0) {
        final label =
            _decodeText(scanner.text.substring(scanner.index + 1, close));
        scanner.index = close + 1;
        return _Link(
          line: link.line,
          startHead: link.startHead,
          endHead: link.endHead,
          length: link.length,
          label: label.isEmpty ? null : label,
        );
      }
    }
    scanner.index = save;
    return link;
  }
}

/// Turns label source into display text: drops quotes and Markdown-string
/// backticks, turns `<br>` into line breaks, strips other HTML tags and
/// decodes Mermaid (`#quot;`) and HTML (`&amp;`) entities.
String _decodeText(String raw) {
  var text = raw.trim();
  if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
    text = text.substring(1, text.length - 1);
  }
  var markdown = false;
  if (text.length >= 2 && text.startsWith('`') && text.endsWith('`')) {
    text = text.substring(1, text.length - 1);
    markdown = true;
  }

  text = text
      .replaceAll(r'\"', '"')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</?[A-Za-z][^>]*>'), '')
      .replaceAll(RegExp(r'fa:fa-[\w-]+\s*'), '');
  if (markdown) text = text.replaceAll(RegExp(r'\*\*|__|\*'), '');

  text = text.replaceAllMapped(RegExp(r'[#&](#?)(\w+);'), (match) {
    final name = match.group(2)!;
    if (match.group(1)!.isNotEmpty || RegExp(r'^\d+$').hasMatch(name)) {
      final code = int.tryParse(name);
      return code == null ? match.group(0)! : String.fromCharCode(code);
    }
    return switch (name) {
      'quot' => '"',
      'amp' => '&',
      'lt' => '<',
      'gt' => '>',
      'nbsp' => ' ',
      'apos' => "'",
      _ => match.group(0)!,
    };
  });

  return text
      .split('\n')
      .map((line) => line.trim().replaceAll(RegExp(r'\s+'), ' '))
      .join('\n')
      .trim();
}
