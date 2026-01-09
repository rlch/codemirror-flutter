import 'package:codemirror/codemirror.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JavaScript Parser', () {
    test('parses simple function', () {
      final code = '''function greet(name) {
  return "Hello";
}
''';
      
      final tree = jsParser.parse(code);
      expect(tree.length, equals(code.length));
      expect(tree.type.name, equals('Script'));
    });
    
    test('parses class', () {
      final code = '''class Person {
  constructor(name) {
    this.name = name;
  }
}
''';
      
      final tree = jsParser.parse(code);
      expect(tree.length, equals(code.length));
    });
    
    test('parses arrow function', () {
      final code = 'const add = (a, b) => a + b;';
      
      final tree = jsParser.parse(code);
      expect(tree.length, equals(code.length));
    });
  });
}
