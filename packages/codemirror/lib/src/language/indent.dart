/// Indentation system for CodeMirror.
///
/// This module provides infrastructure for computing and applying indentation,
/// including syntax-tree aware indentation strategies.
library;

import 'package:lezer/lezer.dart';
import 'package:meta/meta.dart';

import '../commands/commands.dart' show getIndentUnit, indentString;
import '../text/column.dart' show countColumn;
import '../state/change.dart';
import '../state/facet.dart' hide EditorState, Transaction;
import '../state/state.dart';
import '../state/transaction.dart' hide Transaction;
import 'language.dart';

// Re-export indent utilities for convenience
export '../commands/commands.dart' show getIndentUnit, indentString;
export '../text/column.dart' show countColumn;

// ============================================================================
// Indent Service Facet
// ============================================================================

/// Facet that defines a way to provide a function that computes the
/// appropriate indentation depth, as a column number (see [indentString]),
/// at the start of a given line.
///
/// A return value of `null` indicates no indentation can be determined,
/// and the line should inherit the indentation of the one above it.
final Facet<int? Function(IndentContext context, int pos), List<int? Function(IndentContext context, int pos)>>
    indentService = Facet.define(
  FacetConfig(
    combine: (values) => values.toList(),
  ),
);

// ============================================================================
// IndentContext
// ============================================================================

/// Indentation contexts are used when calling [indentService] functions.
///
/// They provide helper utilities useful in indentation logic, and can
/// selectively override the indentation reported for some lines.
class IndentContext {
  /// The editor state.
  final EditorState state;

  /// The indent unit (number of columns per indentation level).
  final int unit;

  /// Options for the indent context.
  @internal
  final IndentContextOptions options;

  /// Create an indent context.
  IndentContext(
    this.state, {
    IndentContextOptions? options,
  })  : options = options ?? const IndentContextOptions(),
        unit = getIndentUnit(state);

  /// Get a description of the line at the given position, taking
  /// [simulateBreak] into account.
  ///
  /// If there is such a break at [pos], the [bias] argument determines
  /// whether the part of the line before or after the break is used.
  ({String text, int from}) lineAt(int pos, [int bias = 1]) {
    final line = state.doc.lineAt(pos);
    final simulateBreak = options.simulateBreak;
    final simulateDoubleBreak = options.simulateDoubleBreak;

    if (simulateBreak != null && simulateBreak >= line.from && simulateBreak <= line.to) {
      if (simulateDoubleBreak && simulateBreak == pos) {
        return (text: '', from: pos);
      } else if (bias < 0 ? simulateBreak < pos : simulateBreak <= pos) {
        return (text: line.text.substring(simulateBreak - line.from), from: simulateBreak);
      } else {
        return (text: line.text.substring(0, simulateBreak - line.from), from: line.from);
      }
    }
    return (text: line.text, from: line.from);
  }

  /// Get the text directly after [pos], either the entire line
  /// or the next 100 characters, whichever is shorter.
  String textAfterPos(int pos, [int bias = 1]) {
    if (options.simulateDoubleBreak && pos == options.simulateBreak) return '';
    final (:text, :from) = lineAt(pos, bias);
    return text.substring(pos - from, (text.length < pos + 100 - from) ? text.length : pos + 100 - from);
  }

  /// Find the column for the given position.
  int column(int pos, [int bias = 1]) {
    final (:text, :from) = lineAt(pos, bias);
    var result = countColumnStr(text, pos - from);
    final override = options.overrideIndentation;
    if (override != null) {
      final overridden = override(from);
      if (overridden > -1) {
        result += overridden - countColumnStr(text, _findNonWhitespace(text));
      }
    }
    return result;
  }

  /// Find the column position (taking tabs into account) of the given
  /// position in the given string.
  int countColumnStr(String line, [int? pos]) {
    return countColumn(line, state.tabSize, pos);
  }

  /// Find the indentation column of the line at the given point.
  int lineIndent(int pos, [int bias = 1]) {
    final (:text, :from) = lineAt(pos, bias);
    final override = options.overrideIndentation;
    if (override != null) {
      final overridden = override(from);
      if (overridden > -1) return overridden;
    }
    return countColumnStr(text, _findNonWhitespace(text));
  }

  /// Returns the [simulateBreak] for this context, if any.
  int? get simulatedBreak => options.simulateBreak;
}

/// Find the first non-whitespace character position.
int _findNonWhitespace(String text) {
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c != 32 && c != 9) return i; // not space or tab
  }
  return text.length;
}

/// Options for creating an [IndentContext].
class IndentContextOptions {
  /// Override line indentations provided to the indentation helper function.
  ///
  /// This is useful when implementing region indentation, where indentation
  /// for later lines needs to refer to previous lines, which may have been
  /// reindented compared to the original start state.
  ///
  /// If given, this function should return -1 for lines (given by start position)
  /// that didn't change, and an updated indentation otherwise.
  final int Function(int pos)? overrideIndentation;

  /// Make it look, to the indent logic, like a line break was added at
  /// the given position.
  ///
  /// This is mostly useful for implementing something like
  /// `insertNewlineAndIndent`.
  final int? simulateBreak;

  /// When [simulateBreak] is given, this can be used to make the
  /// simulated break behave like a double line break.
  final bool simulateDoubleBreak;

  const IndentContextOptions({
    this.overrideIndentation,
    this.simulateBreak,
    this.simulateDoubleBreak = false,
  });
}

// ============================================================================
// indentNodeProp
// ============================================================================

/// A syntax tree node prop used to associate indentation strategies
/// with node types.
///
/// Such a strategy is a function from an indentation context to a column
/// number (see [indentString]) or null, where null indicates that no
/// definitive indentation can be determined.
final NodeProp<int? Function(TreeIndentContext)> indentNodeProp = NodeProp<int? Function(TreeIndentContext)>(
  deserialize: (_) => throw UnsupportedError('Cannot deserialize indentNodeProp'),
);

// ============================================================================
// getIndentation
// ============================================================================

/// Get the indentation, as a column number, at the given position.
///
/// Will first consult any [indentService] functions that are registered,
/// and if none of those return an indentation, this will check the syntax
/// tree for the [indentNodeProp] and use that if found.
///
/// Returns a number when an indentation could be determined, and null otherwise.
int? getIndentation(Object /* IndentContext | EditorState */ context, int pos) {
  final IndentContext cx;
  if (context is EditorState) {
    cx = IndentContext(context);
  } else {
    cx = context as IndentContext;
  }

  for (final service in cx.state.facet(indentService)) {
    final result = service(cx, pos);
    if (result != null) return result;
  }

  final tree = syntaxTree(cx.state);
  return tree.length >= pos ? _syntaxIndentation(cx, tree, pos) : null;
}

// ============================================================================
// indentRange
// ============================================================================

/// Create a change set that auto-indents all lines touched by the
/// given document range.
ChangeSet indentRange(EditorState state, int from, int to) {
  final updated = <int, int>{};
  final context = IndentContext(
    state,
    options: IndentContextOptions(
      overrideIndentation: (start) => updated[start] ?? -1,
    ),
  );
  final changes = <ChangeSpec>[];

  for (var pos = from; pos <= to;) {
    final line = state.doc.lineAt(pos);
    pos = line.to + 1;
    final indent = getIndentation(context, line.from);
    if (indent == null) continue;

    final effectiveIndent = _hasNonWhitespace(line.text) ? indent : 0;
    final curMatch = RegExp(r'^\s*').firstMatch(line.text);
    final cur = curMatch?.group(0) ?? '';
    final norm = indentString(state, effectiveIndent);

    if (cur != norm) {
      updated[line.from] = effectiveIndent;
      changes.add(ChangeSpec(from: line.from, to: line.from + cur.length, insert: norm));
    }
  }

  return state.changes(changes);
}

bool _hasNonWhitespace(String text) {
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c != 32 && c != 9 && c != 10 && c != 13) return true;
  }
  return false;
}

// ============================================================================
// TreeIndentContext
// ============================================================================

/// Objects of this type provide context information and helper
/// methods to indentation functions registered on syntax nodes.
class TreeIndentContext extends IndentContext {
  final IndentContext _base;

  /// The position at which indentation is being computed.
  final int pos;

  @internal
  final IndentNodeIterator context;

  TreeIndentContext._(
    this._base,
    this.pos,
    this.context,
  ) : super(_base.state, options: _base.options);

  /// The syntax tree node to which the indentation strategy applies.
  SyntaxNode get node => context.node;

  @internal
  static TreeIndentContext create(IndentContext base, int pos, IndentNodeIterator context) {
    return TreeIndentContext._(base, pos, context);
  }

  /// Get the text directly after [this.pos], either the entire line
  /// or the next 100 characters, whichever is shorter.
  String get textAfter => textAfterPos(pos);

  /// Get the indentation at the reference line for [this.node], which
  /// is the line on which it starts, unless there is a node that is
  /// _not_ a parent of this node covering the start of that line.
  ///
  /// If so, the line at the start of that node is tried, again skipping
  /// on if it is covered by another such node.
  int get baseIndent => baseIndentFor(node);

  /// Get the indentation for the reference line of the given node
  /// (see [baseIndent]).
  int baseIndentFor(SyntaxNode node) {
    var line = state.doc.lineAt(node.from);
    // Skip line starts that are covered by a sibling (or cousin, etc)
    // Safety limit to prevent infinite loops
    var iterations = 0;
    const maxIterations = 1000;
    for (; iterations < maxIterations;) {
      iterations++;
      var atBreak = node.resolve(line.from);
      var parentIterations = 0;
      while (atBreak.parent != null && atBreak.parent!.from == atBreak.from && parentIterations++ < 100) {
        atBreak = atBreak.parent!;
      }
      if (_isParent(atBreak, node)) break;
      final newLine = state.doc.lineAt(atBreak.from);
      if (newLine.from == line.from) break; // Prevent infinite loop on same line
      line = newLine;
    }
    return lineIndent(line.from);
  }

  /// Continue looking for indentations in the node's parent nodes,
  /// and return the result of that.
  int? continueIndent() {
    return _indentFor(context.next, _base, pos);
  }
}

bool _isParent(SyntaxNode parent, SyntaxNode of) {
  for (SyntaxNode? cur = of; cur != null; cur = cur.parent) {
    // Compare by position since resolve() may return different object instances
    if (parent.from == cur.from && parent.to == cur.to && parent.type == cur.type) return true;
  }
  return false;
}

// ============================================================================
// Syntax Indentation
// ============================================================================

/// Compute the indentation for a given position from the syntax tree.
int? _syntaxIndentation(IndentContext cx, Tree ast, int pos) {
  var stack = _buildStack(ast, pos);
  final inner = ast.resolveInner(pos, -1).resolve(pos, 0).enterUnfinishedNodesBefore(pos);

  if (inner != stack.node) {
    final add = <SyntaxNode>[];
    for (SyntaxNode? cur = inner;
        cur != null &&
            !(cur.from < stack.node.from ||
                cur.to > stack.node.to ||
                (cur.from == stack.node.from && cur.type == stack.node.type));
        cur = cur.parent) {
      add.add(cur);
    }
    for (var i = add.length - 1; i >= 0; i--) {
      stack = IndentNodeIterator(add[i], stack);
    }
  }

  return _indentFor(stack, cx, pos);
}

/// Build a stack iterator matching JS resolveStack behavior.
/// 
/// The stack should go from innermost node to outermost (root),
/// so that _indentFor finds the first strategy starting from the
/// most specific node containing the position.
IndentNodeIterator _buildStack(Tree ast, int pos) {
  // Start from the innermost node at pos
  final inner = ast.resolveInner(pos);
  
  // Build chain from innermost → outermost (via .next)
  IndentNodeIterator? stack;
  for (SyntaxNode? cur = inner; cur != null; cur = cur.parent) {
    stack = IndentNodeIterator(cur, stack);
  }
  
  // Reverse so we go innermost → outermost when iterating via .next
  IndentNodeIterator? reversed;
  for (var cur = stack; cur != null; cur = cur.next) {
    reversed = IndentNodeIterator(cur.node, reversed);
  }
  
  return reversed ?? IndentNodeIterator(ast.topNode, null);
}

int? _indentFor(IndentNodeIterator? stack, IndentContext cx, int pos) {
  for (var cur = stack; cur != null; cur = cur.next) {
    final strategy = _indentStrategy(cur.node);
    if (strategy != null) {
      final context = TreeIndentContext.create(cx, pos, cur);
      final result = strategy(context);
      // Debug output for deeply nested case (uncomment to debug)
      // print('_indentFor: node=${cur.node.name}(${cur.node.from}-${cur.node.to}) pos=$pos baseIndent=${context.baseIndent} result=$result');
      return result;
    }
  }
  return 0;
}

bool _ignoreClosed(TreeIndentContext cx) {
  return cx.pos == cx.options.simulateBreak && cx.options.simulateDoubleBreak;
}

int? Function(TreeIndentContext)? _indentStrategy(SyntaxNode tree) {
  final strategy = tree.type.prop(indentNodeProp);
  if (strategy != null) return strategy;

  final first = tree.firstChild;
  List<String>? close;
  if (first != null && (close = first.type.prop(NodeProp.closedBy)) != null) {
    final last = tree.lastChild;
    final closed = last != null && close!.contains(last.name);
    final lastFrom = last?.from;
    return (cx) => _delimitedStrategy(
          cx,
          true,
          1,
          null,
          closed && !_ignoreClosed(cx) ? lastFrom : null,
        );
  }

  return tree.parent == null ? _topIndent : null;
}

int _topIndent(TreeIndentContext cx) => 0;

// ============================================================================
// Delimited Indentation Strategy
// ============================================================================

/// Check whether a delimited node is aligned (meaning there are
/// non-skipped nodes on the same line as the opening delimiter).
/// If so, return the opening token.
({int from, int to})? _bracketedAligned(TreeIndentContext context) {
  final tree = context.node;
  final openToken = tree.childAfter(tree.from);
  final last = tree.lastChild;
  if (openToken == null) return null;

  final sim = context.options.simulateBreak;
  final openLine = context.state.doc.lineAt(openToken.from);
  final lineEnd = sim == null || sim <= openLine.from ? openLine.to : (openLine.to < sim ? openLine.to : sim);

  for (var pos = openToken.to;;) {
    final next = tree.childAfter(pos);
    // Compare by position since childAfter may return different object instances
    final isLast = next != null && last != null && next.from == last.from && next.to == last.to;
    if (next == null || isLast) return null;
    if (!next.type.isSkipped) {
      if (next.from >= lineEnd) return null;
      final spaceMatch = RegExp(r'^ *').firstMatch(openLine.text.substring(openToken.to - openLine.from));
      final space = spaceMatch?.group(0)?.length ?? 0;
      return (from: openToken.from, to: openToken.to + space);
    }
    pos = next.to;
  }
}

/// An indentation strategy for delimited (usually bracketed) nodes.
///
/// Will, by default, indent one unit more than the parent's base
/// indent unless the line starts with a closing token. When [align]
/// is true and there are non-skipped nodes on the node's opening
/// line, the content of the node will be aligned with the end of the
/// opening node, like this:
///
/// ```
/// foo(bar,
///     baz)
/// ```
int? Function(TreeIndentContext) delimitedIndent({
  required String closing,
  bool align = true,
  int units = 1,
}) {
  return (context) => _delimitedStrategy(context, align, units, closing, null);
}

int? _delimitedStrategy(
  TreeIndentContext context,
  bool align,
  int units,
  String? closing,
  int? closedAt,
) {
  final after = context.textAfter;
  final spaceMatch = RegExp(r'^\s*').firstMatch(after);
  final space = spaceMatch?.group(0)?.length ?? 0;
  
  // Check if we're after the closing bracket (at or past node.to)
  // In this case, continue to parent for indentation
  if (context.pos >= context.node.to) {
    // But only if there's nothing after us on this line, or only whitespace/newline
    // This handles `const x = {}|` -> indent 0
    // But not `[{},|]` -> indent should come from the array
    final afterTrimmed = after.trim();
    if (afterTrimmed.isEmpty || afterTrimmed.startsWith('\n')) {
      return context.continueIndent();
    }
  }
  
  final closed = (closing != null && after.substring(space).startsWith(closing)) ||
      closedAt == context.pos + space;
  final aligned = align ? _bracketedAligned(context) : null;

  if (aligned != null) {
    return closed ? context.column(aligned.from) : context.column(aligned.to);
  }
  return context.baseIndent + (closed ? 0 : context.unit * units);
}

// ============================================================================
// Helper Indentation Strategies
// ============================================================================

/// An indentation strategy that aligns a node's content to its base
/// indentation.
int? flatIndent(TreeIndentContext context) => context.baseIndent;

/// Creates an indentation strategy that, by default, indents
/// continued lines one unit more than the node's base indentation.
///
/// You can provide [except] to prevent indentation of lines that
/// match a pattern (for example `/^else\b/` in `if`/`else`
/// constructs), and you can change the amount of units used with the
/// [units] option.
int? Function(TreeIndentContext) continuedIndent({
  RegExp? except,
  int units = 1,
}) {
  return (context) {
    final matchExcept = except != null && except.hasMatch(context.textAfter);
    return context.baseIndent + (matchExcept ? 0 : units * context.unit);
  };
}

// ============================================================================
// indentOnInput
// ============================================================================

const int _dontIndentBeyond = 200;

/// Enables reindentation on input.
///
/// When a language defines an `indentOnInput` field in its language data,
/// which must hold a [RegExp], the line at the cursor will be reindented
/// whenever new text is typed and the input from the start of the line
/// up to the cursor matches that regexp.
///
/// To avoid unnecessary reindents, it is recommended to start the
/// regexp with `^` (usually followed by `\s*`), and end it with `$`.
/// For example, `/^\s*\}$/` will reindent when a closing brace is
/// added at the start of a line.
Extension indentOnInput() {
  return transactionFilter.of((tr) {
    if (!tr.docChanged ||
        (!tr.isUserEvent('input.type') && !tr.isUserEvent('input.complete'))) {
      return tr;
    }

    final startState = tr.startState as EditorState;
    final rules = startState.languageDataAt<RegExp>('indentOnInput', startState.selection.main.head);
    if (rules.isEmpty) return tr;

    final doc = tr.newDoc;
    final head = tr.newSelection.main.head;
    final line = doc.lineAt(head);
    if (head > line.from + _dontIndentBeyond) return tr;

    final lineStart = doc.sliceString(line.from, head);
    if (!rules.any((r) => r.hasMatch(lineStart))) return tr;

    final state = tr.state as EditorState;
    var last = -1;
    final changes = <ChangeSpec>[];

    for (final range in state.selection.ranges) {
      final rangeLine = state.doc.lineAt(range.head);
      if (rangeLine.from == last) continue;
      last = rangeLine.from;

      final indent = getIndentation(state, rangeLine.from);
      if (indent == null) continue;

      final curMatch = RegExp(r'^\s*').firstMatch(rangeLine.text);
      final cur = curMatch?.group(0) ?? '';
      final norm = indentString(state, indent);

      if (cur != norm) {
        changes.add(ChangeSpec(from: rangeLine.from, to: rangeLine.from + cur.length, insert: norm));
      }
    }

    if (changes.isEmpty) return tr;
    return [
      tr,
      TransactionSpec(changes: changes, sequential: true),
    ];
  });
}

// ============================================================================
// Internal Node Iterator
// ============================================================================

/// Internal node iterator for syntax indentation.
@internal
class IndentNodeIterator {
  final SyntaxNode node;
  IndentNodeIterator? next;

  IndentNodeIterator(this.node, this.next);
}
