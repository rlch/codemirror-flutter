import 'package:codemirror/codemirror.dart';
import 'package:test/test.dart';

void main() {
  group('LspPosition', () {
    test('equality', () {
      expect(
        const LspPosition(line: 1, character: 5),
        equals(const LspPosition(line: 1, character: 5)),
      );
      expect(
        const LspPosition(line: 1, character: 5),
        isNot(equals(const LspPosition(line: 1, character: 6))),
      );
    });

    test('isBefore', () {
      const p1 = LspPosition(line: 1, character: 5);
      const p2 = LspPosition(line: 2, character: 0);
      const p3 = LspPosition(line: 1, character: 10);

      expect(p1.isBefore(p2), isTrue);
      expect(p1.isBefore(p3), isTrue);
      expect(p2.isBefore(p1), isFalse);
      expect(p1.isBefore(p1), isFalse);
    });

    test('isAfter', () {
      const p1 = LspPosition(line: 1, character: 5);
      const p2 = LspPosition(line: 2, character: 0);

      expect(p2.isAfter(p1), isTrue);
      expect(p1.isAfter(p2), isFalse);
      expect(p1.isAfter(p1), isFalse);
    });
  });

  group('LspRange', () {
    test('contains', () {
      const range = LspRange(
        start: LspPosition(line: 1, character: 0),
        end: LspPosition(line: 3, character: 0),
      );

      expect(range.contains(const LspPosition(line: 2, character: 5)), isTrue);
      expect(range.contains(const LspPosition(line: 1, character: 0)), isTrue);
      expect(range.contains(const LspPosition(line: 0, character: 5)), isFalse);
      expect(range.contains(const LspPosition(line: 3, character: 0)), isFalse);
    });

    test('isEmpty', () {
      const empty = LspRange(
        start: LspPosition(line: 1, character: 5),
        end: LspPosition(line: 1, character: 5),
      );
      const nonEmpty = LspRange(
        start: LspPosition(line: 1, character: 5),
        end: LspPosition(line: 1, character: 10),
      );

      expect(empty.isEmpty, isTrue);
      expect(nonEmpty.isEmpty, isFalse);
    });
  });

  group('LspPositionConversions', () {
    test('offsetToLspPosition single line', () {
      const doc = 'Hello, World!';
      expect(doc.offsetToLspPosition(0), equals(const LspPosition(line: 0, character: 0)));
      expect(doc.offsetToLspPosition(7), equals(const LspPosition(line: 0, character: 7)));
      expect(doc.offsetToLspPosition(13), equals(const LspPosition(line: 0, character: 13)));
    });

    test('offsetToLspPosition multiline', () {
      const doc = 'Line 1\nLine 2\nLine 3';
      expect(doc.offsetToLspPosition(0), equals(const LspPosition(line: 0, character: 0)));
      expect(doc.offsetToLspPosition(6), equals(const LspPosition(line: 0, character: 6)));
      expect(doc.offsetToLspPosition(7), equals(const LspPosition(line: 1, character: 0)));
      expect(doc.offsetToLspPosition(14), equals(const LspPosition(line: 2, character: 0)));
      expect(doc.offsetToLspPosition(20), equals(const LspPosition(line: 2, character: 6)));
    });

    test('offsetToLspPosition clamps to bounds', () {
      const doc = 'Hello';
      expect(doc.offsetToLspPosition(-5), equals(const LspPosition(line: 0, character: 0)));
      expect(doc.offsetToLspPosition(100), equals(const LspPosition(line: 0, character: 5)));
    });

    test('lspPositionToOffset single line', () {
      const doc = 'Hello, World!';
      expect(doc.lspPositionToOffset(const LspPosition(line: 0, character: 0)), equals(0));
      expect(doc.lspPositionToOffset(const LspPosition(line: 0, character: 7)), equals(7));
    });

    test('lspPositionToOffset multiline', () {
      const doc = 'Line 1\nLine 2\nLine 3';
      expect(doc.lspPositionToOffset(const LspPosition(line: 0, character: 0)), equals(0));
      expect(doc.lspPositionToOffset(const LspPosition(line: 1, character: 0)), equals(7));
      expect(doc.lspPositionToOffset(const LspPosition(line: 2, character: 0)), equals(14));
      expect(doc.lspPositionToOffset(const LspPosition(line: 2, character: 6)), equals(20));
    });

    test('lspPositionToOffset clamps to bounds', () {
      const doc = 'Hello';
      expect(doc.lspPositionToOffset(const LspPosition(line: 10, character: 0)), equals(5));
      expect(doc.lspPositionToOffset(const LspPosition(line: 0, character: 100)), equals(5));
    });

    test('roundtrip offset -> position -> offset', () {
      const doc = 'function foo() {\n  return 42;\n}';
      for (var i = 0; i <= doc.length; i++) {
        final pos = doc.offsetToLspPosition(i);
        final offset = doc.lspPositionToOffset(pos);
        expect(offset, equals(i), reason: 'Roundtrip failed at offset $i');
      }
    });

    test('endLspPosition', () {
      expect(''.endLspPosition, equals(const LspPosition(line: 0, character: 0)));
      expect('Hello'.endLspPosition, equals(const LspPosition(line: 0, character: 5)));
      expect('Line 1\nLine 2'.endLspPosition, equals(const LspPosition(line: 1, character: 6)));
    });

    test('lineCount', () {
      expect(''.lineCount, equals(1));
      expect('Hello'.lineCount, equals(1));
      expect('Line 1\nLine 2'.lineCount, equals(2));
      expect('a\nb\nc'.lineCount, equals(3));
      expect('a\nb\nc\n'.lineCount, equals(4));
    });
  });
}
