import 'package:codemirror/codemirror.dart';
import 'package:test/test.dart';

void main() {
  group('VirtualDocument', () {
    group('basic properties', () {
      test('computes bodyOffset correctly', () {
        final doc = VirtualDocument(
          prefix: 'prefix\n',
          body: 'body',
          suffix: '\nsuffix',
        );
        expect(doc.bodyOffset, equals(7)); // 'prefix\n' = 7 chars
      });

      test('computes bodyStartLine correctly', () {
        final doc = VirtualDocument(
          prefix: 'line1\nline2\n',
          body: 'body',
          suffix: '',
        );
        expect(doc.bodyStartLine, equals(2)); // 2 newlines before body
      });

      test('fullContent concatenates correctly', () {
        final doc = VirtualDocument(
          prefix: 'prefix-',
          body: 'body',
          suffix: '-suffix',
        );
        expect(doc.fullContent, equals('prefix-body-suffix'));
      });

      test('fullLength is correct', () {
        final doc = VirtualDocument(
          prefix: 'pre',
          body: 'body',
          suffix: 'suf',
        );
        expect(doc.fullLength, equals(10));
      });
    });

    group('offset conversions', () {
      late VirtualDocument doc;

      setUp(() {
        doc = VirtualDocument(
          prefix: 'const x = 1;\n', // 13 chars
          body: 'return x;',         // 9 chars
          suffix: '\n}',              // 2 chars
        );
      });

      test('toFullOffset converts visible to full', () {
        expect(doc.toFullOffset(0), equals(13));
        expect(doc.toFullOffset(5), equals(18));
        expect(doc.toFullOffset(9), equals(22));
      });

      test('toFullOffset clamps to body bounds', () {
        expect(doc.toFullOffset(-5), equals(13));
        expect(doc.toFullOffset(100), equals(22));
      });

      test('toVisibleOffset converts full to visible', () {
        expect(doc.toVisibleOffset(13), equals(0));
        expect(doc.toVisibleOffset(18), equals(5));
        expect(doc.toVisibleOffset(22), equals(9));
      });

      test('toVisibleOffset returns null outside visible range', () {
        expect(doc.toVisibleOffset(0), isNull);   // in prefix
        expect(doc.toVisibleOffset(12), isNull);  // in prefix
        expect(doc.toVisibleOffset(23), isNull);  // in suffix
      });

      test('isOffsetInVisibleRange', () {
        expect(doc.isOffsetInVisibleRange(0), isFalse);
        expect(doc.isOffsetInVisibleRange(12), isFalse);
        expect(doc.isOffsetInVisibleRange(13), isTrue);
        expect(doc.isOffsetInVisibleRange(22), isTrue);
        expect(doc.isOffsetInVisibleRange(23), isFalse);
      });
    });

    group('position conversions', () {
      late VirtualDocument doc;

      setUp(() {
        // prefix has 2 lines
        doc = VirtualDocument(
          prefix: 'function foo() {\n  const x = 1;\n',
          body: '  return x;\n  console.log(x);',
          suffix: '\n}',
        );
      });

      test('toFullPosition adds prefix lines', () {
        expect(
          doc.toFullPosition(const LspPosition(line: 0, character: 2)),
          equals(const LspPosition(line: 2, character: 2)),
        );
        expect(
          doc.toFullPosition(const LspPosition(line: 1, character: 5)),
          equals(const LspPosition(line: 3, character: 5)),
        );
      });

      test('toVisiblePosition subtracts prefix lines', () {
        expect(
          doc.toVisiblePosition(const LspPosition(line: 2, character: 2)),
          equals(const LspPosition(line: 0, character: 2)),
        );
        expect(
          doc.toVisiblePosition(const LspPosition(line: 3, character: 5)),
          equals(const LspPosition(line: 1, character: 5)),
        );
      });

      test('toVisiblePosition returns null for prefix positions', () {
        expect(doc.toVisiblePosition(const LspPosition(line: 0, character: 0)), isNull);
        expect(doc.toVisiblePosition(const LspPosition(line: 1, character: 5)), isNull);
      });

      test('toVisiblePosition returns null for suffix positions', () {
        // Body has 2 lines (0 and 1 in visible), so line 4+ is in suffix
        expect(doc.toVisiblePosition(const LspPosition(line: 4, character: 0)), isNull);
        expect(doc.toVisiblePosition(const LspPosition(line: 10, character: 0)), isNull);
      });

      test('isPositionInVisibleRange', () {
        expect(doc.isPositionInVisibleRange(const LspPosition(line: 0, character: 0)), isFalse);
        expect(doc.isPositionInVisibleRange(const LspPosition(line: 2, character: 0)), isTrue);
        expect(doc.isPositionInVisibleRange(const LspPosition(line: 3, character: 0)), isTrue);
        expect(doc.isPositionInVisibleRange(const LspPosition(line: 10, character: 0)), isFalse);
      });
    });

    group('range conversions', () {
      late VirtualDocument doc;

      setUp(() {
        doc = VirtualDocument(
          prefix: 'line0\nline1\n',
          body: 'bodyA\nbodyB',
          suffix: '\nend',
        );
      });

      test('toFullRange converts visible range to full', () {
        const visibleRange = LspRange(
          start: LspPosition(line: 0, character: 0),
          end: LspPosition(line: 1, character: 5),
        );
        final fullRange = doc.toFullRange(visibleRange);
        expect(fullRange.start, equals(const LspPosition(line: 2, character: 0)));
        expect(fullRange.end, equals(const LspPosition(line: 3, character: 5)));
      });

      test('toVisibleRange converts full range to visible', () {
        const fullRange = LspRange(
          start: LspPosition(line: 2, character: 0),
          end: LspPosition(line: 3, character: 5),
        );
        final visibleRange = doc.toVisibleRange(fullRange);
        expect(visibleRange, isNotNull);
        expect(visibleRange!.start, equals(const LspPosition(line: 0, character: 0)));
        expect(visibleRange.end, equals(const LspPosition(line: 1, character: 5)));
      });

      test('toVisibleRange returns null for range entirely in prefix', () {
        const fullRange = LspRange(
          start: LspPosition(line: 0, character: 0),
          end: LspPosition(line: 1, character: 5),
        );
        expect(doc.toVisibleRange(fullRange), isNull);
      });

      test('toVisibleRange clamps partial overlap', () {
        // Range starts in prefix, ends in body
        const fullRange = LspRange(
          start: LspPosition(line: 0, character: 0),
          end: LspPosition(line: 2, character: 3),
        );
        final visibleRange = doc.toVisibleRange(fullRange);
        expect(visibleRange, isNotNull);
        expect(visibleRange!.start, equals(const LspPosition(line: 0, character: 0)));
        expect(visibleRange.end, equals(const LspPosition(line: 0, character: 3)));
      });
    });

    group('mutations', () {
      test('withBody creates new doc with updated body', () {
        final doc = VirtualDocument(
          prefix: 'pre-',
          body: 'old',
          suffix: '-suf',
        );
        final newDoc = doc.withBody('new');
        expect(newDoc.prefix, equals('pre-'));
        expect(newDoc.body, equals('new'));
        expect(newDoc.suffix, equals('-suf'));
        expect(doc.body, equals('old')); // original unchanged
      });

      test('withPrefix creates new doc with updated prefix', () {
        final doc = VirtualDocument(
          prefix: 'old-',
          body: 'body',
          suffix: '-suf',
        );
        final newDoc = doc.withPrefix('new-');
        expect(newDoc.prefix, equals('new-'));
        expect(newDoc.body, equals('body'));
        expect(newDoc.bodyOffset, equals(4)); // recalculated
      });

      test('withSuffix creates new doc with updated suffix', () {
        final doc = VirtualDocument(
          prefix: 'pre-',
          body: 'body',
          suffix: '-old',
        );
        final newDoc = doc.withSuffix('-new');
        expect(newDoc.suffix, equals('-new'));
        expect(newDoc.fullContent, equals('pre-body-new'));
      });
    });

    group('simple constructor', () {
      test('creates doc with no prefix or suffix', () {
        final doc = VirtualDocument.simple('just body');
        expect(doc.prefix, equals(''));
        expect(doc.body, equals('just body'));
        expect(doc.suffix, equals(''));
        expect(doc.bodyOffset, equals(0));
        expect(doc.bodyStartLine, equals(0));
      });
    });

    group('real-world scenario', () {
      test('TypeScript function body editing', () {
        // Simulates editing only the body of a TypeScript function
        final doc = VirtualDocument(
          prefix: '''interface Props { name: string; }

function Component(props: Props) {
''',
          body: '''  const greeting = `Hello, \${props.name}!`;
  return <div>{greeting}</div>;''',
          suffix: '''
}
''',
        );

        // Verify structure
        expect(doc.bodyStartLine, equals(3));
        
        // A diagnostic at line 3 (first body line) in full doc
        // should map to line 0 in visible
        final fullPos = const LspPosition(line: 3, character: 8);
        final visiblePos = doc.toVisiblePosition(fullPos);
        expect(visiblePos, isNotNull);
        expect(visiblePos!.line, equals(0));
        expect(visiblePos.character, equals(8));

        // A diagnostic at line 0 (in prefix) should not map
        expect(
          doc.toVisiblePosition(const LspPosition(line: 0, character: 0)),
          isNull,
        );
      });
    });
  });
}
