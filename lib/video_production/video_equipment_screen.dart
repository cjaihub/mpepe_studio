import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';
import '../shared/theme/app_theme.dart';
import '../backend/equipment_repository.dart';
import '../backend/calendar_repository.dart';
import 'package:intl/intl.dart';

class VideoEquipmentScreen extends ConsumerStatefulWidget {
  const VideoEquipmentScreen({super.key});

  @override
  ConsumerState<VideoEquipmentScreen> createState() => _VideoEquipmentScreenState();
}

class _VideoEquipmentScreenState extends ConsumerState<VideoEquipmentScreen> {
  String _selectedCategory = 'All';

  Future<void> _showAddEquipmentDialog(BuildContext context) async {
    HapticFeedback.lightImpact();
    final nameController = TextEditingController();
    String category = 'Camera';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: ctx.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: ctx.border),
          ),
          title: Text(
            'Add Equipment',
            style: TextStyle(
              color: ctx.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: TextStyle(color: ctx.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Equipment Name',
                  labelStyle: TextStyle(color: ctx.textMuted, fontSize: 12),
                  filled: true,
                  fillColor: ctx.surfaceMid,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide(color: ctx.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(color: AppColors.brandBlue),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                dropdownColor: ctx.surface,
                style: TextStyle(color: ctx.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Category',
                  labelStyle: TextStyle(color: ctx.textMuted, fontSize: 12),
                  filled: true,
                  fillColor: ctx.surfaceMid,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide(color: ctx.border),
                  ),
                ),
                items: const ['Camera', 'Lens', 'Lighting', 'Audio']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setModalState(() => category = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: TextStyle(color: ctx.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final id = 'eq_${DateTime.now().millisecondsSinceEpoch}';
                await ref.read(equipmentRepositoryProvider).addEquipment(
                      EquipmentItem(
                        id: id,
                        name: name,
                        category: category,
                        imageUrl: '',
                      ),
                    );
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final equipmentAsync = ref.watch(equipmentStreamProvider);

    return StudioBackground(
      backgroundIcons: const [Icons.videocam_outlined, Icons.movie_creation_outlined, Icons.camera_alt_outlined],
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Equipment', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: context.textPrimary)),
                      const SizedBox(height: 4),
                      Text(
                        "What's out, what's free",
                        style: TextStyle(color: context.textSecondary, fontSize: 12.5),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add_box_outlined, color: AppColors.brandBlue),
                        onPressed: () => _showAddEquipmentDialog(context),
                        tooltip: 'Add Equipment',
                      ),
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner, color: AppColors.brandBlue),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          context.push('/qr_scanner');
                        },
                        tooltip: 'Scan Equipment QR',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Category Filter
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18.0),
              child: Row(
                children: ['All', 'Camera', 'Lens', 'Lighting', 'Audio'].map((category) {
                  final isSelected = _selectedCategory == category;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(category),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() => _selectedCategory = category);
                      },
                      selectedColor: AppColors.brandBlue.withValues(alpha: 0.2),
                      backgroundColor: Colors.transparent,
                      side: BorderSide(color: isSelected ? AppColors.brandBlue : context.border),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 18),

            // Grid View
            Expanded(
              child: equipmentAsync.when(
                data: (items) {
                  final filteredItems = _selectedCategory == 'All' 
                      ? items 
                      : items.where((i) => i.category == _selectedCategory).toList();

                  if (filteredItems.isEmpty) {
                    return Center(
                      child: Text(
                        'No equipment found',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                      ),
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = filteredItems[index];
                      return _EquipmentGridCard(item: item);
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
                error: (error, stack) => Center(child: Text('Error: $error')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EquipmentGridCard extends ConsumerWidget {
  final EquipmentItem item;

  const _EquipmentGridCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOut = item.status == EquipmentStatus.checkedOut;
    final statusColor = isOut ? AppColors.brandPink : AppColors.brandBlue;

    return GestureDetector(
      onTap: () => _showCheckoutDialog(context, ref, item),
      child: OneovaCard(
        padding: const EdgeInsets.all(12),
        borderColor: statusColor.withValues(alpha: 0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  _getCategoryIcon(item.category),
                  color: context.textSecondary,
                  size: 20,
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                    boxShadow: [BoxShadow(color: statusColor.withValues(alpha: 0.5), blurRadius: 4)],
                  ),
                )
              ],
            ),
            const Spacer(),
            Text(
              item.name,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              isOut ? 'Due: ${item.returnDate != null ? DateFormat('MMM d').format(item.returnDate!) : 'TBD'}' : 'Available',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11),
            ),
            if (isOut && item.checkedOutBy != null) ...[
              const SizedBox(height: 2),
              Text(
                'By ${item.checkedOutBy}',
                style: TextStyle(color: AppColors.brandPink.withValues(alpha: 0.8), fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Camera': return Icons.camera_alt;
      case 'Lens': return Icons.camera;
      case 'Lighting': return Icons.lightbulb;
      case 'Audio': return Icons.mic;
      default: return Icons.inventory;
    }
  }

  void _showCheckoutDialog(BuildContext context, WidgetRef ref, EquipmentItem item) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: _CheckoutSheet(item: item),
      ),
    );
  }
}

class _CheckoutSheet extends ConsumerStatefulWidget {
  final EquipmentItem item;
  const _CheckoutSheet({required this.item});

  @override
  ConsumerState<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<_CheckoutSheet> {
  final _userController = TextEditingController();
  DateTime? _selectedReturnDate;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final isOut = widget.item.status == EquipmentStatus.checkedOut;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border),
      ),
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.item.name,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
              ),
              OneovaPill(
                text: isOut ? 'Checked Out' : 'Available',
                color: isOut ? AppColors.brandPink : AppColors.brandBlue,
                isGhost: true,
              )
            ],
          ),
          const SizedBox(height: 24),
          if (isOut) ...[
            Text('Checked out by: ${widget.item.checkedOutBy ?? 'Unknown'}', style: TextStyle(color: context.textSecondary)),
            const SizedBox(height: 8),
            Text('Due back: ${widget.item.returnDate != null ? DateFormat('MMM d, yyyy').format(widget.item.returnDate!) : 'No date set'}', style: TextStyle(color: context.textSecondary)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandBlue, foregroundColor: Colors.white),
                onPressed: _isLoading ? null : () => _handleReturn(ref),
                child: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Return Equipment'),
              ),
            ),
          ] else ...[
            TextField(
              controller: _userController,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: 'Assign to User',
                labelStyle: TextStyle(color: context.textMuted),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: context.border)),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.brandBlue)),
                filled: true,
                fillColor: context.surfaceMid,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Return Date', style: TextStyle(color: context.textSecondary)),
              subtitle: Text(
                _selectedReturnDate == null ? 'Not set' : DateFormat('MMM d, yyyy').format(_selectedReturnDate!),
                style: const TextStyle(color: AppColors.brandBlue),
              ),
              trailing: const Icon(Icons.calendar_today, color: AppColors.brandBlue),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 1)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null) {
                  setState(() => _selectedReturnDate = date);
                }
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandBlue, foregroundColor: Colors.white),
                onPressed: _isLoading ? null : () => _handleCheckout(ref),
                child: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Check Out'),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Future<void> _handleCheckout(WidgetRef ref) async {
    final user = _userController.text.trim();
    if (user.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a user name')));
      return;
    }

    setState(() => _isLoading = true);
    
    // Update Equipment Status
    await ref.read(equipmentRepositoryProvider).updateEquipmentStatus(
      widget.item.id,
      EquipmentStatus.checkedOut,
      userId: user,
      returnDate: _selectedReturnDate,
    );

    // Add Calendar Sync Here
    final calRepo = ref.read(calendarRepositoryProvider);
    final event = EventModel.create(
      title: 'Return: ${widget.item.name}',
      description: 'Equipment checked out by $user',
      startTime: _selectedReturnDate ?? DateTime.now().add(const Duration(days: 1)),
      endTime: _selectedReturnDate ?? DateTime.now().add(const Duration(days: 1)),
      assignedUsers: [user],
      equipmentIds: [widget.item.id],
      colorHex: '#FF9800', // Orange
      type: 'equipment_return',
    );
    await calRepo.addEvent(event);

    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _handleReturn(WidgetRef ref) async {
    setState(() => _isLoading = true);
    
    await ref.read(equipmentRepositoryProvider).updateEquipmentStatus(
      widget.item.id,
      EquipmentStatus.available,
      userId: null,
      returnDate: null,
    );

    if (mounted) {
      Navigator.pop(context);
    }
  }
}
