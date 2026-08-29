import 'package:flutter/material.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';

class VideoEquipmentScreen extends StatelessWidget {
  const VideoEquipmentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Equipment', style: AppTheme.h1Style),
              const SizedBox(height: 8),
              const Text(
                "What's out, what's free",
                style: TextStyle(color: AppColors.dust, fontSize: 13),
              ),
              const SizedBox(height: 18),
              _EquipmentCard(
                title: 'Sony FX3 — Camera A',
                subtitle: 'Out to Brian O. • due Friday',
                status: 'Out',
                isOut: true,
              ),
              const SizedBox(height: 10),
              _EquipmentCard(
                title: 'DJI RS3 Gimbal',
                subtitle: 'Out to Josiah M. • due today',
                status: 'Out',
                isOut: true,
              ),
              const SizedBox(height: 10),
              _EquipmentCard(
                title: 'Rode Wireless GO II',
                subtitle: 'In the equipment room',
                status: 'Available',
                isOut: false,
              ),
              const SizedBox(height: 10),
              _EquipmentCard(
                title: 'Aputure 300D Light',
                subtitle: 'In the equipment room',
                status: 'Available',
                isOut: false,
              ),
              const SizedBox(height: 10),
              _EquipmentCard(
                title: 'Sony FX3 — Camera B',
                subtitle: 'Out to Amara K. • due Monday',
                status: 'Out',
                isOut: true,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _EquipmentCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String status;
  final bool isOut;

  const _EquipmentCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.isOut,
  });

  @override
  Widget build(BuildContext context) {
    return MpepeCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                const SizedBox(height: 8),
                Text(subtitle, style: const TextStyle(color: AppColors.dust, fontSize: 12)),
              ],
            ),
          ),
          MpepePill(
            label: status,
            color: isOut ? AppColors.violet : AppColors.mint,
            isGhost: true,
          ),
        ],
      ),
    );
  }
}
