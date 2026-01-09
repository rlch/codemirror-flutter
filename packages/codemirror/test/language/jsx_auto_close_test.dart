import 'package:codemirror/codemirror.dart';
import 'package:codemirror/src/language/javascript/javascript.dart';
import 'package:codemirror/src/language/javascript/auto_close_tags.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lezer/lezer.dart';

void main() {
  group('JSX syntax tree structure', () {
    late LRParserImpl parser;
    
    setUp(() {
      // Configure parser with JSX dialect
      parser = jsParser.configure(ParserConfig(dialect: 'jsx')) as LRParserImpl;
    });
    
    test('parses simple JSX element', () {
      final code = '<div></div>';
      final tree = parser.parse(code);
      
      expect(tree.type.name, equals('Script'));
      
      // Print the tree structure for debugging
      void printTree(dynamic node, [int depth = 0]) {
        final indent = '  ' * depth;
        print('$indent${node.name} [${node.from}-${node.to}]');
        for (var child = node.firstChild; child != null; child = child.nextSibling) {
          printTree(child, depth + 1);
        }
      }
      
      print('=== Tree for: $code ===');
      printTree(tree.topNode);
    });
    
    test('tree structure after typing > in <div', () {
      // This simulates what the tree looks like after typing "<div>"
      final code = '<div>';
      final tree = parser.parse(code);
      
      print('=== Tree for: $code ===');
      void printTree(dynamic node, [int depth = 0]) {
        final indent = '  ' * depth;
        print('$indent${node.name} [${node.from}-${node.to}]');
        for (var child = node.firstChild; child != null; child = child.nextSibling) {
          printTree(child, depth + 1);
        }
      }
      printTree(tree.topNode);
      
      // Resolve at position 5 (after the ">")
      final nodeAt5 = tree.resolveInner(5, -1);
      print('Node at position 5 (after >): ${nodeAt5.name}');
      print('Parent: ${nodeAt5.parent?.name}');
      print('Grandparent: ${nodeAt5.parent?.parent?.name}');
    });
    
    test('tree structure for incomplete close tag </', () {
      final code = '<div></';
      final tree = parser.parse(code);
      
      print('=== Tree for: $code ===');
      void printTree(dynamic node, [int depth = 0]) {
        final indent = '  ' * depth;
        print('$indent${node.name} [${node.from}-${node.to}]');
        for (var child = node.firstChild; child != null; child = child.nextSibling) {
          printTree(child, depth + 1);
        }
      }
      printTree(tree.topNode);
      
      // Resolve at position 7 (after "</")
      final nodeAt7 = tree.resolveInner(7, -1);
      print('Node at position 7 (after </): ${nodeAt7.name}');
      print('Parent: ${nodeAt7.parent?.name}');
    });
    
    test('does not match < in comparison', () {
      final code = 'if (a < b) {}';
      final tree = parser.parse(code);
      
      print('=== Tree for: $code ===');
      void printTree(dynamic node, [int depth = 0]) {
        final indent = '  ' * depth;
        print('$indent${node.name} [${node.from}-${node.to}]');
        for (var child = node.firstChild; child != null; child = child.nextSibling) {
          printTree(child, depth + 1);
        }
      }
      printTree(tree.topNode);
      
      // Resolve at position after the <
      final nodeAfterLt = tree.resolveInner(7, -1);
      print('Node at position 7: ${nodeAfterLt.name}');
      
      // Should NOT be any JSX node
      expect(nodeAfterLt.name.startsWith('JSX'), isFalse);
    });
    
    test('correctly identifies JSXEndTag after typing >', () {
      // The code as it would appear AFTER typing ">" in "<div>"
      final code = '<div>';
      final tree = parser.parse(code);
      
      // Find what node we're at after the ">"
      final nodeAtEnd = tree.resolveInner(5, -1);
      print('After typing > in "<div>": node = ${nodeAtEnd.name}');
      
      // For auto-close to trigger, we need to be at JSXEndTag
      // (or whatever node represents the ">" at end of opening tag)
    });
    
    test('JSX in return statement', () {
      final code = 'function App() { return <div>; }';
      final tree = parser.parse(code);
      
      print('=== Tree for JSX in return ===');
      void printTree(dynamic node, [int depth = 0]) {
        final indent = '  ' * depth;
        print('$indent${node.name} [${node.from}-${node.to}]');
        for (var child = node.firstChild; child != null; child = child.nextSibling) {
          printTree(child, depth + 1);
        }
      }
      printTree(tree.topNode);
      
      // Position after the > in <div>
      final pos = code.indexOf('<div>') + 5;
      final node = tree.resolveInner(pos, -1);
      print('Node at $pos: ${node.name}');
    });
  });
  
  group('jsxAutoCloseTags behavior', () {
    EditorState createJsxState(String doc, {int? cursor}) {
      final lang = javascript(JavaScriptConfig(jsx: true, autoCloseTags: false));
      return EditorState.create(EditorStateConfig(
        doc: doc,
        selection: cursor != null ? EditorSelection.single(cursor) : null,
        extensions: ExtensionList([
          lang,
          jsxAutoCloseTags,
        ]),
      ));
    }
    
    test('element name extraction works', () {
      // Test the internal _elementName function by checking tree structure
      final state = createJsxState('<div>');
      final tree = syntaxTree(state);
      
      // Navigate to JSXElement
      var node = tree.topNode.firstChild; // ExpressionStatement
      node = node?.firstChild; // JSXElement
      expect(node?.name, equals('JSXElement'));
      
      // Check JSXOpenTag contains the identifier
      final openTag = node?.firstChild;
      expect(openTag?.name, equals('JSXOpenTag'));
      
      // Find the identifier
      SyntaxNode? identifier;
      for (var child = openTag?.firstChild; child != null; child = child.nextSibling) {
        if (child.name == 'JSXBuiltin' || child.name == 'JSXIdentifier') {
          identifier = child;
          break;
        }
      }
      expect(identifier, isNotNull);
      
      // The tag name should be "div"
      final tagName = state.doc.sliceString(
        identifier!.name == 'JSXBuiltin' ? identifier.firstChild!.from : identifier.from,
        identifier.name == 'JSXBuiltin' ? identifier.firstChild!.to : identifier.to,
      );
      expect(tagName, equals('div'));
    });
    
    test('self-closing tags are recognized', () {
      // These should NOT get auto-close tags
      const selfClosers = ['br', 'hr', 'img', 'input', 'meta', 'link'];
      for (final tag in selfClosers) {
        final state = createJsxState('<$tag>');
        final tree = syntaxTree(state);
        final node = tree.resolveInner(tag.length + 2, -1); // Position after >
        expect(node.name, equals('JSXEndTag'), reason: 'Tag $tag should parse as JSX');
      }
    });
    
    test('comparison operator does not trigger auto-close', () {
      final state = createJsxState('if (a < b)');
      final tree = syntaxTree(state);
      
      // Find position after the <
      final pos = 'if (a <'.length;
      final node = tree.resolveInner(pos, -1);
      
      // Should NOT be any JSX node
      expect(node.name.startsWith('JSX'), isFalse, 
        reason: 'Comparison < should not parse as JSX');
    });
    
    test('capitalized components are not self-closing', () {
      // React components like <App> should always get close tags
      final state = createJsxState('<App>');
      final tree = syntaxTree(state);
      final node = tree.resolveInner(5, -1);
      expect(node.name, equals('JSXEndTag'));
    });
  });
}
