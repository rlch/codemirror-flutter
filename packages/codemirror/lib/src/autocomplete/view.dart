import 'dart:async';

import '../state/facet.dart' hide EditorState, Transaction;
import '../state/state.dart';
import '../state/transaction.dart';
import '../view/editor_view.dart';
import '../view/view_plugin.dart';
import '../view/view_update.dart';
import 'completion.dart';
import 'config.dart';
import 'state.dart' hide State;
import 'state.dart' as cs show State;

typedef Command = bool Function(EditorViewState);

Command moveCompletionSelection(bool forward, [String by = 'option']) {
  return (EditorViewState view) {
    final cState = view.state.field(completionState);
    if (cState == null || cState.open == null || cState.open!.disabled) {
      return false;
    }
    if (DateTime.now().millisecondsSinceEpoch - cState.open!.timestamp <
        view.state.facet(completionConfig).interactionDelay) {
      return true;
    }
    var step = 1;
    if (by == 'page') {
      step = 5;
    }
    final length = cState.open!.options.length;
    var selected = cState.open!.selected > -1
        ? cState.open!.selected + step * (forward ? 1 : -1)
        : forward
            ? 0
            : length - 1;
    if (selected < 0) {
      selected = by == 'page' ? 0 : length - 1;
    } else if (selected >= length) {
      selected = by == 'page' ? length - 1 : 0;
    }
    view.dispatch([TransactionSpec(effects: [setSelectedEffect.of(selected)])]);
    return true;
  };
}

bool acceptCompletion(EditorViewState view) {
  final cState = view.state.field(completionState);
  if (view.state.isReadOnly ||
      cState == null ||
      cState.open == null ||
      cState.open!.selected < 0 ||
      cState.open!.disabled) {
    return false;
  }
  if (DateTime.now().millisecondsSinceEpoch - cState.open!.timestamp <
      view.state.facet(completionConfig).interactionDelay) {
    return true;
  }
  return applyCompletion(view, cState.open!.options[cState.open!.selected]);
}

bool startCompletion(EditorViewState view) {
  final cState = view.state.field(completionState);
  if (cState == null) return false;
  view.dispatch([TransactionSpec(effects: [startCompletionEffect.of(true)])]);
  return true;
}

bool closeCompletion(EditorViewState view) {
  final cState = view.state.field(completionState);
  if (cState == null || !cState.active.any((a) => a.state != cs.State.inactive)) return false;
  view.dispatch([TransactionSpec(effects: [closeCompletionEffect.of(null)])]);
  return true;
}

class RunningQuery {
  final int time = DateTime.now().millisecondsSinceEpoch;
  final List<Transaction> updates = [];
  CompletionResult? done;
  bool isDone = false;
  final ActiveSource active;
  final CompletionContext context;

  RunningQuery(this.active, this.context);
}

const _maxUpdateCount = 50;
const _minAbortTime = 1000;

enum CompositionState { none, started, changed, changedAndMoved }

class CompletionPluginValue extends PluginValue {
  final EditorViewState view;
  Timer? debounceUpdate;
  List<RunningQuery> running = [];
  Timer? debounceAccept;
  bool pendingStart = false;
  CompositionState composing = CompositionState.none;

  CompletionPluginValue(this.view) {
    final cState = view.state.field(completionState);
    if (cState != null) {
      for (final active in cState.active) {
        if (active.isPending) startQuery(active);
      }
    }
  }

  @override
  void update(ViewUpdate update) {
    final cState = update.state.field(completionState);
    final conf = update.state.facet(completionConfig);
    if (!update.selectionSet &&
        !update.docChanged &&
        identical(update.startState.field(completionState), cState)) {
      return;
    }

    var doesReset = false;
    for (final tr in update.transactions) {
      final type = getUpdateType(tr, conf);
      if ((type & UpdateType.reset) != 0 ||
          (tr.selection != null || tr.docChanged) && (type & UpdateType.simpleInteraction) == 0) {
        doesReset = true;
        break;
      }
    }

    for (var i = 0; i < running.length; i++) {
      final query = running[i];
      if (doesReset ||
          query.context.abortOnDocChange && update.docChanged ||
          query.updates.length + update.transactions.length > _maxUpdateCount &&
              DateTime.now().millisecondsSinceEpoch - query.time > _minAbortTime) {
        query.context.abort();
        running.removeAt(i);
        i--;
      } else {
        query.updates.addAll(update.transactions);
      }
    }

    debounceUpdate?.cancel();
    if (update.transactions.any((tr) => tr.effects.any((e) => e.is_(startCompletionEffect)))) {
      pendingStart = true;
    }
    final delay = pendingStart ? 50 : conf.activateOnTypingDelay;
    final hasPending =
        cState != null && cState.active.any((a) => a.isPending && !running.any((q) => identical(q.active.source, a.source)));
    debounceUpdate = hasPending ? Timer(Duration(milliseconds: delay), startUpdate) : null;

    if (composing != CompositionState.none) {
      for (final tr in update.transactions) {
        if (tr.isUserEvent('input.type')) {
          composing = CompositionState.changed;
        } else if (composing == CompositionState.changed && tr.selection != null) {
          composing = CompositionState.changedAndMoved;
        }
      }
    }
  }

  void startUpdate() {
    debounceUpdate = null;
    pendingStart = false;
    final cState = view.state.field(completionState);
    if (cState == null) return;
    for (final active in cState.active) {
      if (active.isPending && !running.any((r) => identical(r.active.source, active.source))) {
        startQuery(active);
      }
    }
    if (running.isNotEmpty && cState.open != null && cState.open!.disabled) {
      debounceAccept = Timer(
        Duration(milliseconds: view.state.facet(completionConfig).updateSyncTime),
        accept,
      );
    }
  }

  void startQuery(ActiveSource active) {
    final pos = cur(view.state);
    final context = CompletionContext(state: view.state, pos: pos, explicit: active.explicit, view: view);
    final pending = RunningQuery(active, context);
    running.add(pending);
    Future.value(active.source(context)).then((result) {
      if (!pending.context.aborted) {
        pending.done = result;
        pending.isDone = true;
        scheduleAccept();
      }
    }).catchError((Object err) {
      view.dispatch([TransactionSpec(effects: [closeCompletionEffect.of(null)])]);
      logException(view.state, err);
    });
  }

  void scheduleAccept() {
    if (running.every((q) => q.isDone)) {
      accept();
    } else {
      debounceAccept ??= Timer(
        Duration(milliseconds: view.state.facet(completionConfig).updateSyncTime),
        accept,
      );
    }
  }

  void accept() {
    debounceAccept?.cancel();
    debounceAccept = null;

    final updated = <ActiveSource>[];
    final conf = view.state.facet(completionConfig);
    final cState = view.state.field(completionState);

    for (var i = 0; i < running.length; i++) {
      final query = running[i];
      if (!query.isDone) continue;
      running.removeAt(i);
      i--;

      if (query.done != null) {
        final pos = cur(query.updates.isNotEmpty ? query.updates[0].startState as EditorState : view.state);
        final limit = pos < query.done!.from + (query.active.explicit ? 0 : 1)
            ? pos
            : query.done!.from + (query.active.explicit ? 0 : 1);
        ActiveSource activeResult = ActiveResult(
          source: query.active.source,
          explicit: query.active.explicit,
          limit: limit,
          result: query.done!,
          from: query.done!.from,
          to: query.done!.to ?? pos,
        );
        for (final tr in query.updates) {
          activeResult = activeResult.updateFor(tr, getUpdateType(tr, conf));
        }
        if (activeResult.hasResult()) {
          updated.add(activeResult);
          continue;
        }
      }

      final current = cState?.active.cast<ActiveSource?>().firstWhere(
            (a) => identical(a?.source, query.active.source),
            orElse: () => null,
          );
      if (current != null && current.isPending) {
        if (query.done == null) {
          var activeSource = ActiveSource(source: query.active.source, state: cs.State.inactive);
          for (final tr in query.updates) {
            activeSource = activeSource.updateFor(tr, getUpdateType(tr, conf));
          }
          if (!activeSource.isPending) updated.add(activeSource);
        } else {
          startQuery(current);
        }
      }
    }

    if (updated.isNotEmpty || (cState?.open != null && cState!.open!.disabled)) {
      view.dispatch([TransactionSpec(effects: [setActiveEffect.of(updated)])]);
    }
  }

  @override
  void destroy(EditorViewState view) {
    debounceUpdate?.cancel();
    debounceAccept?.cancel();
  }

  void onBlur(dynamic event) {
    final state = view.state.field(completionState);
    if (state != null && state.tooltip != null && view.state.facet(completionConfig).closeOnBlur) {
      Timer(const Duration(milliseconds: 10), () {
        view.dispatch([TransactionSpec(effects: [closeCompletionEffect.of(null)])]);
      });
    }
  }

  void onCompositionStart() {
    composing = CompositionState.started;
  }

  void onCompositionEnd() {
    if (composing == CompositionState.changedAndMoved) {
      Timer(const Duration(milliseconds: 20), () {
        view.dispatch([TransactionSpec(effects: [startCompletionEffect.of(false)])]);
      });
    }
    composing = CompositionState.none;
  }
}

ViewPlugin<CompletionPluginValue>? _completionPluginInstance;

ViewPlugin<CompletionPluginValue> get completionPlugin {
  return _completionPluginInstance ??= ViewPlugin.define<CompletionPluginValue>(
    (view) => CompletionPluginValue(view),
    ViewPluginSpec(
      eventHandlers: {
        'blur': (event, view) {
          final plugin = view.plugin(_completionPluginInstance!);
          plugin?.onBlur(event);
          return false;
        },
        'compositionstart': (event, view) {
          final plugin = view.plugin(_completionPluginInstance!);
          plugin?.onCompositionStart();
          return false;
        },
        'compositionend': (event, view) {
          final plugin = view.plugin(_completionPluginInstance!);
          plugin?.onCompositionEnd();
          return false;
        },
      },
    ),
  );
}

final commitCharacters = Prec.highest(
  viewPlugin.of(ViewPlugin.define<_CommitCharacterPlugin>(
    (view) => _CommitCharacterPlugin(view),
    ViewPluginSpec(
      eventHandlers: {
        'keydown': (event, view) {
          final field = view.state.field(completionState);
          if (field == null ||
              field.open == null ||
              field.open!.disabled ||
              field.open!.selected < 0) {
            return false;
          }
          final key = event is String ? event : (event as dynamic).key as String?;
          if (key == null || key.length > 1) return false;
          final option = field.open!.options[field.open!.selected];
          final result = field.active.cast<ActiveSource?>().firstWhere(
                (a) => identical(a?.source, option.source),
                orElse: () => null,
              );
          if (result is! ActiveResult) return false;
          final commitChars = option.completion.commitCharacters ?? result.result.commitCharacters;
          if (commitChars != null && commitChars.contains(key)) {
            applyCompletion(view, option);
          }
          return false;
        },
      },
    ),
  )),
);

class _CommitCharacterPlugin extends PluginValue {
  _CommitCharacterPlugin(this.view);
  final EditorViewState view;
}
