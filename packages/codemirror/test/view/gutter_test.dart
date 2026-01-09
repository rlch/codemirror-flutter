import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codemirror/src/state/facet.dart' hide EditorState, Transaction;
import 'package:codemirror/src/state/range_set.dart';
import 'package:codemirror/src/state/state.dart';
import 'package:codemirror/src/view/gutter.dart';

// Test marker implementation
class TestMarker extends GutterMarker {
  final String label;
  
  TestMarker(this.label);
  
  @override
  bool markerEq(GutterMarker other) => 
      other is TestMarker && label == other.label;
  
  @override
  Widget? toWidget(BuildContext context) => Text(label);
  
  @override
  String get elementClass => 'test-marker';
}

void main() {
  group('GutterMarker', () {
    test('compare returns true for same instance', () {
      final marker = TestMarker('test');
      expect(marker.compare(marker), isTrue);
    });

    test('compare returns true for equal markers', () {
      final marker1 = TestMarker('test');
      final marker2 = TestMarker('test');
      expect(marker1.compare(marker2), isTrue);
    });

    test('compare returns false for different markers', () {
      final marker1 = TestMarker('test1');
      final marker2 = TestMarker('test2');
      expect(marker1.compare(marker2), isFalse);
    });

    test('has correct default RangeValue properties', () {
      final marker = TestMarker('test');
      expect(marker.startSide, -1);
      expect(marker.endSide, -1);
      expect(marker.point, isTrue);
    });
  });

  group('GutterConfig', () {
    test('has sensible defaults', () {
      const config = GutterConfig();
      expect(config.className, isNull);
      expect(config.renderEmptyElements, isFalse);
      expect(config.side, GutterSide.before);
    });

    test('can customize all properties', () {
      const config = GutterConfig(
        className: 'my-gutter',
        renderEmptyElements: true,
        side: GutterSide.after,
      );
      expect(config.className, 'my-gutter');
      expect(config.renderEmptyElements, isTrue);
      expect(config.side, GutterSide.after);
    });
  });

  group('GutterSide', () {
    test('has before and after values', () {
      expect(GutterSide.before, isNotNull);
      expect(GutterSide.after, isNotNull);
      expect(GutterSide.before, isNot(GutterSide.after));
    });
  });

  group('gutter extension', () {
    test('creates extension with config', () {
      final ext = gutter(const GutterConfig(className: 'test'));
      expect(ext, isA<Extension>());
    });
  });

  group('gutters extension', () {
    test('creates extension', () {
      final ext = gutters();
      expect(ext, isA<Extension>());
    });

    test('accepts fixed parameter', () {
      final fixedExt = gutters(fixed: true);
      expect(fixedExt, isA<Extension>());
      
      final unfixedExt = gutters(fixed: false);
      expect(unfixedExt, isA<Extension>());
    });
  });

  group('NumberMarker', () {
    test('stores number string', () {
      final marker = NumberMarker('42');
      expect(marker.number, '42');
    });

    test('markerEq compares numbers', () {
      final m1 = NumberMarker('42');
      final m2 = NumberMarker('42');
      final m3 = NumberMarker('43');
      
      expect(m1.markerEq(m2), isTrue);
      expect(m1.markerEq(m3), isFalse);
    });
  });

  group('lineNumbers extension', () {
    test('creates extension', () {
      final ext = lineNumbers();
      expect(ext, isA<Extension>());
    });

    test('accepts config', () {
      final ext = lineNumbers(LineNumberConfig(
        formatNumber: (n, _) => 'Line $n',
      ));
      expect(ext, isA<Extension>());
    });
  });

  group('highlightActiveLineGutter', () {
    test('creates extension', () {
      final ext = highlightActiveLineGutter();
      expect(ext, isA<Extension>());
    });
  });

  group('gutterLineClass facet', () {
    test('can provide markers', () {
      final markers = RangeSet.of<GutterMarker>([
        Range.create(0, 0, TestMarker('test')),
      ]);
      
      final state = EditorState.create(EditorStateConfig(
        doc: 'Hello',
        extensions: gutterLineClass.of(markers),
      ));
      
      final result = state.facet(gutterLineClass);
      expect(result, hasLength(1));
    });
  });

  group('activeGutters facet', () {
    test('collects gutter configs', () {
      final state = EditorState.create(EditorStateConfig(
        extensions: ExtensionList([
          gutter(const GutterConfig(className: 'gutter1')),
          gutter(const GutterConfig(className: 'gutter2')),
        ]),
      ));
      
      final gutters = state.facet(activeGutters);
      expect(gutters.length, 2);
      expect(gutters[0].className, 'gutter1');
      expect(gutters[1].className, 'gutter2');
    });
  });

  group('lineNumberMarkers facet', () {
    test('can provide markers to line number gutter', () {
      final markers = RangeSet.of<GutterMarker>([
        Range.create(0, 0, TestMarker('bp')),
      ]);
      
      final state = EditorState.create(EditorStateConfig(
        doc: 'Hello',
        extensions: lineNumberMarkers.of(markers),
      ));
      
      final result = state.facet(lineNumberMarkers);
      expect(result, hasLength(1));
    });
  });
}
