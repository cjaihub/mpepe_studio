import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class SharedBottomNavBar extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  final List<BottomNavigationBarItem> items;
  
  const SharedBottomNavBar({
    super.key, 
    required this.navigationShell,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return _SlidingNavBar(
      currentIndex: navigationShell.currentIndex,
      items: items,
      onTap: (index) => navigationShell.goBranch(index),
    );
  }
}

class _SlidingNavBar extends StatelessWidget {
  final int currentIndex;
  final List<BottomNavigationBarItem> items;
  final ValueChanged<int> onTap;

  const _SlidingNavBar({
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12.0, left: 16.0, right: 16.0),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: context.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(
              color: context.border,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isActive = index == currentIndex;

              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(index),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    margin: EdgeInsets.symmetric(
                      vertical: isActive ? 8.0 : 12.0,
                      horizontal: 8.0,
                    ),
                    decoration: BoxDecoration(
                      color: isActive 
                        ? AppColors.brandBlue
                        : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedScale(
                          scale: isActive ? 1.15 : 1.0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutBack,
                          child: IconTheme(
                            data: IconThemeData(
                              color: isActive 
                                  ? Colors.white
                                  : context.textSecondary,
                              size: isActive ? 24 : 20,
                            ),
                            child: item.icon,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(height: 2),
                          Flexible(
                            child: Text(
                              item.label ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
