import 'package:codemirror/src/view/viewport.dart';
import 'package:test/test.dart';

void main() {
  group('Viewport', () {
    test('creates viewport with from and to', () {
      const vp = Viewport(10, 50);
      expect(vp.from, 10);
      expect(vp.to, 50);
      expect(vp.length, 40);
    });

    test('empty viewport', () {
      const vp = Viewport.empty();
      expect(vp.from, 0);
      expect(vp.to, 0);
      expect(vp.isEmpty, true);
    });

    test('contains checks position', () {
      const vp = Viewport(10, 50);
      expect(vp.contains(10), true);
      expect(vp.contains(30), true);
      expect(vp.contains(50), true);
      expect(vp.contains(9), false);
      expect(vp.contains(51), false);
    });

    test('overlaps checks range overlap', () {
      const vp = Viewport(10, 50);
      expect(vp.overlaps(0, 15), true);
      expect(vp.overlaps(40, 60), true);
      expect(vp.overlaps(20, 30), true);
      expect(vp.overlaps(0, 10), true);
      expect(vp.overlaps(50, 60), true);
      expect(vp.overlaps(0, 9), false);
      expect(vp.overlaps(51, 60), false);
    });

    test('copyWith creates modified copy', () {
      const vp = Viewport(10, 50);
      final vp2 = vp.copyWith(from: 5);
      expect(vp2.from, 5);
      expect(vp2.to, 50);

      final vp3 = vp.copyWith(to: 100);
      expect(vp3.from, 10);
      expect(vp3.to, 100);
    });

    test('equality', () {
      const vp1 = Viewport(10, 50);
      const vp2 = Viewport(10, 50);
      const vp3 = Viewport(10, 60);

      expect(vp1 == vp2, true);
      expect(vp1 == vp3, false);
      expect(vp1.hashCode, vp2.hashCode);
    });

    test('toString', () {
      const vp = Viewport(10, 50);
      expect(vp.toString(), 'Viewport(10, 50)');
    });
  });

  group('ScrollTarget', () {
    test('creates with defaults', () {
      const target = ScrollTarget(5);
      expect(target.range, 5);
      expect(target.y, 'nearest');
      expect(target.x, 'nearest');
      expect(target.yMargin, 5);
      expect(target.xMargin, 5);
      expect(target.isSnapshot, false);
    });

    test('creates with custom values', () {
      const target = ScrollTarget(
        10,
        y: 'center',
        x: 'start',
        yMargin: 20,
        xMargin: 15,
        isSnapshot: true,
      );
      expect(target.range, 10);
      expect(target.y, 'center');
      expect(target.x, 'start');
      expect(target.yMargin, 20);
      expect(target.xMargin, 15);
      expect(target.isSnapshot, true);
    });
  });

  group('VP constants', () {
    test('has expected values', () {
      expect(VP.margin, 1000);
      expect(VP.minCoverMargin, 10);
      expect(VP.maxCoverMargin, 250); // margin / 4
      expect(VP.maxDOMHeight, 7000000);
      expect(VP.maxHorizGap, 2000000);
    });
  });
}
