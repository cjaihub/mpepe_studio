import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../models/brand_persona.dart';
import 'components.dart';

class AccountSwitcherSheet extends ConsumerWidget {
  final List<BrandPersona> personas;
  final BrandPersona? activePersona;
  final Function(BrandPersona) onSelect;
  final VoidCallback onAddAccount;

  const AccountSwitcherSheet({
    super.key,
    required this.personas,
    required this.activePersona,
    required this.onSelect,
    required this.onAddAccount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: context.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Switch Persona',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.brandBlue,
            ),
          ),
          const SizedBox(height: 16),
          if (personas.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'No personas found. Add a new account to get started.',
                style: TextStyle(color: context.textMuted),
                textAlign: TextAlign.center,
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: personas.length,
                itemBuilder: (context, index) {
                  final persona = personas[index];
                  final isActive = persona.id == activePersona?.id;
                  
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isActive 
                        ? const BorderSide(color: AppColors.brandBlue, width: 2)
                        : BorderSide(color: context.border),
                    ),
                    tileColor: isActive ? AppColors.brandBlue.withValues(alpha: 0.1) : context.surface,
                    leading: CircleAvatar(
                      backgroundColor: context.surfaceMid,
                      backgroundImage: persona.avatarUrl.isNotEmpty ? NetworkImage(persona.avatarUrl) : null,
                      child: persona.avatarUrl.isEmpty ? Icon(Icons.person, color: context.textPrimary) : null,
                    ),
                    title: Text(persona.name, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
                    subtitle: Text('Niche: ${persona.niche}', style: TextStyle(color: context.textSecondary, fontSize: 12)),
                    trailing: isActive ? const Icon(Icons.check_circle, color: AppColors.brandBlue) : null,
                    onTap: () {
                      onSelect(persona);
                      Navigator.of(context).pop();
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          OneovaButton(
            text: '+ Add New Account',
            onPressed: () {
              Navigator.of(context).pop();
              onAddAccount();
            },
            isPrimary: true,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
