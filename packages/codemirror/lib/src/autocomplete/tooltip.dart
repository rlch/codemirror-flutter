import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'completion.dart' show Completion, Option;
import 'config.dart' show CompletionConfig;
import 'state.dart' show CompletionDialog;

const double _maxTooltipHeight = 200.0;
const double _minTooltipWidth = 150.0;
const double _maxTooltipWidth = 300.0;
const double _itemHeight = 24.0;
const double _infoMaxWidth = 300.0;
const double _viewPadding = 8.0;
const double _anchorGap = 4.0;

class CompletionTooltipController {
  OverlayEntry? _overlayEntry;
  final void Function(Option option) onAccept;
  
  CompletionDialog? _dialog;
  String? _id;
  CompletionConfig? _config;
  Offset? _anchor;
  double? _lineHeight;

  CompletionTooltipController({
    required this.onAccept,
  });

  void show({
    required BuildContext context,
    required CompletionDialog dialog,
    required String id,
    required CompletionConfig config,
    required Offset anchor,
    required double lineHeight,
  }) {
    _dialog = dialog;
    _id = id;
    _config = config;
    _anchor = anchor;
    _lineHeight = lineHeight;

    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => CompletionPopup(
        dialog: _dialog!,
        id: _id!,
        config: _config!,
        anchor: _anchor!,
        lineHeight: _lineHeight!,
        onAccept: onAccept,
        onDismiss: hide,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void update({
    required CompletionDialog dialog,
    required String id,
    required CompletionConfig config,
    required Offset anchor,
    required double lineHeight,
  }) {
    _dialog = dialog;
    _id = id;
    _config = config;
    _anchor = anchor;
    _lineHeight = lineHeight;
    _overlayEntry?.markNeedsBuild();
  }

  void hide() {
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
    _dialog = null;
    _id = null;
    _config = null;
    _anchor = null;
    _lineHeight = null;
  }

  bool get isShowing => _overlayEntry != null;

  void dispose() {
    hide();
  }
}

class CompletionPopup extends StatefulWidget {
  final CompletionDialog dialog;
  final String id;
  final CompletionConfig config;
  final Offset anchor;
  final double lineHeight;
  final void Function(Option option) onAccept;
  final VoidCallback onDismiss;

  const CompletionPopup({
    super.key,
    required this.dialog,
    required this.id,
    required this.config,
    required this.anchor,
    required this.lineHeight,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  State<CompletionPopup> createState() => _CompletionPopupState();
}

class _CompletionPopupState extends State<CompletionPopup> {
  final ScrollController _scrollController = ScrollController();
  Widget? _infoWidget;
  bool _loadingInfo = false;

  @override
  void initState() {
    super.initState();
    _loadInfoForSelected();
  }

  @override
  void didUpdateWidget(CompletionPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dialog.selected != widget.dialog.selected) {
      _scrollToSelected();
      _loadInfoForSelected();
    }
  }

  void _scrollToSelected() {
    if (widget.dialog.selected < 0 || !_scrollController.hasClients) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      final targetOffset = widget.dialog.selected * _itemHeight;
      final viewportHeight = _scrollController.position.viewportDimension;
      final currentOffset = _scrollController.offset;

      if (targetOffset < currentOffset) {
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
        );
      } else if (targetOffset + _itemHeight > currentOffset + viewportHeight) {
        _scrollController.animateTo(
          targetOffset + _itemHeight - viewportHeight,
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _loadInfoForSelected() {
    _infoWidget = null;
    _loadingInfo = false;

    if (widget.dialog.selected < 0 ||
        widget.dialog.selected >= widget.dialog.options.length) {
      return;
    }

    final completion = widget.dialog.options[widget.dialog.selected].completion;
    final info = completion.info;

    if (info == null) return;

    if (info is String) {
      setState(() {
        _infoWidget = Text(info);
      });
    } else if (info is Widget Function(Completion)) {
      setState(() {
        _infoWidget = info(completion);
      });
    } else if (info is Future<Widget?> Function(Completion)) {
      setState(() {
        _loadingInfo = true;
      });
      info(completion).then((infoWidget) {
        if (mounted) {
          setState(() {
            _infoWidget = infoWidget;
            _loadingInfo = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewSize = Size(constraints.maxWidth, constraints.maxHeight);
        final position = _calculatePosition(
          anchor: widget.anchor,
          lineHeight: widget.lineHeight,
          viewSize: viewSize,
          preferAbove: widget.config.aboveCursor,
        );

        return Stack(
          children: [
            Positioned(
              left: position.left,
              top: position.top,
              child: _buildPopupContent(isDark, position.showAbove),
            ),
          ],
        );
      },
    );
  }

  _PopupPosition _calculatePosition({
    required Offset anchor,
    required double lineHeight,
    required Size viewSize,
    required bool preferAbove,
  }) {
    final optionCount = math.min(widget.dialog.options.length, 10);
    final estimatedHeight = math.min(
      optionCount * _itemHeight + 8,
      _maxTooltipHeight,
    );

    final spaceBelow = viewSize.height - anchor.dy - lineHeight - _viewPadding;
    final spaceAbove = anchor.dy - _viewPadding;

    bool showAbove;
    if (preferAbove) {
      showAbove = spaceAbove >= estimatedHeight || spaceAbove > spaceBelow;
    } else {
      showAbove = spaceBelow < estimatedHeight && spaceAbove > spaceBelow;
    }

    var left = anchor.dx;
    if (left < _viewPadding) {
      left = _viewPadding;
    } else if (left + _maxTooltipWidth > viewSize.width - _viewPadding) {
      left = viewSize.width - _maxTooltipWidth - _viewPadding;
      if (left < _viewPadding) left = _viewPadding;
    }

    double top;
    if (showAbove) {
      top = anchor.dy - estimatedHeight - _anchorGap;
      if (top < _viewPadding) top = _viewPadding;
    } else {
      top = anchor.dy + lineHeight + _anchorGap;
      if (top + estimatedHeight > viewSize.height - _viewPadding) {
        top = viewSize.height - estimatedHeight - _viewPadding;
      }
    }

    return _PopupPosition(
      left: left,
      top: top,
      showAbove: showAbove,
    );
  }

  Widget _buildPopupContent(bool isDark, bool showAbove) {
    final listWidget = _CompletionList(
      dialog: widget.dialog,
      isDark: isDark,
      scrollController: _scrollController,
      onAccept: widget.onAccept,
    );

    if (_infoWidget != null || _loadingInfo) {
      return Row(
        crossAxisAlignment:
            showAbove ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          listWidget,
          const SizedBox(width: 4),
          _InfoPanel(
            isDark: isDark,
            loadingInfo: _loadingInfo,
            infoWidget: _infoWidget,
          ),
        ],
      );
    }

    return listWidget;
  }
}

class _PopupPosition {
  final double left;
  final double top;
  final bool showAbove;

  _PopupPosition({
    required this.left,
    required this.top,
    required this.showAbove,
  });
}

class _CompletionList extends StatelessWidget {
  final CompletionDialog dialog;
  final bool isDark;
  final ScrollController scrollController;
  final void Function(Option option) onAccept;

  const _CompletionList({
    required this.dialog,
    required this.isDark,
    required this.scrollController,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minWidth: _minTooltipWidth,
        maxWidth: _maxTooltipWidth,
        maxHeight: _maxTooltipHeight,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3),
        border: Border.all(
          color: isDark ? const Color(0xFF454545) : const Color(0xFFCCCCCC),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: ListView.builder(
          controller: scrollController,
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: dialog.options.length,
          itemExtent: _itemHeight,
          itemBuilder: (context, index) {
            final option = dialog.options[index];
            final isSelected = index == dialog.selected;
            return _CompletionItem(
              option: option,
              isSelected: isSelected,
              isDark: isDark,
              onTap: () => onAccept(option),
            );
          },
        ),
      ),
    );
  }
}

class _CompletionItem extends StatelessWidget {
  final Option option;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _CompletionItem({
    required this.option,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final completion = option.completion;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: isSelected
              ? (isDark ? const Color(0xFF094771) : const Color(0xFFD6EBFF))
              : null,
          child: Row(
            children: [
              _CompletionIcon(type: completion.type, isDark: isDark),
              const SizedBox(width: 4),
              Expanded(
                child: _CompletionLabel(
                  label: completion.displayLabel ?? completion.label,
                  match: option.match,
                  isSelected: isSelected,
                  isDark: isDark,
                ),
              ),
              if (completion.detail != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    completion.detail!,
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      package: 'codemirror',
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                      color: isDark
                          ? const Color(0xFF808080)
                          : const Color(0xFF666666),
                      decoration: TextDecoration.none,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletionIcon extends StatelessWidget {
  final String? type;
  final bool isDark;

  const _CompletionIcon({
    required this.type,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor =
        isDark ? const Color(0xFFCCCCCC) : const Color(0xFF666666);

    String icon;
    Color color;

    // Nerd Font codicon symbols (nf-cod-symbol_*)
    switch (type) {
      case 'function':
      case 'method':
        icon = '\uea8c'; // nf-cod-symbol_method
        color = const Color(0xFFDCDCAA);
      case 'class':
        icon = '\ueb5b'; // nf-cod-symbol_class
        color = const Color(0xFF4EC9B0);
      case 'interface':
        icon = '\ueb61'; // nf-cod-symbol_interface
        color = const Color(0xFF4EC9B0);
      case 'variable':
        icon = '\uea88'; // nf-cod-symbol_variable
        color = const Color(0xFF9CDCFE);
      case 'constant':
        icon = '\ueb5d'; // nf-cod-symbol_constant
        color = const Color(0xFF4FC1FF);
      case 'type':
        icon = '\uea92'; // nf-cod-symbol_parameter
        color = const Color(0xFF4EC9B0);
      case 'enum':
        icon = '\uea95'; // nf-cod-symbol_enum
        color = const Color(0xFF4EC9B0);
      case 'property':
        icon = '\ueb65'; // nf-cod-symbol_property
        color = const Color(0xFF9CDCFE);
      case 'keyword':
        icon = '\ueb62'; // nf-cod-symbol_keyword
        color = const Color(0xFFC586C0);
      case 'namespace':
        icon = '\uea8b'; // nf-cod-symbol_namespace
        color = const Color(0xFFCCCCCC);
      case 'snippet':
        icon = '\ueb66'; // nf-cod-symbol_snippet
        color = const Color(0xFFCE9178);
      case 'text':
        icon = '\uea93'; // nf-cod-symbol_key
        color = iconColor;
      default:
        icon = '\ueb5f'; // nf-cod-symbol_field
        color = iconColor;
    }

    return SizedBox(
      width: 20,
      child: Text(
        icon,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          package: 'codemirror',
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: color,
          decoration: TextDecoration.none,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _CompletionLabel extends StatelessWidget {
  final String label;
  final List<int> match;
  final bool isSelected;
  final bool isDark;

  const _CompletionLabel({
    required this.label,
    required this.match,
    required this.isSelected,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor =
        isDark ? const Color(0xFFD4D4D4) : const Color(0xFF333333);

    final baseStyle = TextStyle(
      fontFamily: 'JetBrainsMono',
      package: 'codemirror',
      fontSize: 13,
      fontWeight: FontWeight.normal,
      color: baseColor,
      decoration: TextDecoration.none,
    );

    if (match.isEmpty) {
      return Text(
        label,
        style: baseStyle,
        overflow: TextOverflow.ellipsis,
      );
    }

    final spans = <TextSpan>[];
    var lastEnd = 0;

    for (var i = 0; i < match.length; i += 2) {
      final start = match[i];
      final end = match[i + 1];

      if (start > lastEnd) {
        spans.add(TextSpan(text: label.substring(lastEnd, start)));
      }

      spans.add(TextSpan(
        text: label.substring(start, end),
        style: TextStyle(
          decoration: TextDecoration.none,
          color: isSelected
              ? (isDark ? Colors.white : const Color(0xFF000000))
              : (isDark ? const Color(0xFF6CB6FF) : const Color(0xFF0066CC)),
        ),
      ));

      lastEnd = end;
    }

    if (lastEnd < label.length) {
      spans.add(TextSpan(text: label.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: spans,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final bool isDark;
  final bool loadingInfo;
  final Widget? infoWidget;

  const _InfoPanel({
    required this.isDark,
    required this.loadingInfo,
    required this.infoWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: _infoMaxWidth,
        maxHeight: _maxTooltipHeight,
      ),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3),
        border: Border.all(
          color: isDark ? const Color(0xFF454545) : const Color(0xFFCCCCCC),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: loadingInfo
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : SingleChildScrollView(
              child: infoWidget ?? const SizedBox.shrink(),
            ),
    );
  }
}

Widget buildCompletionTooltip({
  required BuildContext context,
  required CompletionDialog dialog,
  required String id,
  required CompletionConfig config,
  required void Function(Option option) onAccept,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  return _CompletionList(
    dialog: dialog,
    isDark: isDark,
    scrollController: ScrollController(),
    onAccept: onAccept,
  );
}
