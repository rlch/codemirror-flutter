/// Autocomplete completion types and utilities.
///
/// This module provides the core types for the autocomplete system including
/// [Completion], [CompletionResult], [CompletionContext], and [CompletionSource].
library;

import 'dart:async';

import 'package:flutter/widgets.dart' show Widget;
import 'package:lezer/lezer.dart' show NodeType;

import '../language/language.dart';
import '../state/change.dart';
import '../state/selection.dart';
import '../state/state.dart';
import '../state/transaction.dart';
import '../view/editor_view.dart';

class Completion {
  final String label;
  final String? displayLabel;
  final String? sortText;
  final String? detail;
  final Object? info;
  final Object? apply;
  final String? type;
  final List<String>? commitCharacters;
  final int? boost;
  final Object? section;

  const Completion({
    required this.label,
    this.displayLabel,
    this.sortText,
    this.detail,
    this.info,
    this.apply,
    this.type,
    this.commitCharacters,
    this.boost,
    this.section,
  });
}

typedef CompletionInfo = ({Widget? widget, void Function()? destroy});

class CompletionSection {
  final String name;
  final Widget Function(CompletionSection section)? header;
  final Object? rank;

  const CompletionSection({
    required this.name,
    this.header,
    this.rank,
  });
}

class CompletionContext {
  final EditorState state;
  final int pos;
  final bool explicit;
  final EditorViewState? view;

  List<void Function()>? _abortListeners = [];
  bool _abortOnDocChange = false;

  CompletionContext({
    required this.state,
    required this.pos,
    required this.explicit,
    this.view,
  });

  ({int from, int to, String text, NodeType type})? tokenBefore(List<String> types) {
    var token = syntaxTree(state).resolveInner(pos, -1);
    while (token.type.name.isNotEmpty && !types.contains(token.type.name)) {
      final parent = token.parent;
      if (parent == null) break;
      token = parent;
    }
    if (types.contains(token.type.name)) {
      return (
        from: token.from,
        to: pos,
        text: state.sliceDoc(token.from, pos),
        type: token.type,
      );
    }
    return null;
  }

  ({int from, int to, String text})? matchBefore(RegExp expr) {
    final line = state.doc.lineAt(pos);
    final start = line.from > pos - 250 ? line.from : pos - 250;
    final str = line.text.substring(start - line.from, pos - line.from);
    final anchored = ensureAnchor(expr, false);
    final match = anchored.firstMatch(str);
    if (match == null) return null;
    return (from: start + match.start, to: pos, text: str.substring(match.start));
  }

  bool get aborted => _abortListeners == null;

  bool get abortOnDocChange => _abortOnDocChange;

  void addEventListener(String type, void Function() listener, {bool onDocChange = false}) {
    if (type == 'abort' && _abortListeners != null) {
      _abortListeners!.add(listener);
      if (onDocChange) _abortOnDocChange = true;
    }
  }

  void abort() {
    final listeners = _abortListeners;
    if (listeners != null) {
      _abortListeners = null;
      for (final listener in listeners) {
        listener();
      }
    }
  }
}

typedef ValidForPredicate = bool Function(String text, int from, int to, EditorState state);

class CompletionResult {
  final int from;
  final int? to;
  final List<Completion> options;
  final Object? validFor;
  final bool? filter;
  final List<int> Function(Completion completion, List<int>? matched)? getMatch;
  final CompletionResult? Function(CompletionResult current, int from, int to, CompletionContext context)? update;
  final CompletionResult? Function(CompletionResult current, ChangeDesc changes)? map;
  final List<String>? commitCharacters;

  const CompletionResult({
    required this.from,
    this.to,
    required this.options,
    this.validFor,
    this.filter,
    this.getMatch,
    this.update,
    this.map,
    this.commitCharacters,
  });

  CompletionResult copyWith({
    int? from,
    int? to,
    List<Completion>? options,
    Object? validFor,
    bool? filter,
    List<int> Function(Completion completion, List<int>? matched)? getMatch,
    CompletionResult? Function(CompletionResult current, int from, int to, CompletionContext context)? update,
    CompletionResult? Function(CompletionResult current, ChangeDesc changes)? map,
    List<String>? commitCharacters,
  }) {
    return CompletionResult(
      from: from ?? this.from,
      to: to ?? this.to,
      options: options ?? this.options,
      validFor: validFor ?? this.validFor,
      filter: filter ?? this.filter,
      getMatch: getMatch ?? this.getMatch,
      update: update ?? this.update,
      map: map ?? this.map,
      commitCharacters: commitCharacters ?? this.commitCharacters,
    );
  }
}

typedef CompletionSource = FutureOr<CompletionResult?> Function(CompletionContext context);

class Option {
  final Completion completion;
  final CompletionSource source;
  final List<int> match;
  int score;

  Option({
    required this.completion,
    required this.source,
    required this.match,
    required this.score,
  });
}

int cur(EditorState state) => state.selection.main.from;

RegExp ensureAnchor(RegExp expr, bool start) {
  final source = expr.pattern;
  final addStart = start && !source.startsWith('^');
  final addEnd = !source.endsWith(r'$');
  if (!addStart && !addEnd) return expr;
  return RegExp(
    '${addStart ? '^' : ''}(?:$source)${addEnd ? r'$' : ''}',
    caseSensitive: expr.isCaseSensitive,
    multiLine: expr.isMultiLine,
    unicode: expr.isUnicode,
    dotAll: expr.isDotAll,
  );
}

final pickedCompletion = Annotation.define<Completion>();

TransactionSpec insertCompletionText(EditorState state, String text, int from, int to) {
  final main = state.selection.main;
  final fromOff = from - main.from;
  final toOff = to - main.from;

  final result = state.changeByRange((range) {
    if (!identical(range, main) &&
        from != to &&
        state.sliceDoc(range.from + fromOff, range.from + toOff) != state.sliceDoc(from, to)) {
      return ChangeByRangeResult(range: range);
    }
    final lines = state.toText(text);
    return ChangeByRangeResult(
      changes: ChangeSpec(
        from: range.from + fromOff,
        to: to == main.from ? range.to : range.from + toOff,
        insert: lines,
      ),
      range: EditorSelection.cursor(range.from + fromOff + lines.length),
    );
  });

  return TransactionSpec(
    changes: result.changes,
    selection: result.selection,
    effects: result.effects,
    scrollIntoView: true,
    userEvent: 'input.complete',
  );
}

String _toSet(Map<String, bool> chars) {
  var flat = chars.keys.join('');
  final words = RegExp(r'\w').hasMatch(flat);
  if (words) flat = flat.replaceAll(RegExp(r'\w'), '');
  final escaped = flat.replaceAllMapped(RegExp(r'[^\w\s]'), (m) => '\\${m.group(0)}');
  return '[${words ? r'\w' : ''}$escaped]';
}

(RegExp, RegExp) _prefixMatch(List<Completion> options) {
  final first = <String, bool>{};
  final rest = <String, bool>{};
  for (final opt in options) {
    final label = opt.label;
    if (label.isNotEmpty) first[label[0]] = true;
    for (var i = 1; i < label.length; i++) {
      rest[label[i]] = true;
    }
  }
  final source = '${_toSet(first)}${_toSet(rest)}*\$';
  return (RegExp('^$source'), RegExp(source));
}

CompletionSource completeFromList(List<Object> list) {
  final options = list.map((o) => o is String ? Completion(label: o) : o as Completion).toList();
  final allWord = options.every((o) => RegExp(r'^\w+$').hasMatch(o.label));
  final (RegExp validFor, RegExp match) = allWord ? (RegExp(r'\w*$'), RegExp(r'\w+$')) : _prefixMatch(options);
  return (CompletionContext context) {
    final token = context.matchBefore(match);
    if (token != null || context.explicit) {
      return CompletionResult(
        from: token?.from ?? context.pos,
        options: options,
        validFor: validFor,
      );
    }
    return null;
  };
}

CompletionSource ifIn(List<String> nodes, CompletionSource source) {
  return (CompletionContext context) {
    for (var pos = syntaxTree(context.state).resolveInner(context.pos, -1); ; ) {
      if (nodes.contains(pos.type.name)) return source(context);
      if (pos.type.isTop) break;
      final parent = pos.parent;
      if (parent == null) break;
      pos = parent;
    }
    return null;
  };
}

CompletionSource ifNotIn(List<String> nodes, CompletionSource source) {
  return (CompletionContext context) {
    for (var pos = syntaxTree(context.state).resolveInner(context.pos, -1); ; ) {
      if (nodes.contains(pos.type.name)) return null;
      if (pos.type.isTop) break;
      final parent = pos.parent;
      if (parent == null) break;
      pos = parent;
    }
    return source(context);
  };
}

final _sourceCache = Expando<CompletionSource>();

CompletionSource asSource(Object source) {
  if (source is CompletionSource) return source;
  if (source is List) {
    var known = _sourceCache[source];
    if (known == null) {
      known = completeFromList(source.cast<Object>());
      _sourceCache[source] = known;
    }
    return known;
  }
  throw ArgumentError('Invalid completion source: $source');
}

final startCompletionEffect = StateEffect.define<bool>();
final closeCompletionEffect = StateEffect.define<void>();
