/// Syntax highlighting tags.
///
/// This module provides the [Tag] class for defining highlighting categories.
library;

/// Global ID counter for tags.
int _nextTagID = 0;

/// Global ID counter for modifiers.
int _nextModifierID = 0;

/// A highlighting tag that denotes a highlighting category.
///
/// Tags are associated with parts of a syntax tree by a language mode, and
/// then mapped to an actual CSS style by a highlighter.
///
/// CodeMirror uses a mostly _closed_ vocabulary of syntax tags (as opposed
/// to traditional open string-based systems, which make it hard for
/// highlighting themes to cover all the tokens produced by the various
/// languages).
///
/// It _is_ possible to define your own highlighting tags for system-internal
/// use, but such tags will not be picked up by regular highlighters (though
/// you can derive them from standard tags to allow highlighters to fall
/// back to those).
class Tag {
  /// Unique identifier for this tag.
  final int id = _nextTagID++;

  /// The optional name of the base tag.
  final String name;

  /// The set of this tag and all its parent tags, starting with this one
  /// itself and sorted in order of decreasing specificity.
  final List<Tag> set;

  /// The base unmodified tag that this one is based on, if it's modified.
  final Tag? base;

  /// The modifiers applied to [base].
  final List<Modifier> modified;

  Tag._(this.name, this.set, this.base, this.modified);

  @override
  String toString() {
    var result = name;
    for (final mod in modified) {
      if (mod.name != null) result = '${mod.name}($result)';
    }
    return result;
  }

  /// Define a new tag.
  ///
  /// If [parent] is given, the tag is treated as a sub-tag of that parent,
  /// and highlighters that don't mention this tag will try to fall back
  /// to the parent tag (or grandparent tag, etc).
  static Tag define([Object? nameOrParent, Tag? parent]) {
    String name;
    if (nameOrParent is String) {
      name = nameOrParent;
    } else if (nameOrParent is Tag) {
      parent = nameOrParent;
      name = '?';
    } else {
      name = '?';
    }

    if (parent?.base != null) {
      throw ArgumentError('Cannot derive from a modified tag');
    }

    final tag = Tag._(name, [], null, []);
    tag.set.add(tag);
    if (parent != null) {
      for (final t in parent.set) {
        tag.set.add(t);
      }
    }
    return tag;
  }

  /// Define a tag modifier.
  ///
  /// A modifier is a function that, given a tag, returns a tag that is a
  /// subtag of the original. Applying the same modifier twice returns the
  /// same value, and applying multiple modifiers in any order produces the
  /// same tag.
  ///
  /// When multiple modifiers are applied to a given base tag, each smaller
  /// set of modifiers is registered as a parent, so that for example
  /// `m1(m2(m3(t1)))` is a subtype of `m1(m2(t1))`, `m1(m3(t1))`, and so on.
  static Tag Function(Tag) defineModifier([String? name]) {
    final mod = Modifier(name);
    return (tag) {
      if (tag.modified.contains(mod)) return tag;
      return Modifier.get_(
        tag.base ?? tag,
        [...tag.modified, mod]..sort((a, b) => a.id - b.id),
      );
    };
  }
}

/// A tag modifier.
class Modifier {
  /// The name of this modifier.
  final String? name;

  /// Unique identifier.
  final int id = _nextModifierID++;

  /// Cached instances of modified tags.
  final List<Tag> instances = [];

  Modifier(this.name);

  /// Get a modified tag, caching it.
  static Tag get_(Tag base, List<Modifier> mods) {
    if (mods.isEmpty) return base;

    // Check if we already have this combination
    final exists = mods[0].instances.firstWhere(
      (t) => t.base == base && _sameArray(mods, t.modified),
      orElse: () => Tag._('', [], null, []), // Placeholder
    );
    if (exists.name.isNotEmpty || exists.set.isNotEmpty) return exists;

    // Create new modified tag
    final set = <Tag>[];
    final tag = Tag._(base.name, set, base, mods);
    for (final m in mods) {
      m.instances.add(tag);
    }

    // Build the set from all combinations of fewer modifiers
    final configs = _powerSet(mods);
    for (final parent in base.set) {
      if (parent.modified.isEmpty) {
        for (final config in configs) {
          set.add(Modifier.get_(parent, config));
        }
      }
    }

    return tag;
  }
}

/// Check if two lists are equal.
bool _sameArray<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Generate the power set of a list, sorted by decreasing length.
List<List<T>> _powerSet<T>(List<T> array) {
  var sets = <List<T>>[[]];
  for (var i = 0; i < array.length; i++) {
    final len = sets.length;
    for (var j = 0; j < len; j++) {
      sets.add([...sets[j], array[i]]);
    }
  }
  sets.sort((a, b) => b.length - a.length);
  return sets;
}
