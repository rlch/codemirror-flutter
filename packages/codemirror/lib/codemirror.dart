/// Native Dart/Flutter port of CodeMirror 6.
///
/// This library provides a high-performance code editor built from scratch
/// in Dart, following the architecture of CodeMirror 6 but using idiomatic
/// Flutter patterns.
///
/// ## Architecture
///
/// The editor is built on three main layers:
///
/// 1. **Text** - Immutable B-tree based document storage with O(log n) operations
/// 2. **State** - Immutable editor state with transaction-based updates
/// 3. **View** - Flutter widgets for rendering and input handling
///
/// ## Usage
///
/// ```dart
/// import 'package:codemirror/codemirror.dart';
///
/// // Create initial state
/// final state = EditorState.create(
///   doc: 'Hello, World!',
///   extensions: [
///     // Add extensions here
///   ],
/// );
///
/// // Use in widget
/// EditorView(
///   state: state,
///   onUpdate: (update) {
///     // Handle state updates
///   },
/// )
/// ```
library;

// Text layer
export 'src/text/text.dart';

// State layer - complete state management system
export 'src/state/state.dart';
export 'src/state/range_set.dart';
export 'src/state/transaction.dart'
    hide
        ResolvedSpec,
        asArray,
        joinRanges,
        mergeTransaction,
        resolveTransaction,
        resolveTransactionInner;
export 'src/state/selection.dart';
export 'src/state/change.dart';
export 'src/state/facet.dart'
    hide
        // Internal classes
        CompartmentInstance,
        CompartmentReconfigure,
        Configuration,
        DynamicSlot,
        FacetProvider,
        FieldInit,
        PrecExtension,
        ProviderType,
        ensureAddr,
        getAddr,
        // Abstract base - concrete is exported from state.dart
        EditorState,
        Transaction;

// View layer
export 'src/view/view.dart';

// Language layer
export 'src/language/language.dart';
export 'src/language/highlight.dart';
export 'src/language/indent.dart' hide IndentNodeIterator;
export 'src/language/matchbrackets.dart';
export 'src/language/fold.dart' hide Transaction;
export 'src/language/javascript/javascript.dart';
export 'src/language/cel/cel.dart';
export 'src/language/goto.dart';
export 'src/language/signature.dart';
export 'src/language/format.dart';
export 'src/language/rename.dart';
export 'src/language/document_highlight.dart';

// Commands & History
export 'src/commands/commands.dart';

// Search & Replace
export 'src/search/search.dart' hide QueryType, StringQuery, RegExpQuery;

// Autocomplete
export 'src/autocomplete/autocomplete.dart';

// Lint
export 'src/lint/lint.dart';

// LSP integration
export 'src/lsp/lsp.dart';