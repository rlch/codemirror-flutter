import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:codemirror/codemirror.dart' hide Text;

/// Demonstrates keymap and input handling from Phase 4.
class KeymapDemo extends StatefulWidget {
  const KeymapDemo({super.key});

  @override
  State<KeymapDemo> createState() => _KeymapDemoState();
}

class _KeymapDemoState extends State<KeymapDemo> {
  final List<String> _keyEvents = [];
  final List<String> _boundCommands = [];
  late EditorState _state;

  // Custom keymap bindings
  // Note: Key names should match Flutter's LogicalKeyboardKey.keyLabel
  // - Single characters: lowercase (s, d, p)
  // - Arrow keys: ArrowUp, ArrowDown, ArrowLeft, ArrowRight
  // - Special keys: Slash, Backslash, etc.
  final List<KeyBinding> _customBindings = [
    KeyBinding(key: 'Ctrl-s', run: (view) => true, preventDefault: true),
    KeyBinding(key: 'Ctrl-Shift-p', run: (view) => true, preventDefault: true),
    KeyBinding(key: 'Alt-ArrowUp', run: (view) => true, preventDefault: true),
    KeyBinding(key: 'Alt-ArrowDown', run: (view) => true, preventDefault: true),
    KeyBinding(key: 'Ctrl-Slash', run: (view) => true, preventDefault: true),
    KeyBinding(key: 'Ctrl-d', run: (view) => true, preventDefault: true),
  ];

  @override
  void initState() {
    super.initState();
    _state = EditorState.create(EditorStateConfig(
      doc: '''// Try pressing keyboard shortcuts!
// The panel below shows key events and matched bindings.

function hello() {
  console.log("Hello, World!");
}

// Custom bindings:
// Ctrl+S - Save (simulated)
// Ctrl+Shift+P - Command Palette
// Alt+Up/Down - Move Line
// Ctrl+/ - Toggle Comment
// Ctrl+D - Select Next Occurrence
''',
    ));
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final keyName = _getKeyName(event);
      if (keyName.isEmpty) return; // Modifier-only press
      
      setState(() {
        _keyEvents.insert(0, keyName);
        if (_keyEvents.length > 10) {
          _keyEvents.removeLast();
        }

        // Check if this matches a binding
        // Normalize the key we pressed
        final normalized = normalizeKeyName(keyName);
        for (final binding in _customBindings) {
          // Normalize the binding key for comparison
          final bindingNorm = normalizeKeyName(binding.key!);
          final macNorm = binding.mac != null ? normalizeKeyName(binding.mac!) : null;
          
          if (bindingNorm == normalized ||
              (macNorm != null && macNorm == normalized)) {
            _boundCommands.insert(0, '${binding.key} → Command executed');
            if (_boundCommands.length > 5) {
              _boundCommands.removeLast();
            }
            break;
          }
        }
      });
    }
  }

  String _getKeyName(KeyEvent event) {
    final parts = <String>[];

    // Get modifiers in correct order: Alt-Ctrl-Meta-Shift
    if (HardwareKeyboard.instance.isAltPressed) parts.add('Alt');
    if (HardwareKeyboard.instance.isControlPressed) parts.add('Ctrl');
    if (HardwareKeyboard.instance.isMetaPressed) parts.add('Meta');
    if (HardwareKeyboard.instance.isShiftPressed) parts.add('Shift');

    final keyLabel = event.logicalKey.keyLabel;
    if (!['Control Left', 'Control Right', 'Alt Left', 'Alt Right',
          'Shift Left', 'Shift Right', 'Meta Left', 'Meta Right']
        .contains(keyLabel)) {
      // Normalize key label: remove spaces, handle special keys
      var key = keyLabel.replaceAll(' ', '');
      // Keep single-character keys lowercase for matching
      if (key.length == 1) {
        key = key.toLowerCase();
      }
      parts.add(key);
    }

    return parts.join('-');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keymap & Input Handling',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'KeyBinding system with normalized key names, multi-stroke support, '
            'and platform-specific bindings (mac vs standard).',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          Expanded(
            child: Row(
              children: [
                // Editor with key capture
                Expanded(
                  flex: 2,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Editor (Focus to capture keys)',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Focus(
                              autofocus: true,
                              onKeyEvent: (node, event) {
                                _handleKeyEvent(event);
                                return KeyEventResult.ignored;
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: theme.colorScheme.outline,
                                    width: 2,
                                  ),
                                ),
                                child: SingleChildScrollView(
                                  child: Text(
                                    _state.doc.toString(),
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // Key event panel
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.keyboard,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Key Events',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: _keyEvents.isEmpty
                                      ? Center(
                                          child: Text(
                                            'Press keys...',
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: theme.colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        )
                                      : ListView.builder(
                                          itemCount: _keyEvents.length,
                                          itemBuilder: (context, index) {
                                            return Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 2),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: index == 0
                                                      ? theme.colorScheme.primaryContainer
                                                      : theme.colorScheme.surfaceContainerHighest,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  _keyEvents[index],
                                                  style: TextStyle(
                                                    fontFamily: 'monospace',
                                                    fontWeight: index == 0
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                  ),
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
                      const SizedBox(height: 16),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: theme.colorScheme.tertiary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Matched Bindings',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: _boundCommands.isEmpty
                                      ? Center(
                                          child: Text(
                                            'Try Ctrl+S, Ctrl+D...',
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: theme.colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        )
                                      : ListView.builder(
                                          itemCount: _boundCommands.length,
                                          itemBuilder: (context, index) {
                                            return Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 2),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: theme.colorScheme.tertiaryContainer,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  _boundCommands[index],
                                                  style: const TextStyle(
                                                    fontFamily: 'monospace',
                                                    fontSize: 12,
                                                  ),
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
          ),

          const SizedBox(height: 16),

          // Binding reference
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Custom Key Bindings',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _customBindings.map((binding) {
                      return Chip(
                        label: Text(
                          binding.key ?? binding.mac ?? '',
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        backgroundColor: theme.colorScheme.secondaryContainer,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
