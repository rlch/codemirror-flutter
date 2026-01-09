import 'package:codemirror/src/state/facet.dart' hide EditorState, Transaction;
import 'package:codemirror/src/state/selection.dart';
import 'package:codemirror/src/state/state.dart';
import 'package:codemirror/src/state/transaction.dart';
import 'package:codemirror/src/view/input.dart';
import 'package:codemirror/src/view/keymap.dart' as km;
import 'package:codemirror/src/view/view_update.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock view for testing input handling.
class MockEditorView {
  EditorState state;
  List<TransactionSpec> dispatchedSpecs = [];
  bool hasFocus = true;

  MockEditorView(this.state);

  void dispatch(List<TransactionSpec> specs) {
    dispatchedSpecs.addAll(specs);
    if (specs.isNotEmpty) {
      final tr = state.update(specs);
      state = tr.state as EditorState;
    }
  }
}

void main() {
  group('InputState', () {
    test('creates with default values', () {
      final mockView = MockEditorView(
        EditorState.create(EditorStateConfig(doc: 'Hello')),
      );
      final input = InputState(mockView);

      expect(input.lastKeyCode, equals(0));
      expect(input.lastKeyTime, equals(0));
      expect(input.lastTouchTime, equals(0));
      expect(input.lastFocusTime, equals(0));
      expect(input.tabFocusMode, equals(-1));
      expect(input.composing, equals(-1));
      expect(input.mouseSelection, isNull);
      expect(input.draggedContent, isNull);
    });

    test('setSelectionOrigin updates origin and time', () {
      final mockView = MockEditorView(
        EditorState.create(EditorStateConfig(doc: 'Hello')),
      );
      final input = InputState(mockView);

      final before = DateTime.now().millisecondsSinceEpoch;
      input.setSelectionOrigin('select.pointer');
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(input.lastSelectionOrigin, equals('select.pointer'));
      expect(input.lastSelectionTime, greaterThanOrEqualTo(before));
      expect(input.lastSelectionTime, lessThanOrEqualTo(after));
    });

    test('handleEscape activates tab focus mode', () {
      final mockView = MockEditorView(
        EditorState.create(EditorStateConfig(doc: 'Hello')),
      );
      final input = InputState(mockView);
      input.tabFocusMode = 0; // Not disabled

      final before = DateTime.now().millisecondsSinceEpoch;
      input.handleEscape();

      // Should set expiry time ~2 seconds in the future
      expect(input.tabFocusMode, greaterThan(before));
      expect(input.tabFocusMode, lessThanOrEqualTo(before + 2100));
    });

    test('destroy cleans up mouse selection', () {
      final mockView = MockEditorView(
        EditorState.create(EditorStateConfig(doc: 'Hello')),
      );
      final input = InputState(mockView);

      // Note: Can't fully test without setting up a mouse selection
      input.destroy();
      expect(input.mouseSelection, isNull);
    });
  });

  group('Clipboard operations', () {
    test('filterClipboardInput applies filters', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello',
          extensions: clipboardInputFilter.of((text, state) {
            return text.toUpperCase();
          }),
        ),
      );

      final filtered = filterClipboardInput(state, 'hello world');
      expect(filtered, equals('HELLO WORLD'));
    });

    test('filterClipboardInput chains multiple filters', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello',
          extensions: ExtensionList([
            clipboardInputFilter.of((text, state) => text.trim()),
            clipboardInputFilter.of((text, state) => text.toUpperCase()),
          ]),
        ),
      );

      final filtered = filterClipboardInput(state, '  hello world  ');
      expect(filtered, equals('HELLO WORLD'));
    });

    test('filterClipboardOutput applies filters', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello',
          extensions: clipboardOutputFilter.of((text, state) {
            return text.toLowerCase();
          }),
        ),
      );

      final filtered = filterClipboardOutput(state, 'HELLO WORLD');
      expect(filtered, equals('hello world'));
    });

    test('copiedRange returns selected text', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello World',
          selection: EditorSelection.single(0, 5), // "Hello"
        ),
      );

      final result = copiedRange(state);
      expect(result.text, equals('Hello'));
      expect(result.ranges.length, equals(1));
      expect(result.linewise, isFalse);
    });

    test('copiedRange handles multiple selections', () {
      // Create selection with two non-overlapping ranges
      final sel = EditorSelection.create([
        EditorSelection.range(0, 5), // "Hello"
        EditorSelection.range(6, 11), // "World"
      ]);

      // Verify the selection was created correctly
      expect(sel.ranges.length, equals(2));

      // Need to enable allowMultipleSelections facet
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello World Test',
          selection: sel,
          extensions: allowMultipleSelections.of(true),
        ),
      );

      // Verify state selection
      expect(state.selection.ranges.length, equals(2));

      final result = copiedRange(state);
      // Multiple ranges are joined with the state's lineBreak
      expect(result.text, equals('Hello\nWorld'));
      expect(result.ranges.length, equals(2));
      expect(result.linewise, isFalse);
    });

    test('copiedRange does linewise copy when nothing selected', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello\nWorld',
          selection: EditorSelection.cursor(2), // Cursor in "Hello"
        ),
      );

      final result = copiedRange(state);
      expect(result.text, equals('Hello'));
      expect(result.linewise, isTrue);
    });
  });

  group('Focus change transaction', () {
    test('focusChangeTransaction returns null with no effects', () {
      final state = EditorState.create(EditorStateConfig(doc: 'Hello'));
      final tr = focusChangeTransaction(state, true);
      expect(tr, isNull);
    });

    test('focusChangeTransaction creates transaction with effects', () {
      final effect = StateEffect.define<bool>();
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello',
          extensions: focusChangeEffect.of((state, focus) => effect.of(focus)),
        ),
      );

      final tr = focusChangeTransaction(state, true);
      expect(tr, isNotNull);
      expect(tr!.effects.length, equals(1));
    });

    test('isFocusChange annotation is added', () {
      final effect = StateEffect.define<bool>();
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello',
          extensions: focusChangeEffect.of((state, focus) => effect.of(focus)),
        ),
      );

      final tr = focusChangeTransaction(state, true);
      expect(tr, isNotNull);
      expect(tr!.annotation(isFocusChangeType), isTrue);
    });
  });

  group('Click behavior facets', () {
    test('clickAddsSelectionRange facet can be configured', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello',
          extensions: clickAddsSelectionRange.of((event) => true),
        ),
      );

      final handlers = state.facet(clickAddsSelectionRange);
      expect(handlers.length, equals(1));
    });

    test('dragMovesSelection facet can be configured', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello',
          extensions: dragMovesSelection.of((event) => false),
        ),
      );

      final handlers = state.facet(dragMovesSelection);
      expect(handlers.length, equals(1));
    });
  });

  group('MouseSelectionStyle', () {
    test('can implement MouseSelectionStyle', () {
      // Create a mock implementation
      final style = _MockMouseSelectionStyle();
      expect(style, isA<MouseSelectionStyle>());
    });
  });

  group('InputState update', () {
    test('update clears key state on transaction', () {
      final mockView = MockEditorView(
        EditorState.create(EditorStateConfig(doc: 'Hello')),
      );
      final input = InputState(mockView);

      input.lastKeyCode = 65; // 'a'
      input.lastSelectionTime = 12345;

      // Create a view update with transactions
      final viewUpdate = ViewUpdate.create(
        mockView.state,
        [mockView.state.update([TransactionSpec()])],
      );

      input.update(viewUpdate);

      expect(input.lastKeyCode, equals(0));
      expect(input.lastSelectionTime, equals(0));
    });

    test('update maps dragged content through changes', () {
      final mockView = MockEditorView(
        EditorState.create(EditorStateConfig(doc: 'Hello World')),
      );
      final input = InputState(mockView);

      // Set dragged content as "World" (6-11)
      input.draggedContent = EditorSelection.range(6, 11);

      // Create an update that inserts text at the start
      final tr = mockView.state.update([
        TransactionSpec(changes: {'from': 0, 'insert': 'XXX'}),
      ]);
      final viewUpdate = ViewUpdate.create(tr.state as EditorState, [tr]);

      input.update(viewUpdate);

      // Dragged content should be mapped (shifted by 3)
      expect(input.draggedContent, isNotNull);
      expect(input.draggedContent!.from, equals(9)); // 6 + 3
      expect(input.draggedContent!.to, equals(14)); // 11 + 3
    });
  });

  group('Tab focus mode', () {
    test('tab focus mode starts disabled', () {
      final mockView = MockEditorView(
        EditorState.create(EditorStateConfig(doc: 'Hello')),
      );
      final input = InputState(mockView);

      expect(input.tabFocusMode, equals(-1));
    });

    test('tab focus mode can be enabled', () {
      final mockView = MockEditorView(
        EditorState.create(EditorStateConfig(doc: 'Hello')),
      );
      final input = InputState(mockView);

      input.tabFocusMode = 0; // Enable without expiry
      expect(input.tabFocusMode, equals(0));
    });

    test('tab focus mode can have expiry', () {
      final mockView = MockEditorView(
        EditorState.create(EditorStateConfig(doc: 'Hello')),
      );
      final input = InputState(mockView);

      final future = DateTime.now().millisecondsSinceEpoch + 5000;
      input.tabFocusMode = future;
      expect(input.tabFocusMode, equals(future));
    });
  });

  group('Composition state', () {
    test('composition state tracks composition', () {
      final mockView = MockEditorView(
        EditorState.create(EditorStateConfig(doc: 'Hello')),
      );
      final input = InputState(mockView);

      expect(input.composing, equals(-1));

      input.composing = 0;
      expect(input.composing, equals(0));

      input.composing = 5;
      expect(input.composing, equals(5));
    });

    test('compositionFirstChange tracks first change', () {
      final mockView = MockEditorView(
        EditorState.create(EditorStateConfig(doc: 'Hello')),
      );
      final input = InputState(mockView);

      expect(input.compositionFirstChange, isNull);

      input.compositionFirstChange = true;
      expect(input.compositionFirstChange, isTrue);

      input.compositionFirstChange = false;
      expect(input.compositionFirstChange, isFalse);
    });
  });

  group('Platform detection', () {
    test('currentPlatform returns valid value', () {
      final platform = km.currentPlatform;
      expect(['mac', 'win', 'linux', 'key'].contains(platform), isTrue);
    });

    test('platform booleans are mutually exclusive', () {
      // At most one should be true
      final platformCount = [km.isMac, km.isWindows, km.isLinux].where((p) => p).length;
      expect(platformCount, lessThanOrEqualTo(1));
    });
  });
}

/// Mock implementation of MouseSelectionStyle for testing.
class _MockMouseSelectionStyle implements MouseSelectionStyle {
  @override
  EditorSelection get(PointerEvent curEvent, bool extend, bool multiple) {
    return EditorSelection.single(0);
  }

  @override
  bool update(ViewUpdate update) {
    return false;
  }
}
