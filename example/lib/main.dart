import 'package:flutter/material.dart';
import 'package:mermaid_flowchart/mermaid_flowchart.dart';

void main() => runApp(const ExampleApp());

/// Sample diagrams, from a quick decision chart to a full architecture.
const Map<String, String> samples = {
  'Architecture': '''
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
''',
  'Decision': '''
flowchart TD
  A[Christmas] -->|Get money| B(Go shopping)
  B --> C{Let me think}
  C -->|One| D[Laptop]
  C -->|Two| E[iPhone]
  C -->|Three| F[Car]
''',
  'Retry loop': '''
graph TD
  A[Request] --> B{Succeeded?}
  B -- Yes --> C[Done]
  B -- No --> D[Wait and retry]
  D --> B
''',
  'Nested subgraphs': '''
flowchart BT
  subgraph Cloud["Cloud"]
    subgraph VPC["Private network"]
      APP["App server"] --> DB[("Database")]
    end
    BUCKET[("Bucket")]
  end
  User((User)) --> APP
  APP --> BUCKET
''',
  'Shapes and links': '''
flowchart LR
  A[Rectangle] --> B(Rounded) --> C([Stadium])
  C -.-> D[[Subroutine]] ==> E[(Database)]
  E --o F((Circle)) --x G{Rhombus}
  G <--> H{{Hexagon}} -- text --> I[/Parallelogram/]
  I ~~~ J[\\Trapezoid/]
''',
  'Styles': '''
flowchart LR
  A:::warm --> B --> C
  B --> D
  classDef warm fill:#fde68a,stroke:#b45309,stroke-width:2px
  style C fill:#bfdbfe,stroke:#1d4ed8,color:#1e3a8a
  style D stroke-dasharray:4 3
  linkStyle 1 stroke:#dc2626,stroke-width:2px
''',
};

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  ThemeMode _mode = ThemeMode.light;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mermaid_flowchart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      themeMode: _mode,
      home: EditorPage(
        dark: _mode == ThemeMode.dark,
        onToggleDark: () => setState(() {
          _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
        }),
      ),
    );
  }
}

/// Edit Mermaid source on one side and see it rendered on the other.
class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.dark,
    required this.onToggleDark,
  });

  final bool dark;
  final VoidCallback onToggleDark;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  String _sample = samples.keys.first;
  late final TextEditingController _source =
      TextEditingController(text: samples[_sample]);

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  void _select(String? name) {
    if (name == null) return;
    setState(() {
      _sample = name;
      _source.text = samples[name]!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final editor = TextField(
      controller: _source,
      onChanged: (_) => setState(() {}),
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        hintText: 'flowchart LR\n  A --> B',
      ),
    );

    final preview = InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.all(200),
      minScale: 0.2,
      maxScale: 4,
      child: MermaidFlowchart(
        source: _source.text,
        errorBuilder: (context) => const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Not a flowchart (start with "flowchart" or "graph").'),
        ),
        onNodeTap: (node) => ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Tapped "${node.id}"'))),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('mermaid_flowchart'),
        actions: [
          DropdownButton<String>(
            value: _sample,
            underline: const SizedBox.shrink(),
            onChanged: _select,
            items: [
              for (final name in samples.keys)
                DropdownMenuItem(value: name, child: Text(name)),
            ],
          ),
          IconButton(
            tooltip: widget.dark ? 'Light theme' : 'Dark theme',
            icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleDark,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 900;
          final children = [
            Expanded(
              flex: 2,
              child: Padding(padding: const EdgeInsets.all(12), child: editor),
            ),
            Expanded(flex: 3, child: ClipRect(child: preview)),
          ];
          return wide ? Row(children: children) : Column(children: children);
        },
      ),
    );
  }
}
