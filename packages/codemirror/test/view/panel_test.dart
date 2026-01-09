import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codemirror/src/state/facet.dart' hide EditorState, Transaction;
import 'package:codemirror/src/state/state.dart';
import 'package:codemirror/src/view/panel.dart';
import 'package:codemirror/src/view/view_update.dart';

// Test panel implementation
class TestPanel extends Panel {
  final String label;
  final bool _top;
  bool mounted = false;
  bool destroyed = false;
  int updateCount = 0;

  TestPanel(this.label, {bool top = false}) : _top = top;

  @override
  Widget build(BuildContext context) => Text(label);

  @override
  bool get top => _top;

  @override
  void mount() {
    mounted = true;
  }

  @override
  void update(ViewUpdate update) {
    updateCount++;
  }

  @override
  void destroy() {
    destroyed = true;
  }
}

void main() {
  group('PanelConfig', () {
    test('has null defaults', () {
      const config = PanelConfig();
      expect(config.topContainerKey, isNull);
      expect(config.bottomContainerKey, isNull);
    });

    test('stores container keys', () {
      final topKey = GlobalKey();
      final bottomKey = GlobalKey();
      
      final config = PanelConfig(
        topContainerKey: topKey,
        bottomContainerKey: bottomKey,
      );
      
      expect(config.topContainerKey, topKey);
      expect(config.bottomContainerKey, bottomKey);
    });
  });

  group('SimplePanel', () {
    test('creates panel from builder', () {
      final panel = SimplePanel(
        builder: (_) => const Text('Test'),
      );
      
      expect(panel.top, isFalse);
    });

    test('respects top parameter', () {
      final topPanel = SimplePanel(
        builder: (_) => const Text('Test'),
        top: true,
      );
      
      expect(topPanel.top, isTrue);
    });

    test('calls lifecycle callbacks', () {
      bool mounted = false;
      bool destroyed = false;
      
      final panel = SimplePanel(
        builder: (_) => const Text('Test'),
        onMount: () => mounted = true,
        onDestroy: () => destroyed = true,
      );
      
      panel.mount();
      expect(mounted, isTrue);
      
      panel.destroy();
      expect(destroyed, isTrue);
    });
  });

  group('panels extension', () {
    test('creates extension without config', () {
      final ext = panels();
      expect(ext, isA<Extension>());
    });

    test('creates extension with config', () {
      final ext = panels(PanelConfig(topContainerKey: GlobalKey()));
      expect(ext, isA<Extension>());
    });
  });

  group('showPanel facet', () {
    test('collects panel constructors', () {
      Panel constructor1(EditorState state) => TestPanel('panel1');
      Panel constructor2(EditorState state) => TestPanel('panel2');
      
      final state = EditorState.create(EditorStateConfig(
        extensions: ExtensionList([
          showPanel.of(constructor1),
          showPanel.of(constructor2),
        ]),
      ));
      
      final panels = state.facet(showPanel);
      expect(panels.whereType<PanelConstructor>(), hasLength(2));
    });

    test('allows null values', () {
      final state = EditorState.create(EditorStateConfig(
        extensions: ExtensionList([
          showPanel.of(null),
          showPanel.of((s) => TestPanel('test')),
        ]),
      ));
      
      final panels = state.facet(showPanel);
      // One null, one constructor
      expect(panels.where((p) => p != null), hasLength(1));
    });
  });

  group('Panel', () {
    test('has default implementations', () {
      final panel = TestPanel('test');
      
      // Should not throw
      panel.mount();
      panel.destroy();
      
      expect(panel.top, isFalse);
    });
  });

  group('PanelView', () {
    testWidgets('renders child when no panels', (tester) async {
      final state = EditorState.create(const EditorStateConfig(
        doc: 'Test',
      ));
      
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PanelView(
            state: state,
            child: const Text('Editor'),
          ),
        ),
      );
      
      expect(find.text('Editor'), findsOneWidget);
    });
  });

  group('PanelContainer', () {
    testWidgets('wraps child', (tester) async {
      final state = EditorState.create(const EditorStateConfig(
        doc: 'Test',
      ));
      
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PanelContainer(
            state: state,
            top: true,
            child: const Text('Content'),
          ),
        ),
      );
      
      expect(find.text('Content'), findsOneWidget);
    });
  });
}
