import 'package:lezer/lezer.dart' as lezer;
import 'package:lezer/lezer.dart' show Tag, TagStyle, tagHighlighter, NodeType, NodeProp, styleTags, ruleNodeProp, Rule;
import 'package:test/test.dart';

void main() {
  group('Tag', () {
    test('defines a basic tag', () {
      final tag = Tag.define('test');
      expect(tag.name, equals('test'));
      expect(tag.set, contains(tag));
    });

    test('derives from parent tag', () {
      final parent = Tag.define('parent');
      final child = Tag.define('child', parent);
      
      expect(child.set, contains(child));
      expect(child.set, contains(parent));
    });

    test('toString includes name', () {
      final tag = Tag.define('keyword');
      expect(tag.toString(), equals('keyword'));
    });

    test('modifier creates subtag', () {
      final modifier = Tag.defineModifier('bold');
      final base = Tag.define('text');
      final modified = modifier(base);
      
      expect(modified.base, equals(base));
      expect(modified.modified.length, equals(1));
    });

    test('same modifier returns same tag', () {
      final modifier = Tag.defineModifier('italic');
      final base = Tag.define('content');
      
      final first = modifier(base);
      final second = modifier(base);
      
      expect(identical(first, second), isTrue);
    });

    test('multiple modifiers combine', () {
      final bold = Tag.defineModifier('bold');
      final italic = Tag.defineModifier('italic');
      final base = Tag.define('text');
      
      final boldItalic1 = italic(bold(base));
      final boldItalic2 = bold(italic(base));
      
      // Order shouldn't matter
      expect(boldItalic1.modified.length, equals(2));
      expect(boldItalic2.modified.length, equals(2));
    });
  });

  group('lezer.Tags', () {
    test('has standard tags', () {
      expect(lezer.Tags.comment, isNotNull);
      expect(lezer.Tags.keyword, isNotNull);
      expect(lezer.Tags.string, isNotNull);
      expect(lezer.Tags.number, isNotNull);
      expect(lezer.Tags.operator, isNotNull);
    });

    test('comment subtags derive from comment', () {
      expect(lezer.Tags.lineComment.set, contains(lezer.Tags.comment));
      expect(lezer.Tags.blockComment.set, contains(lezer.Tags.comment));
      expect(lezer.Tags.docComment.set, contains(lezer.Tags.comment));
    });

    test('has modifiers', () {
      final definedVar = lezer.Tags.definition(lezer.Tags.variableName);
      expect(definedVar.base, equals(lezer.Tags.variableName));
    });
  });

  group('tagHighlighter', () {
    test('creates a highlighter', () {
      final highlighter = tagHighlighter([
        TagStyle(tag: lezer.Tags.keyword, className: 'kw'),
        TagStyle(tag: lezer.Tags.string, className: 'str'),
      ]);
      
      expect(highlighter.style([lezer.Tags.keyword]), equals('kw'));
      expect(highlighter.style([lezer.Tags.string]), equals('str'));
    });

    test('returns null for unmatched tags', () {
      final highlighter = tagHighlighter([
        TagStyle(tag: lezer.Tags.keyword, className: 'kw'),
      ]);
      
      expect(highlighter.style([lezer.Tags.number]), isNull);
    });

    test('matches parent tags', () {
      final highlighter = tagHighlighter([
        TagStyle(tag: lezer.Tags.comment, className: 'comment'),
      ]);
      
      // lineComment is a child of comment
      expect(highlighter.style([lezer.Tags.lineComment]), equals('comment'));
    });

    test('respects all option', () {
      final highlighter = tagHighlighter(
        [TagStyle(tag: lezer.Tags.keyword, className: 'kw')],
        all: 'token',
      );
      
      expect(highlighter.style([lezer.Tags.keyword]), equals('token kw'));
      expect(highlighter.style([lezer.Tags.string]), equals('token'));
    });

    test('handles multiple tags', () {
      final highlighter = tagHighlighter([
        TagStyle(tag: [lezer.Tags.keyword, lezer.Tags.operator], className: 'special'),
      ]);
      
      expect(highlighter.style([lezer.Tags.keyword]), equals('special'));
      expect(highlighter.style([lezer.Tags.operator]), equals('special'));
    });
  });

  group('styleTags', () {
    test('creates a prop source for simple names', () {
      final source = styleTags({
        'Number': lezer.Tags.number,
        'String': lezer.Tags.string,
      });
      
      final numberType = NodeType.define(id: 0, name: 'Number');
      final result = source(numberType);
      
      expect(result, isNotNull);
      expect(result!.$1, equals(ruleNodeProp));
      expect((result.$2 as Rule).tags, contains(lezer.Tags.number));
    });

    test('handles multiple names in one entry', () {
      final source = styleTags({
        'Number BigNumber': lezer.Tags.number,
      });
      
      final numberType = NodeType.define(id: 0, name: 'Number');
      final bigNumberType = NodeType.define(id: 1, name: 'BigNumber');
      
      expect(source(numberType), isNotNull);
      expect(source(bigNumberType), isNotNull);
    });

    test('handles opaque paths', () {
      final source = styleTags({
        'Attribute!': lezer.Tags.meta,
      });
      
      final type = NodeType.define(id: 0, name: 'Attribute');
      final result = source(type);
      
      expect(result, isNotNull);
      expect((result!.$2 as Rule).opaque, isTrue);
    });

    test('handles inherit paths', () {
      final source = styleTags({
        'Emphasis/...': lezer.Tags.emphasis,
      });
      
      final type = NodeType.define(id: 0, name: 'Emphasis');
      final result = source(type);
      
      expect(result, isNotNull);
      expect((result!.$2 as Rule).inherit, isTrue);
    });
  });
}
