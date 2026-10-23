import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/theme/app_theme.dart';

class VirtualGift {
  final String id;
  final String name;
  final String emoji;
  final int coinCost;

  const VirtualGift({
    required this.id,
    required this.name,
    required this.emoji,
    required this.coinCost,
  });
}

const List<VirtualGift> _popularGifts = [
  VirtualGift(id: 'g1', name: 'Rose', emoji: '🌹', coinCost: 1),
  VirtualGift(id: 'g2', name: 'Heart', emoji: '💖', coinCost: 10),
  VirtualGift(id: 'g3', name: 'Coffee', emoji: '☕', coinCost: 50),
  VirtualGift(id: 'g4', name: 'Microphone', emoji: '🎤', coinCost: 99),
  VirtualGift(id: 'g5', name: 'Crown', emoji: '👑', coinCost: 199),
  VirtualGift(id: 'g6', name: 'Diamond', emoji: '💎', coinCost: 500),
  VirtualGift(id: 'g7', name: 'Rocket', emoji: '🚀', coinCost: 999),
  VirtualGift(id: 'g8', name: 'Super Car', emoji: '🏎️', coinCost: 5000),
];

class GiftPickerModal extends StatefulWidget {
  final String targetUserId;
  final Function(VirtualGift) onSendGift;

  const GiftPickerModal({
    super.key,
    required this.targetUserId,
    required this.onSendGift,
  });

  static void show(BuildContext context, {required String targetUserId, required Function(VirtualGift) onSendGift}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (context) => GiftPickerModal(
        targetUserId: targetUserId,
        onSendGift: onSendGift,
      ),
    );
  }

  @override
  State<GiftPickerModal> createState() => _GiftPickerModalState();
}

class _GiftPickerModalState extends State<GiftPickerModal> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  VirtualGift? _selectedGift;
  int _userCoins = 500; // Mock balance

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _sendSelectedGift() {
    if (_selectedGift == null) return;
    
    if (_userCoins >= _selectedGift!.coinCost) {
      HapticFeedback.heavyImpact();
      setState(() {
        _userCoins -= _selectedGift!.coinCost;
      });
      widget.onSendGift(_selectedGift!);
      Navigator.of(context).pop();
    } else {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not enough coins! Please recharge.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: BoxDecoration(
            color: context.surface.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.85 : 0.95),
            border: Border(top: BorderSide(color: context.border, width: 1)),
          ),
          child: Column(
            children: [
              _buildHeader(),
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildGiftGrid(_popularGifts),
                    _buildGiftGrid(_popularGifts.reversed.toList()), // Mock premium
                    _buildGiftGrid([_popularGifts.last, _popularGifts.first]), // Mock exclusives
                  ],
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: context.border,
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 24),
              Text(
                'Send a Gift',
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close, color: context.textPrimary, size: 20),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      indicatorColor: AppColors.brandBlue,
      indicatorWeight: 3,
      labelColor: context.textPrimary,
      unselectedLabelColor: context.textMuted,
      labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
      unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      dividerColor: context.border,
      tabs: const [
        Tab(text: 'Popular'),
        Tab(text: 'Premium'),
        Tab(text: 'Exclusive'),
      ],
    );
  }

  Widget _buildGiftGrid(List<VirtualGift> gifts) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: gifts.length,
      itemBuilder: (context, index) {
        final gift = gifts[index];
        final isSelected = _selectedGift?.id == gift.id;

        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _selectedGift = gift;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.brandBlue.withValues(alpha: 0.2) : context.surfaceMid,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppColors.brandBlue : context.border,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(gift.emoji, style: const TextStyle(fontSize: 32)),
                const SizedBox(height: 8),
                Text(
                  gift.name,
                  style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.monetization_on, color: Colors.amber, size: 12),
                    const SizedBox(width: 2),
                    Text(
                      '${gift.coinCost}',
                      style: GoogleFonts.inter(
                        color: Colors.amber,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(top: BorderSide(color: context.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Balance
          Row(
            children: [
              const Icon(Icons.monetization_on, color: Colors.amber, size: 24),
              const SizedBox(width: 6),
              Text(
                '$_userCoins',
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  // TODO: Route to coin purchase screen
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.border),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Recharge',
                        style: GoogleFonts.inter(
                          color: context.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, color: context.textMuted, size: 14),
                    ],
                  ),
                ),
              )
            ],
          ),
          
          // Send Button
          GestureDetector(
            onTap: _selectedGift != null ? _sendSelectedGift : null,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _selectedGift != null ? 1.0 : 0.5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: _selectedGift != null ? [
                    BoxShadow(color: AppColors.brandBlue.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))
                  ] : [],
                ),
                child: Text(
                  'Send',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
