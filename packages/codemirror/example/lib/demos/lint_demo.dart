import 'package:codemirror/codemirror.dart' hide Text;
import 'package:flutter/material.dart';

/// Demonstrates the Lint system for showing diagnostics (errors, warnings, hints).
class LintDemo extends StatefulWidget {
  const LintDemo({super.key});

  @override
  State<LintDemo> createState() => _LintDemoState();
}

class _LintDemoState extends State<LintDemo> {
  late EditorState _state;
  final _editorKey = GlobalKey<EditorViewState>();

  final String _sampleCode = '''function greet(name) {
  const message = "Hello, " + nam;
  console.log(mesage);
  return tru;
}

const x = 10
const y = 20
const z = x + y;
''';

  List<Diagnostic> _diagnostics = [];
  bool _showGutter = true;
  bool _autoLint = true;

  @override
  void initState() {
    super.initState();
    ensureStateInitialized();
    ensureLintInitialized();
    _initEditor();
  }

  void _initEditor() {
    _state = EditorState.create(
      EditorStateConfig(
        doc: _sampleCode,
        extensions: ExtensionList([
          javascript(),
          syntaxHighlighting(defaultHighlightStyle),
          linter(
            _autoLint ? _lintSource : null,
            const LintConfig(delay: 300),
          ),
          if (_showGutter) lintGutter(),
        ]),
      ),
    );
    
    // Run initial lint
    if (!_autoLint) {
      _runManualLint();
    }
  }

  Future<List<Diagnostic>> _lintSource(EditorViewState view) async {
    // Simulate a real linter by analyzing the document
    return _analyzeDocument(view.state.doc.toString());
  }

  List<Diagnostic> _analyzeDocument(String code) {
    final diagnostics = <Diagnostic>[];
    final lines = code.split('\n');
    var pos = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Check for common typos
      final typos = {
        'nam': ('name', Severity.error, 'Undefined variable "nam", did you mean "name"?'),
        'mesage': ('message', Severity.error, 'Undefined variable "mesage", did you mean "message"?'),
        'tru': ('true', Severity.error, '"tru" is not defined, did you mean "true"?'),
      };

      for (final entry in typos.entries) {
        final typo = entry.key;
        final (_, severity, message) = entry.value;
        var searchPos = 0;
        while (true) {
          final idx = line.indexOf(typo, searchPos);
          if (idx == -1) break;
          // Make sure it's not part of a longer word
          final before = idx > 0 ? line[idx - 1] : ' ';
          final after = idx + typo.length < line.length ? line[idx + typo.length] : ' ';
          if (!RegExp(r'[a-zA-Z_]').hasMatch(before) && !RegExp(r'[a-zA-Z_]').hasMatch(after)) {
            diagnostics.add(Diagnostic(
              from: pos + idx,
              to: pos + idx + typo.length,
              severity: severity,
              message: message,
              source: 'demo-linter',
            ));
          }
          searchPos = idx + 1;
        }
      }

      // Check for missing semicolons (simplified)
      final trimmed = line.trimRight();
      if (trimmed.isNotEmpty &&
          !trimmed.endsWith('{') &&
          !trimmed.endsWith('}') &&
          !trimmed.endsWith(';') &&
          !trimmed.startsWith('//') &&
          !trimmed.startsWith('/*') &&
          !trimmed.startsWith('*') &&
          (trimmed.startsWith('const ') || trimmed.startsWith('let ') || trimmed.startsWith('var '))) {
        diagnostics.add(Diagnostic(
          from: pos + trimmed.length,
          to: pos + trimmed.length,
          severity: Severity.warning,
          message: 'Missing semicolon',
          source: 'demo-linter',
        ));
      }

      // Check for TODO comments
      final todoIdx = line.indexOf('// TODO');
      if (todoIdx != -1) {
        diagnostics.add(Diagnostic(
          from: pos + todoIdx,
          to: pos + line.length,
          severity: Severity.info,
          message: 'TODO comment found',
          source: 'demo-linter',
        ));
      }

      // Check for missing type annotations (hint)
      if (line.contains('function') && line.contains('(') && !line.contains(':')) {
        final funcIdx = line.indexOf('function');
        diagnostics.add(Diagnostic(
          from: pos + funcIdx,
          to: pos + funcIdx + 8,
          severity: Severity.hint,
          message: 'Consider adding type annotations for better type safety',
          source: 'demo-linter',
        ));
      }

      pos += line.length + 1; // +1 for newline
    }

    return diagnostics;
  }

  void _runManualLint() {
    _diagnostics = _analyzeDocument(_state.doc.toString());
    final view = _editorKey.currentState;
    if (view != null) {
      view.dispatch([setDiagnostics(_state, _diagnostics)]);
    }
  }

  void _clearDiagnostics() {
    _diagnostics = [];
    final view = _editorKey.currentState;
    if (view != null) {
      view.dispatch([setDiagnostics(_state, [])]);
    }
  }

  void _goToNextDiagnostic() {
    final view = _editorKey.currentState;
    if (view != null) {
      nextDiagnostic((
        state: view.state,
        dispatch: view.dispatchTransaction,
      ));
    }
  }

  void _goToPreviousDiagnostic() {
    final view = _editorKey.currentState;
    if (view != null) {
      previousDiagnostic((
        state: view.state,
        dispatch: view.dispatchTransaction,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = diagnosticCount(_state);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lint Diagnostics',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Display errors, warnings, hints, and info messages with underlines and gutter markers. '
            'Navigate between diagnostics with the buttons below.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // Controls
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Controls', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        label: const Text('Auto lint'),
                        selected: _autoLint,
                        onSelected: (v) {
                          setState(() {
                            _autoLint = v;
                            _initEditor();
                          });
                        },
                      ),
                      FilterChip(
                        label: const Text('Show gutter'),
                        selected: _showGutter,
                        onSelected: (v) {
                          setState(() {
                            _showGutter = v;
                            _initEditor();
                          });
                        },
                      ),
                      const VerticalDivider(width: 24),
                      FilledButton.icon(
                        onPressed: _runManualLint,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Run Lint'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _clearDiagnostics,
                        icon: const Icon(Icons.clear, size: 18),
                        label: const Text('Clear'),
                      ),
                      const VerticalDivider(width: 24),
                      IconButton.outlined(
                        onPressed: _goToPreviousDiagnostic,
                        icon: const Icon(Icons.arrow_upward),
                        tooltip: 'Previous diagnostic',
                      ),
                      IconButton.outlined(
                        onPressed: _goToNextDiagnostic,
                        icon: const Icon(Icons.arrow_downward),
                        tooltip: 'Next diagnostic (F8)',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Diagnostic count
          Row(
            children: [
              _buildSeverityChip(Severity.error, theme),
              const SizedBox(width: 8),
              _buildSeverityChip(Severity.warning, theme),
              const SizedBox(width: 8),
              _buildSeverityChip(Severity.info, theme),
              const SizedBox(width: 8),
              _buildSeverityChip(Severity.hint, theme),
              const Spacer(),
              Text(
                'Total: $count diagnostics',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Editor
          Expanded(
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
                    setState(() {
                      _state = update.state;
                    });
                  },
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
          const SizedBox(height: 16),

          // Legend
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text('Legend: ', style: theme.textTheme.labelMedium),
                  const SizedBox(width: 12),
                  _buildLegendItem('Error', const Color(0xFFDD1111), theme),
                  const SizedBox(width: 16),
                  _buildLegendItem('Warning', const Color(0xFFFFA500), theme),
                  const SizedBox(width: 16),
                  _buildLegendItem('Info', const Color(0xFF999999), theme),
                  const SizedBox(width: 16),
                  _buildLegendItem('Hint', const Color(0xFF6666DD), theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityChip(Severity severity, ThemeData theme) {
    final count = _diagnostics.where((d) => d.severity == severity).length;
    final color = _severityColor(severity);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count ${severity.name}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }

  Color _severityColor(Severity severity) {
    switch (severity) {
      case Severity.error:
        return const Color(0xFFDD1111);
      case Severity.warning:
        return const Color(0xFFFFA500);
      case Severity.info:
        return const Color(0xFF999999);
      case Severity.hint:
        return const Color(0xFF6666DD);
    }
  }
}
