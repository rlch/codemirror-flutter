import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codemirror/src/view/keymap.dart';
import 'package:codemirror/src/state/state.dart';
import 'package:codemirror/src/state/facet.dart' hide EditorState, Transaction;

void main() {
  group('normalizeKeyName', () {
    test('normalizes single key', () {
      expect(normalizeKeyName('a'), equals('a'));
      expect(normalizeKeyName('Enter'), equals('Enter'));
      expect(normalizeKeyName('Space'), equals(' '));
    });

    test('normalizes modifier order', () {
      // Should always output in order: Alt-Ctrl-Meta-Shift
      expect(normalizeKeyName('Ctrl-a'), equals('Ctrl-a'));
      expect(normalizeKeyName('Alt-a'), equals('Alt-a'));
      expect(normalizeKeyName('Shift-a'), equals('Shift-a'));
      expect(normalizeKeyName('Meta-a'), equals('Meta-a'));
      expect(normalizeKeyName('Ctrl-Shift-a'), equals('Ctrl-Shift-a'));
      expect(normalizeKeyName('Shift-Ctrl-a'), equals('Ctrl-Shift-a'));
      expect(normalizeKeyName('Alt-Ctrl-a'), equals('Alt-Ctrl-a'));
      expect(normalizeKeyName('Ctrl-Alt-a'), equals('Alt-Ctrl-a'));
    });

    test('handles Mod modifier', () {
      // Mod should become Ctrl on non-mac, Meta on mac
      expect(normalizeKeyName('Mod-a', 'linux'), equals('Ctrl-a'));
      expect(normalizeKeyName('Mod-a', 'win'), equals('Ctrl-a'));
      expect(normalizeKeyName('Mod-a', 'mac'), equals('Meta-a'));
    });

    test('handles short modifier forms', () {
      expect(normalizeKeyName('c-a'), equals('Ctrl-a'));
      expect(normalizeKeyName('s-a'), equals('Shift-a'));
      expect(normalizeKeyName('a-a'), equals('Alt-a'));
      expect(normalizeKeyName('m-a'), equals('Meta-a'));
    });

    test('handles Cmd as alias for Meta', () {
      expect(normalizeKeyName('Cmd-a'), equals('Meta-a'));
    });

    test('handles Control as alias for Ctrl', () {
      expect(normalizeKeyName('Control-a'), equals('Ctrl-a'));
    });

    test('handles complex combinations', () {
      expect(normalizeKeyName('Ctrl-Shift-Alt-Meta-a'), equals('Alt-Ctrl-Meta-Shift-a'));
      expect(normalizeKeyName('Meta-Alt-Shift-Ctrl-Enter'), equals('Alt-Ctrl-Meta-Shift-Enter'));
    });

    test('throws on unknown modifiers', () {
      expect(() => normalizeKeyName('Unknown-a'), throwsArgumentError);
    });
  });

  group('KeyBinding', () {
    test('creates binding with key', () {
      final binding = KeyBinding(key: 'Ctrl-s');
      expect(binding.key, equals('Ctrl-s'));
      expect(binding.run, isNull);
    });

    test('creates binding with command', () {
      bool executed = false;
      final binding = KeyBinding(
        key: 'Ctrl-s',
        run: (view) {
          executed = true;
          return true;
        },
      );

      expect(binding.key, equals('Ctrl-s'));
      expect(binding.run, isNotNull);
      expect(binding.run!(null), isTrue);
      expect(executed, isTrue);
    });

    test('supports platform-specific keys', () {
      final binding = KeyBinding(
        key: 'Ctrl-s',
        mac: 'Cmd-s',
        win: 'Ctrl-s',
        linux: 'Ctrl-s',
      );

      expect(binding.key, equals('Ctrl-s'));
      expect(binding.mac, equals('Cmd-s'));
      expect(binding.win, equals('Ctrl-s'));
      expect(binding.linux, equals('Ctrl-s'));
    });

    test('supports shift binding', () {
      final binding = KeyBinding(
        key: 'Ctrl-z',
        run: (view) => true,
        shift: (view) => true,
      );

      expect(binding.run, isNotNull);
      expect(binding.shift, isNotNull);
    });

    test('supports scope', () {
      final binding = KeyBinding(
        key: 'Enter',
        scope: 'panel',
        run: (view) => true,
      );

      expect(binding.scope, equals('panel'));
    });

    test('supports preventDefault and stopPropagation', () {
      final binding = KeyBinding(
        key: 'Tab',
        preventDefault: true,
        stopPropagation: true,
        run: (view) => false,
      );

      expect(binding.preventDefault, isTrue);
      expect(binding.stopPropagation, isTrue);
    });
  });

  group('buildKeymap', () {
    test('builds keymap from bindings', () {
      final bindings = [
        KeyBinding(key: 'Ctrl-s', run: (view) => true),
        KeyBinding(key: 'Ctrl-z', run: (view) => true),
      ];

      final map = buildKeymap(bindings, 'linux');
      expect(map.containsKey('editor'), isTrue);
      expect(map['editor']!.containsKey('Ctrl-s'), isTrue);
      expect(map['editor']!.containsKey('Ctrl-z'), isTrue);
    });

    test('handles multi-stroke bindings', () {
      final bindings = [
        KeyBinding(key: 'Ctrl-k Ctrl-c', run: (view) => true),
      ];

      final map = buildKeymap(bindings, 'linux');
      // Prefix should be registered
      expect(map['editor']!.containsKey('Ctrl-k'), isTrue);
      // Full binding should be registered
      expect(map['editor']!.containsKey('Ctrl-k Ctrl-c'), isTrue);
    });

    test('handles platform-specific keys', () {
      final bindings = [
        KeyBinding(key: 'Ctrl-s', mac: 'Cmd-s', run: (view) => true),
      ];

      final mapLinux = buildKeymap(bindings, 'linux');
      expect(mapLinux['editor']!.containsKey('Ctrl-s'), isTrue);

      final mapMac = buildKeymap(bindings, 'mac');
      expect(mapMac['editor']!.containsKey('Meta-s'), isTrue);
    });

    test('handles shift bindings', () {
      final bindings = [
        KeyBinding(
          key: 'Ctrl-z',
          run: (view) => true,
          shift: (view) => true,
        ),
      ];

      final map = buildKeymap(bindings, 'linux');
      expect(map['editor']!.containsKey('Ctrl-z'), isTrue);
      // Shift-Ctrl-z gets normalized to Ctrl-Shift-z
      expect(map['editor']!.containsKey('Ctrl-Shift-z'), isTrue);
    });

    test('handles custom scopes', () {
      final bindings = [
        KeyBinding(key: 'Enter', scope: 'panel', run: (view) => true),
      ];

      final map = buildKeymap(bindings, 'linux');
      expect(map.containsKey('panel'), isTrue);
      expect(map['panel']!.containsKey('Enter'), isTrue);
    });

    test('handles multiple scopes', () {
      final bindings = [
        KeyBinding(key: 'Escape', scope: 'editor panel', run: (view) => true),
      ];

      final map = buildKeymap(bindings, 'linux');
      expect(map.containsKey('editor'), isTrue);
      expect(map.containsKey('panel'), isTrue);
      expect(map['editor']!.containsKey('Escape'), isTrue);
      expect(map['panel']!.containsKey('Escape'), isTrue);
    });

    test('combines multiple handlers for same key', () {
      var count = 0;
      final bindings = [
        KeyBinding(key: 'Ctrl-a', run: (view) { count++; return false; }),
        KeyBinding(key: 'Ctrl-a', run: (view) { count++; return true; }),
      ];

      final map = buildKeymap(bindings, 'linux');
      final binding = map['editor']!['Ctrl-a']!;
      expect(binding.run.length, equals(2));
    });

    test('throws on conflicting prefix usage', () {
      final bindings = [
        KeyBinding(key: 'Ctrl-k', run: (view) => true),
        KeyBinding(key: 'Ctrl-k Ctrl-c', run: (view) => true),
      ];

      expect(() => buildKeymap(bindings, 'linux'), throwsArgumentError);
    });
  });

  group('keymap facet', () {
    test('registers with state', () {
      final state = EditorState.create(
        EditorStateConfig(
          extensions: keymap.of([
            KeyBinding(key: 'Ctrl-s', run: (view) => true),
          ]),
        ),
      );

      final bindings = state.facet(keymap);
      expect(bindings.length, equals(1));
      expect(bindings[0].length, equals(1));
    });

    test('combines multiple keymaps', () {
      final state = EditorState.create(
        EditorStateConfig(
          extensions: ExtensionList([
            keymap.of([KeyBinding(key: 'Ctrl-s', run: (view) => true)]),
            keymap.of([KeyBinding(key: 'Ctrl-z', run: (view) => true)]),
          ]),
        ),
      );

      final bindings = state.facet(keymap);
      expect(bindings.length, equals(2));
    });
  });

  group('keymapOf', () {
    test('creates extension from bindings', () {
      final ext = keymapOf([
        KeyBinding(key: 'Ctrl-a', run: (view) => true),
      ]);

      final state = EditorState.create(EditorStateConfig(extensions: ext));
      final bindings = state.facet(keymap);
      expect(bindings.length, equals(1));
    });
  });

  group('platform detection', () {
    test('currentPlatform returns valid value', () {
      final platform = currentPlatform;
      expect(['mac', 'win', 'linux', 'key'].contains(platform), isTrue);
    });
  });
}
