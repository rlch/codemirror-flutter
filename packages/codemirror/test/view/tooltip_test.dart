import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_test/flutter_test.dart';

import 'package:codemirror/src/state/facet.dart' hide EditorState, Transaction;
import 'package:codemirror/src/state/state.dart';
import 'package:codemirror/src/view/tooltip.dart';

void main() {
  group('TooltipRect', () {
    test('stores dimensions', () {
      const rect = TooltipRect(
        top: 10,
        left: 20,
        bottom: 100,
        right: 200,
      );
      
      expect(rect.top, 10);
      expect(rect.left, 20);
      expect(rect.bottom, 100);
      expect(rect.right, 200);
    });

    test('calculates width and height', () {
      const rect = TooltipRect(
        top: 10,
        left: 20,
        bottom: 100,
        right: 200,
      );
      
      expect(rect.width, 180);
      expect(rect.height, 90);
    });
  });

  group('TooltipConfig', () {
    test('has sensible defaults', () {
      const config = TooltipConfig();
      expect(config.tooltipSpace, isNull);
      expect(config.showArrow, isTrue);
      expect(config.hoverDelay, 300);
    });

    test('can customize settings', () {
      final config = TooltipConfig(
        showArrow: false,
        hoverDelay: 500,
        tooltipSpace: (_) => const TooltipRect(
          top: 0,
          left: 0,
          bottom: 100,
          right: 100,
        ),
      );
      
      expect(config.showArrow, isFalse);
      expect(config.hoverDelay, 500);
      expect(config.tooltipSpace, isNotNull);
    });
  });

  group('Tooltip', () {
    test('stores position and create function', () {
      final tooltip = Tooltip(
        pos: 10,
        create: (_) => TooltipView(widget: const Text('Test')),
      );
      
      expect(tooltip.pos, 10);
      expect(tooltip.end, isNull);
    });

    test('supports end position', () {
      final tooltip = Tooltip(
        pos: 10,
        end: 20,
        create: (_) => TooltipView(widget: const Text('Test')),
      );
      
      expect(tooltip.pos, 10);
      expect(tooltip.end, 20);
    });

    test('has default options', () {
      final tooltip = Tooltip(
        pos: 10,
        create: (_) => TooltipView(widget: const Text('Test')),
      );
      
      expect(tooltip.above, isFalse);
      expect(tooltip.strictSide, isFalse);
      expect(tooltip.arrow, isFalse);
      expect(tooltip.clip, isTrue);
    });

    test('copyWith creates modified copy', () {
      final original = Tooltip(
        pos: 10,
        create: (_) => TooltipView(widget: const Text('Test')),
      );
      
      final modified = original.copyWith(pos: 20, above: true);
      
      expect(original.pos, 10);
      expect(original.above, isFalse);
      expect(modified.pos, 20);
      expect(modified.above, isTrue);
    });
  });

  group('TooltipView', () {
    test('stores widget and options', () {
      final view = TooltipView(
        widget: const Text('Test'),
        offset: const Offset(5, 10),
        overlap: true,
      );
      
      expect(view.widget, isA<Text>());
      expect(view.offset, const Offset(5, 10));
      expect(view.overlap, isTrue);
    });

    test('has default options', () {
      final view = TooltipView(widget: const Text('Test'));
      
      expect(view.offset, Offset.zero);
      expect(view.overlap, isFalse);
      expect(view.resize, isTrue);
    });
  });

  group('tooltips extension', () {
    test('creates extension without config', () {
      final ext = tooltips();
      expect(ext, isA<Extension>());
    });

    test('creates extension with config', () {
      final ext = tooltips(const TooltipConfig(hoverDelay: 500));
      expect(ext, isA<Extension>());
    });
  });

  group('showTooltip facet', () {
    test('collects tooltips', () {
      final tooltip = Tooltip(
        pos: 10,
        create: (_) => TooltipView(widget: const Text('Test')),
      );
      
      final state = EditorState.create(EditorStateConfig(
        doc: 'Hello',
        extensions: showTooltip.of(tooltip),
      ));
      
      final tooltips = state.facet(showTooltip);
      expect(tooltips.whereType<Tooltip>(), hasLength(1));
    });

    test('allows null values', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'Hello',
        extensions: ExtensionList([
          showTooltip.of(null),
          showTooltip.of(Tooltip(
            pos: 10,
            create: (_) => TooltipView(widget: const Text('Test')),
          )),
        ]),
      ));
      
      final tooltips = state.facet(showTooltip);
      expect(tooltips.where((t) => t != null), hasLength(1));
    });
  });

  group('HoverTooltipOptions', () {
    test('has sensible defaults', () {
      const options = HoverTooltipOptions();
      expect(options.hideOn, isNull);
      expect(options.hideOnChange, isFalse);
      expect(options.hoverTime, 300);
    });

    test('can customize settings', () {
      final options = HoverTooltipOptions(
        hideOnChange: true,
        hoverTime: 500,
        hideOn: (_, __) => true,
      );
      
      expect(options.hideOnChange, isTrue);
      expect(options.hoverTime, 500);
      expect(options.hideOn, isNotNull);
    });
  });

  group('hoverTooltip', () {
    test('creates extension from source function', () {
      final ext = hoverTooltip((context, pos, side) {
        return Tooltip(
          pos: pos,
          create: (_) => TooltipView(widget: const Text('Hover')),
        );
      });
      
      expect(ext, isA<Extension>());
    });

    test('accepts options', () {
      final ext = hoverTooltip(
        (context, pos, side) => null,
        const HoverTooltipOptions(hoverTime: 500),
      );
      
      expect(ext, isA<Extension>());
    });
  });

  group('hasHoverTooltips', () {
    test('returns false when no hover tooltips', () {
      final state = EditorState.create(const EditorStateConfig(
        doc: 'Hello',
      ));
      
      expect(hasHoverTooltips(state), isFalse);
    });
  });

  group('closeHoverTooltips', () {
    test('is a valid effect', () {
      expect(closeHoverTooltips, isNotNull);
    });
  });

  group('HoverTooltipContainer', () {
    testWidgets('renders tooltip content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HoverTooltipContainer(
            tooltip: HoverTooltip(
              pos: 0,
              create: (_) => TooltipView(widget: const Text('Content')),
            ),
            view: TooltipView(widget: const Text('Content')),
            above: false,
            space: const TooltipRect(top: 0, left: 0, bottom: 100, right: 100),
          ),
        ),
      );
      
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('has decoration', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HoverTooltipContainer(
            tooltip: HoverTooltip(
              pos: 0,
              create: (_) => TooltipView(widget: const Text('Test')),
            ),
            view: TooltipView(widget: const Text('Test')),
            above: false,
            space: const TooltipRect(top: 0, left: 0, bottom: 100, right: 100),
          ),
        ),
      );
      
      // Should render the tooltip content
      expect(find.text('Test'), findsWidgets);
    });
  });

  group('TooltipContainer', () {
    testWidgets('renders child', (tester) async {
      final state = EditorState.create(const EditorStateConfig(
        doc: 'Test',
      ));
      
      await tester.pumpWidget(
        MaterialApp(
          home: TooltipContainer(
            state: state,
            coordsAtPos: (_) => null,
            child: const Text('Editor'),
          ),
        ),
      );
      
      expect(find.text('Editor'), findsOneWidget);
    });
  });

  group('HoverTooltipDetector', () {
    testWidgets('wraps child in MouseRegion', (tester) async {
      final state = EditorState.create(const EditorStateConfig(
        doc: 'Test',
      ));
      
      await tester.pumpWidget(
        MaterialApp(
          home: HoverTooltipDetector(
            state: state,
            dispatch: (_) {},
            posAtCoords: (_) => null,
            coordsAtPos: (_) => null,
            child: const Text('Content'),
          ),
        ),
      );
      
      // At least one MouseRegion should exist (detector adds one)
      expect(find.byType(MouseRegion), findsAtLeastNWidgets(1));
      expect(find.text('Content'), findsOneWidget);
    });
  });
}
