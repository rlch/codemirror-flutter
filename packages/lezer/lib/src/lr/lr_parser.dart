/// LR Parser implementation.
///
/// This module provides [LRParser] which is the main parser class
/// for LR grammars.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../common/iter_mode.dart';
import '../common/node_prop.dart';
import '../common/node_set.dart' as common;
import '../common/node_type.dart' as common;
import '../common/parser.dart' as parser_lib show PartialParse, Parser, ParseWrapper;
import '../common/parser.dart' show Input;
import '../common/tree.dart';
import '../common/tree_buffer.dart';
import '../common/tree_fragment.dart';
import 'constants.dart';
import 'decode.dart';
import 'stack.dart';
import 'token.dart';

/// Dialect configuration for the parser.
class DialectImpl implements Dialect {
  /// The source dialect string.
  final String? source;

  @override
  final List<bool> flags;

  /// Disabled terms.
  final Uint8List? disabled;

  DialectImpl(this.source, this.flags, this.disabled);

  @override
  // Note: In JS, out-of-bounds access returns undefined which != 0 (false).
  // In Dart, we need explicit bounds check to match that behavior.
  bool allows(int term) =>
      disabled == null || term >= disabled!.length || disabled![term] == 0;
}

/// Fragment cursor for incremental parsing.
class _FragmentCursor {
  int i = 0;
  TreeFragment? fragment;
  int safeFrom = -1;
  int safeTo = -1;
  final List<Tree> trees = [];
  final List<int> start = [];
  final List<int> index = [];
  late int nextStart;

  final List<TreeFragment> fragments;
  final common.NodeSet nodeSet;

  _FragmentCursor(this.fragments, this.nodeSet) {
    _nextFragment();
  }

  void _nextFragment() {
    final fr = fragment = i == fragments.length ? null : fragments[i++];
    if (fr != null) {
      safeFrom = fr.openStart
          ? _cutAt(fr.tree, fr.from + fr.offset, 1) - fr.offset
          : fr.from;
      safeTo = fr.openEnd
          ? _cutAt(fr.tree, fr.to + fr.offset, -1) - fr.offset
          : fr.to;
      while (trees.isNotEmpty) {
        trees.removeLast();
        start.removeLast();
        index.removeLast();
      }
      trees.add(fr.tree);
      start.add(-fr.offset);
      index.add(0);
      nextStart = safeFrom;
    } else {
      nextStart = 1000000000;
    }
  }

  Tree? nodeAt(int pos) {
    if (pos < nextStart) return null;
    while (fragment != null && safeTo <= pos) {
      _nextFragment();
    }
    if (fragment == null) return null;

    while (true) {
      final last = trees.length - 1;
      if (last < 0) {
        _nextFragment();
        return null;
      }
      final top = trees[last];
      final idx = index[last];
      if (idx == top.children.length) {
        trees.removeLast();
        start.removeLast();
        index.removeLast();
        continue;
      }
      final next = top.children[idx];
      final startPos = start[last] + top.positions[idx];
      if (startPos > pos) {
        nextStart = startPos;
        return null;
      }
      if (next is Tree) {
        if (startPos == pos) {
          if (startPos < safeFrom) return null;
          final endPos = startPos + next.length;
          if (endPos <= safeTo) {
            final lookAhead = next.prop(NodeProp.lookAhead);
            if (lookAhead == null || endPos + lookAhead < fragment!.to) {
              return next;
            }
          }
        }
        index[last]++;
        final threshold = safeFrom < pos ? pos : safeFrom;
        if (startPos + next.length >= threshold) {
          trees.add(next);
          start.add(startPos);
          index.add(0);
        }
      } else {
        index[last]++;
        nextStart = startPos + (next as TreeBuffer).length;
      }
    }
  }
}

int _cutAt(Tree tree, int pos, int side) {
  final cursor = tree.cursor(IterMode.includeAnonymous);
  cursor.moveTo(pos);
  while (true) {
    if (!(side < 0 ? cursor.childBefore(pos) : cursor.childAfter(pos))) {
      while (true) {
        if ((side < 0 ? cursor.to < pos : cursor.from > pos) &&
            !cursor.type.isError) {
          return side < 0
              ? (cursor.to - 1).clamp(0, pos - Lookahead.margin)
              : (cursor.from + 1).clamp(pos + Lookahead.margin, tree.length);
        }
        if (side < 0 ? cursor.prevSibling() : cursor.nextSibling()) break;
        if (!cursor.parent()) return side < 0 ? 0 : tree.length;
      }
    }
  }
}

/// Token cache for the parser.
class _TokenCache {
  final List<CachedToken> tokens;
  CachedToken? mainToken;
  final List<int> actions = [];
  final InputStream stream;

  _TokenCache(LRParserImpl parser, this.stream)
      : tokens = List.generate(parser.tokenizers.length, (_) => CachedToken());

  List<int> getActions(Stack stack) {
    var actionIndex = 0;
    CachedToken? main;
    final parser = stack.p.parser as LRParserImpl;
    final tokenizers = parser.tokenizers;

    final mask = parser.stateSlot(stack.state, ParseState.tokenizerMask);
    final context = stack.curContext?.hash ?? 0;
    var lookAhead = 0;

    for (var i = 0; i < tokenizers.length; i++) {
      if (((1 << i) & mask) == 0) continue;
      final tokenizer = tokenizers[i];
      final token = tokens[i];
      if (main != null && !tokenizer.fallback) continue;
      if (tokenizer.contextual ||
          token.start != stack.pos ||
          token.mask != mask ||
          token.context != context) {
        _updateCachedToken(token, tokenizer, stack);
        token.mask = mask;
        token.context = context;
      }
      if (token.lookAhead > token.end + Lookahead.margin) {
        lookAhead = lookAhead > token.lookAhead ? lookAhead : token.lookAhead;
      }

      if (token.value != Term.err) {
        final startIndex = actionIndex;
        if (token.extended > -1) {
          actionIndex = _addActions(stack, token.extended, token.end, actionIndex);
        }
        actionIndex = _addActions(stack, token.value, token.end, actionIndex);
        if (!tokenizer.extend) {
          main = token;
          if (actionIndex > startIndex) break;
        }
      }
    }

    while (actions.length > actionIndex) {
      actions.removeLast();
    }
    if (lookAhead > 0) stack.setLookAhead(lookAhead);
    if (main == null && stack.pos == stream.end) {
      main = CachedToken();
      main.value = parser.eofTerm;
      main.start = main.end = stack.pos;
      actionIndex = _addActions(stack, main.value, main.end, actionIndex);
    }
    mainToken = main;
    return actions;
  }

  CachedToken getMainToken(Stack stack) {
    if (mainToken != null) return mainToken!;
    final main = CachedToken();
    main.start = stack.pos;
    main.end = (stack.pos + 1).clamp(0, stack.p.stream.end);
    main.value =
        stack.pos == stack.p.stream.end ? (stack.p.parser as LRParserImpl).eofTerm : Term.err;
    return main;
  }

  void _updateCachedToken(CachedToken token, Tokenizer tokenizer, Stack stack) {
    final start = stream.clipPos(stack.pos);
    tokenizer.token(stream.reset(start, token), stack);
    if (token.value > -1) {
      final parser = stack.p.parser as LRParserImpl;

      for (var i = 0; i < parser.specialized.length; i++) {
        if (parser.specialized[i] == token.value) {
          final result =
              parser.specializers[i](stream.read(token.start, token.end), stack);
          if (result >= 0 && parser.dialect.allows(result >> 1)) {
            if ((result & 1) == Specialize.specialize) {
              token.value = result >> 1;
            } else {
              token.extended = result >> 1;
            }
            break;
          }
        }
      }
    } else {
      token.value = Term.err;
      token.end = stream.clipPos(start + 1);
    }
  }

  int _putAction(int action, int token, int end, int index) {
    // Don't add duplicate actions
    for (var i = 0; i < index; i += 3) {
      if (actions[i] == action) return index;
    }
    if (index >= actions.length) {
      actions.add(action);
      actions.add(token);
      actions.add(end);
    } else {
      actions[index] = action;
      actions[index + 1] = token;
      actions[index + 2] = end;
    }
    return index + 3;
  }

  int _addActions(Stack stack, int token, int end, int index) {
    final state = stack.state;
    final parser = stack.p.parser as LRParserImpl;
    final data = parser.data;

    for (var set = 0; set < 2; set++) {
      for (var i = parser.stateSlot(
              state, set != 0 ? ParseState.skip : ParseState.actions);
          ;
          i += 3) {
        if (data[i] == Seq.end) {
          if (data[i + 1] == Seq.next) {
            i = _pair(data, i + 2);
          } else {
            if (index == 0 && data[i + 1] == Seq.other) {
              index = _putAction(_pair(data, i + 2), token, end, index);
            }
            break;
          }
        }
        if (data[i] == token) {
          index = _putAction(_pair(data, i + 1), token, end, index);
        }
      }
    }
    return index;
  }
}

int _pair(List<int> data, int off) => data[off] | (data[off + 1] << 16);

/// A parse implementation.
class ParseImpl implements Parse, parser_lib.PartialParse {
  /// Active parse stacks.
  List<Stack> stacks;
  int recovering = 0;
  _FragmentCursor? fragments;
  int nextStackID = 0x2654; // ♔, ♕, etc.
  int minStackPos = 0;

  @override
  final List<Tree> reused = [];

  @override
  final InputStream stream;

  late final _TokenCache tokens;
  final int topTerm;
  @override
  int? stoppedAt;

  @override
  int lastBigReductionStart = -1;

  @override
  int lastBigReductionSize = 0;

  @override
  int bigReductionCount = 0;

  @override
  final LRParserImpl parser;

  final Input input;

  @override
  final List<Range> ranges;

  ParseImpl(this.parser, this.input, List<TreeFragment> fragmentList, this.ranges)
      : stream = InputStream(input, ranges),
        topTerm = parser.top.$2,
        stacks = [] {
    tokens = _TokenCache(parser, stream);
    final from = ranges[0].from;
    stacks = [Stack.start(this, parser.top.$1, from)];
    fragments = fragmentList.isNotEmpty && stream.end - from > parser.bufferLength * 4
        ? _FragmentCursor(fragmentList, parser.nodeSet)
        : null;
  }

  @override
  int get parsedPos => minStackPos;

  @override
  Tree? advance() {
    final currentStacks = stacks;
    final pos = minStackPos;
    final newStacks = stacks = <Stack>[];
    List<Stack>? stopped;
    List<int>? stoppedTokens;

    // Handle excessive left-associative reductions
    if (bigReductionCount > Rec.maxLeftAssociativeReductionCount &&
        currentStacks.length == 1) {
      final s = currentStacks[0];
      while (s.forceReduce() &&
          s.stack.isNotEmpty &&
          s.stack[s.stack.length - 2] >= lastBigReductionStart) {}
      bigReductionCount = lastBigReductionSize = 0;
    }

    for (var i = 0; i < currentStacks.length; i++) {
      final stack = currentStacks[i];
      while (true) {
        tokens.mainToken = null;
        if (stack.pos > pos) {
          newStacks.add(stack);
        } else if (_advanceStack(stack, newStacks, currentStacks)) {
          continue;
        } else {
          stopped ??= [];
          stoppedTokens ??= [];
          stopped.add(stack);
          final tok = tokens.getMainToken(stack);
          stoppedTokens.add(tok.value);
          stoppedTokens.add(tok.end);
        }
        break;
      }
    }

    if (newStacks.isEmpty) {
      final finished = stopped != null ? _findFinished(stopped) : null;
      if (finished != null) {
        return _stackToTree(finished);
      }

      if (parser.strict) {
        throw StateError('No parse at $pos');
      }
      if (recovering == 0) recovering = Rec.distance;
    }

    if (recovering > 0 && stopped != null) {
      final finished = stoppedAt != null && stopped[0].pos > stoppedAt!
          ? stopped[0]
          : _runRecovery(stopped, stoppedTokens!, newStacks);
      if (finished != null) {
        return _stackToTree(finished.forceAll());
      }
    }

    if (recovering > 0) {
      final maxRemaining =
          recovering == 1 ? 1 : recovering * Rec.maxRemainingPerStep;
      if (newStacks.length > maxRemaining) {
        newStacks.sort((a, b) => b.score - a.score);
        while (newStacks.length > maxRemaining) {
          newStacks.removeLast();
        }
      }
      if (newStacks.any((s) => s.reducePos > pos)) recovering--;
    } else if (newStacks.length > 1) {
      // Prune stacks
      outer:
      for (var i = 0; i < newStacks.length - 1; i++) {
        final stack = newStacks[i];
        for (var j = i + 1; j < newStacks.length; j++) {
          final other = newStacks[j];
          if (stack.sameState(other) ||
              (stack.buffer.length > Rec.minBufferLengthPrune &&
                  other.buffer.length > Rec.minBufferLengthPrune)) {
            if (((stack.score - other.score) | (stack.buffer.length - other.buffer.length)) >
                0) {
              newStacks.removeAt(j--);
            } else {
              newStacks.removeAt(i--);
              continue outer;
            }
          }
        }
      }
      if (newStacks.length > Rec.maxStackCount) {
        newStacks.removeRange(Rec.maxStackCount, newStacks.length);
      }
    }

    minStackPos = newStacks[0].pos;
    for (var i = 1; i < newStacks.length; i++) {
      if (newStacks[i].pos < minStackPos) minStackPos = newStacks[i].pos;
    }
    return null;
  }

  @override
  void stopAt(int pos) {
    if (stoppedAt != null && stoppedAt! < pos) {
      throw RangeError("Can't move stoppedAt forward");
    }
    stoppedAt = pos;
  }

  bool _advanceStack(Stack stack, List<Stack> stacks, List<Stack> split) {
    final start = stack.pos;

    if (stoppedAt != null && start > stoppedAt!) {
      return stack.forceReduce() ? true : false;
    }

    if (fragments != null) {
      final strictCx = stack.curContext?.tracker.strict ?? false;
      final cxHash = strictCx ? stack.curContext!.hash : 0;
      for (var cached = fragments!.nodeAt(start); cached != null;) {
        final match = parser.nodeSet.types[cached.type.id] == cached.type
            ? parser.getGoto(stack.state, cached.type.id, false)
            : -1;
        if (match > -1 &&
            cached.length > 0 &&
            (!strictCx || (cached.prop(NodeProp.contextHash) ?? 0) == cxHash)) {
          stack.useNode(cached, match);
          return true;
        }
        if (cached.children.isEmpty || cached.positions[0] > 0) break;
        final inner = cached.children[0];
        if (inner is Tree && cached.positions[0] == 0) {
          cached = inner;
        } else {
          break;
        }
      }
    }

    final defaultReduce = parser.stateSlot(stack.state, ParseState.defaultReduce);
    if (defaultReduce > 0) {
      stack.reduce(defaultReduce);
      return true;
    }

    if (stack.stack.length >= Rec.cutDepth) {
      while (stack.stack.length > Rec.cutTo && stack.forceReduce()) {}
    }

    final actions = tokens.getActions(stack);
    for (var i = 0; i < actions.length;) {
      final action = actions[i++];
      final term = actions[i++];
      final end = actions[i++];
      final last = i == actions.length || split.isEmpty;
      final localStack = last ? stack : stack.split();
      final main = tokens.mainToken;
      localStack.apply(action, term, main?.start ?? localStack.pos, end);
      if (last) {
        return true;
      } else if (localStack.pos > start) {
        stacks.add(localStack);
      } else {
        split.add(localStack);
      }
    }

    return false;
  }

  bool _advanceFully(Stack stack, List<Stack> newStacks) {
    final pos = stack.pos;
    while (true) {
      if (!_advanceStack(stack, [], [])) return false;
      if (stack.pos > pos) {
        _pushStackDedup(stack, newStacks);
        return true;
      }
    }
  }

  Stack? _runRecovery(
      List<Stack> stacks, List<int> tokens, List<Stack> newStacks) {
    Stack? finished;
    var restarted = false;

    for (var i = 0; i < stacks.length; i++) {
      final stack = stacks[i];
      final token = tokens[i << 1];
      var tokenEnd = tokens[(i << 1) + 1];

      if (stack.deadEnd) {
        if (restarted) continue;
        restarted = true;
        stack.restart();
        final done = _advanceFully(stack, newStacks);
        if (done) continue;
      }

      final force = stack.split();
      for (var j = 0; j < Rec.forceReduceLimit && force.forceReduce(); j++) {
        final done = _advanceFully(force, newStacks);
        if (done) break;
      }

      for (final insert in stack.recoverByInsert(token)) {
        _advanceFully(insert, newStacks);
      }

      if (stream.end > stack.pos) {
        if (tokenEnd == stack.pos) {
          tokenEnd++;
        }
        stack.recoverByDelete(token, tokenEnd);
        _pushStackDedup(stack, newStacks);
      } else if (finished == null || finished.score < stack.score) {
        finished = stack;
      }
    }

    return finished;
  }

  Tree _stackToTree(Stack stack) {
    stack.close();
    return Tree.build(
      buffer: StackBufferCursor.create(stack),
      nodeSet: parser.nodeSet,
      topID: topTerm,
      maxBufferLength: parser.bufferLength,
      reused: reused,
      start: ranges[0].from,
      length: stack.pos - ranges[0].from,
      minRepeatType: parser.minRepeatTerm,
    );
  }
}

void _pushStackDedup(Stack stack, List<Stack> newStacks) {
  for (var i = 0; i < newStacks.length; i++) {
    final other = newStacks[i];
    if (other.pos == stack.pos && other.sameState(stack)) {
      if (newStacks[i].score < stack.score) newStacks[i] = stack;
      return;
    }
  }
  newStacks.add(stack);
}

Stack? _findFinished(List<Stack> stacks) {
  Stack? best;
  for (final stack in stacks) {
    final stopped = stack.p.stoppedAt;
    if ((stack.pos == stack.p.stream.end ||
            (stopped != null && stack.pos > stopped)) &&
        (stack.p.parser as LRParserImpl).stateFlag(stack.state, StateFlag.accepting) &&
        (best == null || best.score < stack.score)) {
      best = stack;
    }
  }
  return best;
}

/// Specializer specification.
class SpecializerSpec {
  final int term;
  final int Function(String value, Stack stack)? get;
  final int Function(String value, Stack stack)? external;
  final bool extend;

  const SpecializerSpec({
    required this.term,
    this.get,
    this.external,
    this.extend = false,
  });
}

/// Parser configuration options.
class ParserConfig {
  /// Node prop values to add to the parser's node set.
  final List<NodePropSource>? props;

  /// The name of the @top declaration to parse from.
  final String? top;

  /// A space-separated string of dialects to enable.
  final String? dialect;

  /// Replace the given external tokenizers.
  final List<({ExternalTokenizer from, ExternalTokenizer to})>? tokenizers;

  /// Replace external specializers.
  final List<({int Function(String, Stack) from, int Function(String, Stack) to})>?
      specializers;

  /// Replace the context tracker.
  final ContextTracker<Object?>? contextTracker;

  /// When true, raise an exception on parse errors.
  final bool? strict;

  /// Add a wrapper for mixed parsing.
  final parser_lib.ParseWrapper? wrap;

  /// Maximum buffer length.
  final int? bufferLength;

  const ParserConfig({
    this.props,
    this.top,
    this.dialect,
    this.tokenizers,
    this.specializers,
    this.contextTracker,
    this.strict,
    this.wrap,
    this.bufferLength,
  });
}

/// Parser specification from the generator.
class ParserSpec {
  final int version;
  final Object /* String | Uint32List */ states;
  final Object /* String | Uint16List */ stateData;
  final Object /* String | Uint16List */ goto;
  final String nodeNames;
  final int maxTerm;
  final int repeatNodeCount;
  final List<List<Object>>? nodeProps;
  final List<NodePropSource>? propSources;
  final List<int>? skippedNodes;
  final String tokenData;
  final List<Object /* Tokenizer | int */> tokenizers;
  final Map<String, (int, int)> topRules;
  final ContextTracker<Object?>? context;
  final Map<String, int>? dialects;
  final Map<int, int>? dynamicPrecedences;
  final List<SpecializerSpec>? specialized;
  final int tokenPrec;
  final Map<int, String>? termNames;

  const ParserSpec({
    required this.version,
    required this.states,
    required this.stateData,
    required this.goto,
    required this.nodeNames,
    required this.maxTerm,
    required this.repeatNodeCount,
    this.nodeProps,
    this.propSources,
    this.skippedNodes,
    required this.tokenData,
    required this.tokenizers,
    required this.topRules,
    this.context,
    this.dialects,
    this.dynamicPrecedences,
    this.specialized,
    required this.tokenPrec,
    this.termNames,
  });
}

/// Holds the parse tables for a given grammar.
class LRParserImpl extends parser_lib.Parser implements LRParser {
  /// The parse states for this grammar.
  @internal
  final Uint32List states;

  /// The data blob for parse states.
  @override
  final List<int> data;

  /// The goto table.
  @internal
  final List<int> goto;

  /// The highest term id.
  @internal
  final int maxTerm;

  /// The first repeat-related term id.
  @override
  final int minRepeatTerm;

  /// The tokenizer objects.
  @internal
  final List<Tokenizer> tokenizers;

  /// Top rule mappings.
  @internal
  final Map<String, (int, int)> topRules;

  @override
  final ContextTracker<Object?>? context;

  /// Dialect mappings.
  @internal
  final Map<String, int> dialects;

  /// Dynamic precedences.
  @internal
  final Map<int, int>? dynamicPrecedences;

  /// Specialized token types.
  @internal
  final Uint16List specialized;

  /// Specializer functions.
  @internal
  final List<int Function(String, Stack)> specializers;

  /// Specializer specs.
  @internal
  final List<SpecializerSpec> specializerSpecs;

  @override
  final int tokenPrecTable;

  /// Term name mappings.
  @internal
  final Map<int, String>? termNames;

  @override
  final int maxNode;

  @override
  final DialectImpl dialect;

  /// Parse wrappers.
  @internal
  final List<parser_lib.ParseWrapper> wrappers;

  /// Top rule.
  @internal
  final (int, int) top;

  /// Buffer length.
  @internal
  final int bufferLength;

  /// Whether to be strict.
  @internal
  final bool strict;

  @override
  final common.NodeSet nodeSet;

  /// @internal
  LRParserImpl({
    required this.states,
    required this.data,
    required this.goto,
    required this.maxTerm,
    required this.minRepeatTerm,
    required this.tokenizers,
    required this.topRules,
    required this.context,
    required this.dialects,
    required this.dynamicPrecedences,
    required this.specialized,
    required this.specializers,
    required this.specializerSpecs,
    required this.tokenPrecTable,
    required this.termNames,
    required this.maxNode,
    required this.dialect,
    required this.wrappers,
    required this.top,
    required this.bufferLength,
    required this.strict,
    required this.nodeSet,
  });

  /// Deserialize parser from spec.
  static LRParserImpl deserialize(ParserSpec spec) {
    if (spec.version != FileVersion.version) {
      throw RangeError(
          "Parser version (${spec.version}) doesn't match runtime version (${FileVersion.version})");
    }

    final nodeNames = spec.nodeNames.split(' ');
    final minRepeatTerm = nodeNames.length;
    for (var i = 0; i < spec.repeatNodeCount; i++) {
      nodeNames.add('');
    }

    final topTerms = spec.topRules.values.map((r) => r.$2).toList();
    final nodeProps = <List<(NodeProp<Object?>, Object?)>>[];
    for (var i = 0; i < nodeNames.length; i++) {
      nodeProps.add([]);
    }

    void setProp(int nodeID, NodeProp<Object?> prop, String value) {
      nodeProps[nodeID].add((prop, prop.deserialize(value)));
    }

    if (spec.nodeProps != null) {
      for (final propSpec in spec.nodeProps!) {
        var prop = propSpec[0];
        if (prop is String) {
          // Look up the prop by name
          prop = NodeProp.byName(prop) ?? NodeProp<Object?>(deserialize: (s) => s);
        }
        final nodeProp = prop as NodeProp<Object?>;
        for (var i = 1; i < propSpec.length;) {
          final next = propSpec[i++];
          if (next is int && next >= 0) {
            setProp(next, nodeProp, propSpec[i++] as String);
          } else if (next is int && next < 0) {
            final value = propSpec[i + (-next)] as String;
            for (var j = -next; j > 0; j--) {
              setProp(propSpec[i++] as int, nodeProp, value);
            }
            i++;
          }
        }
      }
    }

    var nodeSet = common.NodeSet(List.generate(nodeNames.length, (i) {
      return common.NodeType.define(
        id: i,
        name: i >= minRepeatTerm ? null : nodeNames[i],
        props: nodeProps[i].map((p) => (p.$1, p.$2)).toList(),
        top: topTerms.contains(i),
        error: i == 0,
        skipped: spec.skippedNodes?.contains(i) ?? false,
      );
    }));

    if (spec.propSources != null) {
      nodeSet = nodeSet.extend(spec.propSources!);
    }

    final tokenArray = decodeArray(spec.tokenData);
    final specializerSpecs = spec.specialized ?? [];
    final specialized = Uint16List(specializerSpecs.length);
    for (var i = 0; i < specializerSpecs.length; i++) {
      specialized[i] = specializerSpecs[i].term;
    }
    final specializers = specializerSpecs.map(_getSpecializer).toList();

    final statesData = spec.states is String
        ? decodeArray32(spec.states as String)
        : spec.states as Uint32List;
    final stateData = decodeArray(spec.stateData);
    final gotoData = decodeArray(spec.goto);

    final dialectMap = spec.dialects ?? {};
    final dialectData = _parseDialect(null, dialectMap, stateData, spec.maxTerm);

    final topRule = spec.topRules[spec.topRules.keys.first]!;

    final tokenizerList = spec.tokenizers.map((value) {
      if (value is int) {
        return TokenGroup(tokenArray, value);
      }
      return value as Tokenizer;
    }).toList();

    return LRParserImpl(
      states: statesData,
      data: stateData,
      goto: gotoData,
      maxTerm: spec.maxTerm,
      minRepeatTerm: minRepeatTerm,
      tokenizers: tokenizerList,
      topRules: spec.topRules,
      context: spec.context,
      dialects: dialectMap,
      dynamicPrecedences: spec.dynamicPrecedences,
      specialized: specialized,
      specializers: specializers,
      specializerSpecs: specializerSpecs,
      tokenPrecTable: spec.tokenPrec,
      termNames: spec.termNames,
      maxNode: nodeSet.types.length - 1,
      dialect: dialectData,
      wrappers: [],
      top: topRule,
      bufferLength: defaultBufferLength,
      strict: false,
      nodeSet: nodeSet,
    );
  }

  @override
  parser_lib.PartialParse createParse(
    Input input,
    List<TreeFragment> fragments,
    List<Range> ranges,
  ) {
    parser_lib.PartialParse parse = ParseImpl(this, input, fragments, ranges);
    for (final w in wrappers) {
      parse = w(parse, input, fragments, ranges);
    }
    return parse;
  }

  @override
  int getGoto(int state, int term, [bool loose = false]) {
    if (term >= goto[0]) return -1;
    for (var pos = goto[term + 1];;) {
      final groupTag = goto[pos++];
      final last = (groupTag & 1) != 0;
      final target = goto[pos++];
      if (last && loose) return target;
      for (var end = pos + (groupTag >> 1); pos < end; pos++) {
        if (goto[pos] == state) return target;
      }
      if (last) return -1;
    }
  }

  @override
  int hasAction(int state, int terminal) {
    for (var set = 0; set < 2; set++) {
      for (var i = stateSlot(state, set != 0 ? ParseState.skip : ParseState.actions);
          ;
          i += 3) {
        final next = data[i];
        if (next == Seq.end) {
          if (data[i + 1] == Seq.next) {
            i = _pair(data, i + 2);
            continue;
          } else if (data[i + 1] == Seq.other) {
            return _pair(data, i + 2);
          }
          break;
        }
        if (next == terminal || next == Term.err) {
          return _pair(data, i + 1);
        }
      }
    }
    return 0;
  }

  @override
  int stateSlot(int state, int slot) {
    return states[(state * ParseState.size) + slot];
  }

  @override
  bool stateFlag(int state, int flag) {
    return (stateSlot(state, ParseState.flags) & flag) > 0;
  }

  @override
  bool validAction(int state, int action) {
    final result = allActions(state, (a) => a == action ? 1 : null);
    return result != null;
  }

  @override
  int? allActions(int state, int? Function(int action) action) {
    final deflt = stateSlot(state, ParseState.defaultReduce);
    int? result = deflt != 0 ? action(deflt) : null;
    for (var i = stateSlot(state, ParseState.actions); result == null;) {
      if (data[i] == Seq.end) {
        if (data[i + 1] == Seq.next) {
          i = _pair(data, i + 2);
        } else {
          break;
        }
      } else {
        result = action(_pair(data, i + 1));
        i += 3;
      }
    }
    return result;
  }

  @override
  List<int> nextStates(int state) {
    final result = <int>[];
    for (var i = stateSlot(state, ParseState.actions);; i += 3) {
      if (data[i] == Seq.end) {
        if (data[i + 1] == Seq.next) {
          i = _pair(data, i + 2);
        } else {
          break;
        }
      }
      if ((data[i + 2] & (Action.reduceFlag >> 16)) == 0) {
        final value = data[i + 1];
        if (!result.any((v) => v == value)) {
          result.add(data[i]);
          result.add(value);
        }
      }
    }
    return result;
  }

  /// Configure the parser.
  LRParserImpl configure(ParserConfig config) {
    var newNodeSet = nodeSet;
    if (config.props != null) {
      newNodeSet = nodeSet.extend(config.props!);
    }

    var newTop = top;
    if (config.top != null) {
      final info = topRules[config.top];
      if (info == null) {
        throw RangeError('Invalid top rule name ${config.top}');
      }
      newTop = info;
    }

    var newTokenizers = tokenizers;
    if (config.tokenizers != null) {
      newTokenizers = tokenizers.map((t) {
        final found = config.tokenizers!.where((r) => r.from == t).firstOrNull;
        return found != null ? found.to : t;
      }).toList();
    }

    var newSpecializers = specializers;
    var newSpecializerSpecs = specializerSpecs;
    if (config.specializers != null) {
      newSpecializers = List.from(specializers);
      newSpecializerSpecs = specializerSpecs.asMap().entries.map((entry) {
        final i = entry.key;
        final s = entry.value;
        final found = config.specializers!.where((r) => r.from == s.external).firstOrNull;
        if (found == null) return s;
        final spec = SpecializerSpec(
          term: s.term,
          get: s.get,
          external: found.to,
          extend: s.extend,
        );
        newSpecializers[i] = _getSpecializer(spec);
        return spec;
      }).toList();
    }

    final newContext = config.contextTracker ?? context;
    final newDialect = config.dialect != null
        ? _parseDialect(config.dialect, dialects, data, maxTerm)
        : dialect;
    final newStrict = config.strict ?? strict;
    final newWrappers =
        config.wrap != null ? [...wrappers, config.wrap!] : wrappers;
    final newBufferLength = config.bufferLength ?? bufferLength;

    return LRParserImpl(
      states: states,
      data: data,
      goto: goto,
      maxTerm: maxTerm,
      minRepeatTerm: minRepeatTerm,
      tokenizers: newTokenizers,
      topRules: topRules,
      context: newContext,
      dialects: dialects,
      dynamicPrecedences: dynamicPrecedences,
      specialized: specialized,
      specializers: newSpecializers,
      specializerSpecs: newSpecializerSpecs,
      tokenPrecTable: tokenPrecTable,
      termNames: termNames,
      maxNode: newNodeSet.types.length - 1,
      dialect: newDialect,
      wrappers: newWrappers,
      top: newTop,
      bufferLength: newBufferLength,
      strict: newStrict,
      nodeSet: newNodeSet,
    );
  }

  /// Whether any wrappers are registered.
  bool hasWrappers() => wrappers.isNotEmpty;

  /// Get the name of a term.
  String getName(int term) {
    if (termNames != null && termNames![term] != null) {
      return termNames![term]!;
    }
    return term <= maxNode && nodeSet.types[term].name.isNotEmpty
        ? nodeSet.types[term].name
        : '$term';
  }

  /// The eof term id.
  int get eofTerm => maxNode + 1;

  /// The type of the top node.
  common.NodeType get topNode => nodeSet.types[top.$2];

  @override
  int dynamicPrecedence(int term) {
    return dynamicPrecedences?[term] ?? 0;
  }
}

DialectImpl _parseDialect(
  String? dialectStr,
  Map<String, int> dialectMap,
  List<int> data,
  int maxTerm,
) {
  final values = dialectMap.keys.toList();
  final flags = List.filled(values.length, false);
  if (dialectStr != null) {
    for (final part in dialectStr.split(' ')) {
      final id = values.indexOf(part);
      if (id >= 0) flags[id] = true;
    }
  }
  Uint8List? disabled;
  for (var i = 0; i < values.length; i++) {
    if (!flags[i]) {
      for (var j = dialectMap[values[i]]!; data[j] != Seq.end;) {
        final id = data[j++];
        disabled ??= Uint8List(maxTerm + 1);
        disabled[id] = 1;
      }
    }
  }
  return DialectImpl(dialectStr, flags, disabled);
}

int Function(String, Stack) _getSpecializer(SpecializerSpec spec) {
  if (spec.external != null) {
    final mask = spec.extend ? Specialize.extend : Specialize.specialize;
    return (value, stack) => (spec.external!(value, stack) << 1) | mask;
  }
  return spec.get!;
}

/// Convenience function to create an LR parser from a spec.
LRParserImpl parseLR(ParserSpec spec) => LRParserImpl.deserialize(spec);
