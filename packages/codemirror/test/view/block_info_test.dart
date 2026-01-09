import 'package:codemirror/src/view/block_info.dart';
import 'package:test/test.dart';

void main() {
  group('BlockInfo', () {
    test('creates with basic properties', () {
      const block = BlockInfo(0, 10, 0, 20);
      expect(block.from, 0);
      expect(block.length, 10);
      expect(block.to, 10);
      expect(block.top, 0);
      expect(block.height, 20);
      expect(block.bottom, 20);
    });

    test('default type is text', () {
      const block = BlockInfo(0, 10, 0, 20);
      expect(block.type, BlockType.text);
      expect(block.isWidget, false);
    });

    test('widget types are recognized', () {
      const before = BlockInfo(0, 0, 0, 10, BlockType.widgetBefore);
      expect(before.type, BlockType.widgetBefore);
      expect(before.isWidget, true);

      const after = BlockInfo(0, 0, 0, 10, BlockType.widgetAfter);
      expect(after.type, BlockType.widgetAfter);
      expect(after.isWidget, true);

      const range = BlockInfo(0, 10, 0, 10, BlockType.widgetRange);
      expect(range.type, BlockType.widgetRange);
      expect(range.isWidget, true);
    });

    test('children can be stored', () {
      final children = [
        const BlockInfo(0, 5, 0, 10),
        const BlockInfo(5, 5, 10, 10),
      ];
      final block = BlockInfo(0, 10, 0, 20, children);
      expect(block.children, children);
    });

    test('scale adjusts top and height', () {
      const block = BlockInfo(0, 10, 100, 20);
      final scaled = block.scale(2);
      expect(scaled.from, 0);
      expect(scaled.length, 10);
      expect(scaled.top, 200);
      expect(scaled.height, 40);
    });

    test('scale with 1 returns same block', () {
      const block = BlockInfo(0, 10, 100, 20);
      final scaled = block.scale(1);
      expect(identical(scaled, block), true);
    });

    test('withTop creates copy with new top', () {
      const block = BlockInfo(0, 10, 100, 20);
      final moved = block.withTop(50);
      expect(moved.from, 0);
      expect(moved.top, 50);
      expect(moved.height, 20);
    });

    test('withTop with same value returns same block', () {
      const block = BlockInfo(0, 10, 100, 20);
      final moved = block.withTop(100);
      expect(identical(moved, block), true);
    });

    test('withHeight creates copy with new height', () {
      const block = BlockInfo(0, 10, 100, 20);
      final resized = block.withHeight(30);
      expect(resized.from, 0);
      expect(resized.top, 100);
      expect(resized.height, 30);
    });

    test('equality', () {
      const block1 = BlockInfo(0, 10, 100, 20);
      const block2 = BlockInfo(0, 10, 100, 20);
      const block3 = BlockInfo(0, 10, 100, 25);

      expect(block1 == block2, true);
      expect(block1 == block3, false);
      expect(block1.hashCode, block2.hashCode);
    });

    test('toString', () {
      const block = BlockInfo(0, 10, 100.5, 20.5);
      expect(
        block.toString(),
        'BlockInfo(0+10, top: 100.5, height: 20.5)',
      );
    });
  });

  group('BlockType', () {
    test('has all expected values', () {
      expect(BlockType.values, contains(BlockType.text));
      expect(BlockType.values, contains(BlockType.widgetBefore));
      expect(BlockType.values, contains(BlockType.widgetAfter));
      expect(BlockType.values, contains(BlockType.widgetRange));
    });
  });
}
