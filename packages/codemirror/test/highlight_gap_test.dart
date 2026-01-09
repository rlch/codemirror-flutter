/// Tests to isolate the highlighting gap issue.
import 'package:codemirror/codemirror.dart' hide Text;
import 'package:flutter_test/flutter_test.dart' hide lessThan;
import 'package:lezer/lezer.dart';

/// The flashcard template body
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

  group('Highlighting Gap Analysis', () {
    test('highlightTree produces spans covering the entire document', () {
      // Parse with JavaScript/JSX
      final lang = javascript(const JavaScriptConfig(jsx: true));
      final parser = lang.language.parser;
      
      print('Document length: ${flashcardBody.length}');
      
      // Parse synchronously with long timeout
      final tree = parser.parse(flashcardBody);
      print('Tree length: ${tree.length}');
      
      expect(tree.length, flashcardBody.length, reason: 'Tree should parse full document');
      
      // Now highlight
      final spans = <(int, int, String)>[];
      highlightTree(tree, [defaultHighlightStyle], (from, to, classes) {
        spans.add((from, to, classes));
      });
      
      print('Total spans from highlightTree: ${spans.length}');
      
      // Sort by position
      spans.sort((a, b) => a.$1.compareTo(b.$1));
      
      // Find the largest gap
      var maxGapStart = 0;
      var maxGapEnd = 0;
      var prevEnd = 0;
      
      for (final span in spans) {
        if (span.$1 > prevEnd) {
          final gapSize = span.$1 - prevEnd;
          if (gapSize > maxGapEnd - maxGapStart) {
            maxGapStart = prevEnd;
            maxGapEnd = span.$1;
          }
        }
        if (span.$2 > prevEnd) prevEnd = span.$2;
      }
      
      print('Largest gap: $maxGapStart - $maxGapEnd (${maxGapEnd - maxGapStart} chars)');
      if (maxGapEnd - maxGapStart > 10) {
        final gapText = flashcardBody.substring(maxGapStart, maxGapEnd.clamp(0, flashcardBody.length));
        print('Gap text: "${gapText.substring(0, (50).clamp(0, gapText.length))}..."');
      }
      
      // Find the last span
      final lastSpan = spans.last;
      print('Last span: ${lastSpan.$3} at ${lastSpan.$1}-${lastSpan.$2}');
      
      // Check that the gap after line 21 is small
      // Offset to line 21 (0-indexed 20)
      final lines = flashcardBody.split('\n');
      var offsetToLine21 = 0;
      for (var i = 0; i < 20; i++) {
        offsetToLine21 += lines[i].length + 1;
      }
      print('Offset to line 21: $offsetToLine21');
      
      // Count spans that cover content after line 21
      final spansAfterLine21 = spans.where((s) => s.$2 > offsetToLine21).length;
      print('Spans ending after line 21: $spansAfterLine21');
      
      // Find span coverage around the problematic area
      final spansAtGapStart = spans.where((s) => s.$1 <= maxGapStart && s.$2 >= maxGapStart).toList();
      final spansAtGapEnd = spans.where((s) => s.$1 <= maxGapEnd && s.$2 >= maxGapEnd).toList();
      print('Spans at gap start ($maxGapStart): ${spansAtGapStart.length}');
      print('Spans at gap end ($maxGapEnd): ${spansAtGapEnd.length}');
      
      // Print spans near the gap
      final spansNearGap = spans.where((s) => s.$1 >= maxGapStart - 20 && s.$1 <= maxGapEnd + 20).toList();
      print('\nSpans near the gap:');
      for (final span in spansNearGap) {
        final text = flashcardBody.substring(span.$1, span.$2.clamp(0, flashcardBody.length));
        final preview = text.length > 30 ? '${text.substring(0, 30)}...' : text;
        print('  ${span.$1}-${span.$2}: ${span.$3} "$preview"');
      }
      
      // The gap should not be larger than some reasonable amount (e.g., 50 chars for whitespace)
      expect(maxGapEnd - maxGapStart < 100, true,
          reason: 'There should not be a gap of more than 100 chars without highlighting');
    });

    test('dump tree nodes around the problematic area', () {
      final lang = javascript(const JavaScriptConfig(jsx: true));
      final parser = lang.language.parser;
      final tree = parser.parse(flashcardBody);
      
      // Find offset of "{!showAnswer ? ("
      final problemText = '{!showAnswer ? (';
      final problemOffset = flashcardBody.indexOf(problemText);
      print('Problem offset: $problemOffset');
      print('Problem text: "${flashcardBody.substring(problemOffset, problemOffset + 50)}"');
      
      // Walk the tree and print ALL nodes up to depth 10 that overlap problem area
      print('\nNodes covering problem area ($problemOffset to ${problemOffset + 200}):');
      
      void printNode(SyntaxNode node, int indent) {
        if (indent > 10) return; // limit depth
        
        // Only print if it overlaps with the problem area
        if (node.from <= problemOffset + 200 && node.to >= problemOffset) {
          final indentStr = '  ' * indent;
          final nodeText = flashcardBody.substring(
            node.from, 
            node.to.clamp(0, flashcardBody.length)
          );
          final preview = nodeText.length > 40 
              ? '${nodeText.substring(0, 40).replaceAll('\n', '\\n')}...' 
              : nodeText.replaceAll('\n', '\\n');
          
          // Check for highlighting rule
          final rule = node.type.prop(ruleNodeProp);
          final hasRule = rule != null;
          final tags = rule?.tags ?? [];
          
          print('$indentStr${node.name} [${node.from}-${node.to}] hasRule=$hasRule tags=$tags "$preview"');
        }
        
        // Recurse into children
        for (var child = node.firstChild; child != null; child = child.nextSibling) {
          printNode(child, indent + 1);
        }
      }
      
      printNode(tree.topNode, 0);
    });
    
    test('dump children of JSXElement [127-1838]', () {
      final lang = javascript(const JavaScriptConfig(jsx: true));
      final parser = lang.language.parser;
      final tree = parser.parse(flashcardBody);
      
      // Find the JSXElement that spans 127-1838
      SyntaxNode? findNode(SyntaxNode node, int from, int to) {
        if (node.from == from && node.to == to) return node;
        for (var child = node.firstChild; child != null; child = child.nextSibling) {
          final found = findNode(child, from, to);
          if (found != null) return found;
        }
        return null;
      }
      
      final columnElement = findNode(tree.topNode, 127, 1838);
      print('Found Column JSXElement: ${columnElement?.name} [${columnElement?.from}-${columnElement?.to}]');
      
      if (columnElement != null) {
        print('\nDirect children of Column JSXElement:');
        var count = 0;
        for (var child = columnElement.firstChild; child != null; child = child.nextSibling) {
          final text = flashcardBody.substring(child.from, child.to.clamp(0, flashcardBody.length));
          final preview = text.length > 50 
              ? '${text.substring(0, 50).replaceAll('\n', '\\n')}...' 
              : text.replaceAll('\n', '\\n');
          
          final rule = child.type.prop(ruleNodeProp);
          print('  ${child.name} [${child.from}-${child.to}] hasRule=${rule != null} tags=${rule?.tags ?? []} "$preview"');
          count++;
        }
        print('Total direct children: $count');
        
        // Also check using cursor
        print('\nUsing tree cursor to walk children:');
        final cursor = tree.cursor();
        // Navigate to JSXElement at position 127
        while (cursor.next()) {
          if (cursor.name == 'JSXElement' && cursor.from == 127) break;
        }
        if (cursor.name == 'JSXElement' && cursor.from == 127) {
          print('Found Column at cursor position');
          if (cursor.firstChild()) {
            var cursorCount = 0;
            do {
              final text = flashcardBody.substring(cursor.from, cursor.to.clamp(0, flashcardBody.length));
              final preview = text.length > 50 
                  ? '${text.substring(0, 50).replaceAll('\n', '\\n')}...' 
                  : text.replaceAll('\n', '\\n');
              print('  [cursor] ${cursor.name} [${cursor.from}-${cursor.to}] "$preview"');
              cursorCount++;
            } while (cursor.nextSibling());
            print('Total children via cursor: $cursorCount');
          }
        }
      }
      
      // Check the raw tree buffer
      print('\n--- Raw tree structure check ---');
      print('Tree type: ${tree.type.name}');
      print('Tree children count: ${tree.children.length}');
      print('Tree positions: ${tree.positions}');
    });
    
    test('check JSXExpressionContainer and ConditionalExpression', () {
      final lang = javascript(const JavaScriptConfig(jsx: true));
      final parser = lang.language.parser;
      final tree = parser.parse(flashcardBody);
      
      // The missing content starts at position 597
      // Let's check what nodes exist at that position
      print('Checking nodes at position 597:');
      
      final cursor = tree.cursor();
      while (cursor.next()) {
        // Find all nodes that contain position 597
        if (cursor.from <= 597 && cursor.to >= 597) {
          final text = flashcardBody.substring(cursor.from, cursor.to.clamp(0, flashcardBody.length));
          final preview = text.length > 60 
              ? '${text.substring(0, 60).replaceAll('\n', '\\n')}...' 
              : text.replaceAll('\n', '\\n');
          
          print('  ${cursor.name} [${cursor.from}-${cursor.to}] "$preview"');
        }
      }
      
      // Now check what's at position 598 and beyond
      print('\nChecking nodes at position 600:');
      final cursor2 = tree.cursor();
      while (cursor2.next()) {
        if (cursor2.from <= 600 && cursor2.to >= 600) {
          final text = flashcardBody.substring(cursor2.from, cursor2.to.clamp(0, flashcardBody.length));
          final preview = text.length > 60 
              ? '${text.substring(0, 60).replaceAll('\n', '\\n')}...' 
              : text.replaceAll('\n', '\\n');
          
          print('  ${cursor2.name} [${cursor2.from}-${cursor2.to}] "$preview"');
        }
      }
      
      // Check tree buffer details
      print('\n--- Checking tree buffer around the gap ---');
      
      // Use enter to find what's at position 600
      final node = tree.topNode.enter(600, 1);
      print('Node at pos 600: ${node?.name} [${node?.from}-${node?.to}]');
      
      if (node != null) {
        print('Parent chain:');
        var parent = node.parent;
        while (parent != null) {
          print('  <- ${parent.name} [${parent.from}-${parent.to}]');
          parent = parent.parent;
        }
      }
    });
    
    test('dump ALL nodes in tree to find what exists after position 597', () {
      final lang = javascript(const JavaScriptConfig(jsx: true));
      final parser = lang.language.parser;
      final tree = parser.parse(flashcardBody);
      
      print('All nodes with start position >= 590:');
      final cursor = tree.cursor();
      var count = 0;
      while (cursor.next()) {
        if (cursor.from >= 590) {
          final text = flashcardBody.substring(cursor.from, cursor.to.clamp(0, flashcardBody.length));
          final preview = text.length > 50 
              ? '${text.substring(0, 50).replaceAll('\n', '\\n')}...' 
              : text.replaceAll('\n', '\\n');
          
          print('  ${cursor.name} [${cursor.from}-${cursor.to}] "$preview"');
          count++;
          if (count > 30) {
            print('  ... (truncated)');
            break;
          }
        }
      }
    });
    
    test('check if nodes exist in tree buffers', () {
      final lang = javascript(const JavaScriptConfig(jsx: true));
      final parser = lang.language.parser;
      final tree = parser.parse(flashcardBody);
      
      // Manually walk the tree and look for TreeBuffer nodes
      print('Walking tree structure directly...');
      
      void walkTree(Tree t, int offset, int depth) {
        final indent = '  ' * depth;
        print('$indent${t.type.name} [${offset}-${offset + t.length}] isAnonymous=${t.type.isAnonymous}');
        
        for (var i = 0; i < t.children.length; i++) {
          final child = t.children[i];
          final childOffset = t.positions[i] + offset;
          
          if (child is Tree) {
            walkTree(child, childOffset, depth + 1);
          } else if (child is TreeBuffer) {
            print('$indent  [TreeBuffer] positions ${childOffset} to ${childOffset + child.length}, ${child.buffer.length ~/ 4} entries');
            
            // Parse the buffer to see what's inside
            final buf = child.buffer;
            print('$indent    First 10 buffer entries:');
            for (var j = 0; j < buf.length && j < 40; j += 4) {
              final nodeId = buf[j];
              final start = buf[j + 1];
              final end = buf[j + 2];
              final parent = buf[j + 3];
              print('$indent      node=$nodeId start=${start + childOffset} end=${end + childOffset} parent=$parent');
            }
          }
        }
      }
      
      walkTree(tree, 0, 0);
    });
    
    test('test cursor with includeAnonymous', () {
      final lang = javascript(const JavaScriptConfig(jsx: true));
      final parser = lang.language.parser;
      final tree = parser.parse(flashcardBody);
      
      print('Cursor with default mode - nodes from 590+:');
      final cursor1 = tree.cursor();
      var count1 = 0;
      while (cursor1.next()) {
        if (cursor1.from >= 590 && count1 < 20) {
          print('  ${cursor1.name} [${cursor1.from}-${cursor1.to}]');
          count1++;
        }
      }
      
      print('\nCursor including anonymous nodes - nodes from 590+:');
      final cursor2 = tree.cursor(IterMode.includeAnonymous);
      var count2 = 0;
      while (cursor2.next()) {
        if (cursor2.from >= 590 && count2 < 30) {
          print('  ${cursor2.name} [${cursor2.from}-${cursor2.to}] isAnonymous=${cursor2.type.isAnonymous}');
          count2++;
        }
      }
    });
    
    test('simulate highlightTree traversal pattern', () {
      final lang = javascript(const JavaScriptConfig(jsx: true));
      final parser = lang.language.parser;
      final tree = parser.parse(flashcardBody);
      
      // Navigate to the Column JSXElement [127-1838]
      final cursor = tree.cursor();
      while (cursor.next()) {
        if (cursor.name == 'JSXElement' && cursor.from == 127 && cursor.to == 1838) {
          break;
        }
      }
      print('Found Column: ${cursor.name} [${cursor.from}-${cursor.to}]');
      
      // Now simulate highlightTree: enter first child and iterate siblings
      print('\nSimulating highlightTree traversal (firstChild, then nextSibling):');
      if (cursor.firstChild()) {
        var count = 0;
        do {
          print('  ${cursor.name} [${cursor.from}-${cursor.to}]');
          count++;
          if (count > 20) {
            print('  ... (limit reached)');
            break;
          }
        } while (cursor.nextSibling());
      }
      cursor.parent();
      
      print('\nExpected: Should see JSXEscape [597-1824] after JSXText [590-597]');
    });
    
    test('debug anonymous node traversal', () {
      final lang = javascript(const JavaScriptConfig(jsx: true));
      final parser = lang.language.parser;
      final tree = parser.parse(flashcardBody);
      
      // Find the anonymous node [597-1829] and check its children
      print('Looking at tree structure around position 597...');
      
      // Walk tree manually
      void inspectNode(Tree t, int offset, int depth, String indent) {
        final typeInfo = t.type.isAnonymous ? ' (ANON)' : '';
        print('$indent${t.type.name} [${offset}-${offset + t.length}]$typeInfo');
        
        for (var i = 0; i < t.children.length; i++) {
          final child = t.children[i];
          final childOffset = t.positions[i] + offset;
          
          // Only print nodes near 597
          final childEnd = childOffset + (child is Tree ? child.length : (child as TreeBuffer).length);
          if (childEnd < 580 || childOffset > 650) continue;
          
          if (child is Tree) {
            inspectNode(child, childOffset, depth + 1, '$indent  ');
          } else {
            print('$indent  [TreeBuffer] [${childOffset}-${childEnd}]');
          }
        }
      }
      
      inspectNode(tree, 0, 0, '');
    });
  });
}
