import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'command_palette_overlay.dart';

class CommandPaletteIntent extends Intent {
  const CommandPaletteIntent();
}

class CommandPaletteWrapper extends StatefulWidget {
  final Widget child;

  const CommandPaletteWrapper({super.key, required this.child});

  @override
  State<CommandPaletteWrapper> createState() => _CommandPaletteWrapperState();
}

class _CommandPaletteWrapperState extends State<CommandPaletteWrapper> {
  OverlayEntry? _overlayEntry;

  void _toggleCommandPalette() {
    if (_overlayEntry != null) {
      _closeCommandPalette();
    } else {
      _showCommandPalette();
    }
  }

  void _showCommandPalette() {
    if (_overlayEntry != null) return;
    
    _overlayEntry = OverlayEntry(
      builder: (context) => CommandPaletteOverlay(
        onClose: _closeCommandPalette,
      ),
    );
    
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _closeCommandPalette() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyK): const CommandPaletteIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK): const CommandPaletteIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          CommandPaletteIntent: CallbackAction<CommandPaletteIntent>(
            onInvoke: (CommandPaletteIntent intent) {
              _toggleCommandPalette();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          canRequestFocus: false,
          child: widget.child,
        ),
      ),
    );
  }
}
