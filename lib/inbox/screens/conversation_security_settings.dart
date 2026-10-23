import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/theme/app_theme.dart';
import '../../backend/security/models/privacy_enums.dart';

class ConversationSecuritySettings extends ConsumerStatefulWidget {
  final String conversationId;

  const ConversationSecuritySettings({super.key, required this.conversationId});

  @override
  ConsumerState<ConversationSecuritySettings> createState() => _ConversationSecuritySettingsState();
}

class _ConversationSecuritySettingsState extends ConsumerState<ConversationSecuritySettings> {
  // These would typically come from a ConversationProvider. Mocking for UI building.
  EncryptionMode _encryptionMode = EncryptionMode.standard;
  AiAccessMode _aiAccessMode = AiAccessMode.allowed;
  RetentionPolicy _retentionPolicy = RetentionPolicy.forever;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        title: Text('Chat Security', style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimary)),
        iconTheme: IconThemeData(color: context.textPrimary),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSectionHeader('Encryption'),
          _buildSwitchOption(
            title: 'End-to-End Encryption',
            subtitle: _encryptionMode == EncryptionMode.e2ee 
                ? 'Messages are encrypted. Neither Oneova nor AI can read them.'
                : 'Standard TLS encryption. Server can process AI requests.',
            icon: Icons.lock,
            value: _encryptionMode == EncryptionMode.e2ee,
            onChanged: (val) {
              setState(() {
                _encryptionMode = val ? EncryptionMode.e2ee : EncryptionMode.standard;
                if (val) {
                  _aiAccessMode = AiAccessMode.never; // AI cannot read E2EE chats by default
                }
              });
            },
          ),
          const SizedBox(height: 24),

          _buildSectionHeader('AI Access'),
          _buildEnumSelector<AiAccessMode>(
            title: 'Allow AI to access this conversation',
            currentValue: _aiAccessMode,
            options: [
              MapEntry(AiAccessMode.never, 'Never'),
              MapEntry(AiAccessMode.askEveryTime, 'Ask every time'),
              MapEntry(AiAccessMode.allowed, 'Allowed'),
            ],
            onChanged: _encryptionMode == EncryptionMode.e2ee 
                ? null // Disabled if E2EE is ON
                : (val) => setState(() => _aiAccessMode = val!),
          ),
          if (_encryptionMode == EncryptionMode.e2ee)
            const Padding(
              padding: EdgeInsets.only(top: 8.0, left: 4),
              child: Text(
                'AI access is disabled when End-to-End Encryption is active.',
                style: TextStyle(color: Colors.amber, fontSize: 12),
              ),
            ),
          const SizedBox(height: 24),

          _buildSectionHeader('Retention Policy'),
          _buildEnumSelector<RetentionPolicy>(
            title: 'Keep messages',
            currentValue: _retentionPolicy,
            options: [
              MapEntry(RetentionPolicy.twentyFourHours, '24 Hours'),
              MapEntry(RetentionPolicy.sevenDays, '7 Days'),
              MapEntry(RetentionPolicy.thirtyDays, '30 Days'),
              MapEntry(RetentionPolicy.forever, 'Forever'),
            ],
            onChanged: (val) => setState(() => _retentionPolicy = val!),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: context.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSwitchOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? AppColors.brandBlue : context.border,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: value ? AppColors.brandBlue : context.textSecondary, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: context.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.brandBlue,
          ),
        ],
      ),
    );
  }

  Widget _buildEnumSelector<T>({
    required String title,
    required T currentValue,
    required List<MapEntry<T, String>> options,
    required ValueChanged<T?>? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          DropdownButtonFormField<T>(
            initialValue: currentValue,
            decoration: InputDecoration(
              filled: true,
              fillColor: context.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: context.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: context.border),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            dropdownColor: context.surfaceMid,
            style: TextStyle(color: context.textPrimary),
            items: options.map((entry) {
              return DropdownMenuItem<T>(
                value: entry.key,
                child: Text(entry.value),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
