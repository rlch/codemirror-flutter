import 'package:codemirror/src/view/block_info.dart';
import 'package:codemirror/src/view/height_map.dart';
import 'package:test/test.dart';

void main() {
  group('HeightOracle', () {
    test('creates with default values', () {
      final oracle = HeightOracle();
      expect(oracle.lineHeight, 14.0);
      expect(oracle.charWidth, 7.0);
      expect(oracle.textHeight, 14.0);
      expect(oracle.lineWrapping, false);
    });

    test('creates with line wrapping', () {
      final oracle = HeightOracle(true);
      expect(oracle.lineWrapping, true);
    });

    test('heightPerLine returns lineHeight', () {
      final oracle = HeightOracle();
      oracle.lineHeight = 20.0;
      expect(oracle.heightPerLine, 20.0);
    });

    test('heightPerChar is zero when not wrapping', () {
      final oracle = HeightOracle(false);
      expect(oracle.heightPerChar, 0);
    });

    test('heightPerChar calculates when wrapping', () {
      final oracle = HeightOracle(true);
      oracle.lineHeight = 20.0;
      oracle.lineLength = 80.0;
      expect(oracle.heightPerChar, 0.25); // 20 / 80
    });

    test('mustRefreshForWrapping detects wrapping changes', () {
      final oracle = HeightOracle(false);
      expect(oracle.mustRefreshForWrapping('pre'), false);
      expect(oracle.mustRefreshForWrapping('pre-wrap'), true);
      expect(oracle.mustRefreshForWrapping('break-spaces'), true);
    });

    test('mustRefreshForHeights detects significant height differences', () {
      final oracle = HeightOracle();
      oracle.lineHeight = 14.0;

      expect(oracle.mustRefreshForHeights([]), false);
      expect(oracle.mustRefreshForHeights([14.0, 14.0]), false);
      expect(oracle.mustRefreshForHeights([14.0, 15.0]), false);
      expect(oracle.mustRefreshForHeights([14.0, 20.0]), true);
    });

    test('refresh updates values', () {
      final oracle = HeightOracle();
      final changed = oracle.refresh(
        'pre-wrap',
        20.0,
        8.0,
        18.0,
        100.0,
        [20.0, 20.0],
      );

      expect(changed, true);
      expect(oracle.lineHeight, 20.0);
      expect(oracle.charWidth, 8.0);
      expect(oracle.textHeight, 18.0);
      expect(oracle.lineLength, 100.0);
      expect(oracle.lineWrapping, true);
    });

    test('refresh returns false when values unchanged', () {
      final oracle = HeightOracle();
      oracle.refresh('pre', 14.0, 7.0, 14.0, 30.0, []);
      final changed = oracle.refresh('pre', 14.0, 7.0, 14.0, 30.0, []);
      expect(changed, false);
    });

    test('heightForLine estimates height', () {
      final oracle = HeightOracle(false);
      oracle.lineHeight = 20.0;

      expect(oracle.heightForLine(50), 20.0);
      expect(oracle.heightForLine(100), 20.0);
    });

    test('heightForLine wraps long lines', () {
      final oracle = HeightOracle(true);
      oracle.lineHeight = 20.0;
      oracle.lineLength = 50.0;

      expect(oracle.heightForLine(50), 20.0);
      expect(oracle.heightForLine(100), 40.0);
      expect(oracle.heightForLine(150), 60.0);
    });
  });

  group('HeightMapLine', () {
    test('creates with length and height', () {
      final line = HeightMapLine(100, 20.0);
      expect(line.length, 100);
      expect(line.height, 20.0);
      expect(line.measured, false);
    });

    test('creates empty', () {
      final line = HeightMapLine.empty();
      expect(line.length, 0);
      expect(line.height, 0);
    });

    test('blockAt returns block info', () {
      final line = HeightMapLine(100, 20.0);
      final oracle = HeightOracle();

      final block = line.blockAt(10, oracle, 0, 0);
      expect(block.from, 0);
      expect(block.length, 100);
      expect(block.top, 0);
      expect(block.height, 20.0);
    });

    test('lineAt by position', () {
      final line = HeightMapLine(100, 20.0);
      final oracle = HeightOracle();

      final block = line.lineAt(50, QueryType.byPos, oracle, 0, 0);
      expect(block.from, 0);
      expect(block.length, 100);
    });

    test('lineAt by height', () {
      final line = HeightMapLine(100, 20.0);
      final oracle = HeightOracle();

      final block = line.lineAt(10, QueryType.byHeight, oracle, 0, 0);
      expect(block.from, 0);
      expect(block.height, 20.0);
    });

    test('forEachLine calls callback for matching range', () {
      final line = HeightMapLine(100, 20.0);
      final oracle = HeightOracle();
      final blocks = <BlockInfo>[];

      line.forEachLine(0, 50, oracle, 0, 0, blocks.add);
      expect(blocks.length, 1);
      expect(blocks[0].from, 0);
    });

    test('forEachLine skips non-matching range', () {
      final line = HeightMapLine(100, 20.0);
      final oracle = HeightOracle();
      final blocks = <BlockInfo>[];

      line.forEachLine(200, 300, oracle, 0, 0, blocks.add);
      expect(blocks, isEmpty);
    });
  });

  group('HeightMap.empty', () {
    test('creates empty height map', () {
      final map = HeightMap.empty();
      expect(map.length, 0);
      expect(map.height, 0);
    });
  });

  group('MeasuredHeights', () {
    test('stores from and heights', () {
      final measured = MeasuredHeights(100, [20.0, 25.0, 20.0]);
      expect(measured.from, 100);
      expect(measured.heights, [20.0, 25.0, 20.0]);
    });
  });

  group('Height change flag', () {
    test('starts false', () {
      clearHeightChangeFlag();
      expect(heightChangeFlag, false);
    });

    test('can be set', () {
      clearHeightChangeFlag();
      setHeightChangeFlag();
      expect(heightChangeFlag, true);
    });

    test('can be cleared', () {
      setHeightChangeFlag();
      clearHeightChangeFlag();
      expect(heightChangeFlag, false);
    });
  });
}
