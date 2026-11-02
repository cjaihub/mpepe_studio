import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../backend/income_intelligence/widgets/smart_income_cards.dart';

enum SmartIncomeTab {
  all('All Overview'),
  arr('ARR & MRR'),
  capTable('Cap Table'),
  waterfall('Liquidation'),
  provisions('Protective Veto');

  final String label;
  const SmartIncomeTab(this.label);
}

class SmartIncomeChannelView extends ConsumerStatefulWidget {
  const SmartIncomeChannelView({super.key});

  @override
  ConsumerState<SmartIncomeChannelView> createState() => _SmartIncomeChannelViewState();
}

class _SmartIncomeChannelViewState extends ConsumerState<SmartIncomeChannelView> {
  SmartIncomeTab _selectedTab = SmartIncomeTab.all;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sub-tabs
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: SmartIncomeTab.values.map((tab) {
              final isSelected = tab == _selectedTab;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  selected: isSelected,
                  showCheckmark: false,
                  label: Text(
                    tab.label,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Colors.white : context.textSecondary,
                    ),
                  ),
                  backgroundColor: context.surface,
                  selectedColor: AppColors.brandBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    side: BorderSide(
                      color: isSelected ? AppColors.brandBlue : context.border,
                      width: 1.0,
                    ),
                  ),
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedTab = tab);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        // Content
        if (_selectedTab == SmartIncomeTab.all) ...[
          const ArrMrrIntelligenceCard(),
          const SizedBox(height: 16),
          const CapTableEquityDiagramCard(),
          const SizedBox(height: 16),
          const LiquidationPreferenceWaterfallCard(),
          const SizedBox(height: 16),
          const ProtectiveProvisionsGuardCard(),
        ] else if (_selectedTab == SmartIncomeTab.arr) ...[
          const ArrMrrIntelligenceCard(),
        ] else if (_selectedTab == SmartIncomeTab.capTable) ...[
          const CapTableEquityDiagramCard(),
        ] else if (_selectedTab == SmartIncomeTab.waterfall) ...[
          const LiquidationPreferenceWaterfallCard(),
        ] else if (_selectedTab == SmartIncomeTab.provisions) ...[
          const ProtectiveProvisionsGuardCard(),
        ],
      ],
    );
  }
}

