/// External tokenizers for JavaScript.
///
/// Hand-written tokenizers for JavaScript tokens that can't be
/// expressed by lezer's built-in tokenizer.
library;

import 'package:lezer/lezer.dart';

import 'parser_terms.dart' as terms;

/// Whitespace characters.
const List<int> _space = [
  9, 10, 11, 12, 13, 32, 133, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197,
  8198, 8199, 8200, 8201, 8202, 8232, 8233, 8239, 8287, 12288,
];

const int _braceR = 125; // }
const int _semicolon = 59; // ;
const int _slash = 47; // /
const int _asterisk = 42; // *
const int _plus = 43; // +
const int _minus = 45; // -
const int _lt = 60; // <
const int _comma = 44; // ,
const int _question = 63; // ?
const int _dot = 46; // .
const int _bracketL = 91; // [

/// Context tracker that tracks whether we're after a newline.
final ContextTracker<bool> trackNewline = ContextTracker<bool>(
  start: false,
  shift: (context, term, stack, input) {
    return term == terms.lineComment ||
            term == terms.blockComment ||
            term == terms.spaces
        ? context
        : term == terms.newline;
  },
  strict: false,
);

/// External tokenizer for automatic semicolon insertion.
final ExternalTokenizer insertSemicolon = ExternalTokenizer(
  (input, stackRef) {
    final stack = stackRef as dynamic;
    final next = input.next;
    if (next == _braceR || next == -1 || (stack.context as bool? ?? false)) {
      input.acceptToken(terms.insertSemi);
    }
  },
  const ExternalTokenizerOptions(contextual: true, fallback: true),
);

/// External tokenizer for noSemicolon contexts.
final ExternalTokenizer noSemicolon = ExternalTokenizer(
  (input, stackRef) {
    final stack = stackRef as dynamic;
    final next = input.next;
    if (_space.contains(next)) return;
    if (next == _slash) {
      final after = input.peek(1);
      if (after == _slash || after == _asterisk) return;
    }
    if (next != _braceR &&
        next != _semicolon &&
        next != -1 &&
        !(stack.context as bool? ?? false)) {
      input.acceptToken(terms.noSemi);
    }
  },
  const ExternalTokenizerOptions(contextual: true),
);

/// External tokenizer for noSemicolonType contexts (for type annotations).
final ExternalTokenizer noSemicolonType = ExternalTokenizer(
  (input, stackRef) {
    final stack = stackRef as dynamic;
    if (input.next == _bracketL && !(stack.context as bool? ?? false)) {
      input.acceptToken(terms.noSemiType);
    }
  },
  const ExternalTokenizerOptions(contextual: true),
);

/// External tokenizer for operators (++, --, ?.).
final ExternalTokenizer operatorToken = ExternalTokenizer(
  (input, stackRef) {
    final stack = stackRef as dynamic;
    final next = input.next;
    if (next == _plus || next == _minus) {
      input.advance();
      if (next == input.next) {
        input.advance();
        final mayPostfix =
            !(stack.context as bool? ?? false) && stack.canShift(terms.incdec);
        input.acceptToken(mayPostfix ? terms.incdec : terms.incdecPrefix);
      }
    } else if (next == _question && input.peek(1) == _dot) {
      input.advance();
      input.advance();
      // No digit after - not a number like ?.5
      if (input.next < 48 || input.next > 57) {
        input.acceptToken(terms.questionDot);
      }
    }
  },
  const ExternalTokenizerOptions(contextual: true),
);

bool _identifierChar(int ch, bool start) {
  return (ch >= 65 && ch <= 90) || // A-Z
      (ch >= 97 && ch <= 122) || // a-z
      ch == 95 || // _
      ch >= 192 ||
      (!start && ch >= 48 && ch <= 57); // 0-9
}

/// External tokenizer for JSX start tags.
final ExternalTokenizer jsx = ExternalTokenizer(
  (input, stackRef) {
    final stack = stackRef as dynamic;
    if (input.next != _lt || !stack.dialectEnabled(terms.dialectJsx)) return;
    input.advance();
    if (input.next == _slash) return;

    // Scan for an identifier followed by a comma or 'extends', don't
    // treat this as a start tag if present.
    var back = 0;
    while (_space.contains(input.next)) {
      input.advance();
      back++;
    }
    if (_identifierChar(input.next, true)) {
      input.advance();
      back++;
      while (_identifierChar(input.next, false)) {
        input.advance();
        back++;
      }
      while (_space.contains(input.next)) {
        input.advance();
        back++;
      }
      if (input.next == _comma) return;
      const extendsStr = 'extends';
      for (var i = 0;; i++) {
        if (i == 7) {
          if (!_identifierChar(input.next, true)) return;
          break;
        }
        if (input.next != extendsStr.codeUnitAt(i)) break;
        input.advance();
        back++;
      }
    }
    input.acceptToken(terms.jsxStartTag, -back);
  },
);
