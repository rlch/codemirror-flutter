import 'package:codemirror/codemirror.dart' hide Decoration, Text;
import 'package:codemirror/src/view/decoration.dart' as cm;
import 'package:codemirror/src/state/range_set.dart';
import 'package:flutter/material.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';

/// The flashcard template body - extracted from TemplateCodeGenerator.generateFlashcardBody()
const flashcardBody = '''const [showAnswer, setShowAnswer] = useState(false);

return (
  <Padding padding={EdgeInsetsGeometry.all({ value: 24 })}>
    <Column mainAxisAlignment="spaceBetween" crossAxisAlignment="stretch">
      <Expanded>
        <Center>
          <Column mainAxisAlignment="center" crossAxisAlignment="center">
            <Text.h2>{prompt}</Text.h2>
            {showAnswer && (
              <>
                <SizedBox height={24} />
                <Text>{answer}</Text>
              </>
            )}
          </Column>
        </Center>
      </Expanded>
      <SizedBox height={24} />
      {!showAnswer ? (
        <Button
          style={ButtonStyle.primary({ borderRadius: BorderRadius.circular({ radius: 12 }) })}
          onPress={() => setShowAnswer(true)}
        >
          Show Answer
        </Button>
      ) : (
        <Row mainAxisAlignment="spaceEvenly">
          <Expanded>
            <Button style={ButtonStyle.destructive({ borderRadius: BorderRadius.circular({ radius: 8 }) })} onPress={() => controller.submitReview(1)}>Again</Button>
          </Expanded>
          <SizedBox width={8} />
          <Expanded>
            <Button style={ButtonStyle.outline({ borderRadius: BorderRadius.circular({ radius: 8 }) })} onPress={() => controller.submitReview(2)}>Hard</Button>
          </Expanded>
          <SizedBox width={8} />
          <Expanded>
            <Button style={ButtonStyle.secondary({ borderRadius: BorderRadius.circular({ radius: 8 }) })} onPress={() => controller.submitReview(3)}>Good</Button>
          </Expanded>
          <SizedBox width={8} />
          <Expanded>
            <Button style={ButtonStyle.primary({ borderRadius: BorderRadius.circular({ radius: 8 }) })} onPress={() => controller.submitReview(4)}>Easy</Button>
          </Expanded>
        </Row>
      )}
    </Column>
  </Padding>
);
''';

void main() {
  ensureStateInitialized();
  ensureLanguageInitialized();

  group('Flashcard Template Highlighting', () {
    testWidgets('highlights full flashcard body with TSX', (tester) async {
      final docLength = flashcardBody.length;
      print('Flashcard body length: $docLength chars');
      print('Flashcard body lines: ${flashcardBody.split('\n').length}');

      // Find line 21 (0-indexed line 20)
      final lines = flashcardBody.split('\n');
      print('\nLine 20 (0-indexed): "${lines[19]}"');
      print('Line 21 (0-indexed): "${lines[20]}"');
      print('Line 22 (0-indexed): "${lines[21]}"');

      final state = EditorState.create(EditorStateConfig(
        doc: flashcardBody,
        extensions: ExtensionList([
          javascript(const JavaScriptConfig(jsx: true)).extension,
          syntaxHighlighting(defaultHighlightStyle),
        ]),
      ));

      final key = GlobalKey<EditorViewState>();
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EditorView(key: key, state: state))),
      );
      // Pump multiple times to allow parse worker to complete
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      final viewState = key.currentState!;
      
      // Get decorations
      final decoSources = viewState.state.facet(decorationsFacet);
      print('\nDecoration sources count: ${decoSources.length}');

      final allRanges = <(int, int, String)>[];
      for (final source in decoSources) {
        RangeSet<cm.Decoration>? result;
        if (source is RangeSet<cm.Decoration>) {
          result = source;
        } else if (source is Function) {
          result = (source as dynamic)(viewState) as RangeSet<cm.Decoration>?;
        }
        if (result != null && !result.isEmpty) {
          final cursor = result.iter();
          while (cursor.value != null) {
            if (cursor.value is cm.MarkDecoration) {
              allRanges.add((cursor.from, cursor.to, (cursor.value as cm.MarkDecoration).className));
            }
            cursor.next();
          }
        }
      }

      print('\nTotal decorations: ${allRanges.length}');

      // Calculate offset of line 21 (0-indexed line 20) first
      var offsetToLine21 = 0;
      for (var i = 0; i < 20; i++) {
        offsetToLine21 += lines[i].length + 1; // +1 for newline
      }

      // Print distribution by position
      final rangesInFirst614 = allRanges.where((r) => r.$2 <= offsetToLine21).length;
      final rangesAfter614 = allRanges.where((r) => r.$1 >= offsetToLine21).length;
      final rangesOverlapping614 = allRanges.where((r) => r.$1 < offsetToLine21 && r.$2 > offsetToLine21).length;
      print('Decorations ending before offset $offsetToLine21: $rangesInFirst614');
      print('Decorations starting after offset $offsetToLine21: $rangesAfter614');
      print('Decorations overlapping offset $offsetToLine21: $rangesOverlapping614');

      // Sort by position
      allRanges.sort((a, b) => a.$1.compareTo(b.$1));

      // Find the last decoration
      final lastDeco = allRanges.last;
      print('Last decoration: ${lastDeco.$3} at ${lastDeco.$1}-${lastDeco.$2}');
      
      // Check if decorations cover the full document
      final lastDecoEnd = allRanges.map((r) => r.$2).reduce((a, b) => a > b ? a : b);
      print('Last decoration end position: $lastDecoEnd');
      print('Document length: $docLength');
      
      print('Offset to start of line 21 (0-indexed 20): $offsetToLine21');
      
      // Find decorations after line 21 (decorations that END after line 21)
      final decosAfterLine21 = allRanges.where((r) => r.$2 > offsetToLine21).toList();
      print('Decorations ending after line 21: ${decosAfterLine21.length}');
      
      // CRITICAL ASSERTION: There should be many decorations covering content after line 21
      // The content from line 21-48 is about 1240 characters and should have many more decorations
      expect(decosAfterLine21.length, greaterThan(5), 
          reason: 'Should have decorations covering content after line 21');
      
      // Print details for analysis
      print('\nAnalyzing decoration gaps...');
      
      // Find the largest gap in decorations
      final sortedEnds = allRanges.map((r) => r.$2).toList()..sort();
      final sortedStarts = allRanges.map((r) => r.$1).toList()..sort();
      
      var maxGapStart = 0;
      var maxGapEnd = 0;
      for (var i = 0; i < allRanges.length - 1; i++) {
        final currEnd = sortedEnds[i];
        final nextStart = sortedStarts.firstWhere((s) => s >= currEnd, orElse: () => sortedEnds.last);
        if (nextStart - currEnd > maxGapEnd - maxGapStart) {
          maxGapStart = currEnd;
          maxGapEnd = nextStart;
        }
      }
      print('Largest decoration gap: $maxGapStart - $maxGapEnd (${maxGapEnd - maxGapStart} chars)');
      if (maxGapEnd - maxGapStart > 10) {
        print('Gap text preview: "${flashcardBody.substring(maxGapStart, (maxGapEnd).clamp(0, flashcardBody.length)).substring(0, 50.clamp(0, maxGapEnd - maxGapStart))}..."');
      }
      
      // The last decoration should reach near the end of the document
      // (there may be trailing whitespace/newlines without decorations)
      expect(lastDecoEnd, greaterThan(docLength - 10), 
          reason: 'Last decoration should be near end of document');

      // Print some decorations after line 21 for debugging
      print('\nFirst 10 decorations after line 21:');
      for (final deco in decosAfterLine21.take(10)) {
        final text = flashcardBody.substring(
          deco.$1.clamp(0, flashcardBody.length),
          deco.$2.clamp(0, flashcardBody.length),
        );
        final preview = text.length > 30 ? '${text.substring(0, 30)}...' : text;
        print('  ${deco.$3}: "$preview" at ${deco.$1}-${deco.$2}');
      }
    });

    testWidgets('tree length equals document length', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: flashcardBody,
        extensions: ExtensionList([
          javascript(const JavaScriptConfig(jsx: true)).extension,
          syntaxHighlighting(defaultHighlightStyle),
        ]),
      ));

      final key = GlobalKey<EditorViewState>();
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EditorView(key: key, state: state))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final viewState = key.currentState!;
      
      // Get the syntax tree
      final tree = syntaxTree(viewState.state);
      print('Tree length: ${tree.length}');
      print('Doc length: ${viewState.state.doc.length}');
      
      expect(tree.length, viewState.state.doc.length, 
          reason: 'Tree should parse the entire document');
    });
  });
}
