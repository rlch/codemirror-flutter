/// Attribute handling utilities for decorations.
///
/// This module provides helper functions for working with HTML-like
/// attributes on decoration elements. In Flutter, these are used to
/// merge styling properties from multiple sources.
library;

/// Map of attribute name to value.
///
/// Used for decoration styling attributes like 'class', 'style', etc.
typedef Attrs = Map<String, String>;

/// Empty attributes constant.
const Attrs emptyAttrs = <String, String>{};

/// Combine source attributes into target, merging class and style values.
///
/// When both source and target have a 'class' attribute, they are combined
/// with a space. When both have a 'style' attribute, they are combined
/// with a semicolon. Other attributes from source override target.
///
/// Returns the modified target map.
///
/// ```dart
/// final target = {'class': 'foo', 'id': 'bar'};
/// combineAttrs({'class': 'baz', 'data-x': '1'}, target);
/// // Result: {'class': 'foo baz', 'id': 'bar', 'data-x': '1'}
/// ```
Attrs combineAttrs(Attrs source, Attrs target) {
  for (final entry in source.entries) {
    final name = entry.key;
    final value = entry.value;

    if (name == 'class' && target.containsKey('class')) {
      target['class'] = '${target['class']} $value';
    } else if (name == 'style' && target.containsKey('style')) {
      target['style'] = '${target['style']};$value';
    } else {
      target[name] = value;
    }
  }
  return target;
}

/// Compare two attribute maps for equality.
///
/// Returns true if both maps have the same keys and values, optionally
/// ignoring a specific key.
///
/// ```dart
/// attrsEq({'a': '1', 'b': '2'}, {'a': '1', 'b': '2'}); // true
/// attrsEq({'a': '1', 'class': 'x'}, {'a': '1', 'class': 'y'}, 'class'); // true
/// ```
bool attrsEq(Attrs? a, Attrs? b, [String? ignore]) {
  if (identical(a, b)) return true;

  a ??= emptyAttrs;
  b ??= emptyAttrs;

  // Count keys excluding the ignored one
  final aKeyCount = ignore != null && a.containsKey(ignore)
      ? a.length - 1
      : a.length;
  final bKeyCount = ignore != null && b.containsKey(ignore)
      ? b.length - 1
      : b.length;

  if (aKeyCount != bKeyCount) return false;

  for (final key in a.keys) {
    if (key == ignore) continue;
    if (!b.containsKey(key) || a[key] != b[key]) return false;
  }

  return true;
}

/// Parse a class string into a set of class names.
///
/// ```dart
/// parseClasses('foo bar baz'); // {'foo', 'bar', 'baz'}
/// ```
Set<String> parseClasses(String classes) {
  return classes.split(RegExp(r'\s+')).where((c) => c.isNotEmpty).toSet();
}

/// Join a set of class names into a class string.
///
/// ```dart
/// joinClasses({'foo', 'bar', 'baz'}); // 'foo bar baz'
/// ```
String joinClasses(Set<String> classes) {
  return classes.join(' ');
}

/// Merge two class strings, deduplicating.
///
/// ```dart
/// mergeClasses('foo bar', 'bar baz'); // 'foo bar baz'
/// ```
String mergeClasses(String a, String b) {
  final classes = parseClasses(a);
  classes.addAll(parseClasses(b));
  return joinClasses(classes);
}

/// Check if a class string contains a specific class.
///
/// ```dart
/// hasClass('foo bar baz', 'bar'); // true
/// ```
bool hasClass(String classes, String className) {
  return parseClasses(classes).contains(className);
}

/// Add a class to a class string if not already present.
///
/// ```dart
/// addClass('foo bar', 'baz'); // 'foo bar baz'
/// addClass('foo bar', 'foo'); // 'foo bar'
/// ```
String addClass(String classes, String className) {
  final set = parseClasses(classes);
  if (!set.contains(className)) {
    set.add(className);
  }
  return joinClasses(set);
}

/// Remove a class from a class string.
///
/// ```dart
/// removeClass('foo bar baz', 'bar'); // 'foo baz'
/// ```
String removeClass(String classes, String className) {
  final set = parseClasses(classes);
  set.remove(className);
  return joinClasses(set);
}

/// Toggle a class in a class string.
///
/// ```dart
/// toggleClass('foo bar', 'bar'); // 'foo'
/// toggleClass('foo', 'bar'); // 'foo bar'
/// ```
String toggleClass(String classes, String className) {
  final set = parseClasses(classes);
  if (set.contains(className)) {
    set.remove(className);
  } else {
    set.add(className);
  }
  return joinClasses(set);
}
