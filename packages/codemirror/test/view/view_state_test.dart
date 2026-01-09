import 'package:codemirror/codemirror.dart';
import 'package:codemirror/src/view/view_state.dart';
import 'package:codemirror/src/view/viewport.dart';
import 'package:test/test.dart';

void main() {
  // Ensure state module is initialized
  ensureStateInitialized();

  group('ViewState', () {
    late EditorState state;

    setUp(() {
      state = EditorState.create(
        const EditorStateConfig(doc: 'Hello\nWorld\nThis is a test'),
      );
    });

    test('creates from editor state', () {
      final viewState = ViewState(state);
      expect(viewState.state, state);
      expect(viewState.viewport, isNotNull);
      expect(viewState.inView, true);
    });

    test('initializes height oracle', () {
      final viewState = ViewState(state);
      expect(viewState.heightOracle, isNotNull);
      expect(viewState.heightOracle.lineHeight, greaterThan(0));
    });

    test('initializes height map', () {
      final viewState = ViewState(state);
      expect(viewState.heightMap, isNotNull);
    });

    test('has content height', () {
      final viewState = ViewState(state);
      expect(viewState.contentHeight, greaterThanOrEqualTo(0));
    });

    test('has visible ranges', () {
      final viewState = ViewState(state);
      expect(viewState.visibleRanges, isNotNull);
    });

    test('has viewports list', () {
      final viewState = ViewState(state);
      expect(viewState.viewports, isNotEmpty);
      expect(viewState.viewports.first, viewState.viewport);
    });

    test('lineBlockAt returns block info', () {
      final viewState = ViewState(state);
      final block = viewState.lineBlockAt(0);
      expect(block.from, 0);
      // Height may be 0 initially before rendering/measurement
      expect(block.height, greaterThanOrEqualTo(0));
    });

    test('lineBlockAtHeight returns block info', () {
      final viewState = ViewState(state);
      final block = viewState.lineBlockAtHeight(0);
      expect(block, isNotNull);
    });

    test('elementAtHeight returns block info', () {
      final viewState = ViewState(state);
      final block = viewState.elementAtHeight(0);
      expect(block, isNotNull);
    });

    test('scrollAnchorAt returns block info', () {
      final viewState = ViewState(state);
      final block = viewState.scrollAnchorAt(0);
      expect(block, isNotNull);
    });

    test('docHeight is non-negative', () {
      final viewState = ViewState(state);
      expect(viewState.docHeight, greaterThanOrEqualTo(0));
    });

    test('visibleTop and visibleBottom', () {
      final viewState = ViewState(state);
      expect(viewState.visibleTop, viewState.pixelViewport.top);
      expect(viewState.visibleBottom, viewState.pixelViewport.bottom);
    });

    test('scale values default to 1', () {
      final viewState = ViewState(state);
      expect(viewState.scaleX, 1);
      expect(viewState.scaleY, 1);
    });

    test('mustMeasureContent starts true', () {
      final viewState = ViewState(state);
      expect(viewState.mustMeasureContent, true);
    });
  });

  group('EditorRect', () {
    test('creates with bounds', () {
      const rect = EditorRect(left: 0, right: 100, top: 0, bottom: 50);
      expect(rect.left, 0);
      expect(rect.right, 100);
      expect(rect.top, 0);
      expect(rect.bottom, 50);
    });

    test('calculates width and height', () {
      const rect = EditorRect(left: 10, right: 110, top: 20, bottom: 70);
      expect(rect.width, 100);
      expect(rect.height, 50);
    });

    test('toString', () {
      const rect = EditorRect(left: 0, right: 100, top: 0, bottom: 50);
      expect(rect.toString(), 'EditorRect(0.0, 0.0, 100.0, 50.0)');
    });
  });
}
