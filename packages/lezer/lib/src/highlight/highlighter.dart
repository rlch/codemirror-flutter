/// Highlighter interface for mapping tags to styles.
///
/// This module provides the [Highlighter] interface and [tagHighlighter]
/// function for creating highlighters from tag/class pairs.
library;

import '../common/node_type.dart';
import 'tag.dart';

/// A highlighter defines a mapping from highlighting tags and language
/// scopes to CSS class names.
///
/// They are usually defined via [tagHighlighter] or some wrapper around
/// that, but it is also possible to implement them from scratch.
abstract class Highlighter {
  /// Get the set of classes that should be applied to the given set of
  /// highlighting tags, or null if this highlighter doesn't assign a
  /// style to the tags.
  String? style(List<Tag> tags);

  /// When given, the highlighter will only be applied to trees on whose
  /// top node this predicate returns true.
  bool Function(NodeType)? get scope;
}

/// A simple highlighter implementation.
class _SimpleHighlighter implements Highlighter {
  final Map<int, String> _map;
  final String? _all;
  @override
  final bool Function(NodeType)? scope;

  _SimpleHighlighter(this._map, this._all, this.scope);

  @override
  String? style(List<Tag> tags) {
    String? cls = _all;
    for (final tag in tags) {
      for (final sub in tag.set) {
        final tagClass = _map[sub.id];
        if (tagClass != null) {
          cls = cls != null ? '$cls $tagClass' : tagClass;
          break;
        }
      }
    }
    return cls;
  }
}

/// A tag style spec for [tagHighlighter].
class TagStyle {
  /// The tag or tags to target.
  final Object /* Tag | List<Tag> */ tag;

  /// The CSS class to apply.
  final String class_;

  const TagStyle({required this.tag, required String className})
      : class_ = className;
}

/// Define a highlighter from an array of tag/class pairs.
///
/// Classes associated with more specific tags will take precedence.
Highlighter tagHighlighter(
  List<TagStyle> tags, {
  bool Function(NodeType)? scope,
  String? all,
}) {
  final map = <int, String>{};
  for (final style in tags) {
    if (style.tag is List<Tag>) {
      for (final tag in style.tag as List<Tag>) {
        map[tag.id] = style.class_;
      }
    } else {
      map[(style.tag as Tag).id] = style.class_;
    }
  }
  return _SimpleHighlighter(map, all, scope);
}
