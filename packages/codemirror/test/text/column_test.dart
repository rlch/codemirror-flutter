/// Tests ported from ref/text/test/test-cluster.ts
import 'package:flutter_test/flutter_test.dart';
import 'package:codemirror/src/text/column.dart';

void main() {
  // =========================================================================
  // Tests ported from ref/text/test/test-cluster.ts
  // =========================================================================
  group('countColumn (ported from test-cluster.ts)', () {
    // Ported: "counts characters"
    test('counts characters', () {
      expect(countColumn('abc', 4), 3);
    });

    // Ported: "counts tabs correctly"
    test('counts tabs correctly', () {
      expect(countColumn('a\t\tbc\tx', 4), 13);
    });

    // Ported: "handles clusters"
    test('handles clusters', () {
      expect(countColumn('a😎🇫🇷', 4), 3);
    });
  });

  group('findColumn (ported from test-cluster.ts)', () {
    // Ported: "finds positions"
    test('finds positions', () {
      expect(findColumn('abc', 3, 4), 3);
    });

    // Ported: "counts tabs"
    test('counts tabs', () {
      expect(findColumn('a\tbc', 4, 4), 2);
    });

    // Ported: "handles clusters"
    test('handles clusters', () {
      expect(findColumn('a😎🇫🇷bc', 4, 4), 8);
    });
  });

  // =========================================================================
  // Additional Dart-specific tests
  // =========================================================================
  group('countColumn', () {
    test('counts ASCII characters', () {
      expect(countColumn('hello', 4), 5);
      expect(countColumn('hello', 4, 3), 3);
      expect(countColumn('', 4), 0);
    });

    test('handles tabs at start', () {
      expect(countColumn('\thello', 4), 9); // 4 + 5
      expect(countColumn('\thello', 8), 13); // 8 + 5
    });

    test('handles tabs in middle', () {
      expect(countColumn('ab\tc', 4), 5); // 2 + 2(tab to col 4) + 1
      expect(countColumn('abc\td', 4), 5); // 3 + 1(tab to col 4) + 1
      expect(countColumn('abcd\te', 4), 9); // 4 + 4(tab to col 8) + 1
    });

    test('handles multiple tabs', () {
      expect(countColumn('\t\t', 4), 8);
      expect(countColumn('a\tb\tc', 4), 9); // 1 + 3(to col 4) + 1 + 3(to col 8) + 1
    });

    test('handles tabs with custom tab size', () {
      expect(countColumn('\t', 2), 2);
      expect(countColumn('a\t', 2), 2); // 1 + 1(to col 2)
      expect(countColumn('ab\t', 2), 4); // 2 + 2(to col 4)
    });

    test('counts partial string', () {
      expect(countColumn('hello', 4, 3), 3);
      expect(countColumn('\thello', 4, 1), 4); // Just the tab
      expect(countColumn('\thello', 4, 2), 5); // Tab + h
    });

    test('handles Unicode characters', () {
      expect(countColumn('中文', 4), 2); // 2 graphemes
      expect(countColumn('a😀b', 4), 3); // 3 graphemes
    });

    test('handles emoji as single column', () {
      expect(countColumn('😀', 4), 1);
      expect(countColumn('👨‍👩‍👧', 4), 1); // Family emoji = 1 grapheme
    });
  });

  group('findColumn', () {
    test('finds column in ASCII text', () {
      expect(findColumn('hello', 0, 4), 0);
      expect(findColumn('hello', 3, 4), 3);
      expect(findColumn('hello', 5, 4), 5);
    });

    test('returns string length when column past end', () {
      expect(findColumn('hi', 10, 4), 2);
    });

    test('returns -1 in strict mode when column past end', () {
      expect(findColumn('hi', 10, 4, strict: true), -1);
    });

    test('handles tabs', () {
      expect(findColumn('\thello', 0, 4), 0);
      expect(findColumn('\thello', 4, 4), 1); // After tab
      expect(findColumn('\thello', 5, 4), 2); // After tab + h
    });

    test('handles multiple tabs', () {
      expect(findColumn('\t\thello', 0, 4), 0);
      expect(findColumn('\t\thello', 4, 4), 1); // After first tab
      expect(findColumn('\t\thello', 8, 4), 2); // After second tab
      expect(findColumn('\t\thello', 9, 4), 3); // After tabs + h
    });

    test('handles tabs with custom tab size', () {
      expect(findColumn('\t', 2, 2), 1);
      expect(findColumn('a\t', 2, 2), 2); // After a + tab
    });

    test('handles Unicode characters', () {
      // After col 1, we're after the first grapheme cluster
      expect(findColumn('中文', 1, 4), 1); // After first Chinese char (1 grapheme = col 1)
      expect(findColumn('a😀b', 2, 4), 3); // After col 2 (a=col1, emoji=col2), at position 3 (after emoji)
    });

    test('inverse of countColumn', () {
      const testCases = ['hello', '\thello', 'ab\tc', '😀test', '中文'];
      for (final str in testCases) {
        for (var pos = 0; pos <= str.length; pos++) {
          final col = countColumn(str, 4, pos);
          final foundPos = findColumn(str, col, 4);
          expect(foundPos, lessThanOrEqualTo(str.length));
        }
      }
    });
  });

  group('integration', () {
    test('countColumn and findColumn are consistent', () {
      const text = 'a\tb\tc';
      const tabSize = 4;
      
      var col = 0;
      var pos = 0;
      while (pos < text.length) {
        expect(countColumn(text, tabSize, pos), col);
        expect(findColumn(text, col, tabSize), pos);
        
        if (text.codeUnitAt(pos) == 9) {
          col += tabSize - (col % tabSize);
        } else {
          col++;
        }
        pos++;
      }
    });

    test('handles typical code indentation', () {
      const line = '\t\treturn value;';
      expect(countColumn(line, 4), 2 * 4 + 'return value;'.length);
      expect(findColumn(line, 8, 4), 2); // After 2 tabs
    });

    test('handles mixed spaces and tabs', () {
      const line = '  \thello'; // 2 spaces + tab + hello
      expect(countColumn(line, 4), 4 + 5); // 2 + 2(tab to col 4) + 5
    });
  });
}
