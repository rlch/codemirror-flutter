// Facet tests ported from CodeMirror's ref/state/test/test-facet.ts
//
// This test file is a direct port of the original CodeMirror test suite
// to ensure feature parity and correct behavior.
import 'package:flutter_test/flutter_test.dart';
import 'package:codemirror/src/state/state.dart';
import 'package:codemirror/src/state/selection.dart';
import 'package:codemirror/src/state/transaction.dart' hide EditorStateRef;
import 'package:codemirror/src/state/facet.dart'
    hide EditorState, Transaction, StateEffect, StateEffectType;

/// Helper function to create an EditorState with the given extensions.
/// Matches the `mk` function from the TypeScript tests.
EditorState mk([List<Extension> extensions = const []]) {
  return EditorState.create(
    EditorStateConfig(extensions: ExtensionList(extensions)),
  );
}

/// Helper to cast transaction state to EditorState.
EditorState stateOf(Transaction tr) => tr.state as EditorState;

void main() {
  // Ensure state module is initialized
  ensureStateInitialized();

  group('EditorState facets', () {
    // Define test facets INSIDE the group to avoid the type casting issues
    // at the module level during static initialization

    // Ported from test-facet.ts: "allows querying of facets"
    test('allows querying of facets', () {
      final num = Facet.define<int, List<int>>();
      final str = Facet.define<String, List<String>>();

      final st = mk([num.of(10), num.of(20), str.of('x'), str.of('y')]);
      expect(st.facet(num).join(','), equals('10,20'));
      expect(st.facet(str).join(','), equals('x,y'));
    });

    // Ported from test-facet.ts: "includes sub-extenders"
    test('includes sub-extenders', () {
      final num = Facet.define<int, List<int>>();

      Extension e(String s) =>
          ExtensionList([num.of(s.length), num.of(int.parse(s))]);
      final st = mk([num.of(5), e('20'), num.of(40), e('100')]);
      expect(st.facet(num).join(','), equals('5,2,20,40,3,100'));
    });

    // Ported from test-facet.ts: "only includes duplicated extensions once"
    test('only includes duplicated extensions once', () {
      final num = Facet.define<int, List<int>>();

      final e = num.of(50);
      final st = mk([num.of(1), e, num.of(4), e]);
      expect(st.facet(num).join(','), equals('1,50,4'));
    });

    // Ported from test-facet.ts: "returns an empty array for absent facet"
    test('returns an empty array for absent facet', () {
      final num = Facet.define<int, List<int>>();

      final st = mk();
      expect(st.facet(num), equals([]));
    });

    // Ported from test-facet.ts: "sorts extensions by priority"
    test('sorts extensions by priority', () {
      final str = Facet.define<String, List<String>>();

      final st = mk([
        str.of('a'),
        str.of('b'),
        Prec.high(str.of('c')),
        Prec.highest(str.of('d')),
        Prec.low(str.of('e')),
        Prec.high(str.of('f')),
        str.of('g'),
      ]);
      expect(st.facet(str).join(','), equals('d,c,f,a,b,g,e'));
    });

    // Ported from test-facet.ts: "lets sub-extensions inherit their parent's priority"
    test("lets sub-extensions inherit their parent's priority", () {
      final num = Facet.define<int, List<int>>();

      Extension e(int n) => num.of(n);
      final st = mk([num.of(1), Prec.highest(e(2)), e(4)]);
      expect(st.facet(num).join(','), equals('2,1,4'));
    });

    // Ported from test-facet.ts: "supports dynamic facet"
    test('supports dynamic facet', () {
      final num = Facet.define<int, List<int>>();

      final st = mk([num.of(1), num.compute([], (_) => 88)]);
      expect(st.facet(num).join(','), equals('1,88'));
    });

    // Ported from test-facet.ts: "only recomputes a facet value when necessary"
    test('only recomputes a facet value when necessary', () {
      final num = Facet.define<int, List<int>>();
      final str = Facet.define<String, List<String>>();

      final st = mk([
        num.of(1),
        num.compute([str], (s) => (s as EditorState).facet(str).join().length),
        str.of('hello'),
      ]);
      final array = st.facet(num);
      expect(array.join(','), equals('1,5'));
      // Empty update should return the same array instance
      expect(stateOf(st.update([])).facet(num), same(array));
    });

    // Ported from test-facet.ts: "can handle dependencies on facets that aren't present in the state"
    // Note: In JavaScript [].toString() returns "", but in Dart [].toString() returns "[]"
    // We adapt the test to use .join() which works consistently
    test("can handle dependencies on facets that aren't present in the state",
        () {
      final num = Facet.define<int, List<int>>();
      final str = Facet.define<String, List<String>>();
      final bool_ = Facet.define<bool, List<bool>>();

      final st = mk([
        num.compute([str], (s) => (s as EditorState).facet(str).join().length),
        str.compute(
            [bool_], (s) => (s as EditorState).facet(bool_).join(',')),
      ]);
      // bool_ facet is empty, so join() returns "", str facet has [""], num computes "".length = 0
      expect(stateOf(st.update([])).facet(num).join(','), equals('0'));
    });

    // Ported from test-facet.ts: "can specify a dependency on the document"
    test('can specify a dependency on the document', () {
      final num = Facet.define<int, List<int>>();

      var count = 0;
      var st = mk([
        num.compute([docSlot], (_) => count++),
      ]);
      expect(st.facet(num).join(','), equals('0'));
      st = stateOf(st.update([
        const TransactionSpec(changes: {'insert': 'hello', 'from': 0}),
      ]));
      expect(st.facet(num).join(','), equals('1'));
      st = stateOf(st.update([]));
      expect(st.facet(num).join(','), equals('1'));
    });

    // Ported from test-facet.ts: "can specify a dependency on the selection"
    test('can specify a dependency on the selection', () {
      final num = Facet.define<int, List<int>>();

      var count = 0;
      var st = mk([
        num.compute([selectionSlot], (_) => count++),
      ]);
      expect(st.facet(num).join(','), equals('0'));
      st = stateOf(st.update([
        const TransactionSpec(changes: {'insert': 'hello', 'from': 0}),
      ]));
      expect(st.facet(num).join(','), equals('1'));
      st = stateOf(st.update([
        TransactionSpec(selection: EditorSelection.single(2)),
      ]));
      expect(st.facet(num).join(','), equals('2'));
      st = stateOf(st.update([]));
      expect(st.facet(num).join(','), equals('2'));
    });

    // Ported from test-facet.ts: "can provide multiple values at once"
    test('can provide multiple values at once', () {
      final num = Facet.define<int, List<int>>();

      var st = mk([
        num.computeN(
          [docSlot],
          (s) =>
              (s as EditorState).doc.length % 2 != 0 ? [100, 10] : <int>[],
        ),
        num.of(1),
      ]);
      expect(st.facet(num).join(','), equals('1'));
      st = stateOf(st.update([
        const TransactionSpec(changes: {'insert': 'hello', 'from': 0}),
      ]));
      expect(st.facet(num).join(','), equals('100,10,1'));
    });

    // Ported from test-facet.ts: "works with a static combined facet"
    test('works with a static combined facet', () {
      final f = Facet.define<int, int>(
        FacetConfig(combine: (ns) => ns.fold(0, (a, b) => a + b)),
      );
      final st = mk([f.of(1), f.of(2), f.of(3)]);
      expect(st.facet(f), equals(6));
    });

    // Ported from test-facet.ts: "works with a dynamic combined facet"
    test('works with a dynamic combined facet', () {
      final f = Facet.define<int, int>(
        FacetConfig(combine: (ns) => ns.fold(0, (a, b) => a + b)),
      );
      var st = mk([
        f.of(1),
        f.compute([docSlot], (s) => (s as EditorState).doc.length),
        f.of(3),
      ]);
      expect(st.facet(f), equals(4));
      st = stateOf(st.update([
        const TransactionSpec(changes: {'insert': 'hello', 'from': 0}),
      ]));
      expect(st.facet(f), equals(9));
    });

    // Ported from test-facet.ts: "survives reconfiguration"
    test('survives reconfiguration', () {
      final num = Facet.define<int, List<int>>();
      final str = Facet.define<String, List<String>>();

      final st = mk([
        num.compute([docSlot], (s) => (s as EditorState).doc.length),
        num.of(2),
        str.of('3'),
      ]);
      final st2 = stateOf(st.update([
        TransactionSpec(effects: [
          StateEffect.reconfigure.of(ExtensionList([
            num.compute([docSlot], (s) => (s as EditorState).doc.length),
            num.of(2),
          ])),
        ]),
      ]));
      expect(st.facet(num), equals(st2.facet(num)));
      expect(st2.facet(str).length, equals(0));
    });

    // Ported from test-facet.ts: "survives unrelated reconfiguration even without deep-compare"
    test('survives unrelated reconfiguration even without deep-compare', () {
      final str = Facet.define<String, List<String>>();
      final f = Facet.define<int, Map<String, int>>(
        FacetConfig(combine: (v) => {'count': v.length}),
      );
      final st = mk([
        f.compute([docSlot], (s) => (s as EditorState).doc.length),
        f.of(2),
      ]);
      final st2 = stateOf(st.update([
        TransactionSpec(effects: [StateEffect.appendConfig.of(str.of('hi'))]),
      ]));
      expect(st.facet(f), same(st2.facet(f)));
    });

    // Ported from test-facet.ts: "preserves static facets across reconfiguration"
    test('preserves static facets across reconfiguration', () {
      final num = Facet.define<int, List<int>>();
      final str = Facet.define<String, List<String>>();

      final st = mk([num.of(1), num.of(2), str.of('3')]);
      final st2 = stateOf(st.update([
        TransactionSpec(effects: [
          StateEffect.reconfigure.of(ExtensionList([num.of(1), num.of(2)])),
        ]),
      ]));
      expect(st.facet(num), same(st2.facet(num)));
    });

    // Ported from test-facet.ts: "creates newly added fields when reconfiguring"
    test('creates newly added fields when reconfiguring', () {
      final num = Facet.define<int, List<int>>();

      var st = mk([num.of(2)]);
      final events = <String>[];
      final field = StateField.define<int>(
        StateFieldConfig(
          create: (_) {
            events.add('create');
            return 0;
          },
          update: (val, _) {
            events.add('update $val');
            return val + 1;
          },
        ),
      );
      st = stateOf(st.update([
        TransactionSpec(effects: [StateEffect.appendConfig.of(field)]),
      ]));
      expect(events.join(', '), equals('create, update 0'));
      expect(st.field(field), equals(1));
    });

    // Ported from test-facet.ts: "applies effects from reconfiguring transaction to new fields"
    test('applies effects from reconfiguring transaction to new fields', () {
      final num = Facet.define<int, List<int>>();

      var st = mk();
      final effect = StateEffect.define<int>();
      final field = StateField.define<int>(
        StateFieldConfig(
          create: (state) {
            return state.facet(num).isNotEmpty ? state.facet(num)[0] : 0;
          },
          update: (val, tr) {
            final effects = (tr as Transaction).effects;
            return effects.fold(val, (v, e) {
              if (e.is_(effect)) {
                return v + (e.value as int);
              }
              return v;
            });
          },
        ),
      );
      st = stateOf(st.update([
        TransactionSpec(effects: [
          StateEffect.appendConfig.of(ExtensionList([field, num.of(10)])),
          effect.of(5),
        ]),
      ]));
      expect(st.field(field), equals(15));
    });

    // Ported from test-facet.ts: "errors on cyclic dependencies"
    test('errors on cyclic dependencies', () {
      final num = Facet.define<int, List<int>>();
      final str = Facet.define<String, List<String>>();

      expect(
        () => mk([
          num.compute([str], (s) => (s as EditorState).facet(str).length),
          str.compute([num], (s) => (s as EditorState).facet(num).join()),
        ]),
        throwsA(isA<StateError>().having(
          (e) => e.message.toLowerCase(),
          'message',
          contains('cyclic'),
        )),
      );
    });

    // Ported from test-facet.ts: "updates facets computed from static values on reconfigure"
    test('updates facets computed from static values on reconfigure', () {
      final num = Facet.define<int, List<int>>();
      final str = Facet.define<String, List<String>>();
      final bool_ = Facet.define<bool, List<bool>>();

      var st = mk([
        num.compute([str], (state) => (state as EditorState).facet(str).length),
        str.of('A'),
      ]);
      st = stateOf(st.update([
        TransactionSpec(effects: [StateEffect.appendConfig.of(str.of('B'))]),
      ]));
      expect(st.facet(num).join(','), equals('2'));
      // Value should be preserved when unrelated config is appended
      expect(
        st.facet(num),
        same(stateOf(st.update([
          TransactionSpec(
              effects: [StateEffect.appendConfig.of(bool_.of(false))]),
        ])).facet(num)),
      );
    });

    // Ported from test-facet.ts: "preserves dynamic facet values when dependencies stay the same"
    test('preserves dynamic facet values when dependencies stay the same', () {
      final f = Facet.define<Map<String, int>, List<Map<String, int>>>();
      final str = Facet.define<String, List<String>>();
      final bool_ = Facet.define<bool, List<bool>>();

      final st1 = mk([
        f.compute([], (state) => {'a': 1}),
        str.of('A'),
      ]);
      final st2 = stateOf(st1.update([
        TransactionSpec(effects: [StateEffect.appendConfig.of(bool_.of(true))]),
      ]));
      expect(st1.facet(f), same(st2.facet(f)));
    });
  });
}
