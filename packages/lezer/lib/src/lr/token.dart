/// Tokenization support for the LR parser.
///
/// This module provides tokenizer interfaces and implementations
/// for the LR parser runtime.
library;

import 'package:meta/meta.dart';

import '../common/parser.dart' show Input;
import '../common/tree.dart' show Range;
import 'constants.dart';
import 'decode.dart';

// Forward declaration to avoid circular import
// The actual Stack class is in stack.dart
typedef StackRef = Object;

/// A cached token with position and value information.
class CachedToken {
  /// Start position of the token.
  int start = -1;

  /// The token type value.
  int value = -1;

  /// End position of the token.
  int end = -1;

  /// Extended token value (for specializers).
  int extended = -1;

  /// How far ahead we looked while matching this token.
  int lookAhead = 0;

  /// Tokenizer mask when this token was cached.
  int mask = 0;

  /// Context hash when this token was cached.
  int context = 0;
}

final CachedToken _nullToken = CachedToken();

/// A stream for reading input during tokenization.
///
/// Tokenizers interact with the input through this interface. It presents
/// the input as a stream of characters, tracking lookahead and hiding the
/// complexity of ranges from tokenizer code.
class InputStream {
  /// @internal
  String chunk = '';

  /// @internal
  int chunkOff = 0;

  /// @internal
  int chunkPos;

  /// Backup chunk.
  String _chunk2 = '';
  int _chunk2Pos = 0;

  /// The character code of the next code unit in the input, or -1
  /// when the stream is at the end of the input.
  int next = -1;

  /// @internal
  CachedToken token = _nullToken;

  /// The current position of the stream.
  int pos;

  /// @internal
  int end;

  int _rangeIndex = 0;
  Range _range;

  /// The input being tokenized.
  @internal
  final Input input;

  /// The ranges being parsed.
  @internal
  final List<Range> ranges;

  /// @internal
  InputStream(this.input, this.ranges)
      : pos = ranges[0].from,
        chunkPos = ranges[0].from,
        _range = ranges[0],
        end = ranges[ranges.length - 1].to {
    _readNext();
  }

  /// @internal
  int? resolveOffset(int offset, int assoc) {
    var range = _range;
    var index = _rangeIndex;
    var resolvedPos = pos + offset;

    while (resolvedPos < range.from) {
      if (index == 0) return null;
      final nextRange = ranges[--index];
      resolvedPos -= range.from - nextRange.to;
      range = nextRange;
    }

    while (assoc < 0 ? resolvedPos > range.to : resolvedPos >= range.to) {
      if (index == ranges.length - 1) return null;
      final nextRange = ranges[++index];
      resolvedPos += nextRange.from - range.to;
      range = nextRange;
    }

    return resolvedPos;
  }

  /// @internal
  int clipPos(int clipPosValue) {
    if (clipPosValue >= _range.from && clipPosValue < _range.to) {
      return clipPosValue;
    }
    for (final range in ranges) {
      if (range.to > clipPosValue) {
        return clipPosValue < range.from ? range.from : clipPosValue;
      }
    }
    return end;
  }

  /// Look at a code unit near the stream position.
  ///
  /// `.peek(0)` equals `.next`, `.peek(-1)` gives you the previous character.
  int peek(int offset) {
    final idx = chunkOff + offset;
    int resultPos;
    int result;

    if (idx >= 0 && idx < chunk.length) {
      resultPos = pos + offset;
      result = chunk.codeUnitAt(idx);
    } else {
      final resolved = resolveOffset(offset, 1);
      if (resolved == null) return -1;
      resultPos = resolved;

      if (resultPos >= _chunk2Pos &&
          resultPos < _chunk2Pos + _chunk2.length) {
        result = _chunk2.codeUnitAt(resultPos - _chunk2Pos);
      } else {
        var i = _rangeIndex;
        var range = _range;
        while (range.to <= resultPos) {
          range = ranges[++i];
        }
        _chunk2 = input.chunk(resultPos);
        _chunk2Pos = resultPos;
        if (resultPos + _chunk2.length > range.to) {
          _chunk2 = _chunk2.substring(0, range.to - resultPos);
        }
        result = _chunk2.codeUnitAt(0);
      }
    }

    if (resultPos >= token.lookAhead) token.lookAhead = resultPos + 1;
    return result;
  }

  /// Accept a token.
  ///
  /// By default, the end of the token is set to the current stream position,
  /// but you can pass an offset to change that.
  void acceptToken(int tokenValue, [int endOffset = 0]) {
    final endPos =
        endOffset != 0 ? resolveOffset(endOffset, -1) : pos;
    if (endPos == null || endPos < token.start) {
      throw RangeError('Token end out of bounds');
    }
    token.value = tokenValue;
    token.end = endPos;
  }

  /// Accept a token ending at a specific position.
  void acceptTokenTo(int tokenValue, int endPos) {
    token.value = tokenValue;
    token.end = endPos;
  }

  void _getChunk() {
    if (pos >= _chunk2Pos && pos < _chunk2Pos + _chunk2.length) {
      final oldChunk = chunk;
      final oldChunkPos = chunkPos;
      chunk = _chunk2;
      chunkPos = _chunk2Pos;
      _chunk2 = oldChunk;
      _chunk2Pos = oldChunkPos;
      chunkOff = pos - chunkPos;
    } else {
      _chunk2 = chunk;
      _chunk2Pos = chunkPos;
      var nextChunk = input.chunk(pos);
      final chunkEnd = pos + nextChunk.length;
      chunk = chunkEnd > _range.to
          ? nextChunk.substring(0, _range.to - pos)
          : nextChunk;
      chunkPos = pos;
      chunkOff = 0;
    }
  }

  int _readNext() {
    if (chunkOff >= chunk.length) {
      _getChunk();
      if (chunkOff == chunk.length) return next = -1;
    }
    return next = chunk.codeUnitAt(chunkOff);
  }

  /// Move the stream forward N code units (defaults to 1).
  ///
  /// Returns the new value of [next].
  int advance([int n = 1]) {
    chunkOff += n;
    var remaining = n;
    while (pos + remaining >= _range.to) {
      if (_rangeIndex == ranges.length - 1) return _setDone();
      remaining -= _range.to - pos;
      _range = ranges[++_rangeIndex];
      pos = _range.from;
    }
    pos += remaining;
    if (pos >= token.lookAhead) token.lookAhead = pos + 1;
    return _readNext();
  }

  int _setDone() {
    pos = chunkPos = end;
    _range = ranges[_rangeIndex = ranges.length - 1];
    chunk = '';
    return next = -1;
  }

  /// @internal
  InputStream reset(int resetPos, [CachedToken? resetToken]) {
    if (resetToken != null) {
      token = resetToken;
      resetToken.start = resetPos;
      resetToken.lookAhead = resetPos + 1;
      resetToken.value = resetToken.extended = -1;
    } else {
      token = _nullToken;
    }

    if (pos != resetPos) {
      pos = resetPos;
      if (resetPos == end) {
        _setDone();
        return this;
      }
      while (resetPos < _range.from) {
        _range = ranges[--_rangeIndex];
      }
      while (resetPos >= _range.to) {
        _range = ranges[++_rangeIndex];
      }
      if (resetPos >= chunkPos && resetPos < chunkPos + chunk.length) {
        chunkOff = resetPos - chunkPos;
      } else {
        chunk = '';
        chunkOff = 0;
      }
      _readNext();
    }
    return this;
  }

  /// @internal
  String read(int from, int to) {
    if (from >= chunkPos && to <= chunkPos + chunk.length) {
      return chunk.substring(from - chunkPos, to - chunkPos);
    }
    if (from >= _chunk2Pos && to <= _chunk2Pos + _chunk2.length) {
      return _chunk2.substring(from - _chunk2Pos, to - _chunk2Pos);
    }
    if (from >= _range.from && to <= _range.to) {
      return input.read(from, to);
    }

    final result = StringBuffer();
    for (final r in ranges) {
      if (r.from >= to) break;
      if (r.to > from) {
        result.write(input.read(
          from.clamp(r.from, r.to),
          to.clamp(r.from, r.to),
        ));
      }
    }
    return result.toString();
  }
}

/// Interface for tokenizers.
abstract class Tokenizer {
  /// Tokenize at the current input position.
  void token(InputStream input, StackRef stack);

  /// Whether this tokenizer depends on context.
  bool get contextual;

  /// Whether this tokenizer is a fallback.
  bool get fallback;

  /// Whether this tokenizer extends other tokenizers.
  bool get extend;
}

/// A tokenizer based on the parser's token table.
class TokenGroup implements Tokenizer {
  /// The token data.
  final List<int> data;

  /// The tokenizer's group ID.
  final int id;

  TokenGroup(this.data, this.id);

  @override
  bool get contextual => false;

  @override
  bool get fallback => false;

  @override
  bool get extend => false;

  @override
  void token(InputStream input, StackRef stackRef) {
    // Stack provides p.parser which has data and tokenPrecTable
    final stack = stackRef as dynamic;
    final parser = stack.p.parser;
    _readToken(data, input, stack, id, parser.data as List<int>, parser.tokenPrecTable as int);
  }
}

/// A local token group for inline tokenization.
class LocalTokenGroup implements Tokenizer {
  /// The token data.
  final List<int> data;

  /// Precedence table offset.
  final int precTable;

  /// The else token.
  final int? elseToken;

  LocalTokenGroup(Object /* List<int> | String */ data, this.precTable,
      [this.elseToken])
      : data = data is String ? decodeArray(data) : data as List<int>;

  @override
  bool get contextual => false;

  @override
  bool get fallback => false;

  @override
  bool get extend => false;

  @override
  void token(InputStream input, StackRef stackRef) {
    final stack = stackRef as dynamic;
    final start = input.pos;
    var skipped = 0;

    while (true) {
      final atEof = input.next < 0;
      final nextPos = input.resolveOffset(1, 1);
      _readToken(data, input, stack, 0, data, precTable);

      if (input.token.value > -1) break;
      if (elseToken == null) return;
      if (!atEof) skipped++;
      if (nextPos == null) break;
      input.reset(nextPos, input.token);
    }

    if (skipped > 0) {
      input.reset(start, input.token);
      input.acceptToken(elseToken!, skipped);
    }
  }
}

/// Options for external tokenizers.
class ExternalTokenizerOptions {
  /// When true, mark this tokenizer as depending on the current parse stack.
  final bool contextual;

  /// When true, the tokenizer is allowed to run when a previous tokenizer
  /// returned a token that didn't match any of the current state's actions.
  final bool fallback;

  /// When true, tokenizing will not stop after this tokenizer has produced
  /// a token.
  final bool extend;

  const ExternalTokenizerOptions({
    this.contextual = false,
    this.fallback = false,
    this.extend = false,
  });
}

/// External tokenizer for custom tokenization logic.
///
/// `@external tokens` declarations in the grammar should resolve to
/// an instance of this class.
class ExternalTokenizer implements Tokenizer {
  /// The tokenizer function.
  final void Function(InputStream input, StackRef stack) _token;

  @override
  final bool contextual;

  @override
  final bool fallback;

  @override
  final bool extend;

  /// Create an external tokenizer.
  ///
  /// The [token] function should scan for tokens at the stream's position
  /// and call [InputStream.acceptToken] when it finds one.
  ExternalTokenizer(
    this._token, [
    ExternalTokenizerOptions options = const ExternalTokenizerOptions(),
  ])  : contextual = options.contextual,
        fallback = options.fallback,
        extend = options.extend;

  @override
  void token(InputStream input, StackRef stack) => _token(input, stack);
}

/// Read a token from the token data.
void _readToken(
  List<int> data,
  InputStream input,
  dynamic stack,
  int group,
  List<int> precTable,
  int precOffset,
) {
  var state = 0;
  final groupMask = 1 << group;
  final dialect = stack.p.parser.dialect;

  scan:
  while (true) {
    if ((groupMask & data[state]) == 0) {
      break;
    }

    final accEnd = data[state + 1];

    // Accept tokens in this state
    for (var i = state + 3; i < accEnd; i += 2) {
      if ((data[i + 1] & groupMask) > 0) {
        final term = data[i];
        if (dialect.allows(term) &&
            (input.token.value == -1 ||
                input.token.value == term ||
                _overrides(term, input.token.value, precTable, precOffset))) {
          input.acceptToken(term);
          break;
        }
      }
    }

    final nextChar = input.next;
    var low = 0;
    var high = data[state + 2];

    // Special case for EOF
    if (input.next < 0 &&
        high > low &&
        data[accEnd + high * 3 - 3] == Seq.end) {
      state = data[accEnd + high * 3 - 1];
      continue scan;
    }

    // Binary search on the state's edges
    while (low < high) {
      final mid = (low + high) >> 1;
      final index = accEnd + mid + (mid << 1);
      final from = data[index];
      final to = data[index + 1] == 0 ? 0x10000 : data[index + 1];

      if (nextChar < from) {
        high = mid;
      } else if (nextChar >= to) {
        low = mid + 1;
      } else {
        state = data[index + 2];
        input.advance();
        continue scan;
      }
    }
    break;
  }
}

int _findOffset(List<int> data, int start, int term) {
  for (var i = start; data[i] != Seq.end; i++) {
    if (data[i] == term) return i - start;
  }
  return -1;
}

bool _overrides(
  int token,
  int prev,
  List<int> tableData,
  int tableOffset,
) {
  final iPrev = _findOffset(tableData, tableOffset, prev);
  return iPrev < 0 || _findOffset(tableData, tableOffset, token) < iPrev;
}
