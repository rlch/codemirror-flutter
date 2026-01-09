import '../text/text.dart';
import 'completion.dart';

const _range = 50000;
const _minCacheLen = 1000;
const _maxList = 2000;

RegExp _wordRE(String wordChars) {
  final escaped = wordChars.replaceAllMapped(RegExp(r'[\]\-\\]'), (m) => '\\${m[0]}');
  try {
    return RegExp('[\\p{Alphabetic}\\p{Number}_$escaped]+', unicode: true);
  } catch (_) {
    return RegExp('[\\w$escaped]+');
  }
}

RegExp _mapRE(RegExp re, String Function(String source) f) {
  return RegExp(f(re.pattern), unicode: re.isUnicode);
}

final Map<String, Expando<List<Completion>>> _wordCaches = {};

Expando<List<Completion>> _wordCache(String wordChars) {
  return _wordCaches[wordChars] ??= Expando<List<Completion>>();
}

void _storeWords(
  Text doc,
  RegExp wordRE,
  List<Completion> result,
  Set<String> seen,
  int ignoreAt,
) {
  int pos = 0;
  for (final lines = doc.iterLines(); !lines.next().done;) {
    final value = lines.value;
    for (final match in wordRE.allMatches(value)) {
      final word = match[0]!;
      if (!seen.contains(word) && pos + match.start != ignoreAt) {
        result.add(Completion(label: word, type: 'text'));
        seen.add(word);
        if (result.length >= _maxList) return;
      }
    }
    pos += value.length + 1;
  }
}

List<Completion> _collectWords(
  Text doc,
  Expando<List<Completion>> cache,
  RegExp wordRE,
  int to,
  int ignoreAt,
) {
  final big = doc.length >= _minCacheLen;
  final cached = big ? cache[doc] : null;
  if (cached != null) return cached;

  final result = <Completion>[];
  final seen = <String>{};

  final children = doc.children;
  if (children != null) {
    int pos = 0;
    for (final ch in children) {
      if (ch.length >= _minCacheLen) {
        for (final c in _collectWords(ch, cache, wordRE, to - pos, ignoreAt - pos)) {
          if (!seen.contains(c.label)) {
            seen.add(c.label);
            result.add(c);
          }
        }
      } else {
        _storeWords(ch, wordRE, result, seen, ignoreAt - pos);
      }
      pos += ch.length + 1;
    }
  } else {
    _storeWords(doc, wordRE, result, seen, ignoreAt);
  }

  if (big && result.length < _maxList) cache[doc] = result;
  return result;
}

CompletionResult? completeAnyWord(CompletionContext context) {
  final wordChars = context.state.languageDataAt<String>('wordChars', context.pos).join('');
  final re = _wordRE(wordChars);
  final token = context.matchBefore(_mapRE(re, (s) => '$s\$'));
  if (token == null && !context.explicit) return null;
  final from = token?.from ?? context.pos;
  final options = _collectWords(
    context.state.doc,
    _wordCache(wordChars),
    re,
    _range,
    from,
  );
  return CompletionResult(
    from: from,
    options: options,
    validFor: _mapRE(re, (s) => '^$s'),
  );
}
