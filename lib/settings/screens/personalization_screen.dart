import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../backend/recommendation/ova_taste_learner.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/compact/compact.dart';

/// `/settings/personalization`: what Oneova learned about your tastes, from
/// what you watch and your Ova chats. On until you turn it off. Private to you.
class PersonalizationScreen extends StatefulWidget {
  const PersonalizationScreen({super.key});

  @override
  State<PersonalizationScreen> createState() => _PersonalizationScreenState();
}

class _PersonalizationScreenState extends State<PersonalizationScreen> {
  final _learner = OvaTasteLearner.instance;
  bool? _on;
  bool? _sensitive;

  @override
  void initState() {
    super.initState();
    _learner.enabled().then((v) {
      if (mounted) setState(() => _on = v);
    });
    _learner.sensitiveAllowed().then((v) {
      if (mounted) setState(() => _sensitive = v);
    });
  }

  /// Explicit consent for special-category topics (GDPR art. 9, Kenya DPA, NDPA).
  Future<void> _setSensitive(bool v) async {
    if (v) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Include health, faith, politics and money?'),
          content: const Text(
            'Ova may learn interests like "fitness", "gospel", "elections" or "budgeting" from your chats, so your feed '
            'can show more of them. These topics stay private to your account, are used only for your own feed, and '
            'are never used for ads or shared. Turn this off any time and they are deleted. '
            'Sexuality, sexual content, ethnicity and crime are never learned.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('I agree')),
          ],
        ),
      );
      if (yes != true) return;
    }
    setState(() => _sensitive = v);
    await _learner.setSensitiveAllowed(v);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _profile() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid).collection('algorithmic_state').doc('current').snapshots();
  }

  Future<void> _reset() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reset your tastes?'),
        content: const Text('Your feed starts fresh and learns again from what you watch and ask Ova.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reset')),
        ],
      ),
    );
    if (yes == true) await _learner.resetAll();
  }

  @override
  Widget build(BuildContext context) {
    final stream = _profile();
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        toolbarHeight: 50,
        title: Text('Personalisation', style: AppTypography.pageTitle(context.textPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          CompactGroup(children: [
            CompactRow(
              icon: Icons.auto_awesome_rounded,
              title: 'Personalise my feed',
              subtitle: 'Learns from what you watch and your Ova chats',
              showChevron: false,
              trailing: Switch.adaptive(
                value: _on ?? true,
                activeTrackColor: AppColors.brandBlue,
                onChanged: _on == null
                    ? null
                    : (v) async {
                        setState(() => _on = v);
                        await _learner.setEnabled(v);
                      },
              ),
            ),
            CompactRow(
              icon: Icons.health_and_safety_outlined,
              title: 'Include sensitive topics',
              subtitle: 'Health, faith, politics and money. Off unless you agree',
              showChevron: false,
              trailing: Switch.adaptive(
                value: _sensitive ?? false,
                activeTrackColor: AppColors.brandBlue,
                onChanged: _sensitive == null || _on == false ? null : _setSensitive,
              ),
            ),
          ]),
          if (stream != null)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                final data = snap.data?.data() ?? const {};
                final topics = <String, double>{
                  for (final e in ((data['topicAffinities'] as Map?) ?? const {}).entries)
                    if (e.value is num) e.key as String: (e.value as num).toDouble(),
                };
                final fromOva = ((data['ovaTopics'] as Map?) ?? const {}).keys.cast<String>().toSet();
                final list = topics.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CompactSectionHeader('What you like', trailing: list.isEmpty ? null : Text('${list.length}', style: AppTypography.caption(context.textMuted))),
                    if (list.isEmpty)
                      Text('Nothing learned yet. Watch, like and chat with Ova, and your feed will follow.',
                          style: AppTypography.small(context.textSecondary))
                    else
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final e in list.take(40))
                          InputChip(
                            label: Text(e.key, style: AppTypography.small(context.textPrimary)),
                            avatar: fromOva.contains(e.key) ? const Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.brandBlue) : null,
                            visualDensity: VisualDensity.compact,
                            backgroundColor: context.surfaceMid,
                            side: BorderSide(color: context.border),
                            deleteIconColor: context.textMuted,
                            onDeleted: () => _learner.forget(e.key),
                          ),
                      ]),
                    if (list.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      CompactGroup(children: [
                        CompactRow(icon: Icons.restart_alt_rounded, title: 'Reset everything learned', onTap: _reset, destructive: true),
                      ]),
                    ],
                  ],
                );
              },
            ),
          const SizedBox(height: 14),
          Text(
            'Only you and Oneova’s feed see this. Your Ova chats aren’t kept for it, only short topic words. '
            'Health, faith, politics and money are learned only if you turn on sensitive topics. Sexuality, sexual '
            'content, ethnicity, crime and anything that identifies you are never learned. ✦ marks topics from Ova.',
            style: AppTypography.caption(context.textMuted),
          ),
        ],
      ),
    );
  }
}
