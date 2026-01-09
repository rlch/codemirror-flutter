/// Core language support for CodeMirror.
///
/// This module provides the infrastructure for language-aware editing,
/// including syntax parsing, syntax tree access, and language metadata.
library;

import 'dart:async';

import 'package:lezer/lezer.dart' hide ChangedRange;
import 'package:lezer/lezer.dart' as lezer show ChangedRange;
import 'package:meta/meta.dart';

import '../state/change.dart';
import '../state/facet.dart' hide EditorState, Transaction;
import '../state/state.dart';
import '../state/transaction.dart' hide Transaction;
import '../state/transaction.dart' as tx show Transaction;
import '../text/text.dart';
import '../view/view.dart';

// ============================================================================
// Language Data Props
// ============================================================================

/// Node prop stored in a parser's top syntax node to provide the
/// facet that stores language-specific data for that language.
final languageDataProp = NodeProp<Facet<Map<String, dynamic>, List<Map<String, dynamic>>>>(
  deserialize: (_) => throw UnsupportedError('Cannot deserialize languageDataProp'),
);

/// Node prop used to register sublanguages. Should be added to
/// the top level node type for the language.
final sublanguageProp = NodeProp<List<Sublanguage>>(
  deserialize: (_) => throw UnsupportedError('Cannot deserialize sublanguageProp'),
);

/// Helper function to define a facet (to be added to the top syntax
/// node(s) for a language via [languageDataProp]), that will be
/// used to associate language data with the language.
///
/// You probably only need this when subclassing [Language].
Facet<Map<String, dynamic>, List<Map<String, dynamic>>> defineLanguageFacet([
  Map<String, dynamic>? baseData,
]) {
  return Facet.define(
    FacetConfig(
      combine: baseData != null
          ? (values) => [...values, baseData]
          : null,
    ),
  );
}

// ============================================================================
// Sublanguage
// ============================================================================

/// Some languages need to return different language data for some parts
/// of their tree. Sublanguages, registered by adding a node prop to the
/// language's top syntax node, provide a mechanism to do this.
///
/// Note that when using nested parsing, where nested syntax is parsed by
/// a different parser and has its own top node type, you don't need a
/// sublanguage.
class Sublanguage {
  /// Determines whether the data provided by this sublanguage should
  /// completely replace the regular data or be added to it (with
  /// higher-precedence).
  final SublanguageType type;

  /// A predicate that returns whether the node at the queried
  /// position is part of the sublanguage.
  final bool Function(SyntaxNode node, EditorState state) test;

  /// The language data facet that holds the sublanguage's data.
  ///
  /// You'll want to use [defineLanguageFacet] to create this.
  final Facet<Map<String, dynamic>, List<Map<String, dynamic>>> facet;

  const Sublanguage({
    this.type = SublanguageType.extend,
    required this.test,
    required this.facet,
  });
}

/// Type of sublanguage data handling.
enum SublanguageType {
  /// Replace the parent language's data entirely.
  replace,
  /// Extend the parent language's data (higher precedence).
  extend,
}

// ============================================================================
// Work Constants
// ============================================================================

/// Work budget constants for parsing.
// ignore: unused_element
class _Work {
  _Work._();

  /// Milliseconds of work time to perform immediately for a state doc change.
  static const int apply = 20;

  // ignore: unused_field
  /// Minimum amount of work time to perform in an idle callback.
  static const int minSlice = 25;

  /// Amount of work time to perform in pseudo-thread when idle callbacks
  /// aren't supported.
  static const int slice = 100;

  /// Minimum pause between pseudo-thread slices.
  static const int minPause = 100;

  // ignore: unused_field
  /// Maximum pause (timeout) for the pseudo-thread.
  static const int maxPause = 500;

  /// Parse time budgets are assigned per chunk—the parser can run for
  /// ChunkBudget milliseconds at most during ChunkTime milliseconds.
  static const int chunkBudget = 3000;
  static const int chunkTime = 30000;

  /// For every change the editor receives while focused, it gets a
  /// small bonus to its parsing budget.
  static const int changeBonus = 50;

  /// Don't eagerly parse this far beyond the end of the viewport.
  static const int maxParseAhead = 100000;

  /// When initializing the state field (before viewport info is
  /// available), pretend the viewport goes from 0 to here.
  static const int initViewport = 3000;
}

// ============================================================================
// Language Class
// ============================================================================

/// A language object manages parsing and per-language metadata.
///
/// Parse data is managed as a Lezer tree. The class can be used directly,
/// via the [LRLanguage] subclass for Lezer LR parsers, or via a
/// StreamLanguage subclass for stream parsers.
class Language {
  /// The language data facet used for this language.
  final Facet<Map<String, dynamic>, List<Map<String, dynamic>>> data;

  /// The parser object. Can be useful when using this as a nested parser.
  Parser parser;

  /// A language name.
  final String name;

  /// The extension value to install this as the document language.
  late final Extension extension;

  /// Construct a language object.
  ///
  /// If you need to invoke this directly, first define a data facet with
  /// [defineLanguageFacet], and then configure your parser to attach it
  /// to the language's outer syntax node.
  Language(
    this.data,
    this.parser, {
    List<Extension>? extraExtensions,
    this.name = '',
  }) {
    extension = ExtensionList([
      language.of(this),
      EditorState.languageData_.of((state, pos, side) {
        final top = _topNodeAt(state, pos, side);
        final langData = top.type.prop(languageDataProp);
        if (langData == null) return [];
        final base = state.facet(langData);
        final sub = top.type.prop(sublanguageProp);
        if (sub != null) {
          final innerNode = top.resolve(pos - top.from, side);
          for (final sublang in sub) {
            if (sublang.test(innerNode, state)) {
              final subData = state.facet(sublang.facet);
              return sublang.type == SublanguageType.replace
                  ? subData
                  : [...subData, ...base];
            }
          }
        }
        return base;
      }),
      if (extraExtensions != null) ...extraExtensions,
    ]);
  }

  /// Query whether this language is active at the given position.
  bool isActiveAt(EditorState state, int pos, [int side = -1]) {
    return _topNodeAt(state, pos, side).type.prop(languageDataProp) == data;
  }

  /// Find the document regions that were parsed using this language.
  ///
  /// The returned regions will _include_ any nested languages rooted
  /// in this language, when those exist.
  List<({int from, int to})> findRegions(EditorState state) {
    final lang = state.facet(language);
    if (lang?.data == data) {
      return [(from: 0, to: state.doc.length)];
    }
    if (lang == null || !lang.allowsNesting) return [];

    final result = <({int from, int to})>[];

    void explore(Tree tree, int from) {
      if (tree.prop(languageDataProp) == data) {
        result.add((from: from, to: from + tree.length));
        return;
      }
      final mount = tree.prop(NodeProp.mounted);
      if (mount != null) {
        if (mount.tree.prop(languageDataProp) == data) {
          if (mount.overlay != null) {
            for (final r in mount.overlay!) {
              result.add((from: r.from + from, to: r.to + from));
            }
          } else {
            result.add((from: from, to: from + tree.length));
          }
          return;
        } else if (mount.overlay != null) {
          final size = result.length;
          explore(mount.tree, mount.overlay![0].from + from);
          if (result.length > size) return;
        }
      }
      for (var i = 0; i < tree.children.length; i++) {
        final ch = tree.children[i];
        if (ch is Tree) {
          explore(ch, tree.positions[i] + from);
        }
      }
    }

    explore(syntaxTree(state), 0);
    return result;
  }

  /// Indicates whether this language allows nested languages.
  bool get allowsNesting => true;

  /// Internal state field for language state.
  @internal
  static late final StateField<LanguageState> state;

  /// Internal state effect for setting language state.
  @internal
  static late final StateEffectType<LanguageState> setState;
}

/// Get the top node at a position, traversing into nested languages if needed.
SyntaxNode _topNodeAt(EditorState state, int pos, int side) {
  final topLang = state.facet(language);
  var tree = syntaxTree(state).topNode;
  if (topLang == null || topLang.allowsNesting) {
    for (SyntaxNode? node = tree; node != null; node = node.enter(pos, side, mode: IterMode.excludeBuffers)) {
      if (node.type.isTop) tree = node;
    }
  }
  return tree;
}

// ============================================================================
// LRLanguage Class
// ============================================================================

/// A subclass of [Language] for use with Lezer LR parsers.
class LRLanguage extends Language {
  LRLanguage._(
    Facet<Map<String, dynamic>, List<Map<String, dynamic>>> data,
    LRParserImpl parser, {
    String? name,
  }) : super(data, parser, name: name ?? '');

  @override
  LRParserImpl get parser => super.parser as LRParserImpl;

  /// Define a language from a parser.
  static LRLanguage define({
    String? name,
    required LRParserImpl parser,
    Map<String, dynamic>? languageData,
  }) {
    final data = defineLanguageFacet(languageData);
    return LRLanguage._(
      data,
      parser.configure(
        ParserConfig(
          props: [
            languageDataProp.add((type) => type.isTop ? data : null),
          ],
        ),
      ),
      name: name,
    );
  }

  /// Create a new instance of this language with a reconfigured
  /// version of its parser and optionally a new name.
  LRLanguage configure(ParserConfig options, [String? newName]) {
    return LRLanguage._(data, parser.configure(options), name: newName ?? name);
  }

  @override
  bool get allowsNesting => parser.hasWrappers();
}

// ============================================================================
// Syntax Tree Access Functions
// ============================================================================

/// Get the syntax tree for a state, which is the current (possibly
/// incomplete) parse tree of the active language, or the empty tree
/// if there is no language available.
Tree syntaxTree(EditorState state) {
  final field = state.field(Language.state, false);
  return field?.tree ?? Tree.empty;
}

/// Try to get a parse tree that spans at least up to [upto].
///
/// The method will do at most [timeout] milliseconds of work to parse
/// up to that point if the tree isn't already available.
Tree? ensureSyntaxTree(EditorState state, int upto, [int timeout = 50]) {
  final parse = state.field(Language.state, false)?.context;
  if (parse == null) return null;

  final oldViewport = parse.viewport;
  parse.updateViewport((from: 0, to: upto));
  final result = parse.isDone(upto) || parse.work(timeout, upto) ? parse.tree : null;
  parse.updateViewport(oldViewport);
  return result;
}

/// Queries whether there is a full syntax tree available up to the
/// given document position.
///
/// If there isn't, the background parse process _might_ still be working
/// and update the tree further, but there is no guarantee of that—the
/// parser will stop working when it has spent a certain amount of time
/// or has moved beyond the visible viewport.
///
/// Always returns false if no language has been enabled.
bool syntaxTreeAvailable(EditorState state, [int? upto]) {
  return state.field(Language.state, false)?.context.isDone(upto ?? state.doc.length) ?? false;
}

/// Move parsing forward, and update the editor state afterwards to
/// reflect the new tree.
///
/// Will work for at most [timeout] milliseconds. Returns true if the
/// parser managed to get to the given position in that time.
bool forceParsing(EditorViewState view, [int? upto, int timeout = 100]) {
  final viewportTo = view.viewState.viewport.to;
  final success = ensureSyntaxTree(view.state, upto ?? viewportTo, timeout);
  if (success != syntaxTree(view.state)) {
    view.dispatch([const TransactionSpec()]);
  }
  return success != null;
}

/// Tells you whether the language parser is planning to do more
/// parsing work (in a requestIdleCallback pseudo-thread) or has
/// stopped running, either because it parsed the entire document,
/// because it spent too much time and was cut off, or because there
/// is no language parser enabled.
bool syntaxParserRunning(EditorViewState view) {
  // Check if parse worker plugin is running
  // This would need to look up the parse worker plugin instance
  return false; // Simplified implementation
}

// ============================================================================
// DocInput - Input adapter for Text documents
// ============================================================================

/// Lezer-style Input object for a Text document.
class DocInput implements Input {
  /// The document being read.
  final Text doc;

  TextIterator? _cursor;
  int _cursorPos = 0;
  String _string = '';

  /// Create an input object for the given document.
  DocInput(this.doc);

  @override
  int get length => doc.length;

  @override
  bool get lineChunks => true;

  int _syncTo(int pos) {
    _cursor ??= doc.iter();
    _cursor!.next(pos - _cursorPos);
    _string = _cursor!.value;
    _cursorPos = pos + _string.length;
    return _cursorPos - _string.length;
  }

  @override
  String chunk(int pos) {
    _syncTo(pos);
    return _string;
  }

  @override
  String read(int from, int to) {
    final stringStart = _cursorPos - _string.length;
    if (from < stringStart || to >= _cursorPos) {
      return doc.sliceString(from, to);
    } else {
      return _string.substring(from - stringStart, to - stringStart);
    }
  }
}

// ============================================================================
// ParseContext
// ============================================================================

/// Global reference to the current parse context.
ParseContext? _currentContext;

/// A parse context provided to parsers working on the editor content.
class ParseContext {
  final Parser _parser;

  /// The current editor state.
  final EditorState state;

  /// Tree fragments that can be reused by incremental re-parses.
  List<TreeFragment> fragments;

  /// The current syntax tree.
  Tree tree;

  /// Length of the tree that has been parsed.
  int treeLen;

  /// The current editor viewport (or some overapproximation thereof).
  ({int from, int to}) viewport;

  /// Regions that were skipped during parsing.
  List<({int from, int to})> skipped;

  /// Promise that, when resolved, will schedule a new parse.
  Future<void>? scheduleOn;

  PartialParse? _parse;

  /// Temporarily skipped regions.
  @internal
  List<({int from, int to})> tempSkipped = [];

  ParseContext._({
    required Parser parser,
    required this.state,
    required this.fragments,
    required this.tree,
    required this.treeLen,
    required this.viewport,
    required this.skipped,
    this.scheduleOn,
  }) : _parser = parser;

  /// Create a new parse context.
  @internal
  static ParseContext create(
    Parser parser,
    EditorState state,
    ({int from, int to}) viewport,
  ) {
    return ParseContext._(
      parser: parser,
      state: state,
      fragments: [],
      tree: Tree.empty,
      treeLen: 0,
      viewport: viewport,
      skipped: [],
    );
  }

  PartialParse _startParse() {
    return _parser.startParse(DocInput(state.doc), fragments);
  }

  /// Perform parsing work.
  @internal
  bool work(Object /* int | bool Function() */ until, [int? upto]) {
    if (upto != null && upto >= state.doc.length) upto = null;
    if (tree != Tree.empty && isDone(upto ?? state.doc.length)) {
      takeTree();
      return true;
    }
    return _withContext(() {
      bool Function() deadline;
      if (until is int) {
        final endTime = DateTime.now().millisecondsSinceEpoch + until;
        deadline = () => DateTime.now().millisecondsSinceEpoch > endTime;
      } else {
        deadline = until as bool Function();
      }

      _parse ??= _startParse();
      if (upto != null &&
          (_parse!.stoppedAt == null || _parse!.stoppedAt! > upto) &&
          upto < state.doc.length) {
        _parse!.stopAt(upto);
      }

      while (true) {
        final done = _parse!.advance();
        if (done != null) {
          fragments = _withoutTempSkipped(
            TreeFragment.addTree(done, fragments, _parse!.stoppedAt != null),
          );
          treeLen = _parse!.stoppedAt ?? state.doc.length;
          tree = done;
          _parse = null;
          if (treeLen < (upto ?? state.doc.length)) {
            _parse = _startParse();
          } else {
            return true;
          }
        }
        if (deadline()) {
          return false;
        }
      }
    });
  }

  /// Take the current partial tree.
  @internal
  void takeTree() {
    int pos;
    Tree? parsedTree;
    if (_parse != null && (pos = _parse!.parsedPos) >= treeLen) {
      if (_parse!.stoppedAt == null || _parse!.stoppedAt! > pos) {
        _parse!.stopAt(pos);
      }
      _withContext(() {
        while ((parsedTree = _parse!.advance()) == null) {}
      });
      treeLen = pos;
      tree = parsedTree!;
      fragments = _withoutTempSkipped(TreeFragment.addTree(tree, fragments, true));
      _parse = null;
    }
  }

  T _withContext<T>(T Function() f) {
    final prev = _currentContext;
    _currentContext = this;
    try {
      return f();
    } finally {
      _currentContext = prev;
    }
  }

  List<TreeFragment> _withoutTempSkipped(List<TreeFragment> fragments) {
    for (var r = tempSkipped.isNotEmpty ? tempSkipped.removeLast() : null;
        r != null;
        r = tempSkipped.isNotEmpty ? tempSkipped.removeLast() : null) {
      fragments = _cutFragments(fragments, r.from, r.to);
    }
    return fragments;
  }

  /// Apply changes to create a new context.
  @internal
  ParseContext changes(ChangeDesc changes, EditorState newState) {
    var newFragments = fragments;
    var newTree = tree;
    var newTreeLen = treeLen;
    var newViewport = viewport;
    var newSkipped = skipped;

    takeTree();
    if (!changes.empty) {
      final ranges = <lezer.ChangedRange>[];
      changes.iterChangedRanges((fromA, toA, fromB, toB) {
        ranges.add(lezer.ChangedRange(fromA: fromA, toA: toA, fromB: fromB, toB: toB));
      });
      newFragments = TreeFragment.applyChanges(newFragments, ranges);
      newTree = Tree.empty;
      newTreeLen = 0;
      newViewport = (
        from: changes.mapPos(newViewport.from, -1) ?? 0,
        to: changes.mapPos(newViewport.to, 1) ?? newState.doc.length,
      );
      if (skipped.isNotEmpty) {
        newSkipped = [];
        for (final r in skipped) {
          final from = changes.mapPos(r.from, 1) ?? 0;
          final to = changes.mapPos(r.to, -1) ?? newState.doc.length;
          if (from < to) newSkipped.add((from: from, to: to));
        }
      }
    }
    return ParseContext._(
      parser: _parser,
      state: newState,
      fragments: newFragments,
      tree: newTree,
      treeLen: newTreeLen,
      viewport: newViewport,
      skipped: newSkipped,
      scheduleOn: scheduleOn,
    );
  }

  /// Update the viewport.
  @internal
  bool updateViewport(({int from, int to}) newViewport) {
    if (viewport.from == newViewport.from && viewport.to == newViewport.to) {
      return false;
    }
    viewport = newViewport;
    final startLen = skipped.length;
    for (var i = 0; i < skipped.length; i++) {
      final r = skipped[i];
      if (r.from < newViewport.to && r.to > newViewport.from) {
        fragments = _cutFragments(fragments, r.from, r.to);
        skipped.removeAt(i);
        i--;
      }
    }
    if (skipped.length >= startLen) return false;
    reset();
    return true;
  }

  /// Reset the parse state.
  @internal
  void reset() {
    if (_parse != null) {
      takeTree();
      _parse = null;
    }
  }

  /// Notify the parse scheduler that the given region was skipped
  /// because it wasn't in view, and the parse should be restarted
  /// when it comes into view.
  void skipUntilInView(int from, int to) {
    skipped.add((from: from, to: to));
  }

  /// Returns a parser intended to be used as placeholder when
  /// asynchronously loading a nested parser.
  ///
  /// It'll skip its input and mark it as not-really-parsed, so that
  /// the next update will parse it again.
  ///
  /// When [until] is given, a reparse will be scheduled when that
  /// future completes.
  static Parser getSkippingParser([Future<void>? until]) {
    return _SkippingParser(until);
  }

  /// Check if parsing is done up to a position.
  @internal
  bool isDone(int upto) {
    upto = upto < state.doc.length ? upto : state.doc.length;
    return treeLen >= upto &&
        fragments.isNotEmpty &&
        fragments[0].from == 0 &&
        fragments[0].to >= upto;
  }

  /// Get the context for the current parse, or null if no editor
  /// parse is in progress.
  static ParseContext? get() => _currentContext;
}

/// Cut fragments at a range.
List<TreeFragment> _cutFragments(
  List<TreeFragment> fragments,
  int from,
  int to,
) {
  return TreeFragment.applyChanges(
    fragments,
    [lezer.ChangedRange(fromA: from, toA: to, fromB: from, toB: to)],
  );
}

/// A parser that skips its input.
class _SkippingParser extends Parser {
  final Future<void>? _until;

  _SkippingParser(this._until);

  @override
  PartialParse createParse(
    Input input,
    List<TreeFragment> fragments,
    List<Range> ranges,
  ) {
    final from = ranges[0].from;
    final to = ranges[ranges.length - 1].to;
    return _SkippingPartialParse(from, to, _until);
  }
}

class _SkippingPartialParse implements PartialParse {
  final int _from;
  final int _to;
  final Future<void>? _until;

  @override
  int parsedPos;

  @override
  int? stoppedAt;

  _SkippingPartialParse(this._from, this._to, this._until) : parsedPos = _from;

  @override
  Tree? advance() {
    final cx = _currentContext;
    if (cx != null) {
      cx.tempSkipped.add((from: _from, to: _to));
      if (_until != null) {
        cx.scheduleOn = cx.scheduleOn != null
            ? Future.wait([cx.scheduleOn!, _until])
            : _until;
      }
    }
    parsedPos = _to;
    return Tree(NodeType.none, [], [], _to - _from);
  }

  @override
  void stopAt(int pos) {
    stoppedAt = pos;
  }
}

// ============================================================================
// LanguageState
// ============================================================================

/// Internal state for tracking language parsing.
class LanguageState {
  /// The current syntax tree.
  final Tree tree;

  /// The parse context.
  final ParseContext context;

  LanguageState._(this.context) : tree = context.tree;

  /// Apply a transaction.
  @internal
  LanguageState apply(tx.Transaction tr) {
    if (!tr.docChanged && tree == context.tree) return this;
    final newCx = context.changes(tr.changes, tr.state as EditorState);
    // If the previous parse wasn't done, go forward only up to its
    // end position or the end of the viewport
    final upto = context.treeLen == (tr.startState as EditorState).doc.length
        ? null
        : (context.treeLen > newCx.viewport.to
            ? context.treeLen
            : newCx.viewport.to);
    if (!newCx.work(_Work.apply, upto)) newCx.takeTree();
    return LanguageState._(newCx);
  }

  /// Create initial state.
  @internal
  static LanguageState init(EditorState state) {
    final vpTo = _Work.initViewport < state.doc.length
        ? _Work.initViewport
        : state.doc.length;
    final parseState = ParseContext.create(
      state.facet(language)!.parser,
      state,
      (from: 0, to: vpTo),
    );
    if (!parseState.work(_Work.apply, vpTo)) parseState.takeTree();
    return LanguageState._(parseState);
  }
}

// ============================================================================
// Language Facet and State Field
// ============================================================================

/// The facet used to associate a language with an editor state.
///
/// Used by [Language] object's `extension` property (so you don't need
/// to manually wrap your languages in this). Can be used to access the
/// current language on a state.
Facet<Language, Language?> get language {
  _ensureInitialized();
  return _language!;
}

Facet<Language, Language?>? _language;

bool _initialized = false;

void _ensureInitialized() {
  if (_initialized) return;
  _initialized = true;
  
  // Initialize static members
  Language.setState = StateEffect.define<LanguageState>();

  Language.state = StateField.define(
    StateFieldConfig(
      create: (state) => LanguageState.init(state as EditorState),
      update: (value, tr) {
        final transaction = tr as tx.Transaction;
        for (final e in transaction.effects) {
          if (e.is_(Language.setState)) {
            return e.value as LanguageState;
          }
        }
        if ((transaction.startState as EditorState).facet(_language!) !=
            (transaction.state as EditorState).facet(_language!)) {
          return LanguageState.init(transaction.state as EditorState);
        }
        return value.apply(transaction);
      },
    ),
  );
  
  _language = Facet.define(
    FacetConfig(
      combine: (languages) => languages.isNotEmpty ? languages[0] : null,
      enables: (lang) => ExtensionList([
        Language.state,
        _parseWorker,
      ]),
    ),
  );
}

/// Ensure language module is initialized.
void ensureLanguageInitialized() {
  _ensureInitialized();
}

// ============================================================================
// Parse Worker Plugin
// ============================================================================

/// The parse worker plugin that manages background parsing.
final ViewPlugin<_ParseWorker> _parseWorker = ViewPlugin.define(
  (view) => _ParseWorker(view),
  ViewPluginSpec(
    eventHandlers: {
      'focus': (_, view) {
        // Try to get the plugin and schedule work
        return false;
      },
    },
  ),
);

/// Parse worker that runs parsing in the background.
class _ParseWorker extends PluginValue {
  final EditorViewState view;

  Timer? _working;
  int _workScheduled = 0;
  int _chunkEnd = -1;
  int _chunkBudget = -1;

  _ParseWorker(this.view) {
    _scheduleWork();
  }

  @override
  void update(ViewUpdate update) {
    final cx = update.state.field(Language.state, false)?.context;
    if (cx != null) {
      // Use the view stored in this plugin instance
      final vp = view.viewState.viewport;
      final vpRecord = (from: vp.from, to: vp.to);
      if (cx.updateViewport(vpRecord) || vp.to > cx.treeLen) {
        _scheduleWork();
      }
    }
    if (update.docChanged || update.selectionSet) {
      // Use the view stored in this plugin instance
      if (view.hasFocus) _chunkBudget += _Work.changeBonus;
      _scheduleWork();
    }
    final langState = update.state.field(Language.state, false);
    if (langState != null) {
      _checkAsyncSchedule(langState.context);
    }
  }

  void _scheduleWork() {
    if (_working != null) return;
    final field = view.state.field(Language.state, false);
    if (field == null) return;
    if (field.tree != field.context.tree ||
        !field.context.isDone(view.state.doc.length)) {
      _working = Timer(Duration(milliseconds: _Work.minPause), _work);
    }
  }

  void _work() {
    _working = null;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_chunkEnd < now && (_chunkEnd < 0 || view.hasFocus)) {
      _chunkEnd = now + _Work.chunkTime;
      _chunkBudget = _Work.chunkBudget;
    }
    if (_chunkBudget <= 0) return;

    final vp = view.viewState.viewport;
    final vpTo = vp.to;
    final field = view.state.field(Language.state, false);
    if (field == null) return;
    if (field.tree == field.context.tree &&
        field.context.isDone(vpTo + _Work.maxParseAhead)) {
      return;
    }

    final endTime = now + (_chunkBudget < _Work.slice ? _chunkBudget : _Work.slice);
    final viewportFirst = field.context.treeLen < vpTo &&
        view.state.doc.length > vpTo + 1000;
    final done = field.context.work(
      () => DateTime.now().millisecondsSinceEpoch > endTime,
      vpTo + (viewportFirst ? 0 : _Work.maxParseAhead),
    );

    _chunkBudget -= DateTime.now().millisecondsSinceEpoch - now;
    if (done || _chunkBudget <= 0) {
      field.context.takeTree();
      view.dispatch([
        TransactionSpec(
          effects: [Language.setState.of(LanguageState._(field.context))],
        ),
      ]);
    }
    if (_chunkBudget > 0 && !(done && !viewportFirst)) _scheduleWork();
    _checkAsyncSchedule(field.context);
  }

  void _checkAsyncSchedule(ParseContext cx) {
    if (cx.scheduleOn != null) {
      _workScheduled++;
      cx.scheduleOn!.then((_) {
        _scheduleWork();
      }).catchError((error) {
        logException(view.state, error);
      }).whenComplete(() {
        _workScheduled--;
      });
      cx.scheduleOn = null;
    }
  }

  @override
  void destroy(dynamic view) {
    _working?.cancel();
  }

  /// Check if the worker is currently running.
  bool isWorking() => _working != null || _workScheduled > 0;
}

// ============================================================================
// LanguageSupport
// ============================================================================

/// This class bundles a [Language] with an optional set of supporting
/// extensions.
///
/// Language packages are encouraged to export a function that optionally
/// takes a configuration object and returns a LanguageSupport instance,
/// as the main way for client code to use the package.
class LanguageSupport implements ExtensionProvider {
  /// The language object.
  final Language language;

  /// An optional set of supporting extensions.
  ///
  /// When nesting a language in another language, the outer language is
  /// encouraged to include the supporting extensions for its inner
  /// languages in its own set of support extensions.
  final Extension support;

  /// An extension including both the language and its support
  /// extensions.
  @override
  late final Extension extension;

  /// Create a language support object.
  LanguageSupport(this.language, [this.support = const ExtensionList([])]) {
    extension = ExtensionList([language.extension, support]);
  }
}

// ============================================================================
// LanguageDescription
// ============================================================================

/// Language descriptions are used to store metadata about languages
/// and to dynamically load them.
///
/// Their main role is finding the appropriate language for a filename
/// or dynamically loading nested parsers.
class LanguageDescription {
  /// The name of this language.
  final String name;

  /// Alternative names for the mode (lowercased, includes [name]).
  final List<String> alias;

  /// File extensions associated with this language.
  final List<String> extensions;

  /// Optional filename pattern that should be associated with this language.
  final RegExp? filename;

  final Future<LanguageSupport> Function() _loadFunc;

  Future<LanguageSupport>? _loading;

  /// If the language has been loaded, this will hold its value.
  LanguageSupport? support;

  LanguageDescription._({
    required this.name,
    required this.alias,
    required this.extensions,
    this.filename,
    required Future<LanguageSupport> Function() loadFunc,
    this.support,
  }) : _loadFunc = loadFunc;

  /// Start loading the language.
  ///
  /// Will return a future that resolves to a [LanguageSupport] object
  /// when the language successfully loads.
  Future<LanguageSupport> load() {
    return _loading ??= _loadFunc().then((loaded) {
      support = loaded;
      return loaded;
    }).catchError((error) {
      _loading = null;
      throw error;
    });
  }

  /// Create a language description.
  static LanguageDescription of({
    required String name,
    List<String>? alias,
    List<String>? extensions,
    RegExp? filename,
    Future<LanguageSupport> Function()? load,
    LanguageSupport? support,
  }) {
    if (load == null && support == null) {
      throw RangeError("Must pass either 'load' or 'support' to LanguageDescription.of");
    }
    load ??= () => Future.value(support);
    return LanguageDescription._(
      name: name,
      alias: [...(alias ?? <String>[]), name].map((s) => s.toLowerCase()).toList(),
      extensions: extensions ?? [],
      filename: filename,
      loadFunc: load,
      support: support,
    );
  }

  /// Look for a language in the given list of descriptions that
  /// matches the filename.
  ///
  /// Will first match [filename] patterns, and then [extensions],
  /// and return the first language that matches.
  static LanguageDescription? matchFilename(
    List<LanguageDescription> descs,
    String filename,
  ) {
    for (final d in descs) {
      if (d.filename != null && d.filename!.hasMatch(filename)) return d;
    }
    final ext = RegExp(r'\.([^.]+)$').firstMatch(filename);
    if (ext != null) {
      for (final d in descs) {
        if (d.extensions.contains(ext.group(1))) return d;
      }
    }
    return null;
  }

  /// Look for a language whose name or alias matches the given
  /// name (case-insensitively).
  ///
  /// If [fuzzy] is true, and no direct match is found, this'll also
  /// search for a language whose name or alias occurs in the string
  /// (for names shorter than three characters, only when surrounded
  /// by non-word characters).
  static LanguageDescription? matchLanguageName(
    List<LanguageDescription> descs,
    String name, [
    bool fuzzy = true,
  ]) {
    name = name.toLowerCase();
    for (final d in descs) {
      if (d.alias.any((a) => a == name)) return d;
    }
    if (fuzzy) {
      for (final d in descs) {
        for (final a in d.alias) {
          final found = name.indexOf(a);
          if (found > -1 &&
              (a.length > 2 ||
                  (!RegExp(r'\w').hasMatch(found > 0 ? name[found - 1] : '') &&
                      !RegExp(r'\w')
                          .hasMatch(found + a.length < name.length ? name[found + a.length] : '')))) {
            return d;
          }
        }
      }
    }
    return null;
  }
}