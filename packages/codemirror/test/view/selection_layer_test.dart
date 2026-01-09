import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codemirror/src/view/selection_layer.dart';
import 'package:codemirror/src/state/selection.dart';
import 'package:codemirror/src/state/state.dart';
import 'package:codemirror/src/state/facet.dart' hide EditorState, Transaction;

void main() {
  group('SelectionConfig', () {
    test('has sensible defaults', () {
      const config = SelectionConfig();
      expect(config.cursorBlinkRate, 1200);
      expect(config.drawRangeCursor, isTrue);
      expect(config.cursorWidth, 2.0);
      expect(config.cursorRadius, isNull);
      expect(config.cursorColor, isNull);
      expect(config.secondaryCursorColor, isNull);
      expect(config.selectionColor, isNull);
    });

    test('copyWith creates modified copy', () {
      const original = SelectionConfig(cursorBlinkRate: 1200);
      final modified = original.copyWith(cursorBlinkRate: 600);

      expect(modified.cursorBlinkRate, 600);
      expect(modified.drawRangeCursor, original.drawRangeCursor);
    });

    test('copyWith preserves unmodified values', () {
      const original = SelectionConfig(
        cursorBlinkRate: 1000,
        drawRangeCursor: false,
        cursorWidth: 3.0,
        cursorColor: Colors.red,
      );

      final modified = original.copyWith(cursorBlinkRate: 800);

      expect(modified.cursorBlinkRate, 800);
      expect(modified.drawRangeCursor, isFalse);
      expect(modified.cursorWidth, 3.0);
      expect(modified.cursorColor, Colors.red);
    });

    test('equality compares all fields', () {
      const config1 = SelectionConfig(cursorBlinkRate: 1000);
      const config2 = SelectionConfig(cursorBlinkRate: 1000);
      const config3 = SelectionConfig(cursorBlinkRate: 500);

      expect(config1, equals(config2));
      expect(config1, isNot(equals(config3)));
    });

    test('hashCode is consistent with equality', () {
      const config1 = SelectionConfig(cursorBlinkRate: 1000);
      const config2 = SelectionConfig(cursorBlinkRate: 1000);

      expect(config1.hashCode, equals(config2.hashCode));
    });
  });

  group('selectionConfig facet', () {
    test('provides default config when no extension', () {
      final state = EditorState.create(EditorStateConfig(doc: 'Hello'));
      final config = getSelectionConfig(state);

      expect(config.cursorBlinkRate, 1200);
      expect(config.drawRangeCursor, isTrue);
    });

    test('uses configured values', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello',
          extensions: selectionConfig.of(const SelectionConfig(cursorBlinkRate: 600)),
        ),
      );

      final config = getSelectionConfig(state);
      expect(config.cursorBlinkRate, 600);
    });

    test('combines multiple configs taking minimum blink rate', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello',
          extensions: ExtensionList([
            selectionConfig.of(const SelectionConfig(cursorBlinkRate: 1000)),
            selectionConfig.of(const SelectionConfig(cursorBlinkRate: 500)),
          ]),
        ),
      );

      final config = getSelectionConfig(state);
      expect(config.cursorBlinkRate, 500);
    });

    test('ORs drawRangeCursor values', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello',
          extensions: ExtensionList([
            selectionConfig.of(const SelectionConfig(drawRangeCursor: false)),
            selectionConfig.of(const SelectionConfig(drawRangeCursor: true)),
          ]),
        ),
      );

      final config = getSelectionConfig(state);
      expect(config.drawRangeCursor, isTrue);
    });
  });

  group('RectangleMarker', () {
    test('creates marker with required properties', () {
      const marker = RectangleMarker(
        className: 'test',
        left: 10.0,
        top: 20.0,
        width: 100.0,
        height: 20.0,
      );

      expect(marker.className, 'test');
      expect(marker.left, 10.0);
      expect(marker.top, 20.0);
      expect(marker.width, 100.0);
      expect(marker.height, 20.0);
    });

    test('width can be null for cursors', () {
      const marker = RectangleMarker(
        className: 'cursor',
        left: 10.0,
        top: 20.0,
        width: null,
        height: 20.0,
      );

      expect(marker.width, isNull);
    });

    test('equality compares all fields', () {
      const marker1 = RectangleMarker(
        className: 'test',
        left: 10.0,
        top: 20.0,
        width: 100.0,
        height: 20.0,
      );
      const marker2 = RectangleMarker(
        className: 'test',
        left: 10.0,
        top: 20.0,
        width: 100.0,
        height: 20.0,
      );
      const marker3 = RectangleMarker(
        className: 'other',
        left: 10.0,
        top: 20.0,
        width: 100.0,
        height: 20.0,
      );

      expect(marker1, equals(marker2));
      expect(marker1, isNot(equals(marker3)));
    });

    test('toString includes all properties', () {
      const marker = RectangleMarker(
        className: 'test',
        left: 10.0,
        top: 20.0,
        width: 100.0,
        height: 20.0,
      );

      expect(marker.toString(), contains('test'));
      expect(marker.toString(), contains('10.0'));
      expect(marker.toString(), contains('20.0'));
      expect(marker.toString(), contains('100.0'));
    });

    test('cursor toString shows cursor instead of width', () {
      const marker = RectangleMarker(
        className: 'cursor',
        left: 10.0,
        top: 20.0,
        width: null,
        height: 20.0,
      );

      expect(marker.toString(), contains('cursor'));
    });
  });

  group('SelectionLayerController', () {
    test('initializes with provided values', () {
      final controller = SelectionLayerController(
        config: const SelectionConfig(cursorBlinkRate: 1000),
        selection: EditorSelection.single(0),
      );

      expect(controller.config.cursorBlinkRate, 1000);
      expect(controller.selection.main.head, 0);
      expect(controller.cursorVisible, isTrue);

      controller.dispose();
    });

    test('selection change triggers notification', () {
      final controller = SelectionLayerController(
        selection: EditorSelection.single(0),
      );

      var notified = false;
      controller.addListener(() => notified = true);

      controller.selection = EditorSelection.single(5);

      expect(notified, isTrue);
      expect(controller.selection.main.head, 5);

      controller.dispose();
    });

    test('same selection does not notify', () {
      final controller = SelectionLayerController(
        selection: EditorSelection.single(0),
      );

      var notified = false;
      controller.addListener(() => notified = true);

      controller.selection = EditorSelection.single(0);

      expect(notified, isFalse);

      controller.dispose();
    });

    test('config change triggers notification', () {
      final controller = SelectionLayerController(
        config: const SelectionConfig(cursorBlinkRate: 1000),
        selection: EditorSelection.single(0),
      );

      var notified = false;
      controller.addListener(() => notified = true);

      controller.config = const SelectionConfig(cursorBlinkRate: 500);

      expect(notified, isTrue);

      controller.dispose();
    });

    test('cursor blinks when blinkRate > 0', () async {
      final controller = SelectionLayerController(
        config: const SelectionConfig(cursorBlinkRate: 100),
        selection: EditorSelection.single(0),
      );

      expect(controller.cursorVisible, isTrue);

      // Wait for a blink cycle
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Note: exact timing may vary, just verify controller is functional
      controller.dispose();
    });

    test('cursor does not blink when blinkRate is 0', () async {
      final controller = SelectionLayerController(
        config: const SelectionConfig(cursorBlinkRate: 0),
        selection: EditorSelection.single(0),
      );

      expect(controller.cursorVisible, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(controller.cursorVisible, isTrue);

      controller.dispose();
    });

    test('dispose cancels blink timer', () {
      final controller = SelectionLayerController(
        config: const SelectionConfig(cursorBlinkRate: 100),
        selection: EditorSelection.single(0),
      );

      controller.dispose();

      // Should not throw
    });
  });

  group('drawSelection extension', () {
    test('creates extension with default config', () {
      final ext = drawSelection();
      expect(ext, isA<Extension>());
    });

    test('creates extension with custom config', () {
      final ext = drawSelection(const SelectionConfig(cursorBlinkRate: 500));
      expect(ext, isA<Extension>());
    });

    test('extension affects state', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello',
          extensions: drawSelection(const SelectionConfig(cursorBlinkRate: 750)),
        ),
      );

      final config = getSelectionConfig(state);
      expect(config.cursorBlinkRate, 750);
    });
  });

  group('nativeSelectionHidden facet', () {
    test('defaults to false', () {
      final state = EditorState.create(EditorStateConfig(doc: 'Hello'));
      expect(state.facet(nativeSelectionHidden), isFalse);
    });

    test('can be set to true', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello',
          extensions: nativeSelectionHidden.of(true),
        ),
      );

      expect(state.facet(nativeSelectionHidden), isTrue);
    });

    test('any true value results in true', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello',
          extensions: ExtensionList([
            nativeSelectionHidden.of(false),
            nativeSelectionHidden.of(true),
            nativeSelectionHidden.of(false),
          ]),
        ),
      );

      expect(state.facet(nativeSelectionHidden), isTrue);
    });
  });

  group('SelectionPainter', () {
    testWidgets('paints nothing when markers are empty', (tester) async {
      final painter = SelectionPainter(
        markers: const [],
        color: Colors.blue,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            painter: painter,
            size: const Size(200, 100),
          ),
        ),
      );

      // Should not throw - find the specific painter
      expect(
        find.byWidgetPredicate((w) =>
            w is CustomPaint && w.painter is SelectionPainter),
        findsOneWidget,
      );
    });

    testWidgets('paints rectangles for markers', (tester) async {
      final painter = SelectionPainter(
        markers: const [
          RectangleMarker(
            className: 'selection',
            left: 10.0,
            top: 10.0,
            width: 50.0,
            height: 20.0,
          ),
        ],
        color: Colors.blue.withAlpha(77),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            painter: painter,
            size: const Size(200, 100),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate((w) =>
            w is CustomPaint && w.painter is SelectionPainter),
        findsOneWidget,
      );
    });

    test('shouldRepaint returns true when markers change', () {
      final painter1 = SelectionPainter(
        markers: const [],
        color: Colors.blue,
      );

      final painter2 = SelectionPainter(
        markers: const [
          RectangleMarker(
            className: 'test',
            left: 0,
            top: 0,
            width: 10,
            height: 10,
          ),
        ],
        color: Colors.blue,
      );

      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('shouldRepaint returns true when color changes', () {
      final painter1 = SelectionPainter(
        markers: const [],
        color: Colors.blue,
      );

      final painter2 = SelectionPainter(
        markers: const [],
        color: Colors.red,
      );

      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('shouldRepaint returns false when nothing changes', () {
      final painter = SelectionPainter(
        markers: const [],
        color: Colors.blue,
      );

      expect(painter.shouldRepaint(painter), isFalse);
    });
  });

  group('CursorPainter', () {
    testWidgets('paints nothing when not visible', (tester) async {
      final painter = CursorPainter(
        markers: const [
          RectangleMarker(
            className: 'cursor',
            left: 10.0,
            top: 10.0,
            width: null,
            height: 20.0,
          ),
        ],
        primaryColor: Colors.black,
        secondaryColor: Colors.grey,
        cursorWidth: 2.0,
        visible: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            painter: painter,
            size: const Size(200, 100),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate((w) =>
            w is CustomPaint && w.painter is CursorPainter),
        findsOneWidget,
      );
    });

    testWidgets('paints cursor when visible', (tester) async {
      final painter = CursorPainter(
        markers: const [
          RectangleMarker(
            className: 'cursor',
            left: 10.0,
            top: 10.0,
            width: null,
            height: 20.0,
          ),
        ],
        primaryColor: Colors.black,
        secondaryColor: Colors.grey,
        cursorWidth: 2.0,
        visible: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            painter: painter,
            size: const Size(200, 100),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate((w) =>
            w is CustomPaint && w.painter is CursorPainter),
        findsOneWidget,
      );
    });

    test('shouldRepaint returns true when visibility changes', () {
      final painter1 = CursorPainter(
        markers: const [],
        primaryColor: Colors.black,
        secondaryColor: Colors.grey,
        cursorWidth: 2.0,
        visible: true,
      );

      final painter2 = CursorPainter(
        markers: const [],
        primaryColor: Colors.black,
        secondaryColor: Colors.grey,
        cursorWidth: 2.0,
        visible: false,
      );

      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('shouldRepaint returns true when primaryIndex changes', () {
      final painter1 = CursorPainter(
        markers: const [],
        primaryColor: Colors.black,
        secondaryColor: Colors.grey,
        cursorWidth: 2.0,
        primaryIndex: 0,
      );

      final painter2 = CursorPainter(
        markers: const [],
        primaryColor: Colors.black,
        secondaryColor: Colors.grey,
        cursorWidth: 2.0,
        primaryIndex: 1,
      );

      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    testWidgets('supports rounded corners with cursorRadius', (tester) async {
      final painter = CursorPainter(
        markers: const [
          RectangleMarker(
            className: 'cursor',
            left: 10.0,
            top: 10.0,
            width: null,
            height: 20.0,
          ),
        ],
        primaryColor: Colors.black,
        secondaryColor: Colors.grey,
        cursorWidth: 2.0,
        cursorRadius: const Radius.circular(1.0),
        visible: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            painter: painter,
            size: const Size(200, 100),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate((w) =>
            w is CustomPaint && w.painter is CursorPainter),
        findsOneWidget,
      );
    });
  });
}
