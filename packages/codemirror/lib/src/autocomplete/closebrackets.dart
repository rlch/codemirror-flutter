/// Close brackets extension for CodeMirror.
///
/// This module provides automatic bracket closing, including:
/// - Inserting closing brackets when opening brackets are typed
/// - Skipping over already-inserted closing brackets
/// - Deleting bracket pairs together
library;

import '../language/language.dart';
import '../state/change.dart';
import '../state/facet.dart' hide EditorState, Transaction;
import '../state/range_set.dart';
import '../state/selection.dart';
import '../state/state.dart';
import '../state/transaction.dart' hide Transaction;
import '../state/transaction.dart' as tx show Transaction;
import '../text/text.dart';
import '../view/view.dart';

/// Configuration for bracket closing behavior.
class CloseBracketConfig {
  /// The opening brackets to close. Defaults to `["(", "[", "{", "'", '"']`.
  /// Brackets may be single characters or a triple of quotes (as in `"'''"`).
  final List<String> brackets;

  /// Characters in front of which newly opened brackets are automatically
  /// closed. Closing always happens in front of whitespace. Defaults to
  /// `")]}:;>"`.
  final String before;

  /// When determining whether a given node may be a string, recognize
  /// these prefixes before the opening quote.
  final List<String> stringPrefixes;

  const CloseBracketConfig({
    this.brackets = const ['(', '[', '{', "'", '"'],
    this.before = ')]}:;>',
    this.stringPrefixes = const [],
  });
}

const _defaults = CloseBracketConfig();

// Effect mapping returns null to drop the effect when the position is deleted
final _closeBracketEffect = StateEffect.define<int>(
  map: (value, mapping) {
    final mapped = mapping.mapPos(value, -1, MapMode.trackAfter);
    // Return null to drop the effect if position was deleted
    // mapPos returns null when the position is deleted with trackAfter
    return mapped;
  },
);

class _ClosedBracket extends RangeValue {
  @override
  int get startSide => 1;

  @override
  int get endSide => -1;

  @override
  bool eq(RangeValue other) => other is _ClosedBracket;
}

final _closedBracket = _ClosedBracket();

late final StateField<RangeSet<_ClosedBracket>> _bracketState;

bool _bracketStateInitialized = false;

void _ensureBracketStateInitialized() {
  if (_bracketStateInitialized) return;
  _bracketStateInitialized = true;

  _bracketState = StateField.define(
    StateFieldConfig(
      create: (_) => RangeSet.empty<_ClosedBracket>(),
      update: (value, tr) {
        final transaction = tr as tx.Transaction;
        value = value.map(transaction.changes);
        if (transaction.selection != null) {
          final line = (transaction.state as EditorState)
              .doc
              .lineAt(transaction.selection!.main.head);
          value = value.update(
            RangeSetUpdate(filter: (from, _, __) => from >= line.from && from <= line.to),
          );
        }
        for (final effect in transaction.effects) {
          if (effect.is_(_closeBracketEffect)) {
            final pos = effect.value as int;
            value = value.update(
              RangeSetUpdate(
                add: [Range.create(pos, pos + 1, _closedBracket)],
              ),
            );
          }
        }
        return value;
      },
    ),
  );
}

/// Input handler that intercepts bracket typing.
final _closeBracketInputHandler = EditorView.inputHandler.of((view, from, to, insert) {
  final v = view as EditorViewState;
  // Match JS: skip during composition or if read-only
  if (v.composing || v.compositionStarted || v.state.isReadOnly) return false;
  final sel = v.state.selection.main;
  // Only handle single-char insertions at cursor
  if (insert.length > 2 ||
      (insert.length == 2 && _codePointSize(insert, 0) == 1) ||
      from != sel.from ||
      to != sel.to) {
    return false;
  }
  final tr = insertBracket(v.state, insert);
  if (tr == null) return false;
  v.dispatchTransaction(tr);
  return true;
});

/// Extension to enable bracket-closing behavior.
///
/// When a closeable bracket is typed, its closing bracket is immediately
/// inserted after the cursor. When closing a bracket directly in front of
/// a closing bracket inserted by the extension, the cursor moves over that
/// bracket.
///
/// Note: Unlike the JS version, you must separately add [closeBracketsKeymap]
/// if you want Backspace to delete bracket pairs.
Extension closeBrackets() {
  _ensureBracketStateInitialized();
  // Match JS: only inputHandler and bracketState, NOT the keymap
  return ExtensionList([
    _closeBracketInputHandler,
    _bracketState,
  ]);
}

const _definedClosing = '()[]{}<>«»»«［］｛｝';

String _closing(int ch) {
  for (var i = 0; i < _definedClosing.length; i += 2) {
    if (_definedClosing.codeUnitAt(i) == ch) {
      return _definedClosing[i + 1];
    }
  }
  return String.fromCharCode(ch < 128 ? ch : ch + 1);
}

CloseBracketConfig _config(EditorState state, int pos) {
  // Language data can provide either a CloseBracketConfig or a raw Map
  final data = state.languageDataAt<dynamic>('closeBrackets', pos);
  if (data.isEmpty) return _defaults;

  final value = data[0];
  if (value is CloseBracketConfig) {
    return value;
  } else if (value is Map) {
    // Convert raw Map format (e.g., {'brackets': ['(', '[', ...]})
    final brackets = value['brackets'];
    final before = value['before'];
    final stringPrefixes = value['stringPrefixes'];
    return CloseBracketConfig(
      brackets: brackets is List ? brackets.cast<String>() : _defaults.brackets,
      before: before is String ? before : _defaults.before,
      stringPrefixes:
          stringPrefixes is List ? stringPrefixes.cast<String>() : _defaults.stringPrefixes,
    );
  }
  return _defaults;
}

/// Interface for state command targets.
///
/// This allows `deleteBracketPair` to be tested without a full EditorViewState.
abstract class StateCommandTarget {
  EditorState get state;
  void dispatchTransaction(tx.Transaction tr);
}

/// Command that implements deleting a pair of matching brackets when
/// the cursor is between them.
///
/// Accepts either an [EditorViewState] or any object implementing
/// [StateCommandTarget] with `state` and `dispatchTransaction`.
bool deleteBracketPair(dynamic view) {
  // Support both EditorViewState (runtime) and StateCommandTarget (testing)
  final EditorState state;
  final void Function(tx.Transaction) dispatch;
  
  if (view is StateCommandTarget) {
    state = view.state;
    dispatch = view.dispatchTransaction;
  } else {
    final v = view as EditorViewState;
    state = v.state;
    dispatch = v.dispatchTransaction;
  }
  
  if (state.isReadOnly) return false;
  final conf = _config(state, state.selection.main.head);
  final tokens = conf.brackets;
  SelectionRange? dont;
  final result = state.changeByRange((range) {
    if (range.empty) {
      final before = _prevChar(state.doc, range.head);
      for (final token in tokens) {
        if (token == before && _nextChar(state.doc, range.head) == _closing(token.codeUnitAt(0))) {
          return ChangeByRangeResult(
            changes: ChangeSpec(
              from: range.head - token.length,
              to: range.head + token.length,
            ),
            range: EditorSelection.cursor(range.head - token.length),
          );
        }
      }
    }
    dont = range;
    return ChangeByRangeResult(range: range);
  });
  if (dont == null) {
    // Match JS: dispatch(state.update(changes, {...}))
    dispatch(
      state.update([
        TransactionSpec(
          changes: result.changes,
          selection: result.selection,
          scrollIntoView: true,
          userEvent: 'delete.backward',
        ),
      ]),
    );
  }
  return dont == null;
}

/// Close-brackets related key bindings.
///
/// Binds Backspace to [deleteBracketPair].
final List<KeyBinding> closeBracketsKeymap = [
  KeyBinding(key: 'Backspace', run: deleteBracketPair),
];

/// Implements the extension's behavior on text insertion.
///
/// If the given string counts as a bracket in the language around the
/// selection, and replacing the selection with it requires custom
/// behavior (inserting a closing version or skipping past a
/// previously-closed bracket), this function returns a transaction
/// representing that custom behavior.
///
/// You only need this if you want to programmatically insert brackets—the
/// [closeBrackets] extension will take care of running this for user input.
tx.Transaction? insertBracket(EditorState state, String bracket) {
  final conf = _config(state, state.selection.main.head);
  final tokens = conf.brackets;
  for (final tok in tokens) {
    final closed = _closing(tok.codeUnitAt(0));
    if (bracket == tok) {
      return closed == tok
          ? _handleSame(state, tok, tokens.contains(tok + tok + tok), conf)
          : _handleOpen(state, tok, closed, conf.before);
    }
    if (bracket == closed && _closedBracketAt(state, state.selection.main.from)) {
      return _handleClose(state, tok, closed);
    }
  }
  return null;
}

bool _closedBracketAt(EditorState state, int pos) {
  _ensureBracketStateInitialized();
  final field = state.field(_bracketState, false);
  if (field == null) return false;
  var found = false;
  // Match JS: iterate between 0 and doc.length
  // RangeSet.between callback returns false to stop iteration
  field.between(0, state.doc.length, (from, _, __) {
    if (from == pos) found = true;
    return !found; // return false to stop when found
  });
  return found;
}

String _nextChar(Text doc, int pos) {
  final next = doc.sliceString(pos, pos + 2);
  if (next.isEmpty) return '';
  return next.substring(0, _codePointSize(next, 0));
}

String _prevChar(Text doc, int pos) {
  final prev = doc.sliceString(pos - 2 < 0 ? 0 : pos - 2, pos);
  if (prev.isEmpty) return '';
  return _codePointSize(prev, 0) == prev.length ? prev : prev.substring(1);
}

int _codePointSize(String str, int pos) {
  if (pos >= str.length) return 0;
  final code = str.codeUnitAt(pos);
  if (code >= 0xD800 && code < 0xDC00 && pos + 1 < str.length) {
    final next = str.codeUnitAt(pos + 1);
    if (next >= 0xDC00 && next < 0xE000) return 2;
  }
  return 1;
}

tx.Transaction? _handleOpen(
  EditorState state,
  String open,
  String close,
  String closeBefore,
) {
  SelectionRange? dont;
  final result = state.changeByRange((range) {
    if (!range.empty) {
      return ChangeByRangeResult(
        changes: [
          ChangeSpec(from: range.from, insert: open),
          ChangeSpec(from: range.to, insert: close),
        ],
        effects: [_closeBracketEffect.of(range.to + open.length)],
        range: EditorSelection.range(
          range.anchor + open.length,
          range.head + open.length,
        ),
      );
    }
    final next = _nextChar(state.doc, range.head);
    if (next.isEmpty || RegExp(r'\s').hasMatch(next) || closeBefore.contains(next)) {
      return ChangeByRangeResult(
        changes: ChangeSpec(from: range.head, insert: open + close),
        effects: [_closeBracketEffect.of(range.head + open.length)],
        range: EditorSelection.cursor(range.head + open.length),
      );
    }
    dont = range;
    return ChangeByRangeResult(range: range);
  });
  if (dont != null) return null;
  // Match JS: return state.update(...) which returns a Transaction
  return state.update([
    TransactionSpec(
      changes: result.changes,
      selection: result.selection,
      effects: result.effects,
      scrollIntoView: true,
      userEvent: 'input.type',
    ),
  ]);
}

tx.Transaction? _handleClose(EditorState state, String open, String close) {
  // Match JS: only move selection over the existing closing bracket, no text change
  // JS: let moved = state.selection.ranges.map(range => {...})
  SelectionRange? dont;
  final moved = <SelectionRange>[];
  
  for (final range in state.selection.ranges) {
    if (range.empty && _nextChar(state.doc, range.head) == close) {
      moved.add(EditorSelection.cursor(range.head + close.length));
    } else {
      dont = range;
      moved.add(range);
    }
  }
  
  if (dont != null) return null;
  
  // Match JS: pure selection update, no text changes
  // Note: JS also emits skipBracketEffect to clear markers, but we rely on
  // the bracket state field's line-based filtering instead
  return state.update([
    TransactionSpec(
      selection: EditorSelection.create(moved, state.selection.mainIndex),
      scrollIntoView: true,
    ),
  ]);
}

tx.Transaction? _handleSame(
  EditorState state,
  String token,
  bool allowTriple,
  CloseBracketConfig config,
) {
  final stringPrefixes = config.stringPrefixes;
  SelectionRange? dont;
  final result = state.changeByRange((range) {
    if (!range.empty) {
      return ChangeByRangeResult(
        changes: [
          ChangeSpec(from: range.from, insert: token),
          ChangeSpec(from: range.to, insert: token),
        ],
        effects: [_closeBracketEffect.of(range.to + token.length)],
        range: EditorSelection.range(
          range.anchor + token.length,
          range.head + token.length,
        ),
      );
    }
    final pos = range.head;
    final next = _nextChar(state.doc, pos);
    if (next == token) {
      if (_nodeStart(state, pos)) {
        return ChangeByRangeResult(
          changes: ChangeSpec(from: pos, insert: token + token),
          effects: [_closeBracketEffect.of(pos + token.length)],
          range: EditorSelection.cursor(pos + token.length),
        );
      } else if (_closedBracketAt(state, pos)) {
        final isTriple =
            allowTriple && state.sliceDoc(pos, pos + token.length * 3) == token + token + token;
        final content = isTriple ? token + token + token : token;
        return ChangeByRangeResult(
          changes: ChangeSpec(from: pos, to: pos + content.length, insert: content),
          range: EditorSelection.cursor(pos + content.length),
        );
      }
    } else if (allowTriple && state.sliceDoc(pos - 2 * token.length, pos) == token + token) {
      final start = _canStartStringAt(state, pos - 2 * token.length, stringPrefixes);
      if (start > -1 && _nodeStart(state, start)) {
        return ChangeByRangeResult(
          changes: ChangeSpec(from: pos, insert: token + token + token + token),
          effects: [_closeBracketEffect.of(pos + token.length)],
          range: EditorSelection.cursor(pos + token.length),
        );
      }
    } else if (state.charCategorizer(pos)(next) != CharCategory.word) {
      final start = _canStartStringAt(state, pos, stringPrefixes);
      if (start > -1 && !_probablyInString(state, pos, token, stringPrefixes)) {
        return ChangeByRangeResult(
          changes: ChangeSpec(from: pos, insert: token + token),
          effects: [_closeBracketEffect.of(pos + token.length)],
          range: EditorSelection.cursor(pos + token.length),
        );
      }
    }
    dont = range;
    return ChangeByRangeResult(range: range);
  });
  if (dont != null) return null;
  // Match JS: return state.update(...)
  return state.update([
    TransactionSpec(
      changes: result.changes,
      selection: result.selection,
      effects: result.effects,
      scrollIntoView: true,
      userEvent: 'input.type',
    ),
  ]);
}

bool _nodeStart(EditorState state, int pos) {
  final tree = syntaxTree(state).resolveInner(pos + 1, 0);
  return tree.parent != null && tree.from == pos;
}

bool _probablyInString(
  EditorState state,
  int pos,
  String quoteToken,
  List<String> prefixes,
) {
  var node = syntaxTree(state).resolveInner(pos, -1);
  final maxPrefix = prefixes.fold(0, (m, p) => m > p.length ? m : p.length);
  for (var i = 0; i < 5; i++) {
    final nodeTo =
        node.to < node.from + quoteToken.length + maxPrefix ? node.to : node.from + quoteToken.length + maxPrefix;
    final start = state.sliceDoc(node.from, nodeTo);
    final quotePos = start.indexOf(quoteToken);
    if (quotePos == 0 || (quotePos > -1 && prefixes.contains(start.substring(0, quotePos)))) {
      var first = node.firstChild;
      while (first != null &&
          first.from == node.from &&
          first.to - first.from > quoteToken.length + quotePos) {
        if (state.sliceDoc(first.to - quoteToken.length, first.to) == quoteToken) {
          return false;
        }
        first = first.firstChild;
      }
      return true;
    }
    final parent = node.to == pos ? node.parent : null;
    if (parent == null) break;
    node = parent;
  }
  return false;
}

int _canStartStringAt(EditorState state, int pos, List<String> prefixes) {
  final charCat = state.charCategorizer(pos);
  if (charCat(state.sliceDoc(pos - 1, pos)) != CharCategory.word) return pos;
  for (final prefix in prefixes) {
    final start = pos - prefix.length;
    if (state.sliceDoc(start, pos) == prefix &&
        charCat(state.sliceDoc(start - 1, start)) != CharCategory.word) {
      return start;
    }
  }
  return -1;
}
