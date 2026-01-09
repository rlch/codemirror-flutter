/// LR parser module.
///
/// This module provides the LR parser runtime for executing
/// pre-compiled grammar tables.
library;

export 'constants.dart'
    show
        Action,
        StateFlag,
        Specialize,
        Term,
        Seq,
        ParseState,
        FileVersion,
        Lookahead,
        Recover;
export 'decode.dart';
export 'lr_parser.dart';
export 'stack.dart' show Stack, StackBufferCursor, ContextTracker;
export 'token.dart'
    show
        CachedToken,
        InputStream,
        Tokenizer,
        TokenGroup,
        LocalTokenGroup,
        ExternalTokenizer,
        ExternalTokenizerOptions;
