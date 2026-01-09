// State tests ported from CodeMirror's ref/state/test/test-state.ts
// and ref/state/test/test-facet.ts
//
// This test file is a direct port of the original CodeMirror test suite
// to ensure feature parity and correct behavior.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:codemirror/src/state/state.dart';
import 'package:codemirror/src/state/selection.dart';
import 'package:codemirror/src/state/transaction.dart' hide EditorStateRef;
import 'package:codemirror/src/state/change.dart';
import 'package:codemirror/src/state/facet.dart'
    hide EditorState, Transaction, StateEffect, StateEffectType;
import 'package:codemirror/src/state/transaction.dart' as tx show Transaction;

/// Helper extension to get typed state from transaction
extension TransactionExt on tx.Transaction {
  EditorState get typedState => state as EditorState;
}

void main() {
  // Ensure state module is initialized
  ensureStateInitialized();

  group('EditorState', () {
    // ==========================================================================
    // Basic state operations
    // ==========================================================================

    // Ported from test-state.ts: "holds doc and selection properties"
    test('holds doc and selection properties', () {
      final state = EditorState.create(
        const EditorStateConfig(doc: 'hello'),
      );
      expect(state.doc.toString(), 'hello');
      expect(state.selection.main.from, 0);
    });

    // Ported from test-state.ts: "can apply changes"
    test('can apply changes', () {
      final state = EditorState.create(
        const EditorStateConfig(doc: 'hello'),
      );
      final transaction = state.update([
        TransactionSpec(
          changes: [
            {'from': 2, 'to': 4, 'insert': 'w'},
            {'from': 5, 'insert': '!'},
          ],
        ),
      ]);
      expect(transaction.typedState.doc.toString(), 'hewo!');
    });

    // Ported from test-state.ts: "maps selection through changes"
    test('maps selection through changes', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'abcdefgh',
          extensions: EditorState.allowMultipleSelections_.of(true),
          selection: EditorSelection.create([
            EditorSelection.cursor(0),
            EditorSelection.cursor(4),
            EditorSelection.cursor(8),
          ]),
        ),
      );
      final newState = state.update([state.replaceSelection('Q')]).typedState;
      expect(newState.doc.toString(), 'QabcdQefghQ');
      expect(
        newState.selection.ranges.map((r) => r.from).join('/'),
        '1/6/11',
      );
    });

    // Ported from test-state.ts: "can store annotations on transactions"
    test('can store annotations on transactions', () {
      final someAnnotation = Annotation.define<int>();
      final tr = EditorState.create(const EditorStateConfig(doc: 'foo'))
          .update([TransactionSpec(annotations: [someAnnotation.of(55)])]);
      expect(tr.annotation(someAnnotation), 55);
    });

    // Ported from test-state.ts: "throws when a change's bounds are invalid"
    test("throws when a change's bounds are invalid", () {
      final state = EditorState.create(const EditorStateConfig(doc: '1234'));
      expect(
        () => state.update([
          const TransactionSpec(changes: {'from': -1, 'to': 1})
        ]),
        throwsRangeError,
      );
      expect(
        () => state.update([
          const TransactionSpec(changes: {'from': 2, 'to': 1})
        ]),
        throwsRangeError,
      );
      expect(
        () => state.update([
          const TransactionSpec(changes: {'from': 2, 'to': 10, 'insert': 'x'})
        ]),
        throwsRangeError,
      );
    });

    // ==========================================================================
    // Facet configuration
    // ==========================================================================

    // Ported from test-state.ts: "stores and updates tab size"
    test('stores and updates tab size', () {
      final deflt = EditorState.create(const EditorStateConfig());
      final two = EditorState.create(
        EditorStateConfig(extensions: EditorState.tabSize_.of(2)),
      );
      expect(deflt.tabSize, 4);
      expect(two.tabSize, 2);
      final updated = deflt.update([
        TransactionSpec(
          effects: [StateEffect.reconfigure.of(EditorState.tabSize_.of(8))],
        ),
      ]).typedState;
      expect(updated.tabSize, 8);
    });

    // Ported from test-state.ts: "stores and updates the line separator"
    test('stores and updates the line separator', () {
      final deflt = EditorState.create(const EditorStateConfig());
      final crlf = EditorState.create(
        EditorStateConfig(extensions: EditorState.lineSeparator_.of('\r\n')),
      );
      expect(deflt.facet(EditorState.lineSeparator_), null);
      expect(deflt.toText('a\nb').lines, 2);
      expect(crlf.facet(EditorState.lineSeparator_), '\r\n');
      expect(crlf.toText('a\nb').lines, 1);
      final updated = crlf.update([
        TransactionSpec(
          effects: [
            StateEffect.reconfigure.of(EditorState.lineSeparator_.of('\n'))
          ],
        ),
      ]).typedState;
      expect(updated.facet(EditorState.lineSeparator_), '\n');
    });

    // ==========================================================================
    // StateField tests
    // ==========================================================================

    // Ported from test-state.ts: "stores and updates fields"
    test('stores and updates fields', () {
      final field1 = StateField.define<int>(
        StateFieldConfig(create: (_) => 0, update: (val, _) => val + 1),
      );
      final field2 = StateField.define<int>(
        StateFieldConfig(
          create: (state) => state.field(field1)! + 10,
          update: (val, _) => val,
        ),
      );
      final state = EditorState.create(
        EditorStateConfig(extensions: ExtensionList([field1, field2])),
      );
      expect(state.field(field1), 0);
      expect(state.field(field2), 10);
      final newState = state.update([]).typedState;
      expect(newState.field(field1), 1);
      expect(newState.field(field2), 10);
    });

    // Ported from test-state.ts: "allows fields to have an initializer"
    test('allows fields to have an initializer', () {
      final field = StateField.define<int>(
        StateFieldConfig(create: (_) => 0, update: (val, _) => val + 1),
      );
      final state = EditorState.create(
        EditorStateConfig(extensions: field.init((_) => 10)),
      );
      expect(state.field(field), 10);
      expect(state.update([]).typedState.field(field), 11);
    });

    // Ported from test-state.ts: "can be serialized to JSON"
    test('can be serialized to JSON', () {
      final field = StateField.define<Map<String, int>>(
        StateFieldConfig(
          create: (_) => {'n': 0},
          update: (val, _) => {'n': val['n']! + 1},
          toJson: (v, _) => {'number': v['n']},
          fromJson: (j, _) =>
              {'n': (j as Map<String, dynamic>)['number'] as int},
        ),
      );
      final fields = {'f': field};
      final state = EditorState.create(
        EditorStateConfig(extensions: field),
      ).update([]).typedState;
      final json = state.toJson(fields);
      expect(jsonEncode(json['f']), '{"number":1}');
      final state2 =
          EditorState.fromJson(json, const EditorStateConfig(), fields);
      expect(jsonEncode(state2.field(field)), '{"n":1}');
    });

    // Ported from test-state.ts: "can preserve fields across reconfiguration"
    test('can preserve fields across reconfiguration', () {
      final field = StateField.define<int>(
        StateFieldConfig(create: (_) => 0, update: (val, _) => val + 1),
      );
      final start = EditorState.create(
        EditorStateConfig(extensions: field),
      ).update([]).typedState;
      expect(start.field(field), 1);
      expect(
        start.update([
          TransactionSpec(effects: [StateEffect.reconfigure.of(field)]),
        ]).typedState.field(field),
        2,
      );
      expect(
        start.update([
          TransactionSpec(
            effects: [StateEffect.reconfigure.of(const ExtensionList([]))],
          ),
        ]).typedState.field(field, false),
        null,
      );
    });

    // ==========================================================================
    // Compartment tests
    // ==========================================================================

    // Ported from test-state.ts: "can replace extension groups"
    test('can replace extension groups', () {
      final comp = Compartment();
      final f = Facet.define<int, List<int>>();
      final content = f.of(10);
      var state = EditorState.create(
        EditorStateConfig(
          extensions: ExtensionList([comp.of(content), f.of(20)]),
        ),
      );
      expect(comp.get(state), content);
      expect(state.facet(f).join(','), '10,20');

      final content2 = ExtensionList([f.of(1), f.of(2)]);
      state = state.update([
        TransactionSpec(effects: [comp.reconfigure(content2)]),
      ]).typedState;
      expect(comp.get(state), content2);
      expect(state.facet(f).join(','), '1,2,20');

      state = state.update([
        TransactionSpec(effects: [comp.reconfigure(f.of(3))]),
      ]).typedState;
      expect(state.facet(f).join(','), '3,20');
    });

    // Ported from test-state.ts: "raises an error on duplicate extension groups"
    test('raises an error on duplicate extension groups', () {
      final comp = Compartment();
      final f = Facet.define<int, List<int>>();
      expect(
        () => EditorState.create(
          EditorStateConfig(
            extensions: ExtensionList([comp.of(f.of(1)), comp.of(f.of(2))]),
          ),
        ),
        throwsRangeError,
      );
      expect(
        () => EditorState.create(
          EditorStateConfig(
            extensions: comp.of(comp.of(f.of(1))),
          ),
        ),
        throwsRangeError,
      );
    });

    // Ported from test-state.ts: "preserves compartments on reconfigure"
    test('preserves compartments on reconfigure', () {
      final comp = Compartment();
      final f = Facet.define<int, List<int>>();
      final init = comp.of(f.of(10));
      var state = EditorState.create(
        EditorStateConfig(extensions: ExtensionList([init, f.of(20)])),
      );
      state = state.update([
        TransactionSpec(effects: [comp.reconfigure(f.of(0))]),
      ]).typedState;
      expect(state.facet(f).join(','), '0,20');
      state = state.update([
        TransactionSpec(
          effects: [
            StateEffect.reconfigure.of(ExtensionList([init, f.of(2)]))
          ],
        ),
      ]).typedState;
      expect(state.facet(f).join(','), '0,2');
    });

    // Ported from test-state.ts: "forgets dropped compartments"
    test('forgets dropped compartments', () {
      final comp = Compartment();
      final f = Facet.define<int, List<int>>();
      final init = comp.of(f.of(10));
      var state = EditorState.create(
        EditorStateConfig(extensions: ExtensionList([init, f.of(20)])),
      );
      state = state.update([
        TransactionSpec(effects: [comp.reconfigure(f.of(0))]),
      ]).typedState;
      expect(state.facet(f).join(','), '0,20');
      state = state.update([
        TransactionSpec(effects: [StateEffect.reconfigure.of(f.of(2))]),
      ]).typedState;
      expect(state.facet(f).join(','), '2');
      expect(comp.get(state), null);
      state = state.update([
        TransactionSpec(
          effects: [
            StateEffect.reconfigure.of(ExtensionList([init, f.of(2)]))
          ],
        ),
      ]).typedState;
      expect(state.facet(f).join(','), '10,2');
    });

    // Ported from test-state.ts: "allows facets computed from fields"
    test('allows facets computed from fields', () {
      final field = StateField.define<List<int>>(
        StateFieldConfig(
          create: (_) => [0],
          update: (v, tr) {
            if (tr.docChanged) {
              // Cast to full Transaction to access newDoc
              final fullTr = tr as tx.Transaction;
              return [fullTr.newDoc.length];
            }
            return v;
          },
        ),
      );
      final facet = Facet.define<int, List<int>>();
      var state = EditorState.create(
        EditorStateConfig(
          extensions: ExtensionList([
            field,
            facet.compute([field], (s) => s.field(field)![0]),
            facet.of(1),
          ]),
        ),
      );
      expect(state.facet(facet).join(','), '0,1');
      final state2 = state.update([]).typedState;
      expect(state2.facet(facet), state.facet(facet));
      final state3 = state.update([
        const TransactionSpec(changes: {'insert': 'hi', 'from': 0}),
      ]).typedState;
      expect(state3.facet(facet).join(','), '2,1');
    });

    // ==========================================================================
    // Selection handling
    // ==========================================================================

    // Ported from test-state.ts: "blocks multiple selections when not allowed"
    test('blocks multiple selections when not allowed', () {
      final cursors = EditorSelection.create([
        EditorSelection.cursor(0),
        EditorSelection.cursor(1),
      ]);
      final state = EditorState.create(
        EditorStateConfig(selection: cursors, doc: '123'),
      );
      expect(state.selection.ranges.length, 1);
      expect(
        state
            .update([TransactionSpec(selection: cursors)])
            .typedState
            .selection
            .ranges
            .length,
        1,
      );
    });

    // ==========================================================================
    // changeByRange tests
    // ==========================================================================

    group('changeByRange', () {
      // Ported from test-state.ts: "can make simple changes"
      test('can make simple changes', () {
        var state = EditorState.create(const EditorStateConfig(doc: 'hi'));
        final result = state.changeByRange((r) => ChangeByRangeResult(
              changes: ChangeSpec(from: r.from, to: r.from + 1, insert: 'q'),
              range: EditorSelection.cursor(r.from + 1),
            ));
        state = state.update([
          TransactionSpec(
            changes: result.changes,
            selection: result.selection,
          ),
        ]).typedState;
        expect(state.doc.toString(), 'qi');
        expect(state.selection.main.from, 1);
      });

      // Ported from test-state.ts: "does the right thing when there are multiple selections"
      test('does the right thing when there are multiple selections', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: '1 2 3 4',
            selection: EditorSelection.create([
              EditorSelection.range(0, 1),
              EditorSelection.range(2, 3),
              EditorSelection.range(4, 5),
              EditorSelection.range(6, 7),
            ]),
            extensions: EditorState.allowMultipleSelections_.of(true),
          ),
        );
        final result = state.changeByRange((r) => ChangeByRangeResult(
              changes: ChangeSpec(
                from: r.from,
                to: r.to,
                insert: '-' * ((r.from >> 1) + 1),
              ),
              range: EditorSelection.range(r.from, r.from + 1 + (r.from >> 1)),
            ));
        state = state.update([
          TransactionSpec(
            changes: result.changes,
            selection: result.selection,
          ),
        ]).typedState;
        expect(state.doc.toString(), '- -- --- ----');
        expect(
          state.selection.ranges.map((r) => '${r.from}-${r.to}').join(' '),
          '0-1 2-4 5-8 9-13',
        );
      });
    });

    // ==========================================================================
    // changeFilter tests
    // ==========================================================================

    group('changeFilter', () {
      // Ported from test-state.ts: "can cancel changes"
      test('can cancel changes', () {
        // Cancels all changes that add length
        final state = EditorState.create(
          EditorStateConfig(
            extensions:
                changeFilter.of((tr) => tr.changes.newLength <= tr.changes.length),
            doc: 'one two',
          ),
        );
        final tr1 = state.update([
          const TransactionSpec(
              changes: {'from': 3, 'insert': ' three'}, anchor: 13),
        ]);
        expect(tr1.typedState.doc.toString(), 'one two');
        expect(tr1.typedState.selection.main.head, 7);
        final tr2 = state.update([
          const TransactionSpec(changes: {'from': 4, 'to': 7, 'insert': '2'}),
        ]);
        expect(tr2.typedState.doc.toString(), 'one 2');
      });

      // Ported from test-state.ts: "can split changes"
      test('can split changes', () {
        // Disallows changes in the middle third of the document
        final state = EditorState.create(
          EditorStateConfig(
            extensions: changeFilter.of((tr) => [
                  (tr.startState as EditorState).doc.length ~/ 3,
                  (2 * (tr.startState as EditorState).doc.length) ~/ 3,
                ]),
            doc: 'onetwo',
          ),
        );
        expect(
          state.update([
            const TransactionSpec(changes: {'from': 0, 'to': 6}),
          ]).typedState.doc.toString(),
          'et',
        );
      });

      // Ported from test-state.ts: "combines filter masks"
      test('combines filter masks', () {
        final state = EditorState.create(
          EditorStateConfig(
            extensions: ExtensionList([
              changeFilter.of((_) => [0, 2]),
              changeFilter.of((_) => [4, 6]),
            ]),
            doc: 'onetwo',
          ),
        );
        expect(
          state.update([
            const TransactionSpec(changes: {'from': 0, 'to': 6}),
          ]).typedState.doc.toString(),
          'onwo',
        );
      });

      // Ported from test-state.ts: "can be turned off"
      test('can be turned off', () {
        final state = EditorState.create(
          EditorStateConfig(extensions: changeFilter.of((_) => false)),
        );
        expect(
          state.update([
            const TransactionSpec(changes: {'from': 0, 'insert': 'hi'}),
          ]).typedState.doc.length,
          0,
        );
        expect(
          state.update([
            const TransactionSpec(
                changes: {'from': 0, 'insert': 'hi'}, filter: false),
          ]).typedState.doc.length,
          2,
        );
      });
    });

    // ==========================================================================
    // transactionFilter tests
    // ==========================================================================

    group('transactionFilter', () {
      // Ported from test-state.ts: "can constrain the selection"
      test('can constrain the selection', () {
        final state = EditorState.create(
          EditorStateConfig(
            extensions: transactionFilter.of((tr) {
              if (tr.selection != null && tr.selection!.main.to > 4) {
                return [tr, const TransactionSpec(anchor: 4)];
              }
              return tr;
            }),
            doc: 'one two',
          ),
        );
        expect(state.update([const TransactionSpec(anchor: 3)]).selection!.main.to,
            3);
        expect(state.update([const TransactionSpec(anchor: 7)]).selection!.main.to,
            4);
      });

      // Ported from test-state.ts: "can append sequential changes"
      test('can append sequential changes', () {
        final state = EditorState.create(
          EditorStateConfig(
            extensions: transactionFilter.of((tr) {
              return [
                tr,
                TransactionSpec(
                  changes: {'from': tr.changes.newLength, 'insert': '!'},
                  sequential: true,
                ),
              ];
            }),
            doc: 'one two',
          ),
        );
        expect(
          state.update([
            const TransactionSpec(changes: {'from': 3, 'insert': ','}),
          ]).typedState.doc.toString(),
          'one, two!',
        );
      });
    });

    // ==========================================================================
    // transactionExtender tests
    // ==========================================================================

    group('transactionExtender', () {
      // Ported from test-state.ts: "can add annotations"
      test('can add annotations', () {
        final ann = Annotation.define<int>();
        final state = EditorState.create(
          EditorStateConfig(
            extensions: transactionExtender.of((_) => TransactionSpec(
                  annotations: [ann.of(100)],
                )),
          ),
        );
        final tr = state.update([
          const TransactionSpec(changes: {'from': 0, 'insert': '!'}),
        ]);
        expect(tr.annotation(ann), 100);
        final trNoFilter = state.update([
          const TransactionSpec(
              changes: {'from': 0, 'insert': '!'}, filter: false),
        ]);
        expect(trNoFilter.annotation(ann), 100);
      });

      // Ported from test-state.ts: "allows multiple extenders to take effect"
      test('allows multiple extenders to take effect', () {
        final eff = StateEffect.define<int>();
        final state = EditorState.create(
          EditorStateConfig(
            extensions: ExtensionList([
              transactionExtender
                  .of((_) => TransactionSpec(effects: [eff.of(1)])),
              transactionExtender
                  .of((_) => TransactionSpec(effects: [eff.of(2)])),
            ]),
          ),
        );
        final tr = state.update([const TransactionSpec(scrollIntoView: true)]);
        expect(
          tr.effects.map((e) => e.is_(eff) ? e.value : 0).join(','),
          '2,1',
        );
      });
    });
  });

  // ============================================================================
  // Facet tests (from test-facet.ts)
  // ============================================================================

  group('EditorState facets', () {
    final num = Facet.define<int, List<int>>();
    final str = Facet.define<String, List<String>>();

    // Ported from test-facet.ts: "allows querying of facets"
    test('allows querying of facets', () {
      final state = EditorState.create(
        EditorStateConfig(
          extensions: ExtensionList([
            num.of(10),
            num.of(20),
            str.of('x'),
            str.of('y'),
          ]),
        ),
      );
      expect(state.facet(num).join(','), '10,20');
      expect(state.facet(str).join(','), 'x,y');
    });

    // Ported from test-facet.ts: "includes sub-extenders"
    test('includes sub-extenders', () {
      Extension e(String s) =>
          ExtensionList([num.of(s.length), num.of(int.parse(s))]);
      final state = EditorState.create(
        EditorStateConfig(
          extensions:
              ExtensionList([num.of(5), e('20'), num.of(40), e('100')]),
        ),
      );
      expect(state.facet(num).join(','), '5,2,20,40,3,100');
    });

    // Ported from test-facet.ts: "only includes duplicated extensions once"
    test('only includes duplicated extensions once', () {
      final e = num.of(50);
      final state = EditorState.create(
        EditorStateConfig(
          extensions: ExtensionList([num.of(1), e, num.of(4), e]),
        ),
      );
      expect(state.facet(num).join(','), '1,50,4');
    });

    // Ported from test-facet.ts: "returns an empty array for absent facet"
    test('returns an empty array for absent facet', () {
      final state = EditorState.create(const EditorStateConfig());
      expect(state.facet(num).isEmpty, true);
    });

    // Ported from test-facet.ts: "sorts extensions by priority"
    test('sorts extensions by priority', () {
      final state = EditorState.create(
        EditorStateConfig(
          extensions: ExtensionList([
            str.of('a'),
            str.of('b'),
            Prec.high(str.of('c')),
            Prec.highest(str.of('d')),
            Prec.low(str.of('e')),
            Prec.high(str.of('f')),
            str.of('g'),
          ]),
        ),
      );
      expect(state.facet(str).join(','), 'd,c,f,a,b,g,e');
    });

    // Ported from test-facet.ts: "lets sub-extensions inherit their parent's priority"
    test("lets sub-extensions inherit their parent's priority", () {
      Extension e(int n) => num.of(n);
      final state = EditorState.create(
        EditorStateConfig(
          extensions: ExtensionList([num.of(1), Prec.highest(e(2)), e(4)]),
        ),
      );
      expect(state.facet(num).join(','), '2,1,4');
    });

    // Ported from test-facet.ts: "supports dynamic facet"
    test('supports dynamic facet', () {
      final state = EditorState.create(
        EditorStateConfig(
          extensions: ExtensionList([
            num.of(1),
            num.compute([], (_) => 88),
          ]),
        ),
      );
      expect(state.facet(num).join(','), '1,88');
    });

    // Ported from test-facet.ts: "works with a static combined facet"
    test('works with a static combined facet', () {
      final f = Facet.define<int, int>(
        FacetConfig(combine: (ns) => ns.fold(0, (a, b) => a + b)),
      );
      final state = EditorState.create(
        EditorStateConfig(
          extensions: ExtensionList([f.of(1), f.of(2), f.of(3)]),
        ),
      );
      expect(state.facet(f), 6);
    });

    // Ported from test-facet.ts: "works with a dynamic combined facet"
    test('works with a dynamic combined facet', () {
      final f = Facet.define<int, int>(
        FacetConfig(combine: (ns) => ns.fold(0, (a, b) => a + b)),
      );
      final state = EditorState.create(
        EditorStateConfig(
          extensions: ExtensionList([
            f.of(1),
            f.compute([docSlot], (s) => (s as EditorState).doc.length),
            f.of(3),
          ]),
        ),
      );
      expect(state.facet(f), 4);
      final newState = state.update([
        const TransactionSpec(changes: {'insert': 'hello', 'from': 0}),
      ]).typedState;
      expect(newState.facet(f), 9);
    });
  });

  // ============================================================================
  // Transaction tests
  // ============================================================================

  group('Transaction', () {
    test('has time annotation', () {
      final tr = EditorState.create(const EditorStateConfig()).update([]);
      expect(tr.annotation(Transaction.time), isNotNull);
    });

    test('docChanged is true when changes exist', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'hello'));
      final trNoChange = state.update([]);
      final trWithChange = state.update([
        const TransactionSpec(changes: {'from': 0, 'insert': 'x'}),
      ]);
      expect(trNoChange.docChanged, false);
      expect(trWithChange.docChanged, true);
    });

    test('isUserEvent works correctly', () {
      final state = EditorState.create(const EditorStateConfig());
      final tr = state.update([
        const TransactionSpec(userEvent: 'select.pointer'),
      ]);
      expect(tr.isUserEvent('select'), true);
      expect(tr.isUserEvent('select.pointer'), true);
      expect(tr.isUserEvent('select.pointer.mouse'), false);
      expect(tr.isUserEvent('input'), false);
    });
  });

  // ============================================================================
  // StateEffect tests
  // ============================================================================

  group('StateEffect', () {
    test('can define custom effects', () {
      final effect = StateEffect.define<String>();
      final state = EditorState.create(const EditorStateConfig());
      final tr = state.update([
        TransactionSpec(effects: [effect.of('hello')]),
      ]);
      expect(tr.effects.length, 1);
      expect(tr.effects[0].is_(effect), true);
      expect(tr.effects[0].value, 'hello');
    });

    test('can map effects through changes', () {
      final effect = StateEffect.define<int>(
        map: (value, change) => change.mapPos(value),
      );
      final state = EditorState.create(const EditorStateConfig(doc: 'hello'));
      final tr = state.update([
        TransactionSpec(
          changes: {'from': 0, 'insert': 'abc'},
          effects: [effect.of(2)],
        ),
      ]);
      // Effect positions are mapped through changes
      expect(tr.effects[0].is_(effect), true);
      // Note: Effects in the same TransactionSpec as changes refer to the
      // document AFTER the spec's changes, so they are not mapped.
      // If effects were in a separate spec, they would be mapped.
      expect(tr.effects[0].value, 2);
    });

    test('maps effects through changes from different specs', () {
      final effect = StateEffect.define<int>(
        map: (value, change) => change.mapPos(value),
      );
      final state = EditorState.create(const EditorStateConfig(doc: 'hello'));
      // When effects are in a different spec than the changes, they get mapped
      final tr = state.update([
        const TransactionSpec(changes: {'from': 0, 'insert': 'abc'}),
        TransactionSpec(effects: [effect.of(2)]),
      ]);
      expect(tr.effects[0].is_(effect), true);
      // Position 2 is mapped through the insertion -> becomes 5
      expect(tr.effects[0].value, 5);
    });
  });

  // ============================================================================
  // EditorSelection tests
  // ============================================================================

  group('EditorSelection', () {
    test('normalizes overlapping ranges', () {
      final sel = EditorSelection.create([
        EditorSelection.range(0, 5),
        EditorSelection.range(3, 8),
      ]);
      expect(sel.ranges.length, 1);
      expect(sel.ranges[0].from, 0);
      expect(sel.ranges[0].to, 8);
    });

    test('sorts ranges', () {
      final sel = EditorSelection.create([
        EditorSelection.range(10, 15),
        EditorSelection.range(0, 5),
      ]);
      expect(sel.ranges[0].from, 0);
      expect(sel.ranges[1].from, 10);
    });

    test('tracks main index through normalization', () {
      final sel = EditorSelection.create([
        EditorSelection.range(10, 15),
        EditorSelection.range(0, 5),
      ], 0);
      // Main was at index 0 (10-15), after sorting it should be at index 1
      expect(sel.main.from, 10);
      expect(sel.mainIndex, 1);
    });

    test('creates cursor selection', () {
      final cursor = EditorSelection.cursor(5);
      expect(cursor.from, 5);
      expect(cursor.to, 5);
      expect(cursor.empty, true);
    });

    test('creates range selection', () {
      final range = EditorSelection.range(2, 7);
      expect(range.from, 2);
      expect(range.to, 7);
      expect(range.empty, false);
      expect(range.anchor, 2);
      expect(range.head, 7);
    });

    test('handles inverted range', () {
      final range = EditorSelection.range(7, 2);
      expect(range.from, 2);
      expect(range.to, 7);
      expect(range.anchor, 7);
      expect(range.head, 2);
    });

    test('maps through changes', () {
      final sel = EditorSelection.create([
        EditorSelection.cursor(5),
        EditorSelection.range(10, 15),
      ]);
      final changes = ChangeSet.of([
        {'from': 0, 'insert': 'abc'},
      ], 20, null);
      final mapped = sel.map(changes);
      expect(mapped.ranges[0].from, 8); // 5 + 3
      expect(mapped.ranges[1].from, 13); // 10 + 3
      expect(mapped.ranges[1].to, 18); // 15 + 3
    });
  });

  // ============================================================================
  // ChangeSet tests
  // ============================================================================

  group('ChangeSet', () {
    test('can create empty changeset', () {
      final cs = ChangeSet.emptySet(10);
      expect(cs.empty, true);
      expect(cs.length, 10);
      expect(cs.newLength, 10);
    });

    test('can create changeset with insertions', () {
      final cs = ChangeSet.of([
        {'from': 0, 'insert': 'abc'},
      ], 5, null);
      expect(cs.empty, false);
      expect(cs.length, 5);
      expect(cs.newLength, 8);
    });

    test('can create changeset with deletions', () {
      final cs = ChangeSet.of([
        {'from': 2, 'to': 4},
      ], 10, null);
      expect(cs.empty, false);
      expect(cs.length, 10);
      expect(cs.newLength, 8);
    });

    test('can create changeset with replacement', () {
      final cs = ChangeSet.of([
        {'from': 2, 'to': 5, 'insert': 'xy'},
      ], 10, null);
      expect(cs.empty, false);
      expect(cs.length, 10);
      expect(cs.newLength, 9); // 10 - 3 + 2
    });

    test('maps positions correctly', () {
      final cs = ChangeSet.of([
        {'from': 5, 'insert': 'abc'},
      ], 10, null);
      expect(cs.mapPos(0), 0);
      expect(cs.mapPos(5), 5);
      expect(cs.mapPos(6), 9); // After insertion
      expect(cs.mapPos(10), 13);
    });

    test('composes changesets', () {
      final cs1 = ChangeSet.of([
        {'from': 0, 'insert': 'abc'},
      ], 5, null);
      final cs2 = ChangeSet.of([
        {'from': 3, 'to': 5, 'insert': 'x'},
      ], 8, null);
      final composed = cs1.compose(cs2);
      expect(composed.length, 5);
      expect(composed.newLength, 7); // abcx + rest
    });
  });

  // ============================================================================
  // Annotation tests
  // ============================================================================

  group('Annotation', () {
    test('can define and use annotations', () {
      final ann = Annotation.define<String>();
      final instance = ann.of('test');
      expect(instance.value, 'test');
      expect(instance.type, ann);
    });

    test('can retrieve annotations from transaction', () {
      final ann1 = Annotation.define<String>();
      final ann2 = Annotation.define<int>();
      final state = EditorState.create(const EditorStateConfig());
      final tr = state.update([
        TransactionSpec(annotations: [
          ann1.of('hello'),
          ann2.of(42),
        ]),
      ]);
      expect(tr.annotation(ann1), 'hello');
      expect(tr.annotation(ann2), 42);
    });

    test('returns null for absent annotation', () {
      final ann = Annotation.define<String>();
      final state = EditorState.create(const EditorStateConfig());
      final tr = state.update([]);
      expect(tr.annotation(ann), null);
    });
  });
}
