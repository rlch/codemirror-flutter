export 'closebrackets.dart'
    show
        CloseBracketConfig,
        closeBrackets,
        closeBracketsKeymap,
        deleteBracketPair,
        insertBracket;
export 'completion.dart'
    show
        Completion,
        CompletionContext,
        CompletionResult,
        CompletionSource,
        CompletionSection,
        pickedCompletion,
        completeFromList,
        ifIn,
        ifNotIn,
        insertCompletionText;
export 'config.dart' show CompletionConfig;
export 'snippet.dart'
    show
        snippet,
        snippetCompletion,
        nextSnippetField,
        prevSnippetField,
        hasNextSnippetField,
        hasPrevSnippetField,
        clearSnippet,
        snippetKeymap,
        ensureSnippetInitialized;
export 'state.dart' show completionState, CompletionState, ActiveSource, ActiveResult, CompletionDialog, setSelectedEffect, applyCompletion;
export 'view.dart' show startCompletion, closeCompletion, acceptCompletion, moveCompletionSelection, completionPlugin;
export 'word.dart' show completeAnyWord;

import '../state/facet.dart' hide EditorState, Transaction;
import '../state/state.dart';
import '../view/editor_view.dart';
import '../view/keymap.dart';
import 'completion.dart';
import 'config.dart';
import 'state.dart' hide State;
import 'state.dart' as cs show State;
import 'view.dart' hide Command;

Extension autocompletion([CompletionConfig config = const CompletionConfig()]) {
  return ExtensionList([
    commitCharacters,
    completionState,
    completionConfig.of(config),
    completionPlugin.extension,
    completionKeymapExt,
  ]);
}

final List<KeyBinding> completionKeymap = [
  KeyBinding(key: 'Ctrl-Space', run: _wrapCmd(startCompletion)),
  KeyBinding(mac: 'Alt-`', run: _wrapCmd(startCompletion)),
  KeyBinding(mac: 'Alt-i', run: _wrapCmd(startCompletion)),
  KeyBinding(key: 'Escape', run: _wrapCmd(closeCompletion)),
  KeyBinding(key: 'ArrowDown', run: _wrapCmd(moveCompletionSelection(true))),
  KeyBinding(key: 'ArrowUp', run: _wrapCmd(moveCompletionSelection(false))),
  KeyBinding(key: 'Ctrl-n', run: _wrapCmd(moveCompletionSelection(true))),
  KeyBinding(key: 'Ctrl-p', run: _wrapCmd(moveCompletionSelection(false))),
  KeyBinding(key: 'PageDown', run: _wrapCmd(moveCompletionSelection(true, 'page'))),
  KeyBinding(key: 'PageUp', run: _wrapCmd(moveCompletionSelection(false, 'page'))),
  KeyBinding(key: 'Enter', run: _wrapCmd(acceptCompletion)),
  KeyBinding(key: 'Tab', run: _wrapCmd(acceptCompletion)),
];

Command _wrapCmd(bool Function(EditorViewState) cmd) {
  return (view) => cmd(view as EditorViewState);
}

final Extension completionKeymapExt = Prec.highest(
  keymap.computeN(
    [completionConfig],
    (state) => state.facet(completionConfig).defaultKeymap ? [completionKeymap] : [],
  ),
);

String? completionStatus(EditorState state) {
  final cState = state.field(completionState, false);
  if (cState == null) return null;
  if (cState.active.any((a) => a.isPending)) return 'pending';
  if (cState.active.any((a) => a.state != cs.State.inactive)) return 'active';
  return null;
}

List<Completion> currentCompletions(EditorState state) {
  final open = state.field(completionState, false)?.open;
  if (open == null || open.disabled) return const [];
  return open.options.map((o) => o.completion).toList();
}

Completion? selectedCompletion(EditorState state) {
  final open = state.field(completionState, false)?.open;
  if (open == null || open.disabled || open.selected < 0) return null;
  return open.options[open.selected].completion;
}

int? selectedCompletionIndex(EditorState state) {
  final open = state.field(completionState, false)?.open;
  if (open == null || open.disabled || open.selected < 0) return null;
  return open.selected;
}

StateEffect<int> setSelectedCompletion(int index) {
  return setSelectedEffect.of(index);
}
