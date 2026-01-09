/// Dart port of Lezer - an incremental GLR parser system.
///
/// This library provides:
/// - **Common**: Tree structure, NodeType, NodeProp, Parser interface
/// - **Highlight**: Syntax highlighting tags and tree highlighting
/// - **LR**: LR parser runtime for executing pre-compiled grammar tables
///
/// ## Usage
///
/// ```dart
/// import 'package:lezer/lezer.dart';
///
/// // Parse code with a language parser
/// final tree = parser.parse(code);
///
/// // Highlight the tree
/// highlightTree(tree, highlighter, (from, to, classes) {
///   // Apply styling
/// });
/// ```
library;

// Common exports
export 'src/common/iter_mode.dart';
export 'src/common/node_prop.dart'; // MountedTree now exported for mixed-language support
export 'src/common/node_type.dart' hide NodeFlag;
export 'src/common/node_set.dart';
export 'src/common/tree.dart' hide NodeIterator;
export 'src/common/tree_buffer.dart' hide Side;
export 'src/common/tree_cursor.dart';
export 'src/common/syntax_node.dart' hide BufferContext;
export 'src/common/parser.dart';
export 'src/common/tree_fragment.dart';
export 'src/common/mix.dart';

// Highlight exports
export 'src/highlight/tag.dart';
export 'src/highlight/tags.dart';
export 'src/highlight/style_tags.dart';
export 'src/highlight/highlighter.dart';
export 'src/highlight/highlight_tree.dart';

// LR parser exports
export 'src/lr/decode.dart';
export 'src/lr/lr_parser.dart';
export 'src/lr/stack.dart' show Stack, ContextTracker;
export 'src/lr/token.dart'
    show
        CachedToken,
        InputStream,
        Tokenizer,
        TokenGroup,
        LocalTokenGroup,
        ExternalTokenizer,
        ExternalTokenizerOptions;
