import 'package:test/test.dart';
import 'package:codemirror/src/view/bidi.dart';
import 'package:codemirror/src/state/selection.dart';
import 'package:codemirror/src/text/text.dart';

void main() {
  group('Direction', () {
    test('ltr has level 0', () {
      expect(Direction.ltr.level, 0);
    });

    test('rtl has level 1', () {
      expect(Direction.rtl.level, 1);
    });
  });

  group('BidiSpan', () {
    test('creates span with from, to, level', () {
      final span = BidiSpan(0, 10, 0);
      expect(span.from, 0);
      expect(span.to, 10);
      expect(span.level, 0);
    });

    test('even level is ltr', () {
      expect(BidiSpan(0, 10, 0).dir, Direction.ltr);
      expect(BidiSpan(0, 10, 2).dir, Direction.ltr);
    });

    test('odd level is rtl', () {
      expect(BidiSpan(0, 10, 1).dir, Direction.rtl);
      expect(BidiSpan(0, 10, 3).dir, Direction.rtl);
    });

    test('side returns correct position for ltr', () {
      final span = BidiSpan(0, 10, 0); // LTR

      // For LTR span with LTR direction:
      // end=true returns to (10), end=false returns from (0)
      expect(span.side(true, Direction.ltr), 10);
      expect(span.side(false, Direction.ltr), 0);
    });

    test('side returns correct position for rtl', () {
      final span = BidiSpan(0, 10, 1); // RTL

      // For RTL span with RTL direction:
      // end=true returns to (10), end=false returns from (0)
      expect(span.side(true, Direction.rtl), 10);
      expect(span.side(false, Direction.rtl), 0);
    });

    test('forward returns true for same direction', () {
      final ltrSpan = BidiSpan(0, 10, 0);
      final rtlSpan = BidiSpan(0, 10, 1);

      expect(ltrSpan.forward(true, Direction.ltr), isTrue);
      expect(rtlSpan.forward(true, Direction.rtl), isTrue);
    });

    test('forward returns false for opposite direction', () {
      final ltrSpan = BidiSpan(0, 10, 0);
      final rtlSpan = BidiSpan(0, 10, 1);

      expect(ltrSpan.forward(true, Direction.rtl), isFalse);
      expect(rtlSpan.forward(true, Direction.ltr), isFalse);
    });

    group('find', () {
      test('finds span containing index', () {
        final order = [
          BidiSpan(0, 5, 0),
          BidiSpan(5, 10, 1),
          BidiSpan(10, 15, 0),
        ];

        expect(BidiSpan.find(order, 3, 0, 0), 0);
        expect(BidiSpan.find(order, 7, 1, 0), 1);
        expect(BidiSpan.find(order, 12, 0, 0), 2);
      });

      test('prefers span matching level', () {
        final order = [
          BidiSpan(0, 10, 0),
          BidiSpan(0, 10, 1), // Overlapping span
        ];

        expect(BidiSpan.find(order, 5, 0, 0), 0);
        expect(BidiSpan.find(order, 5, 1, 0), 1);
      });

      test('throws for index out of range', () {
        final order = [BidiSpan(0, 5, 0)];
        expect(() => BidiSpan.find(order, 10, 0, 0), throwsRangeError);
      });

      test('handles boundary positions', () {
        final order = [
          BidiSpan(0, 5, 0),
          BidiSpan(5, 10, 0),
        ];

        // At boundary (5), both spans contain it
        expect(BidiSpan.find(order, 5, 0, 0), anyOf(0, 1));
      });
    });

    test('equality', () {
      expect(BidiSpan(0, 10, 0), equals(BidiSpan(0, 10, 0)));
      expect(BidiSpan(0, 10, 0), isNot(equals(BidiSpan(0, 10, 1))));
      expect(BidiSpan(0, 10, 0), isNot(equals(BidiSpan(0, 11, 0))));
    });
  });

  group('hasRtlText', () {
    test('returns false for pure LTR text', () {
      expect(hasRtlText('Hello World'), isFalse);
      expect(hasRtlText('12345'), isFalse);
      expect(hasRtlText(''), isFalse);
    });

    test('returns true for Hebrew text', () {
      expect(hasRtlText('שלום'), isTrue);
    });

    test('returns true for Arabic text', () {
      expect(hasRtlText('مرحبا'), isTrue);
    });

    test('returns true for mixed text', () {
      expect(hasRtlText('Hello שלום World'), isTrue);
    });
  });

  group('Isolate', () {
    test('creates isolate with all properties', () {
      final isolate = Isolate(
        from: 5,
        to: 10,
        direction: Direction.rtl,
        inner: [
          Isolate(from: 6, to: 8, direction: Direction.ltr),
        ],
      );

      expect(isolate.from, 5);
      expect(isolate.to, 10);
      expect(isolate.direction, Direction.rtl);
      expect(isolate.inner.length, 1);
    });

    test('default inner is empty', () {
      final isolate = Isolate(from: 0, to: 5, direction: Direction.ltr);
      expect(isolate.inner, isEmpty);
    });
  });

  group('isolatesEq', () {
    test('empty lists are equal', () {
      expect(isolatesEq([], []), isTrue);
    });

    test('different lengths are not equal', () {
      expect(
        isolatesEq(
          [Isolate(from: 0, to: 5, direction: Direction.ltr)],
          [],
        ),
        isFalse,
      );
    });

    test('same isolates are equal', () {
      expect(
        isolatesEq(
          [Isolate(from: 0, to: 5, direction: Direction.ltr)],
          [Isolate(from: 0, to: 5, direction: Direction.ltr)],
        ),
        isTrue,
      );
    });

    test('different from values are not equal', () {
      expect(
        isolatesEq(
          [Isolate(from: 0, to: 5, direction: Direction.ltr)],
          [Isolate(from: 1, to: 5, direction: Direction.ltr)],
        ),
        isFalse,
      );
    });

    test('different directions are not equal', () {
      expect(
        isolatesEq(
          [Isolate(from: 0, to: 5, direction: Direction.ltr)],
          [Isolate(from: 0, to: 5, direction: Direction.rtl)],
        ),
        isFalse,
      );
    });

    test('recursively compares inner isolates', () {
      expect(
        isolatesEq(
          [
            Isolate(
              from: 0,
              to: 10,
              direction: Direction.ltr,
              inner: [Isolate(from: 2, to: 5, direction: Direction.rtl)],
            ),
          ],
          [
            Isolate(
              from: 0,
              to: 10,
              direction: Direction.ltr,
              inner: [Isolate(from: 2, to: 5, direction: Direction.rtl)],
            ),
          ],
        ),
        isTrue,
      );
    });
  });

  group('computeOrder', () {
    test('returns trivial order for empty string', () {
      final order = computeOrder('', Direction.ltr);
      expect(order.length, 1);
      expect(order[0].from, 0);
      expect(order[0].to, 0);
      expect(order[0].level, 0);
    });

    test('returns trivial order for LTR-only text', () {
      final order = computeOrder('Hello World', Direction.ltr);
      expect(order.length, 1);
      expect(order[0].from, 0);
      expect(order[0].to, 11);
      expect(order[0].level, 0);
    });

    test('handles RTL base direction for LTR text', () {
      final order = computeOrder('Hello', Direction.rtl);
      expect(order.isNotEmpty, isTrue);
    });

    test('handles Hebrew text in LTR context', () {
      final order = computeOrder('שלום', Direction.ltr);
      expect(order.isNotEmpty, isTrue);
      // Hebrew should be RTL (level 1+)
      expect(order.any((s) => s.level > 0), isTrue);
    });

    test('handles mixed LTR and RTL text', () {
      final order = computeOrder('Hello שלום World', Direction.ltr);
      expect(order.length, greaterThan(1));
    });

    test('handles numbers in RTL context', () {
      final order = computeOrder('مرحبا 123 عالم', Direction.rtl);
      expect(order.isNotEmpty, isTrue);
    });
  });

  group('trivialOrder', () {
    test('returns single LTR span', () {
      final order = trivialOrder(10);
      expect(order.length, 1);
      expect(order[0].from, 0);
      expect(order[0].to, 10);
      expect(order[0].level, 0);
    });

    test('handles zero length', () {
      final order = trivialOrder(0);
      expect(order.length, 1);
      expect(order[0].from, 0);
      expect(order[0].to, 0);
    });
  });

  group('autoDirection', () {
    test('returns LTR for pure ASCII', () {
      expect(autoDirection('Hello World', 0, 11), Direction.ltr);
    });

    test('returns LTR for numbers', () {
      expect(autoDirection('12345', 0, 5), Direction.ltr);
    });

    test('returns LTR for empty range', () {
      expect(autoDirection('Hello', 0, 0), Direction.ltr);
    });

    test('returns RTL for Hebrew', () {
      expect(autoDirection('שלום', 0, 4), Direction.rtl);
    });

    test('returns RTL for Arabic', () {
      expect(autoDirection('مرحبا', 0, 5), Direction.rtl);
    });

    test('returns based on first strong character', () {
      // First strong character is Hebrew
      expect(autoDirection('  שלום Hello', 0, 12), Direction.rtl);
      // First strong character is Latin
      expect(autoDirection('Hello שלום', 0, 10), Direction.ltr);
    });

    test('respects range boundaries', () {
      // The Hebrew is at positions 6-9
      expect(autoDirection('Hello שלום World', 6, 10), Direction.rtl);
      expect(autoDirection('Hello שלום World', 0, 5), Direction.ltr);
    });
  });

  group('moveVisually', () {
    test('moves forward in LTR text', () {
      final line = Text.of(['Hello']).lineAt(0);
      final order = trivialOrder(5);
      final cursor = EditorSelection.cursor(0);

      final result = moveVisually(line, order, Direction.ltr, cursor, true);

      expect(result, isNotNull);
      expect(result!.head, 1);
    });

    test('moves backward in LTR text', () {
      final line = Text.of(['Hello']).lineAt(0);
      final order = trivialOrder(5);
      final cursor = EditorSelection.cursor(3);

      final result = moveVisually(line, order, Direction.ltr, cursor, false);

      expect(result, isNotNull);
      expect(result!.head, 2);
    });

    test('returns null at start of line moving backward', () {
      final line = Text.of(['Hello']).lineAt(0);
      final order = trivialOrder(5);
      final cursor = EditorSelection.cursor(0);

      final result = moveVisually(line, order, Direction.ltr, cursor, false);

      expect(result, isNull);
    });

    test('returns null at end of line moving forward', () {
      final line = Text.of(['Hello']).lineAt(0);
      final order = trivialOrder(5);
      final cursor = EditorSelection.cursor(5);

      final result = moveVisually(line, order, Direction.ltr, cursor, true);

      expect(result, isNull);
    });

    test('handles surrogate pairs', () {
      // Text with emoji (surrogate pair)
      final line = Text.of(['A😀B']).lineAt(0);
      final order = trivialOrder(4); // A + 2 code units for emoji + B

      final cursor = EditorSelection.cursor(1); // After 'A'

      final result = moveVisually(line, order, Direction.ltr, cursor, true);

      expect(result, isNotNull);
      // Should move past the entire emoji (2 code units)
      expect(result!.head, 3);
    });

    test('updates movedOver variable', () {
      final line = Text.of(['Hello']).lineAt(0);
      final order = trivialOrder(5);
      final cursor = EditorSelection.cursor(0);

      moveVisually(line, order, Direction.ltr, cursor, true);

      expect(movedOver, 'H');
    });
  });
}
