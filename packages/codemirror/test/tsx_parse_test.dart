import 'package:codemirror/src/language/javascript/javascript.dart';
import 'package:lezer/lezer.dart';

void main() {
  // Test TSX parsing directly
  final tsxCode = '''// TSX Example
import React, { FC } from 'react';

interface Props {
  name: string;
}

const Hello: FC<Props> = ({ name }) => {
  return <div>Hello {name}</div>;
};
''';

  print('=== Testing TSX Parsing ===');
  print('Input length: ${tsxCode.length}');
  print('');
  
  // Configure parser for TSX
  final parser = jsParser.configure(ParserConfig(dialect: 'jsx ts'));
  print('Parser dialect flags: ${parser.dialect.flags}');
  print('Parser dialects map: ${jsParser.dialects}');
  print('');
  
  // Parse the code
  final tree = parser.parse(tsxCode);
  print('Tree length: ${tree.length}');
  print('Tree type: ${tree.type.name}');
  print('');
  
  // Dump the tree structure
  print('=== Tree Structure ===');
  _printTree(tree, tsxCode, 0);
  
  // Also test just TypeScript (no jsx)
  print('\n=== Testing TypeScript Only ===');
  final tsParser = jsParser.configure(ParserConfig(dialect: 'ts'));
  final tsTree = tsParser.parse(tsxCode);
  print('Tree length: ${tsTree.length}');
  _printTree(tsTree, tsxCode, 0);
  
  // Also test just JSX (no ts)
  print('\n=== Testing JSX Only ===');
  final jsxParser = jsParser.configure(ParserConfig(dialect: 'jsx'));
  final jsxTree = jsxParser.parse(tsxCode);
  print('Tree length: ${jsxTree.length}');
  _printTree(jsxTree, tsxCode, 0);
  
  // Test plain JS
  print('\n=== Testing Plain JS ===');
  final jsParserPlain = jsParser.configure(ParserConfig(dialect: ''));
  final jsTree = jsParserPlain.parse(tsxCode);
  print('Tree length: ${jsTree.length}');
  _printTree(jsTree, tsxCode, 0);
}

void _printTree(Tree tree, String source, int indent) {
  final cursor = tree.cursor();
  var depth = 0;
  do {
    final prefix = '  ' * (indent + depth);
    final nodeText = source.substring(
      cursor.from.clamp(0, source.length),
      cursor.to.clamp(0, source.length),
    );
    final preview = nodeText.length > 40 
        ? '${nodeText.substring(0, 40)}...' 
        : nodeText;
    final previewClean = preview.replaceAll('\n', '\\n');
    print('$prefix${cursor.name}[${cursor.from}-${cursor.to}]: "$previewClean"');
    
    if (cursor.firstChild()) {
      depth++;
    } else {
      while (!cursor.nextSibling()) {
        if (!cursor.parent()) return;
        depth--;
      }
    }
  } while (true);
}
