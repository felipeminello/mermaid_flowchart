import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_flowchart/mermaid_flowchart.dart';
import 'package:mermaid_flowchart_example/main.dart';

void main() {
  testWidgets('every sample renders without errors', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ExampleApp());
    for (final name in samples.keys) {
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: name);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is FlowchartPainter,
        ),
        findsOneWidget,
        reason: name,
      );
    }
  });
}
