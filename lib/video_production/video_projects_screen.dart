import 'package:flutter/material.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';

class VideoProjectsScreen extends StatelessWidget {
  const VideoProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Projects', style: AppTheme.h1Style),
              const SizedBox(height: 8),
              const Text(
                'Scripting -> Filming -> Editing -> Review -> Delivered',
                style: TextStyle(color: AppColors.dust, fontSize: 13),
              ),
              const SizedBox(height: 18),
              MpepeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Episode 12 — Studio Q&A', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    const SizedBox(height: 8),
                    const Text('Brian O. • Faith N.', style: TextStyle(color: AppColors.dust, fontSize: 12)),
                    const SizedBox(height: 10),
                    const StepProgressIndicator(totalSteps: 5, completedSteps: 3),
                    const SizedBox(height: 8),
                    const Text('Editing', style: TextStyle(color: AppColors.dust, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              MpepeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Cinematic Travel Vlogs Ep.4', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    const SizedBox(height: 8),
                    const Text('Josiah M. • Faith N.', style: TextStyle(color: AppColors.dust, fontSize: 12)),
                    const SizedBox(height: 10),
                    const StepProgressIndicator(totalSteps: 5, completedSteps: 4),
                    const SizedBox(height: 8),
                    const Text('Review', style: TextStyle(color: AppColors.dust, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              MpepeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Chef Malik — Kitchen Tour', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    const SizedBox(height: 8),
                    const Text('Brian O. • Amara K.', style: TextStyle(color: AppColors.dust, fontSize: 12)),
                    const SizedBox(height: 10),
                    const StepProgressIndicator(totalSteps: 5, completedSteps: 1),
                    const SizedBox(height: 8),
                    const Text('Filming', style: TextStyle(color: AppColors.dust, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              MpepeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('5 Gimbal Moves — Reshoot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    const SizedBox(height: 8),
                    const Text('Josiah M. • Amara K.', style: TextStyle(color: AppColors.dust, fontSize: 12)),
                    const SizedBox(height: 10),
                    const StepProgressIndicator(totalSteps: 5, completedSteps: 5),
                    const SizedBox(height: 8),
                    const Text('Delivered', style: TextStyle(color: AppColors.dust, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
