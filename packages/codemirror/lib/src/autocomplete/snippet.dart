import 'package:flutter/widgets.dart' show SizedBox, Widget;

import '../commands/commands.dart' show indentUnit;
import '../state/change.dart';
import '../state/facet.dart' hide EditorState, Transaction;
import '../state/selection.dart';
import '../state/state.dart';
import '../state/transaction.dart' hide Transaction;
import '../state/transaction.dart' as tx show Transaction;
import '../text/text.dart';
import '../state/range_set.dart' show Range;
import '../view/decoration.dart';
import '../view/keymap.dart';

class FieldPos {
  int field;
  final int line;
  int from;
  int to;

  FieldPos(this.field, this.line, this.from, this.to);
}

class FieldRange {
  final int field;
  final int from;
  final int to;

  FieldRange(this.field, this.from, this.to);

  FieldRange? map(ChangeDesc changes) {
    final newFrom = changes.mapPos(from, -1, MapMode.trackDel);
    final newTo = changes.mapPos(to, 1, MapMode.trackDel);
    if (newFrom == null || newTo == null) return null;
    return FieldRange(field, newFrom, newTo);
  }
}

class Snippet {
  final List<String> lines;
  final List<FieldPos> fieldPositions;

  Snippet(this.lines, this.fieldPositions);

  ({List<String> text, List<FieldRange> ranges}) instantiate(EditorState state, int pos) {
    final text = <String>[];
    final lineStart = [pos];
    final lineObj = state.doc.lineAt(pos);
    final baseIndentMatch = RegExp(r'^\s*').firstMatch(lineObj.text);
    final baseIndent = baseIndentMatch?.group(0) ?? '';

    var currentPos = pos;
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (text.isNotEmpty) {
        var indent = baseIndent;
        final tabsMatch = RegExp(r'^\t*').firstMatch(line);
        final tabs = tabsMatch?.group(0)?.length ?? 0;
        for (var j = 0; j < tabs; j++) {
          indent += state.facet(indentUnit);
        }
        lineStart.add(currentPos + indent.length - tabs);
        line = indent + line.substring(tabs);
      }
      text.add(line);
      currentPos += line.length + 1;
    }

    final ranges = fieldPositions.map((pos) {
      return FieldRange(pos.field, lineStart[pos.line] + pos.from, lineStart[pos.line] + pos.to);
    }).toList();

    return (text: text, ranges: ranges);
  }

  static Snippet parse(String template) {
    final fields = <({int? seq, String name})>[];
    final lines = <String>[];
    final positions = <FieldPos>[];

    for (var line in template.split(RegExp(r'\r\n?|\n'))) {
      RegExpMatch? m;
      while ((m = RegExp(r'[#$]\{(?:(\d+)(?::([^{}]*))?|((?:\\[{}]|[^{}])*))\}').firstMatch(line)) != null) {
        final seq = m!.group(1) != null ? int.parse(m.group(1)!) : null;
        final rawName = m.group(2) ?? m.group(3) ?? '';
        var found = -1;
        final name = rawName.replaceAllMapped(RegExp(r'\\([{}])'), (m) => m.group(1)!);

        for (var i = 0; i < fields.length; i++) {
          if (seq != null
              ? fields[i].seq == seq
              : name.isNotEmpty
                  ? fields[i].name == name
                  : false) {
            found = i;
          }
        }

        if (found < 0) {
          var i = 0;
          while (i < fields.length && (seq == null || (fields[i].seq != null && fields[i].seq! < seq))) {
            i++;
          }
          fields.insert(i, (seq: seq, name: name));
          found = i;
          for (final pos in positions) {
            if (pos.field >= found) pos.field++;
          }
        }

        for (final pos in positions) {
          if (pos.line == lines.length && pos.from > m.start) {
            final snip = m.group(2) != null ? 3 + (m.group(1) ?? '').length : 2;
            pos.from -= snip;
            pos.to -= snip;
          }
        }

        positions.add(FieldPos(found, lines.length, m.start, m.start + name.length));
        line = line.substring(0, m.start) + rawName + line.substring(m.start + m.group(0)!.length);
      }

      var index = 0;
      line = line.replaceAllMapped(RegExp(r'\\([{}])'), (match) {
        for (final pos in positions) {
          if (pos.line == lines.length && pos.from > index + match.start) {
            pos.from--;
            pos.to--;
          }
        }
        index = match.start;
        return match.group(1)!;
      });
      lines.add(line);
    }

    return Snippet(lines, positions);
  }
}

final _fieldMarker = Decoration.widgetDecoration(
  WidgetDecorationSpec(widget: _SnippetFieldWidget()),
);

final _fieldRange = Decoration.mark(
  MarkDecorationSpec(className: 'cm-snippetField'),
);

class _SnippetFieldWidget extends WidgetType {
  @override
  Widget toWidget(dynamic view) => const SizedBox.shrink();

  @override
  bool ignoreEvent(dynamic event) => false;
}

class ActiveSnippet {
  final List<FieldRange> ranges;
  final int active;
  final DecorationSet deco;

  ActiveSnippet(this.ranges, this.active)
      : deco = Decoration.createSet(
          ranges
              .map((r) => (r.from == r.to ? _fieldMarker : _fieldRange).range(r.from, r.to))
              .cast<Range<Decoration>>()
              .toList(),
          sort: true,
        );

  ActiveSnippet? map(ChangeDesc changes) {
    final newRanges = <FieldRange>[];
    for (final r in ranges) {
      final mapped = r.map(changes);
      if (mapped == null) return null;
      newRanges.add(mapped);
    }
    return ActiveSnippet(newRanges, active);
  }

  bool selectionInsideField(EditorSelection sel) {
    return sel.ranges.every((range) {
      return ranges.any((r) => r.field == active && r.from <= range.from && r.to >= range.to);
    });
  }
}

late final StateEffectType<ActiveSnippet?> _setActive;
late final StateEffectType<int> _moveToField;
late final StateField<ActiveSnippet?> _snippetState;
late final Facet<List<KeyBinding>, List<KeyBinding>> _snippetKeymap;

bool _initialized = false;

void _ensureInitialized() {
  if (_initialized) return;
  _initialized = true;

  _setActive = StateEffect.define<ActiveSnippet?>(
    map: (value, changes) => value?.map(changes),
  );

  _moveToField = StateEffect.define<int>();

  _snippetState = StateField.define(
    StateFieldConfig(
      create: (_) => null,
      update: (value, tr) {
        final transaction = tr as tx.Transaction;
        for (final effect in transaction.effects) {
          if (effect.is_(_setActive)) {
            return effect.value as ActiveSnippet?;
          }
          if (effect.is_(_moveToField) && value != null) {
            return ActiveSnippet(value.ranges, effect.value as int);
          }
        }
        if (value != null && transaction.docChanged) {
          value = value.map(transaction.changes);
        }
        if (value != null && transaction.selection != null && !value.selectionInsideField(transaction.selection!)) {
          value = null;
        }
        return value;
      },
    ),
  );

  _snippetKeymap = Facet.define<List<KeyBinding>, List<KeyBinding>>(
    FacetConfig(
      combine: (maps) => maps.isNotEmpty ? maps[0] : _defaultSnippetKeymap,
    ),
  );
}

void ensureSnippetInitialized() {
  _ensureInitialized();
}

StateField<ActiveSnippet?> get snippetState {
  _ensureInitialized();
  return _snippetState;
}

Facet<List<KeyBinding>, List<KeyBinding>> get snippetKeymap {
  _ensureInitialized();
  return _snippetKeymap;
}

EditorSelection _fieldSelection(List<FieldRange> ranges, int field) {
  return EditorSelection.create(
    ranges.where((r) => r.field == field).map((r) => EditorSelection.range(r.from, r.to)).toList(),
  );
}

typedef SnippetApplyFn = void Function(
  ({EditorState state, void Function(tx.Transaction) dispatch}) editor,
  dynamic completion,
  int from,
  int to,
);

SnippetApplyFn snippet(String template) {
  _ensureInitialized();
  final parsed = Snippet.parse(template);

  return (editor, completion, from, to) {
    final result = parsed.instantiate(editor.state, from);
    final text = result.text;
    final ranges = result.ranges;
    final main = editor.state.selection.main;

    final changes = ChangeSpec(
      from: from,
      to: to == main.from ? main.to : to,
      insert: Text.of(text),
    );

    EditorSelection? selection;
    if (ranges.isNotEmpty) {
      selection = _fieldSelection(ranges, 0);
    }

    final effects = <StateEffect<dynamic>>[];
    if (ranges.any((r) => r.field > 0)) {
      final active = ActiveSnippet(ranges, 0);
      effects.add(_setActive.of(active));
      if (editor.state.field(_snippetState, false) == null) {
        effects.add(StateEffect.appendConfig.of(ExtensionList([
          _snippetState,
          _addSnippetKeymap,
        ])));
      }
    }

    editor.dispatch(editor.state.update([
      TransactionSpec(
        changes: changes,
        selection: selection,
        effects: effects.isNotEmpty ? effects : null,
        scrollIntoView: true,
        userEvent: 'input.complete',
      ),
    ]));
  };
}

bool Function(({EditorState state, void Function(tx.Transaction) dispatch})) _moveField(int dir) {
  _ensureInitialized();
  return (target) {
    final active = target.state.field(_snippetState, false);
    if (active == null || (dir < 0 && active.active == 0)) return false;

    final next = active.active + dir;
    final last = dir > 0 && !active.ranges.any((r) => r.field == next + dir);

    target.dispatch(target.state.update([
      TransactionSpec(
        selection: _fieldSelection(active.ranges, next),
        effects: [_setActive.of(last ? null : ActiveSnippet(active.ranges, next))],
        scrollIntoView: true,
      ),
    ]));
    return true;
  };
}

bool clearSnippet(({EditorState state, void Function(tx.Transaction) dispatch}) target) {
  _ensureInitialized();
  final active = target.state.field(_snippetState, false);
  if (active == null) return false;
  target.dispatch(target.state.update([
    TransactionSpec(effects: [_setActive.of(null)]),
  ]));
  return true;
}

final nextSnippetField = _moveField(1);
final prevSnippetField = _moveField(-1);

bool hasNextSnippetField(EditorState state) {
  _ensureInitialized();
  final active = state.field(_snippetState, false);
  return active != null && active.ranges.any((r) => r.field == active.active + 1);
}

bool hasPrevSnippetField(EditorState state) {
  _ensureInitialized();
  final active = state.field(_snippetState, false);
  return active != null && active.active > 0;
}

Command _stateCmd(bool Function(({EditorState state, void Function(tx.Transaction) dispatch})) cmd) {
  return (view) {
    final state = (view as dynamic).state as EditorState;
    void dispatch(tx.Transaction tr) => (view as dynamic).dispatchTransaction(tr);
    return cmd((state: state, dispatch: dispatch));
  };
}

final List<KeyBinding> _defaultSnippetKeymap = [
  KeyBinding(key: 'Tab', run: _stateCmd(nextSnippetField), shift: _stateCmd(prevSnippetField)),
  KeyBinding(key: 'Escape', run: _stateCmd(clearSnippet)),
];

Extension get _addSnippetKeymap => Prec.highest(
      keymap.compute([_snippetKeymap], (state) => state.facet(_snippetKeymap)),
    );

({String label, String? detail, String? info, SnippetApplyFn apply}) snippetCompletion(
  String template,
  String label, {
  String? detail,
  String? info,
}) {
  return (
    label: label,
    detail: detail,
    info: info,
    apply: snippet(template),
  );
}
