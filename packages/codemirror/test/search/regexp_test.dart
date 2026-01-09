import 'package:flutter_test/flutter_test.dart';
import 'package:codemirror/codemirror.dart';

void main() {
  group('RegExpCursor', () {
    test('finds simple pattern matches', () {
      final doc = Text.of(['hello world hello']);
      final cursor = RegExpCursor(doc, r'hello');

      final match1 = cursor.next();
      expect(match1, isNotNull);
      expect(match1!.from, 0);
      expect(match1.to, 5);
      expect(match1.match[0], 'hello');

      final match2 = cursor.next();
      expect(match2, isNotNull);
      expect(match2!.from, 12);
      expect(match2.to, 17);

      expect(cursor.next(), isNull);
    });

    test('finds no matches when pattern not present', () {
      final doc = Text.of(['hello world']);
      final cursor = RegExpCursor(doc, r'xyz');

      expect(cursor.next(), isNull);
    });

    test('supports capture groups', () {
      final doc = Text.of(['hello 123 world 456']);
      final cursor = RegExpCursor(doc, r'(\d+)');

      final match1 = cursor.next();
      expect(match1, isNotNull);
      expect(match1!.match[0], '123');
      expect(match1.match[1], '123');

      final match2 = cursor.next();
      expect(match2, isNotNull);
      expect(match2!.match[0], '456');
    });

    test('case insensitive search', () {
      final doc = Text.of(['Hello HELLO hello']);
      final cursor = RegExpCursor(
        doc,
        r'hello',
        options: RegExpCursorOptions(ignoreCase: true),
      );

      expect(cursor.next(), isNotNull);
      expect(cursor.next(), isNotNull);
      expect(cursor.next(), isNotNull);
      expect(cursor.next(), isNull);
    });

    test('searches within range', () {
      final doc = Text.of(['hello world hello']);
      final cursor = RegExpCursor(doc, r'hello', from: 6);

      final match = cursor.next();
      expect(match, isNotNull);
      expect(match!.from, 12);

      expect(cursor.next(), isNull);
    });

    test('handles word boundaries', () {
      final doc = Text.of(['hello helloworld hello']);
      final cursor = RegExpCursor(doc, r'\bhello\b');

      final match1 = cursor.next();
      expect(match1, isNotNull);
      expect(match1!.from, 0);
      expect(match1.to, 5);

      final match2 = cursor.next();
      expect(match2, isNotNull);
      expect(match2!.from, 17);
      expect(match2.to, 22);

      expect(cursor.next(), isNull);
    });

    test('handles character classes', () {
      final doc = Text.of(['abc123def456']);
      final cursor = RegExpCursor(doc, r'[0-9]+');

      final match1 = cursor.next();
      expect(match1, isNotNull);
      expect(match1!.match[0], '123');

      final match2 = cursor.next();
      expect(match2, isNotNull);
      expect(match2!.match[0], '456');
    });

    test('handles start of line', () {
      final doc = Text.of(['hello', 'world']);
      final cursor = RegExpCursor(doc, r'^hello');

      final match = cursor.next();
      expect(match, isNotNull);
      expect(match!.from, 0);

      expect(cursor.next(), isNull);
    });

    test('implements Iterator interface', () {
      final doc = Text.of(['a1b2c3']);
      final cursor = RegExpCursor(doc, r'\d');

      final matches = <({int from, int to, RegExpMatch match})>[];
      while (cursor.moveNext()) {
        matches.add(cursor.current);
      }

      expect(matches.length, 3);
      expect(matches[0].match[0], '1');
      expect(matches[1].match[0], '2');
      expect(matches[2].match[0], '3');
    });
  });

  group('validRegExp', () {
    test('returns true for valid patterns', () {
      expect(validRegExp(r'hello'), isTrue);
      expect(validRegExp(r'\d+'), isTrue);
      expect(validRegExp(r'^start'), isTrue);
      expect(validRegExp(r'[a-z]+'), isTrue);
    });

    test('returns false for invalid patterns', () {
      expect(validRegExp(r'['), isFalse);
      expect(validRegExp(r'('), isFalse);
      expect(validRegExp(r'*'), isFalse);
    });
  });
}
