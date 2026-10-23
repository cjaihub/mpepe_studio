import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'command_palette_models.dart';
import 'search_providers.dart';
import '../theme/app_theme.dart';

class CommandPaletteOverlay extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  const CommandPaletteOverlay({super.key, required this.onClose});

  @override
  ConsumerState<CommandPaletteOverlay> createState() => _CommandPaletteOverlayState();
}

class _CommandPaletteOverlayState extends ConsumerState<CommandPaletteOverlay> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      ref.read(commandPaletteQueryProvider.notifier).update(_searchController.text);
      setState(() {
        _selectedIndex = 0; // Reset selection on search change
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _executeSelected(List<CommandItem> commands) async {
    if (commands.isEmpty) return;
    final item = commands[_selectedIndex];
    
    // Check permission logic
    if (item.requiresPermission) {
      // Stub check: in reality you would check the user's role or auth claims
      // For this implementation, we will simulate a permission check
      // final hasPermission = true; // Replace with actual permission logic 
    }
    
    // Close the palette first so navigation isn't blocked by the overlay
    widget.onClose();
    
    // Execute command
    await item.onExecute(context);
  }

  @override
  Widget build(BuildContext context) {
    final filteredCommands = ref.watch(filteredCommandsProvider);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Background dimmer
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              color: Colors.black.withValues(alpha: 0.5),
            ),
          ),
          
          // Center Dialog
          Center(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent || event is KeyRepeatEvent) {
                  final commandsCount = ref.read(filteredCommandsProvider).length;
                  if (commandsCount == 0) return KeyEventResult.ignored;

                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    setState(() {
                      _selectedIndex = (_selectedIndex + 1) % commandsCount;
                    });
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    setState(() {
                      _selectedIndex = (_selectedIndex - 1 + commandsCount) % commandsCount;
                    });
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                    widget.onClose();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                width: 600,
                constraints: const BoxConstraints(maxHeight: 400),
                decoration: BoxDecoration(
                  color: context.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.border, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Search Input
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        style: TextStyle(color: context.textPrimary, fontSize: 18),
                        decoration: InputDecoration(
                          hintText: 'Search commands, contacts, messages...',
                          hintStyle: TextStyle(color: context.textSecondary),
                          prefixIcon: Icon(Icons.search, color: context.textSecondary),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _executeSelected(filteredCommands),
                      ),
                    ),
                    Divider(height: 1, color: context.surfaceMid),
                    
                    // Results List
                    Flexible(
                      child: filteredCommands.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Text(
                                'No results found',
                                style: TextStyle(color: context.textSecondary),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filteredCommands.length,
                              itemBuilder: (context, index) {
                                final command = filteredCommands[index];
                                final isSelected = index == _selectedIndex;

                                return MouseRegion(
                                  onEnter: (_) {
                                    setState(() {
                                      _selectedIndex = index;
                                    });
                                  },
                                  child: ListTile(
                                    selected: isSelected,
                                    selectedTileColor: AppColors.brandBlue,
                                    leading: Icon(
                                      command.icon,
                                      color: isSelected ? Colors.white : context.textSecondary,
                                    ),
                                    title: Text(
                                      command.title,
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : context.textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: command.subtitle != null
                                        ? Text(
                                            command.subtitle!,
                                            style: TextStyle(
                                              color: isSelected ? Colors.white70 : context.textSecondary,
                                            ),
                                          )
                                        : null,
                                    trailing: Text(
                                      command.category.name.toUpperCase(),
                                      style: TextStyle(
                                        color: isSelected ? Colors.white54 : context.textMuted,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _selectedIndex = index;
                                      });
                                      _executeSelected(filteredCommands);
                                    },
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
    );
  }
}
