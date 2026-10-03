// Regenerates the screenshots in doc/ used by the README and pub.dev:
//
//   flutter test tool/screenshots_test.dart
//
// Tests render with a placeholder font, so a real one is loaded first. The
// default path is Arial on macOS; set SCREENSHOT_FONT to use another file.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_flowchart/mermaid_flowchart.dart';

const _architecture = '''
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

const _decision = '''
flowchart TD
  A[Christmas] -->|Get money| B(Go shopping)
  B --> C{Let me think}
  C -->|One| D[Laptop]
  C -->|Two| E[iPhone]
  C -->|Three| F[Car]
''';

Future<void> _capture(
  WidgetTester tester,
  String source,
  String file, {
  Brightness brightness = Brightness.light,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: brightness, fontFamily: 'Screenshot'),
      home: Material(
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: MermaidFlowchart(source: source),
          ),
        ),
      ),
    ),
  );
  // MaterialApp animates theme changes.
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('doc/$file').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('screenshots', (tester) async {
    final font = Platform.environment['SCREENSHOT_FONT'] ??
        '/System/Library/Fonts/Supplemental/Arial.ttf';
    final bytes = File(font).readAsBytesSync();
    await (FontLoader('Screenshot')
          ..addFont(Future.value(ByteData.view(bytes.buffer))))
        .load();
    tester.view.physicalSize = const Size(3000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _capture(tester, _architecture, 'architecture_light.png');
    await _capture(
      tester,
      _architecture,
      'architecture_dark.png',
      brightness: Brightness.dark,
    );
    await _capture(tester, _decision, 'decision.png');
  });
}
