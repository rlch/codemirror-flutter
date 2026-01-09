import 'package:codemirror/codemirror.dart' hide Text;
import 'package:flutter/material.dart';

/// Comprehensive LSP features demo.
///
/// Demonstrates all LSP-style language features:
/// - Go to Definition (Ctrl+click, F12)
/// - Find References (Shift+F12)
/// - Signature Help (auto-trigger on '(')
/// - Document Formatting (Shift+Alt+F)
/// - Rename Symbol (F2)
/// - Document Highlight (automatic on cursor move)
class LspDemo extends StatefulWidget {
  const LspDemo({super.key});

  @override
  State<LspDemo> createState() => _LspDemoState();
}

class _LspDemoState extends State<LspDemo> {
  late EditorState _state;
  final _editorKey = GlobalKey<EditorViewState>();
  
  String _lastAction = 'None';
  List<String> _actionLog = [];

  final String _sampleCode = '''// LSP Features Demo - Try the features below!
interface User {
  id: number;
  name: string;
  email: string;
}

function greet(user: User, message: string): string {
  const greeting = `\${message}, \${user.name}!`;
  console.log(greeting);
  return greeting;
}

function processUsers(users: User[]): void {
  for (const user of users) {
    greet(user, "Hello");
  }
}

const alice: User = { id: 1, name: "Alice", email: "alice@example.com" };
const bob: User = { id: 2, name: "Bob", email: "bob@example.com" };

processUsers([alice, bob]);

// Try these:
// 1. Ctrl+click on "User" to go to definition
// 2. F2 on "greet" to rename
// 3. Type "greet(" to see signature help
// 4. Shift+Alt+F to format document
// 5. Move cursor to "user" to see highlights
''';

  // Simulated symbol database
  final Map<String, _SymbolDef> _symbols = {};
  
  @override
  void initState() {
    super.initState();
    ensureStateInitialized();
    ensureLanguageInitialized();
    _buildSymbolDatabase();
    _initEditor();
  }
  
  void _buildSymbolDatabase() {
    // Build symbol locations from sample code
    // User interface at line 2
    _symbols['User'] = _SymbolDef(
      definitionPos: _sampleCode.indexOf('interface User'),
      type: 'interface User { id: number; name: string; email: string; }',
      references: [],
    );
    
    // greet function at line 8
    _symbols['greet'] = _SymbolDef(
      definitionPos: _sampleCode.indexOf('function greet'),
      type: '(user: User, message: string) => string',
      references: [],
      signature: _SignatureData(
        label: 'greet(user: User, message: string): string',
        documentation: 'Generates a greeting for the given user.',
        parameters: [
          (label: 'user: User', doc: 'The user to greet'),
          (label: 'message: string', doc: 'The greeting message'),
        ],
      ),
    );
    
    // processUsers function
    _symbols['processUsers'] = _SymbolDef(
      definitionPos: _sampleCode.indexOf('function processUsers'),
      type: '(users: User[]) => void',
      references: [],
      signature: _SignatureData(
        label: 'processUsers(users: User[]): void',
        documentation: 'Processes an array of users.',
        parameters: [
          (label: 'users: User[]', doc: 'Array of users to process'),
        ],
      ),
    );
    
    // Find all references
    _findReferences('User', _symbols['User']!);
    _findReferences('greet', _symbols['greet']!);
    _findReferences('processUsers', _symbols['processUsers']!);
    _findReferences('user', null); // local variable
    _findReferences('alice', null);
    _findReferences('bob', null);
  }
  
  void _findReferences(String name, _SymbolDef? symbol) {
    final refs = <int>[];
    var idx = 0;
    while (true) {
      idx = _sampleCode.indexOf(name, idx);
      if (idx == -1) break;
      // Check it's a whole word
      final before = idx > 0 ? _sampleCode[idx - 1] : ' ';
      final after = idx + name.length < _sampleCode.length 
          ? _sampleCode[idx + name.length] 
          : ' ';
      if (!RegExp(r'[a-zA-Z0-9_$]').hasMatch(before) &&
          !RegExp(r'[a-zA-Z0-9_$]').hasMatch(after)) {
        refs.add(idx);
      }
      idx++;
    }
    if (symbol != null) {
      symbol.references = refs;
    } else {
      _symbols[name] = _SymbolDef(
        definitionPos: refs.isNotEmpty ? refs.first : 0,
        type: name,
        references: refs,
      );
    }
  }

  void _initEditor() {
    _state = EditorState.create(
      EditorStateConfig(
        doc: _sampleCode,
        extensions: ExtensionList([
          javascript(const JavaScriptConfig(typescript: true)),
          syntaxHighlighting(defaultHighlightStyle),
          keymap.of(standardKeymap),
          
          // Go to Definition
          gotoDefinition(
            _definitionSource,
            GotoDefinitionOptions(
              showHoverUnderline: true,
              navigator: _navigateToDefinition,
            ),
          ),
          keymap.of(gotoDefinitionKeymap),
          
          // Find References
          findReferences(
            _referencesSource,
            FindReferencesOptions(
              display: _showReferences,
            ),
          ),
          keymap.of(findReferencesKeymap),
          
          // Signature Help
          signatureHelp(
            _signatureSource,
            const SignatureHelpOptions(
              triggerCharacters: ['(', ','],
              retriggerCharacters: [')'],
            ),
          ),
          keymap.of(signatureHelpKeymap),
          
          // Document Formatting
          documentFormatting(
            _formatSource,
            const DocumentFormattingOptions(tabSize: 2, insertSpaces: true),
          ),
          keymap.of(documentFormattingKeymap),
          
          // Rename Symbol
          renameSymbol(
            _renameSource,
            RenameOptions(prepareSource: _prepareRename),
          ),
          keymap.of(renameKeymap),
          
          // Document Highlight
          documentHighlight(
            _highlightSource,
            const DocumentHighlightOptions(delay: 100),
          ),
          
          // Hover Tooltip
          hoverTooltip(_hoverSource),
        ]),
      ),
    );
  }
  
  void _logAction(String action) {
    setState(() {
      _lastAction = action;
      _actionLog.insert(0, '[${DateTime.now().toString().substring(11, 19)}] $action');
      if (_actionLog.length > 10) {
        _actionLog = _actionLog.sublist(0, 10);
      }
    });
  }
  
  // Go to Definition source
  Future<DefinitionResult?> _definitionSource(EditorState state, int pos) async {
    await Future.delayed(const Duration(milliseconds: 50));
    
    final word = _getWordAt(state.doc.toString(), pos);
    if (word == null) return null;
    
    final symbol = _symbols[word.text];
    if (symbol == null) return null;
    
    _logAction('Go to Definition: ${word.text}');
    
    return DefinitionResult.single(DefinitionLocation(
      pos: symbol.definitionPos,
      end: symbol.definitionPos + word.text.length,
    ));
  }
  
  void _navigateToDefinition(DefinitionLocation location, EditorState state) {
    final editorState = _editorKey.currentState;
    if (editorState == null) return;
    
    _logAction('Navigating to position ${location.pos}');
    
    // Update selection to definition location
    final tr = state.update([
      TransactionSpec(
        selection: EditorSelection.single(location.pos, location.end ?? location.pos),
        scrollIntoView: true,
      ),
    ]);
    setState(() {
      _state = tr.state as EditorState;
    });
  }
  
  // Find References source
  Future<ReferencesResult?> _referencesSource(EditorState state, int pos) async {
    await Future.delayed(const Duration(milliseconds: 50));
    
    final word = _getWordAt(state.doc.toString(), pos);
    if (word == null) return null;
    
    final symbol = _symbols[word.text];
    if (symbol == null) return null;
    
    _logAction('Find References: ${word.text} (${symbol.references.length} found)');
    
    return ReferencesResult(
      symbol.references.map((pos) => DefinitionLocation(
        pos: pos,
        end: pos + word.text.length,
      )).toList(),
    );
  }
  
  void _showReferences(ReferencesResult result, EditorState state, int originPos) {
    _logAction('References: ${result.references.map((r) => r.pos).join(', ')}');
  }
  
  // Signature Help source
  Future<SignatureResult?> _signatureSource(EditorState state, int pos) async {
    await Future.delayed(const Duration(milliseconds: 30));
    
    // Find the function name before the '('
    final doc = state.doc.toString();
    var searchPos = pos - 1;
    
    // Find opening paren
    int parenDepth = 0;
    while (searchPos >= 0) {
      final char = doc[searchPos];
      if (char == ')') {
        parenDepth++;
      } else if (char == '(') {
        if (parenDepth == 0) break;
        parenDepth--;
      }
      searchPos--;
    }
    
    if (searchPos < 0) return null;
    
    // Get word before paren
    final word = _getWordAt(doc, searchPos - 1);
    if (word == null) return null;
    
    final symbol = _symbols[word.text];
    if (symbol?.signature == null) return null;
    
    // Detect active parameter
    final activeParam = detectActiveParameter(doc, searchPos + 1, pos);
    
    _logAction('Signature Help: ${word.text}(param $activeParam)');
    
    final sig = symbol!.signature!;
    return SignatureResult(
      signatures: [
        SignatureInfo(
          label: sig.label,
          documentation: sig.documentation,
          parameters: sig.parameters.map((p) => ParameterInfo(
            label: p.label,
            documentation: p.doc,
          )).toList(),
          activeParameter: activeParam,
        ),
      ],
      triggerPos: searchPos,
    );
  }
  
  // Format document button handler
  void _formatDocument() async {
    final result = await _formatSource(_state);
    if (result != null && result.isNotEmpty) {
      final spec = applyFormatEdits(_state, result);
      final tr = _state.update([spec]);
      setState(() {
        _state = tr.state as EditorState;
      });
    }
  }
  
  // Document Formatting source
  Future<FormatResult?> _formatSource(EditorState state) async {
    await Future.delayed(const Duration(milliseconds: 100));
    
    _logAction('Format Document');
    
    // Simple formatting: normalize indentation
    final lines = state.doc.toString().split('\n');
    final formatted = StringBuffer();
    var indent = 0;
    
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      
      // Decrease indent for closing braces
      if (line.startsWith('}') || line.startsWith(']') || line.startsWith(')')) {
        indent = (indent - 1).clamp(0, 100);
      }
      
      if (line.isNotEmpty) {
        formatted.write('  ' * indent);
        formatted.write(line);
      }
      if (i < lines.length - 1) formatted.write('\n');
      
      // Increase indent for opening braces
      if (line.endsWith('{') || line.endsWith('[') || line.endsWith('(')) {
        indent++;
      }
    }
    
    return FormatResult.replaceAll(formatted.toString(), state.doc.length);
  }
  
  // Rename Symbol sources
  Future<PrepareRenameResult?> _prepareRename(EditorState state, int pos) async {
    await Future.delayed(const Duration(milliseconds: 30));
    
    final word = _getWordAt(state.doc.toString(), pos);
    if (word == null) return null;
    
    // Check if it's a known symbol
    if (!_symbols.containsKey(word.text)) {
      return PrepareRenameResult.error('Cannot rename "${word.text}"');
    }
    
    _logAction('Prepare Rename: ${word.text}');
    
    return PrepareRenameResult(
      from: word.from,
      to: word.to,
      placeholder: word.text,
    );
  }
  
  Future<RenameResult?> _renameSource(EditorState state, int pos, String newName) async {
    await Future.delayed(const Duration(milliseconds: 50));
    
    final word = _getWordAt(state.doc.toString(), pos);
    if (word == null) return null;
    
    final symbol = _symbols[word.text];
    if (symbol == null) return null;
    
    _logAction('Rename: ${word.text} → $newName (${symbol.references.length} occurrences)');
    
    return RenameResult(
      locations: symbol.references.map((pos) => RenameLocation(
        from: pos,
        to: pos + word.text.length,
      )).toList(),
    );
  }
  
  // Document Highlight source
  Future<DocumentHighlightResult?> _highlightSource(EditorState state, int pos) async {
    await Future.delayed(const Duration(milliseconds: 30));
    
    final word = _getWordAt(state.doc.toString(), pos);
    if (word == null) return null;
    
    final symbol = _symbols[word.text];
    if (symbol == null) return null;
    
    return DocumentHighlightResult(
      symbol.references.map((p) => DocumentHighlight(
        from: p,
        to: p + word.text.length,
        kind: p == symbol.definitionPos ? HighlightKind.write : HighlightKind.read,
      )).toList(),
    );
  }
  
  // Hover Tooltip source
  Future<HoverTooltip?> _hoverSource(EditorState state, int pos, int side) async {
    await Future.delayed(const Duration(milliseconds: 50));
    
    final word = _getWordAt(state.doc.toString(), pos);
    if (word == null) return null;
    
    final symbol = _symbols[word.text];
    if (symbol == null) return null;
    
    final content = '''```typescript
${symbol.type}
```

**${word.text}** - ${symbol.references.length} references''';
    
    return createMarkdownTooltip(
      pos: word.from,
      end: word.to,
      content: content,
    );
  }
  
  // Helper: get word at position
  _WordRange? _getWordAt(String doc, int pos) {
    if (pos < 0 || pos >= doc.length) return null;
    
    var start = pos;
    var end = pos;
    
    while (start > 0 && _isWordChar(doc[start - 1])) {
      start--;
    }
    while (end < doc.length && _isWordChar(doc[end])) {
      end++;
    }
    
    if (start == end) return null;
    
    return _WordRange(start, end, doc.substring(start, end));
  }
  
  bool _isWordChar(String char) => RegExp(r'[a-zA-Z0-9_$]').hasMatch(char);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LSP Features', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Demonstrates LSP-style language intelligence features with mock data.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // Quick actions and buttons
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Keyboard Shortcuts', style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                _KeyboardHint('Ctrl+Click', 'Go to Definition'),
                                _KeyboardHint('F12', 'Go to Definition'),
                                _KeyboardHint('Shift+F12', 'Find References'),
                                _KeyboardHint('F2', 'Rename Symbol'),
                                _KeyboardHint('Ctrl+Shift+Space', 'Signature Help'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Format button
                      FilledButton.icon(
                        onPressed: _formatDocument,
                        icon: const Icon(Icons.auto_fix_high, size: 18),
                        label: const Text('Format'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Main content
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Editor
                Expanded(
                  flex: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.outline),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: EditorView(
                        key: _editorKey,
                        state: _state,
                        onUpdate: (update) {
                          setState(() => _state = update.state);
                        },
                        autofocus: true,
                        backgroundColor: theme.brightness == Brightness.dark
                            ? HighlightTheme.darkBackground
                            : HighlightTheme.lightBackground,
                        highlightTheme: theme.brightness == Brightness.dark
                            ? HighlightTheme.dark
                            : HighlightTheme.light,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Action log
                SizedBox(
                  width: 280,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.history, size: 18, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text('Action Log', style: theme.textTheme.titleSmall),
                            ],
                          ),
                          const Divider(),
                          Text(
                            'Last: $_lastAction',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _actionLog.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Text(
                                    _actionLog[index],
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyboardHint extends StatelessWidget {
  final String shortcut;
  final String action;

  const _KeyboardHint(this.shortcut, this.action);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Text(
              shortcut,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            action,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SymbolDef {
  final int definitionPos;
  final String type;
  List<int> references;
  final _SignatureData? signature;

  _SymbolDef({
    required this.definitionPos,
    required this.type,
    required this.references,
    this.signature,
  });
}

class _SignatureData {
  final String label;
  final String documentation;
  final List<({String label, String doc})> parameters;

  _SignatureData({
    required this.label,
    required this.documentation,
    required this.parameters,
  });
}

class _WordRange {
  final int from;
  final int to;
  final String text;

  _WordRange(this.from, this.to, this.text);
}
