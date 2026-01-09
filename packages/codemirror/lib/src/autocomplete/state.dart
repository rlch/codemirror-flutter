import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import '../state/change.dart';
import '../state/facet.dart' hide EditorState, Transaction;
import '../state/state.dart';
import '../state/transaction.dart';
import '../view/editor_view.dart';
import '../view/tooltip.dart';
import 'completion.dart';
import 'config.dart';
import 'filter.dart';

enum State { inactive, pending, result }

class UpdateType {
  UpdateType._();

  static const int none = 0;
  static const int typing = 1;
  static const int backspacing = 2;
  static const int simpleInteraction = typing | backspacing;
  static const int activate = 4;
  static const int reset = 8;
  static const int resetIfTouching = 16;
}

int _score(Completion option) {
  return (option.boost ?? 0) * 100 +
      (option.apply != null ? 10 : 0) +
      (option.info != null ? 5 : 0) +
      (option.type != null ? 1 : 0);
}

List<Option> sortOptions(List<ActiveSource> active, EditorState state) {
  final options = <Option>[];
  List<CompletionSection>? sections;
  Map<String, int>? dynamicSectionScore;

  void addOption(Option option) {
    options.add(option);
    final section = option.completion.section;
    if (section != null) {
      sections ??= [];
      final name = section is String ? section : (section as CompletionSection).name;
      if (!sections!.any((s) => s.name == name)) {
        sections!.add(section is String ? CompletionSection(name: section) : section as CompletionSection);
      }
    }
  }

  final conf = state.facet(completionConfig);
  for (final a in active) {
    if (a.hasResult()) {
      final ar = a as ActiveResult;
      final getMatch = ar.result.getMatch;
      if (ar.result.filter == false) {
        for (final option in ar.result.options) {
          addOption(Option(
            completion: option,
            source: a.source,
            match: getMatch != null ? getMatch(option, null) : [],
            score: 1000000000 - options.length,
          ));
        }
      } else {
        final pattern = state.sliceDoc(ar.from, ar.to);
        for (final option in ar.result.options) {
          final ({int score, List<int> matched})? match;
          if (conf.filterStrict) {
            match = StrictMatcher(pattern).match(option.label);
          } else {
            match = FuzzyMatcher(pattern).match(option.label);
          }
          if (match != null) {
            final matched = option.displayLabel == null
                ? match.matched
                : getMatch != null
                    ? getMatch(option, match.matched)
                    : <int>[];
            final score = match.score + (option.boost ?? 0);
            addOption(Option(
              completion: option,
              source: a.source,
              match: matched,
              score: score,
            ));
            final sec = option.section;
            if (sec is CompletionSection && sec.rank == 'dynamic') {
              final name = sec.name;
              dynamicSectionScore ??= {};
              dynamicSectionScore[name] = math.max(score, dynamicSectionScore[name] ?? -1000000000);
            }
          }
        }
      }
    }
  }

  if (sections != null) {
    final sectionOrder = <String, int>{};
    var pos = 0;

    int cmp(CompletionSection a, CompletionSection b) {
      final aRank = a.rank;
      final bRank = b.rank;
      if (aRank == 'dynamic' && bRank == 'dynamic' && dynamicSectionScore != null) {
        return (dynamicSectionScore[b.name] ?? 0) - (dynamicSectionScore[a.name] ?? 0);
      }
      final aNum = aRank is int ? aRank : 1000000000;
      final bNum = bRank is int ? bRank : 1000000000;
      if (aNum != bNum) return aNum - bNum;
      return a.name.compareTo(b.name);
    }

    sections!.sort(cmp);
    for (final s in sections!) {
      pos -= 100000;
      sectionOrder[s.name] = pos;
    }
    for (final option in options) {
      final section = option.completion.section;
      if (section != null) {
        final name = section is String ? section : (section as CompletionSection).name;
        option.score += sectionOrder[name]!;
      }
    }
  }

  final result = <Option>[];
  Completion? prev;
  final compare = conf.compareCompletions;
  final sorted = options.toList()
    ..sort((a, b) {
      final scoreDiff = b.score - a.score;
      if (scoreDiff != 0) return scoreDiff;
      return compare(a.completion, b.completion);
    });

  for (final opt in sorted) {
    final cur = opt.completion;
    if (prev == null ||
        prev.label != cur.label ||
        prev.detail != cur.detail ||
        (prev.type != null && cur.type != null && prev.type != cur.type) ||
        prev.apply != cur.apply ||
        prev.boost != cur.boost) {
      result.add(opt);
    } else if (_score(opt.completion) > _score(prev)) {
      result[result.length - 1] = opt;
    }
    prev = opt.completion;
  }
  return result;
}

class CompletionDialog {
  final List<Option> options;
  final Map<String, String> attrs;
  final HoverTooltip tooltip;
  final int timestamp;
  final int selected;
  final bool disabled;

  const CompletionDialog({
    required this.options,
    required this.attrs,
    required this.tooltip,
    required this.timestamp,
    required this.selected,
    required this.disabled,
  });

  CompletionDialog setSelected(int selected, String id) {
    if (selected == this.selected || selected >= options.length) return this;
    return CompletionDialog(
      options: options,
      attrs: makeAttrs(id, selected),
      tooltip: tooltip,
      timestamp: timestamp,
      selected: selected,
      disabled: disabled,
    );
  }

  static CompletionDialog? build(
    List<ActiveSource> active,
    EditorState state,
    String id,
    CompletionDialog? prev,
    CompletionConfig conf,
    bool didSetActive,
  ) {
    if (prev != null && !didSetActive && active.any((s) => s.isPending)) {
      return prev.setDisabled();
    }
    final options = sortOptions(active, state);
    if (options.isEmpty) {
      return prev != null && active.any((a) => a.isPending) ? prev.setDisabled() : null;
    }
    var selected = state.facet(completionConfig).selectOnOpen ? 0 : -1;
    if (prev != null && prev.selected != selected && prev.selected != -1) {
      final selectedValue = prev.options[prev.selected].completion;
      for (var i = 0; i < options.length; i++) {
        if (identical(options[i].completion, selectedValue)) {
          selected = i;
          break;
        }
      }
    }
    return CompletionDialog(
      options: options,
      attrs: makeAttrs(id, selected),
      tooltip: HoverTooltip(
        pos: active.fold<int>(100000000, (a, b) => b.hasResult() ? math.min(a, (b as ActiveResult).from) : a),
        create: _createTooltip,
        above: conf.aboveCursor,
      ),
      timestamp: prev?.timestamp ?? DateTime.now().millisecondsSinceEpoch,
      selected: selected,
      disabled: false,
    );
  }

  CompletionDialog map(ChangeDesc changes) {
    return CompletionDialog(
      options: options,
      attrs: attrs,
      tooltip: tooltip.copyWith(pos: changes.mapPos(tooltip.pos)),
      timestamp: timestamp,
      selected: selected,
      disabled: disabled,
    );
  }

  CompletionDialog setDisabled() {
    return CompletionDialog(
      options: options,
      attrs: attrs,
      tooltip: tooltip,
      timestamp: timestamp,
      selected: selected,
      disabled: true,
    );
  }
}

class CompletionState {
  final List<ActiveSource> active;
  final String id;
  final CompletionDialog? open;

  const CompletionState({
    required this.active,
    required this.id,
    this.open,
  });

  static CompletionState start() {
    return CompletionState(
      active: const [],
      id: 'cm-ac-${(math.Random().nextDouble() * 2000000).floor().toRadixString(36)}',
    );
  }

  CompletionState update(Transaction tr) {
    final state = tr.state as EditorState;
    final conf = state.facet(completionConfig);

    final sources = conf.override ??
        state
            .languageDataAt<Object>('autocomplete', cur(state))
            .map((s) => asSource(s))
            .toList();
    var activeList = sources.map((source) {
      final value = active.firstWhere((s) => identical(s.source, source),
              orElse: () => ActiveSource(
                    source: source,
                    state: active.any((a) => a.state != State.inactive) ? State.pending : State.inactive,
                  ))
          .update(tr, conf);
      return value;
    }).toList();

    if (activeList.length == active.length) {
      var allSame = true;
      for (var i = 0; i < activeList.length; i++) {
        if (!identical(activeList[i], active[i])) {
          allSame = false;
          break;
        }
      }
      if (allSame) activeList = active;
    }

    var openDialog = open;
    final didSet = tr.effects.any((e) => e.is_(setActiveEffect));
    if (openDialog != null && tr.docChanged) openDialog = openDialog.map(tr.changes);
    if (tr.selection != null ||
        activeList.any((a) => a.hasResult() && tr.changes.touchesRange((a as ActiveResult).from, a.to)) ||
        !sameResults(activeList, active) ||
        didSet) {
      openDialog = CompletionDialog.build(activeList, state, id, openDialog, conf, didSet);
    } else if (openDialog != null && openDialog.disabled && !activeList.any((a) => a.isPending)) {
      openDialog = null;
    }

    if (openDialog == null && activeList.every((a) => !a.isPending) && activeList.any((a) => a.hasResult())) {
      activeList = activeList.map((a) => a.hasResult() ? ActiveSource(source: a.source, state: State.inactive) : a).toList();
    }
    for (final effect in tr.effects) {
      if (effect.is_(setSelectedEffect)) {
        openDialog = openDialog?.setSelected(effect.value as int, id);
      }
    }

    return identical(activeList, active) && identical(openDialog, open)
        ? this
        : CompletionState(active: activeList, id: id, open: openDialog);
  }

  HoverTooltip? get tooltip => open?.tooltip;

  Map<String, String> get attrs {
    if (open != null) return open!.attrs;
    if (active.isNotEmpty) return _baseAttrs;
    return const {};
  }
}

bool sameResults(List<ActiveSource> a, List<ActiveSource> b) {
  if (identical(a, b)) return true;
  var iA = 0;
  var iB = 0;
  while (true) {
    while (iA < a.length && !a[iA].hasResult()) {
      iA++;
    }
    while (iB < b.length && !b[iB].hasResult()) {
      iB++;
    }
    final endA = iA == a.length;
    final endB = iB == b.length;
    if (endA || endB) return endA == endB;
    if (!identical((a[iA++] as ActiveResult).result, (b[iB++] as ActiveResult).result)) return false;
  }
}

const _baseAttrs = {'aria-autocomplete': 'list'};

Map<String, String> makeAttrs(String id, int selected) {
  final result = <String, String>{
    'aria-autocomplete': 'list',
    'aria-haspopup': 'listbox',
    'aria-controls': id,
  };
  if (selected > -1) result['aria-activedescendant'] = '$id-$selected';
  return result;
}

int getUpdateType(Transaction tr, CompletionConfig conf) {
  if (tr.isUserEvent('input.complete')) {
    final completion = tr.annotation(pickedCompletion);
    if (completion != null && conf.activateOnCompletion(completion)) {
      return UpdateType.activate | UpdateType.reset;
    }
  }
  final typing = tr.isUserEvent('input.type');
  if (typing && conf.activateOnTyping) return UpdateType.activate | UpdateType.typing;
  if (typing) return UpdateType.typing;
  if (tr.isUserEvent('delete.backward')) return UpdateType.backspacing;
  if (tr.selection != null) return UpdateType.reset;
  if (tr.docChanged) return UpdateType.resetIfTouching;
  return UpdateType.none;
}

class ActiveSource {
  final CompletionSource source;
  final State state;
  final bool explicit;

  const ActiveSource({
    required this.source,
    required this.state,
    this.explicit = false,
  });

  bool hasResult() => false;

  bool get isPending => state == State.pending;

  ActiveSource update(Transaction tr, CompletionConfig conf) {
    final type = getUpdateType(tr, conf);
    ActiveSource value = this;
    if ((type & UpdateType.reset) != 0 || ((type & UpdateType.resetIfTouching) != 0 && touches(tr))) {
      value = ActiveSource(source: value.source, state: State.inactive);
    }
    if ((type & UpdateType.activate) != 0 && value.state == State.inactive) {
      value = ActiveSource(source: source, state: State.pending);
    }
    value = value.updateFor(tr, type);

    for (final effect in tr.effects) {
      if (effect.is_(startCompletionEffect)) {
        value = ActiveSource(source: value.source, state: State.pending, explicit: effect.value as bool);
      } else if (effect.is_(closeCompletionEffect)) {
        value = ActiveSource(source: value.source, state: State.inactive);
      } else if (effect.is_(setActiveEffect)) {
        for (final active in effect.value as List<ActiveSource>) {
          if (identical(active.source, value.source)) value = active;
        }
      }
    }
    return value;
  }

  ActiveSource updateFor(Transaction tr, int type) => map(tr.changes);

  ActiveSource map(ChangeDesc changes) => this;

  bool touches(Transaction tr) {
    return tr.changes.touchesRange(cur(tr.state as EditorState));
  }
}

class ActiveResult extends ActiveSource {
  final int limit;
  final CompletionResult result;
  final int from;
  final int to;

  const ActiveResult({
    required super.source,
    required super.explicit,
    required this.limit,
    required this.result,
    required this.from,
    required this.to,
  }) : super(state: State.result);

  @override
  bool hasResult() => true;

  @override
  ActiveSource updateFor(Transaction tr, int type) {
    if ((type & UpdateType.simpleInteraction) == 0) return map(tr.changes);
    CompletionResult? res = result;
    if (res.map != null && !tr.changes.empty) res = res.map!(res, tr.changes);
    final newFrom = tr.changes.mapPos(from)!;
    final newTo = tr.changes.mapPos(to, 1)!;
    final pos = cur(tr.state as EditorState);
    if (pos > newTo ||
        res == null ||
        ((type & UpdateType.backspacing) != 0 &&
            (cur(tr.startState as EditorState) == from || pos < limit))) {
      return ActiveSource(
        source: source,
        state: (type & UpdateType.activate) != 0 ? State.pending : State.inactive,
      );
    }
    final newLimit = tr.changes.mapPos(limit)!;
    if (checkValid(res.validFor, tr.state as EditorState, newFrom, newTo)) {
      return ActiveResult(
        source: source,
        explicit: explicit,
        limit: newLimit,
        result: res,
        from: newFrom,
        to: newTo,
      );
    }
    if (res.update != null) {
      final updated = res.update!(res, newFrom, newTo, CompletionContext(state: tr.state as EditorState, pos: pos, explicit: false));
      if (updated != null) {
        return ActiveResult(
          source: source,
          explicit: explicit,
          limit: newLimit,
          result: updated,
          from: updated.from,
          to: updated.to ?? cur(tr.state as EditorState),
        );
      }
    }
    return ActiveSource(source: source, state: State.pending, explicit: explicit);
  }

  @override
  ActiveSource map(ChangeDesc changes) {
    if (changes.empty) return this;
    final res = result.map != null ? result.map!(result, changes) : result;
    if (res == null) return ActiveSource(source: source, state: State.inactive);
    return ActiveResult(
      source: source,
      explicit: explicit,
      limit: changes.mapPos(limit)!,
      result: result,
      from: changes.mapPos(from)!,
      to: changes.mapPos(to, 1)!,
    );
  }

  @override
  bool touches(Transaction tr) {
    return tr.changes.touchesRange(from, to);
  }
}

bool checkValid(Object? validFor, EditorState state, int from, int to) {
  if (validFor == null) return false;
  final text = state.sliceDoc(from, to);
  if (validFor is ValidForPredicate) return validFor(text, from, to, state);
  if (validFor is RegExp) return ensureAnchor(validFor, true).hasMatch(text);
  return false;
}

final setActiveEffect = StateEffect.define<List<ActiveSource>>(
  map: (sources, mapping) => sources.map((s) => s.map(mapping)).toList(),
);

final setSelectedEffect = StateEffect.define<int>();

final completionState = StateField.define<CompletionState>(
  StateFieldConfig(
    create: (_) => CompletionState.start(),
    update: (value, transaction) => value.update(transaction as Transaction),
  ),
);

bool applyCompletion(EditorViewState view, Option option) {
  final apply = option.completion.apply ?? option.completion.label;
  final state = view.state;
  final result = state.field(completionState)?.active.firstWhere(
        (a) => identical(a.source, option.source),
        orElse: () => ActiveSource(source: option.source, state: State.inactive),
      );
  if (result == null || result is! ActiveResult) return false;

  if (apply is String) {
    final spec = insertCompletionText(state, apply, result.from, result.to);
    view.dispatch([
      TransactionSpec(
        changes: spec.changes,
        selection: spec.selection,
        annotations: [pickedCompletion.of(option.completion)],
      ),
    ]);
  } else if (apply is void Function(EditorViewState, Completion, int, int)) {
    apply(view, option.completion, result.from, result.to);
  }
  return true;
}

TooltipView _createTooltip(context) {
  throw UnimplementedError('completionTooltip not yet implemented');
}
