/// Parse stack for the LR parser.
///
/// This module provides [Stack] which tracks parsing progress
/// during LR parsing.
library;

import 'package:meta/meta.dart';

import '../common/node_set.dart' as common;
import '../common/tree.dart';
import 'constants.dart';
import 'token.dart' show InputStream;

/// A parse stack.
///
/// These are used internally by the parser to track parsing progress.
/// They also provide some properties and methods that external code
/// such as a tokenizer can use to get information about the parse state.
class Stack {
  /// The parse that this stack is part of.
  @internal
  final Parse p;

  /// Holds state, input pos, buffer index triplets for all but the top state.
  @internal
  final List<int> stack;

  /// The current parse state.
  @internal
  int state;

  /// The position at which the next reduce should take place.
  @internal
  int reducePos;

  /// The input position up to which this stack has parsed.
  int pos;

  /// The dynamic score of the stack.
  @internal
  int score;

  /// The output buffer. Holds (type, start, end, size) quads.
  @internal
  final List<int> buffer;

  /// The base offset of the buffer.
  @internal
  int bufferBase;

  /// Current context.
  @internal
  StackContext? curContext;

  /// How far ahead we've looked.
  @internal
  int lookAhead;

  /// A parent stack from which this was split off.
  @internal
  final Stack? parent;

  /// @internal
  Stack(
    this.p,
    this.stack,
    this.state,
    this.reducePos,
    this.pos,
    this.score,
    this.buffer,
    this.bufferBase,
    this.curContext,
    this.lookAhead,
    this.parent,
  );

  @override
  String toString() {
    final states = <int>[];
    for (var i = 0; i < stack.length; i += 3) {
      states.add(stack[i]);
    }
    states.add(state);
    final scoreStr = score != 0 ? '!$score' : '';
    return '[$states]@$pos$scoreStr';
  }

  /// Start an empty stack.
  @internal
  static Stack start(Parse p, int startState, [int startPos = 0]) {
    final cx = p.parser.context;
    return Stack(
      p,
      [],
      startState,
      startPos,
      startPos,
      0,
      [],
      0,
      cx != null ? StackContext(cx, cx.start) : null,
      0,
      null,
    );
  }

  /// The stack's current context value, if any.
  Object? get context => curContext?.context;

  /// Push a state onto the stack.
  @internal
  void pushState(int newState, int start) {
    stack.add(state);
    stack.add(start);
    stack.add(bufferBase + buffer.length);
    state = newState;
  }

  /// Apply a reduce action.
  @internal
  void reduce(int action) {
    final depth = action >> Action.reduceDepthShift;
    final type = action & Action.valueMask;
    final parser = p.parser;

    final lookaheadRecord =
        reducePos < pos - Lookahead.margin && setLookAhead(pos);

    final dPrec = parser.dynamicPrecedence(type);
    if (dPrec != 0) score += dPrec;

    if (depth == 0) {
      pushState(parser.getGoto(state, type, true), reducePos);
      if (type < parser.minRepeatTerm) {
        storeNode(type, reducePos, reducePos, lookaheadRecord ? 8 : 4, true);
      }
      _reduceContext(type, reducePos);
      return;
    }

    // Find the base index
    final base = stack.length -
        ((depth - 1) * 3) -
        ((action & Action.stayFlag) != 0 ? 6 : 0);
    final start = base > 0 ? stack[base - 2] : p.ranges[0].from;
    final size = reducePos - start;

    // Track big reductions
    // Note: type can be larger than nodeSet.types.length for internal grammar
    // tokens. Use bounds check (equivalent to TypeScript's optional chaining).
    final nodeType = type < parser.nodeSet.types.length
        ? parser.nodeSet.types[type]
        : null;
    if (size >= Recover.minBigReduction && nodeType?.isAnonymous == false) {
      if (start == p.lastBigReductionStart) {
        p.bigReductionCount++;
        p.lastBigReductionSize = size;
      } else if (p.lastBigReductionSize < size) {
        p.bigReductionCount = 1;
        p.lastBigReductionStart = start;
        p.lastBigReductionSize = size;
      }
    }

    final bufBase = base > 0 ? stack[base - 1] : 0;
    final count = bufferBase + buffer.length - bufBase;

    // Store normal terms or repeat reductions
    if (type < parser.minRepeatTerm || (action & Action.repeatFlag) != 0) {
      final storePos =
          parser.stateFlag(state, StateFlag.skipped) ? pos : reducePos;
      storeNode(type, start, storePos, count + 4, true);
    }

    if ((action & Action.stayFlag) != 0) {
      state = stack[base];
    } else {
      final baseStateID = stack[base - 3];
      state = parser.getGoto(baseStateID, type, true);
    }

    while (stack.length > base) {
      stack.removeLast();
    }
    _reduceContext(type, start);
  }

  /// Store a node in the buffer.
  @internal
  void storeNode(int term, int start, int end,
      [int size = 4, bool mustSink = false]) {
    if (term == Term.err &&
        (stack.isEmpty || stack[stack.length - 1] < buffer.length + bufferBase)) {
      // Try to omit/merge adjacent error nodes
      Stack? cur = this;
      var top = buffer.length;
      if (top == 0 && parent != null) {
        top = bufferBase - parent!.bufferBase;
        cur = parent;
      }
      if (top > 0 &&
          cur!.buffer[top - 4] == Term.err &&
          cur.buffer[top - 1] > -1) {
        if (start == end) return;
        if (cur.buffer[top - 2] >= start) {
          cur.buffer[top - 2] = end;
          return;
        }
      }
    }

    if (!mustSink || pos == end) {
      buffer.add(term);
      buffer.add(start);
      buffer.add(end);
      buffer.add(size);
    } else {
      // There may be skipped nodes that have to be moved forward
      var index = buffer.length;
      if (index > 0 &&
          (buffer[index - 4] != Term.err || buffer[index - 1] < 0)) {
        var mustMove = false;
        for (var scan = index;
            scan > 0 && buffer[scan - 2] > end;
            scan -= 4) {
          if (buffer[scan - 1] >= 0) {
            mustMove = true;
            break;
          }
        }
        if (mustMove) {
          while (index > 0 && buffer[index - 2] > end) {
            buffer.add(buffer[index - 4]);
            buffer.add(buffer[index - 3]);
            buffer.add(buffer[index - 2]);
            buffer.add(buffer[index - 1]);
            index -= 4;
            if (size > 4) size -= 4;
          }
        }
      }
      if (index < buffer.length) {
        buffer[index] = term;
        buffer[index + 1] = start;
        buffer[index + 2] = end;
        buffer[index + 3] = size;
      } else {
        buffer.add(term);
        buffer.add(start);
        buffer.add(end);
        buffer.add(size);
      }
    }
  }

  /// Apply a shift action.
  @internal
  void shift(int action, int type, int start, int end) {
    if ((action & Action.gotoFlag) != 0) {
      pushState(action & Action.valueMask, pos);
    } else if ((action & Action.stayFlag) == 0) {
      // Regular shift
      final nextState = action;
      final parser = p.parser;
      if (end > pos || type <= parser.maxNode) {
        pos = end;
        if (!parser.stateFlag(nextState, StateFlag.skipped)) {
          reducePos = end;
        }
      }
      pushState(nextState, start);
      _shiftContext(type, start);
      if (type <= parser.maxNode) {
        buffer.add(type);
        buffer.add(start);
        buffer.add(end);
        buffer.add(4);
      }
    } else {
      // Shift-and-stay (skipped token)
      pos = end;
      _shiftContext(type, start);
      if (type <= p.parser.maxNode) {
        buffer.add(type);
        buffer.add(start);
        buffer.add(end);
        buffer.add(4);
      }
    }
  }

  /// Apply an action.
  @internal
  void apply(int action, int next, int nextStart, int nextEnd) {
    if ((action & Action.reduceFlag) != 0) {
      reduce(action);
    } else {
      shift(action, next, nextStart, nextEnd);
    }
  }

  /// Add a prebuilt (reused) node into the buffer.
  @internal
  void useNode(Tree value, int next) {
    var index = p.reused.length - 1;
    if (index < 0 || p.reused[index] != value) {
      p.reused.add(value);
      index = p.reused.length - 1;
    }
    final start = pos;
    reducePos = pos = start + value.length;
    pushState(next, start);
    buffer.add(index);
    buffer.add(start);
    buffer.add(reducePos);
    buffer.add(-1); // size == -1 means this is a reused value
    if (curContext != null) {
      _updateContext(curContext!.tracker.reuse(
        curContext!.context,
        value,
        this,
        p.stream.reset(pos - value.length),
      ));
    }
  }

  /// Split the stack.
  @internal
  Stack split() {
    Stack? parentStack = this;
    var off = buffer.length;

    // Copy outstanding skipped tokens
    while (off > 0 && parentStack.buffer[off - 2] > reducePos) {
      off -= 4;
    }
    final newBuffer = buffer.sublist(off);
    final base = bufferBase + off;

    // Make sure parent points to an actual parent with content
    while (parentStack != null && base == parentStack.bufferBase) {
      parentStack = parentStack.parent;
    }

    return Stack(
      p,
      List<int>.from(stack),
      state,
      reducePos,
      pos,
      score,
      newBuffer,
      base,
      curContext,
      lookAhead,
      parentStack,
    );
  }

  /// Try to recover from an error by 'deleting' (ignoring) one token.
  @internal
  void recoverByDelete(int next, int nextEnd) {
    final isNode = next <= p.parser.maxNode;
    if (isNode) storeNode(next, pos, nextEnd, 4);
    storeNode(Term.err, pos, nextEnd, isNode ? 8 : 4);
    pos = reducePos = nextEnd;
    score -= Recover.delete;
  }

  /// Check if the given term would be able to be shifted.
  bool canShift(int term) {
    final sim = _SimulatedStack(this);
    while (true) {
      final action = p.parser.stateSlot(sim.state, ParseState.defaultReduce);
      final hasAction =
          action != 0 ? action : p.parser.hasAction(sim.state, term);
      if (hasAction == 0) return false;
      if ((hasAction & Action.reduceFlag) == 0) return true;
      sim.reduce(hasAction);
    }
  }

  /// Apply recovery by inserting missing tokens.
  @internal
  List<Stack> recoverByInsert(int next) {
    if (stack.length >= Recover.maxInsertStackDepth) return [];

    var nextStates = p.parser.nextStates(state);
    if (nextStates.length > Recover.maxNext << 1 ||
        stack.length >= Recover.dampenInsertStackDepth) {
      final best = <int>[];
      for (var i = 0; i < nextStates.length; i += 2) {
        final s = nextStates[i + 1];
        if (s != state && p.parser.hasAction(s, next) != 0) {
          best.add(nextStates[i]);
          best.add(s);
        }
      }
      if (stack.length < Recover.dampenInsertStackDepth) {
        for (var i = 0;
            best.length < Recover.maxNext << 1 && i < nextStates.length;
            i += 2) {
          final s = nextStates[i + 1];
          if (!best.any((v) => v == s)) {
            best.add(nextStates[i]);
            best.add(s);
          }
        }
      }
      nextStates = best;
    }

    final result = <Stack>[];
    for (var i = 0; i < nextStates.length && result.length < Recover.maxNext; i += 2) {
      final s = nextStates[i + 1];
      if (s == state) continue;
      final newStack = split();
      newStack.pushState(s, pos);
      newStack.storeNode(Term.err, newStack.pos, newStack.pos, 4, true);
      newStack._shiftContext(nextStates[i], pos);
      newStack.reducePos = pos;
      newStack.score -= Recover.insert;
      result.add(newStack);
    }
    return result;
  }

  /// Force a reduce, if possible.
  @internal
  bool forceReduce() {
    final parser = p.parser;
    var reduceAction = parser.stateSlot(state, ParseState.forcedReduce);
    if ((reduceAction & Action.reduceFlag) == 0) return false;

    if (!parser.validAction(state, reduceAction)) {
      final depth = reduceAction >> Action.reduceDepthShift;
      final term = reduceAction & Action.valueMask;
      final target = stack.length - depth * 3;
      if (target < 0 || parser.getGoto(stack[target], term, false) < 0) {
        final backup = findForcedReduction();
        if (backup == null) return false;
        reduceAction = backup;
      }
      storeNode(Term.err, pos, pos, 4, true);
      score -= Recover.reduce;
    }
    reducePos = pos;
    reduce(reduceAction);
    return true;
  }

  /// Try to find a valid forced reduction.
  @internal
  int? findForcedReduction() {
    final parser = p.parser;
    final seen = <int>[];

    int? explore(int exploreState, int depth) {
      if (seen.contains(exploreState)) return null;
      seen.add(exploreState);
      return parser.allActions(exploreState, (action) {
        if ((action & (Action.stayFlag | Action.gotoFlag)) != 0) {
          return null;
        } else if ((action & Action.reduceFlag) != 0) {
          final rDepth = (action >> Action.reduceDepthShift) - depth;
          if (rDepth > 1) {
            final term = action & Action.valueMask;
            final target = stack.length - rDepth * 3;
            if (target >= 0 && parser.getGoto(stack[target], term, false) >= 0) {
              return (rDepth << Action.reduceDepthShift) |
                  Action.reduceFlag |
                  term;
            }
          }
        } else {
          final found = explore(action, depth + 1);
          if (found != null) return found;
        }
        return null;
      });
    }

    return explore(state, 0);
  }

  /// Force all remaining reductions.
  @internal
  Stack forceAll() {
    while (!p.parser.stateFlag(state, StateFlag.accepting)) {
      if (!forceReduce()) {
        storeNode(Term.err, pos, pos, 4, true);
        break;
      }
    }
    return this;
  }

  /// Check whether this state has no further actions.
  @internal
  bool get deadEnd {
    if (stack.length != 3) return false;
    final parser = p.parser;
    return parser.data[parser.stateSlot(state, ParseState.actions)] == Seq.end &&
        parser.stateSlot(state, ParseState.defaultReduce) == 0;
  }

  /// Restart the stack.
  @internal
  void restart() {
    storeNode(Term.err, pos, pos, 4, true);
    state = stack[0];
    stack.clear();
  }

  /// Check if this stack has the same state as another.
  @internal
  bool sameState(Stack other) {
    if (state != other.state || stack.length != other.stack.length) {
      return false;
    }
    for (var i = 0; i < stack.length; i += 3) {
      if (stack[i] != other.stack[i]) return false;
    }
    return true;
  }

  /// Get the parser used by this stack.
  LRParser get parser => p.parser;

  /// Test whether a given dialect is enabled.
  bool dialectEnabled(int dialectID) => p.parser.dialect.flags[dialectID];

  void _shiftContext(int term, int start) {
    if (curContext != null) {
      _updateContext(curContext!.tracker.shift(
        curContext!.context,
        term,
        this,
        p.stream.reset(start),
      ));
    }
  }

  void _reduceContext(int term, int start) {
    if (curContext != null) {
      _updateContext(curContext!.tracker.reduce(
        curContext!.context,
        term,
        this,
        p.stream.reset(start),
      ));
    }
  }

  /// @internal
  void emitContext() {
    final last = buffer.length - 1;
    if (last < 0 || buffer[last] != -3) {
      buffer.add(curContext!.hash);
      buffer.add(pos);
      buffer.add(pos);
      buffer.add(-3);
    }
  }

  /// @internal
  void emitLookAhead() {
    final last = buffer.length - 1;
    if (last < 0 || buffer[last] != -4) {
      buffer.add(lookAhead);
      buffer.add(pos);
      buffer.add(pos);
      buffer.add(-4);
    }
  }

  void _updateContext(Object? newContext) {
    if (newContext != curContext!.context) {
      final newCx = StackContext(curContext!.tracker, newContext);
      if (newCx.hash != curContext!.hash) emitContext();
      curContext = newCx;
    }
  }

  /// @internal
  bool setLookAhead(int newLookAhead) {
    if (newLookAhead <= lookAhead) return false;
    emitLookAhead();
    lookAhead = newLookAhead;
    return true;
  }

  /// @internal
  void close() {
    if (curContext != null && curContext!.tracker.strict) emitContext();
    if (lookAhead > 0) emitLookAhead();
  }
}

/// Context tracking for the stack.
class StackContext {
  /// The context tracker.
  final ContextTracker<Object?> tracker;

  /// The current context value.
  final Object? context;

  /// Hash of the context.
  final int hash;

  StackContext(this.tracker, this.context)
      : hash = tracker.strict ? tracker.hash(context) : 0;
}

/// Simulated stack for lookahead.
class _SimulatedStack {
  int state;
  List<int> stack;
  int base;
  final Stack start;

  _SimulatedStack(this.start)
      : state = start.state,
        stack = start.stack,
        base = start.stack.length;

  void reduce(int action) {
    final term = action & Action.valueMask;
    final depth = action >> Action.reduceDepthShift;
    if (depth == 0) {
      if (identical(stack, start.stack)) stack = List<int>.from(stack);
      stack.add(state);
      stack.add(0);
      stack.add(0);
      base += 3;
    } else {
      base -= (depth - 1) * 3;
    }
    final gotoState = start.p.parser.getGoto(stack[base - 3], term, true);
    state = gotoState;
  }
}

/// Buffer cursor for reading the stack buffer.
@internal
class StackBufferCursor implements BufferCursor {
  /// The current stack.
  Stack stack;

  /// Position in the buffer.
  int pos;

  /// Index in the current buffer.
  int index;

  /// The current buffer.
  List<int> buffer;

  StackBufferCursor(this.stack, this.pos, this.index) : buffer = stack.buffer {
    if (index == 0) _maybeNext();
  }

  /// Create a cursor at the end of a stack's buffer.
  static StackBufferCursor create(Stack stack, [int? startPos]) {
    final pos = startPos ?? (stack.bufferBase + stack.buffer.length);
    return StackBufferCursor(stack, pos, pos - stack.bufferBase);
  }

  void _maybeNext() {
    final next = stack.parent;
    if (next != null) {
      index = stack.bufferBase - next.bufferBase;
      stack = next;
      buffer = next.buffer;
    }
  }

  /// Get the current node's type ID.
  @override
  int get id => buffer[index - 4];

  /// Get the current node's start position.
  @override
  int get start => buffer[index - 3];

  /// Get the current node's end position.
  @override
  int get end => buffer[index - 2];

  /// Get the current node's size.
  @override
  int get size => buffer[index - 1];

  /// Move to the next node.
  @override
  void next() {
    index -= 4;
    pos -= 4;
    if (index == 0) _maybeNext();
  }

  /// Create a copy of this cursor.
  @override
  StackBufferCursor fork() {
    return StackBufferCursor(stack, pos, index);
  }
}

// These are defined in lr_parser.dart but needed here
// Use abstract classes to avoid circular imports

/// Parse interface - implemented by ParseImpl in lr_parser.dart
abstract class Parse {
  LRParser get parser;
  List<Range> get ranges;
  List<Tree> get reused;
  InputStream get stream;
  int get lastBigReductionStart;
  set lastBigReductionStart(int value);
  int get lastBigReductionSize;
  set lastBigReductionSize(int value);
  int get bigReductionCount;
  set bigReductionCount(int value);
  int? get stoppedAt;
}

/// LRParser interface - implemented by LRParserImpl in lr_parser.dart
abstract class LRParser {
  ContextTracker<Object?>? get context;
  common.NodeSet get nodeSet;
  int get minRepeatTerm;
  int get maxNode;
  List<int> get data;
  int get tokenPrecTable;
  Dialect get dialect;
  int dynamicPrecedence(int term);
  int getGoto(int state, int term, bool loose);
  bool stateFlag(int state, int flag);
  int stateSlot(int state, int slot);
  bool validAction(int state, int action);
  int hasAction(int state, int terminal);
  List<int> nextStates(int state);
  int? allActions(int state, int? Function(int action) action);
}

/// Dialect interface
abstract class Dialect {
  List<bool> get flags;
  bool allows(int term);
}

/// Context tracker for custom context during parsing.
class ContextTracker<T> {
  /// The initial value of the context.
  final T start;

  /// Update the context on shift.
  final T Function(T context, int term, Stack stack, InputStream input) _shift;

  /// Update the context on reduce.
  final T Function(T context, int term, Stack stack, InputStream input) _reduce;

  /// Update the context on reuse.
  final T Function(T context, Tree node, Stack stack, InputStream input) _reuse;

  /// Hash the context.
  final int Function(T context) _hash;

  /// Whether this context is strict.
  final bool strict;

  /// Create a context tracker.
  ContextTracker({
    required this.start,
    T Function(T context, int term, Stack stack, InputStream input)? shift,
    T Function(T context, int term, Stack stack, InputStream input)? reduce,
    T Function(T context, Tree node, Stack stack, InputStream input)? reuse,
    int Function(T context)? hash,
    this.strict = true,
  })  : _shift = shift ?? _identity,
        _reduce = reduce ?? _identity,
        _reuse = reuse ?? _identityReuse,
        _hash = hash ?? _zeroHash;

  T shift(T context, int term, Stack stack, InputStream input) =>
      _shift(context, term, stack, input);

  T reduce(T context, int term, Stack stack, InputStream input) =>
      _reduce(context, term, stack, input);

  T reuse(T context, Tree node, Stack stack, InputStream input) =>
      _reuse(context, node, stack, input);

  int hash(T context) => _hash(context);
}

T _identity<T>(T context, int term, Stack stack, InputStream input) => context;
T _identityReuse<T>(T context, Tree node, Stack stack, InputStream input) =>
    context;
int _zeroHash<T>(T context) => 0;
