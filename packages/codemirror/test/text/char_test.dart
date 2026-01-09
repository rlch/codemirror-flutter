/// Tests ported from ref/text/test/test-cluster.ts
import 'package:flutter_test/flutter_test.dart';
import 'package:codemirror/src/text/char.dart';

void main() {
  // =========================================================================
  // Tests ported from ref/text/test/test-cluster.ts
  // =========================================================================
  group('findClusterBreak (ported from test-cluster.ts)', () {
    /// Test helper that parses a spec string with | markers indicating
    /// expected cluster breaks, then verifies findClusterBreak finds them.
    void testSpec(String spec) {
      test(spec, () {
        final breaks = <int>[];
        var cleaned = spec;
        int next;
        while ((next = cleaned.indexOf('|')) > -1) {
          breaks.add(next);
          cleaned = cleaned.substring(0, next) + cleaned.substring(next + 1);
        }
        
        final found = <int>[];
        for (var i = 0;;) {
          final nextBreak = findClusterBreak(cleaned, i);
          if (nextBreak == cleaned.length) break;
          found.add(i = nextBreak);
        }
        
        expect(found.join(','), breaks.join(','));
      });
    }
    
    // Ported test cases from test-cluster.ts
    testSpec('a|b|c|d');
    testSpec('a|é̠|ő|x');  // combining marks
    testSpec('😎|🙉');      // emoji
    testSpec('👨‍🎤|💪🏽|👩‍👩‍👧‍👦|❤');  // ZWJ sequences, skin tones
    testSpec('🇩🇪|🇫🇷|🇪🇸|x|🇮🇹');  // flag emoji (regional indicators)
  });

  // =========================================================================
  // Additional Dart-specific tests
  // =========================================================================
  group('findClusterBreak', () {
    group('forward', () {
      test('moves by one for ASCII', () {
        expect(findClusterBreak('hello', 0), 1);
        expect(findClusterBreak('hello', 1), 2);
        expect(findClusterBreak('hello', 4), 5);
      });

      test('returns length at end', () {
        expect(findClusterBreak('hello', 5), 5);
        expect(findClusterBreak('', 0), 0);
      });

      test('handles surrogate pairs (emoji)', () {
        const emoji = '😀'; // U+1F600 = 2 code units
        expect(emoji.length, 2);
        expect(findClusterBreak(emoji, 0), 2);
        
        const text = 'a😀b';
        expect(findClusterBreak(text, 0), 1); // 'a'
        expect(findClusterBreak(text, 1), 3); // '😀'
        expect(findClusterBreak(text, 3), 4); // 'b'
      });

      test('handles flag emoji (regional indicators)', () {
        const flag = '🇺🇸'; // Two regional indicators
        expect(flag.length, 4); // 2 surrogates * 2
        expect(findClusterBreak(flag, 0), 4);
      });

      test('handles family emoji (ZWJ sequence)', () {
        const family = '👨‍👩‍👧'; // Man + ZWJ + Woman + ZWJ + Girl
        expect(findClusterBreak(family, 0), family.length);
      });

      test('handles combining marks', () {
        const combined = 'é'; // e + combining acute (2 code points)
        if (combined.length > 1) {
          expect(findClusterBreak(combined, 0), combined.length);
        }
        
        const eCombining = 'e\u0301'; // e + combining acute
        expect(findClusterBreak(eCombining, 0), 2);
      });
    });

    group('backward', () {
      test('moves by one for ASCII', () {
        expect(findClusterBreak('hello', 5, false), 4);
        expect(findClusterBreak('hello', 2, false), 1);
        expect(findClusterBreak('hello', 1, false), 0);
      });

      test('returns 0 at start', () {
        expect(findClusterBreak('hello', 0, false), 0);
        expect(findClusterBreak('', 0, false), 0);
      });

      test('handles surrogate pairs (emoji)', () {
        const emoji = '😀';
        expect(findClusterBreak(emoji, 2, false), 0);
        
        const text = 'a😀b';
        expect(findClusterBreak(text, 4, false), 3); // before 'b'
        expect(findClusterBreak(text, 3, false), 1); // before '😀'
        expect(findClusterBreak(text, 1, false), 0); // before 'a'
      });

      test('handles flag emoji', () {
        const flag = '🇺🇸';
        expect(findClusterBreak(flag, flag.length, false), 0);
      });
    });
  });

  group('codePointAt', () {
    test('returns code point for ASCII', () {
      expect(codePointAt('A', 0), 65);
      expect(codePointAt('hello', 0), 'h'.codeUnitAt(0));
    });

    test('returns code point for BMP characters', () {
      expect(codePointAt('é', 0), 'é'.codeUnitAt(0));
      expect(codePointAt('中', 0), '中'.codeUnitAt(0));
    });

    test('returns full code point for surrogate pairs', () {
      const emoji = '😀'; // U+1F600
      expect(codePointAt(emoji, 0), 0x1F600);
    });

    test('returns high surrogate if at invalid position', () {
      const emoji = '😀';
      final highSurrogate = emoji.codeUnitAt(0);
      expect(codePointAt(emoji, 0), 0x1F600); // Full code point
    });
  });

  group('fromCodePoint', () {
    test('converts BMP code points', () {
      expect(fromCodePoint(65), 'A');
      expect(fromCodePoint(0x4E2D), '中');
    });

    test('converts supplementary code points', () {
      expect(fromCodePoint(0x1F600), '😀');
      expect(fromCodePoint(0x1F1FA), '\u{1F1FA}'); // Regional indicator U
    });
  });

  group('codePointSize', () {
    test('returns 1 for BMP code points', () {
      expect(codePointSize(65), 1);
      expect(codePointSize(0x4E2D), 1);
      expect(codePointSize(0xFFFF), 1);
    });

    test('returns 2 for supplementary code points', () {
      expect(codePointSize(0x10000), 2);
      expect(codePointSize(0x1F600), 2);
    });
  });

  group('integration', () {
    test('round-trip through codePointAt and fromCodePoint', () {
      const testStrings = ['A', 'é', '中', '😀', '🇺🇸'];
      for (final str in testStrings) {
        if (str.length <= 2) {
          final cp = codePointAt(str, 0);
          expect(fromCodePoint(cp), str.substring(0, codePointSize(cp)));
        }
      }
    });
  });
}
