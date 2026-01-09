import 'package:codemirror/src/language/javascript/javascript.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lezer/lezer.dart';

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
  test('Dump tree around gap', () {
    // Configure parser for JSX
    final parser = jsParser.configure(ParserConfig(dialect: 'jsx'));
    
    // Parse the code
    final tree = parser.parse(flashcardBody);
    print('Tree length: ${tree.length}');
    print('Doc length: ${flashcardBody.length}');
    print('');
    
    // Find position 597-700 (around the gap start)
    print('=== Full tree dump for JSXElement[127-1838] ===');
    _dumpAllChildren(tree, flashcardBody, 127, 1838);
    
    // Also print nodes from 1800-1855 (end of document)
    print('\n=== Nodes covering positions 1800-1855 ===');
    _printNodesInRange(tree, flashcardBody, 1800, 1855);
    
    // Print the text at those positions
    print('\n=== Text at positions 590-650 ===');
    print('"${flashcardBody.substring(590, 650)}"');
  });
}

void _printNodesInRange(Tree tree, String source, int from, int to) {
  final cursor = tree.cursor();
  do {
    // Check if this node overlaps our range
    if (cursor.from < to && cursor.to > from) {
      final nodeText = source.substring(
        cursor.from.clamp(0, source.length),
        cursor.to.clamp(0, source.length),
      );
      final preview = nodeText.length > 50 
          ? '${nodeText.substring(0, 50)}...' 
          : nodeText;
      final previewClean = preview.replaceAll('\n', '\\n');
      
      // Get the node's highlight prop
      final rule = cursor.type.prop(ruleNodeProp);
      final tags = rule?.tags.map((t) => t.toString()).join(', ') ?? 'no tags';
      
      print('${cursor.name}[${cursor.from}-${cursor.to}] tags=[$tags]: "$previewClean"');
    }
    
    if (cursor.firstChild()) {
      // Continue traversing
    } else {
      while (!cursor.nextSibling()) {
        if (!cursor.parent()) return;
      }
    }
  } while (true);
}

void _dumpAllChildren(Tree tree, String source, int from, int to) {
  // Find the node starting at 'from' and dump all its children
  final cursor = tree.cursor();
  
  // Navigate to the target node
  bool found = false;
  do {
    if (cursor.from == from && cursor.to == to) {
      found = true;
      break;
    }
  } while (cursor.next());
  
  if (!found) {
    print('Could not find node at [$from-$to]');
    return;
  }
  
  print('Found: ${cursor.name}[${cursor.from}-${cursor.to}]');
  print('Children count (if available)...');
  
  // List all direct children
  if (cursor.firstChild()) {
    var childCount = 0;
    do {
      childCount++;
      final nodeText = source.substring(
        cursor.from.clamp(0, source.length),
        cursor.to.clamp(0, source.length),
      );
      final preview = nodeText.length > 40 
          ? '${nodeText.substring(0, 40)}...' 
          : nodeText;
      final previewClean = preview.replaceAll('\n', '\\n');
      print('  Child $childCount: ${cursor.name}[${cursor.from}-${cursor.to}]: "$previewClean"');
    } while (cursor.nextSibling());
    print('Total children: $childCount');
  } else {
    print('No children');
  }
}
