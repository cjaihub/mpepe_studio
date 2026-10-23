import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/theme/app_theme.dart';

class AdvancedPostSettings {
  final String ageRestriction; // 'all', '13+', '16+', '18+'
  final String privacy; // 'public', 'followers', 'private'
  final bool allowComments;
  final bool allowDuet;
  final bool allowStitch;
  final bool allowDownload;
  final bool isAiGenerated;
  final bool isBrandedContent;
  final String geoRadiusTier; // 'local_10km', 'city_50km', 'regional', 'global'
  final String? location;
  final String? link;

  const AdvancedPostSettings({
    this.ageRestriction = 'all',
    this.privacy = 'public',
    this.allowComments = true,
    this.allowDuet = true,
    this.allowStitch = true,
    this.allowDownload = true,
    this.isAiGenerated = false,
    this.isBrandedContent = false,
    this.geoRadiusTier = 'global',
    this.location,
    this.link,
  });

  AdvancedPostSettings copyWith({
    String? ageRestriction,
    String? privacy,
    bool? allowComments,
    bool? allowDuet,
    bool? allowStitch,
    bool? allowDownload,
    bool? isAiGenerated,
    bool? isBrandedContent,
    String? geoRadiusTier,
    String? location,
    String? link,
  }) {
    return AdvancedPostSettings(
      ageRestriction: ageRestriction ?? this.ageRestriction,
      privacy: privacy ?? this.privacy,
      allowComments: allowComments ?? this.allowComments,
      allowDuet: allowDuet ?? this.allowDuet,
      allowStitch: allowStitch ?? this.allowStitch,
      allowDownload: allowDownload ?? this.allowDownload,
      isAiGenerated: isAiGenerated ?? this.isAiGenerated,
      isBrandedContent: isBrandedContent ?? this.isBrandedContent,
      geoRadiusTier: geoRadiusTier ?? this.geoRadiusTier,
      location: location ?? this.location,
      link: link ?? this.link,
    );
  }
}

class AdvancedSettingsSheet extends StatefulWidget {
  final AdvancedPostSettings initialSettings;
  final Function(AdvancedPostSettings settings) onSave;

  const AdvancedSettingsSheet({
    super.key,
    required this.initialSettings,
    required this.onSave,
  });

  @override
  State<AdvancedSettingsSheet> createState() => _AdvancedSettingsSheetState();
}

class _AdvancedSettingsSheetState extends State<AdvancedSettingsSheet> {
  late String _ageRestriction;
  late String _privacy;
  late bool _allowComments;
  late bool _allowDuet;
  late bool _allowStitch;
  late bool _allowDownload;
  late bool _isAiGenerated;
  late bool _isBrandedContent;
  late String _geoRadiusTier;
  late TextEditingController _locationController;
  late TextEditingController _linkController;

  @override
  void initState() {
    super.initState();
    final s = widget.initialSettings;
    _ageRestriction = s.ageRestriction;
    _privacy = s.privacy;
    _allowComments = s.allowComments;
    _allowDuet = s.allowDuet;
    _allowStitch = s.allowStitch;
    _allowDownload = s.allowDownload;
    _isAiGenerated = s.isAiGenerated;
    _isBrandedContent = s.isBrandedContent;
    _geoRadiusTier = s.geoRadiusTier;
    _locationController = TextEditingController(text: s.location ?? '');
    _linkController = TextEditingController(text: s.link ?? '');
  }

  @override
  void dispose() {
    _locationController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  void _save() {
    HapticFeedback.lightImpact();
    final updated = AdvancedPostSettings(
      ageRestriction: _ageRestriction,
      privacy: _privacy,
      allowComments: _allowComments,
      allowDuet: _allowDuet,
      allowStitch: _allowStitch,
      allowDownload: _allowDownload,
      isAiGenerated: _isAiGenerated,
      isBrandedContent: _isBrandedContent,
      geoRadiusTier: _geoRadiusTier,
      location: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
      link: _linkController.text.trim().isEmpty ? null : _linkController.text.trim(),
    );
    widget.onSave(updated);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: context.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Advanced Settings',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    minimumSize: const Size(0, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  child: Text(
                    'Save',
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: context.border, height: 1),

          // Content List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // 1. Age Restriction
                _buildSectionHeader('AGE RESTRICTION & AUDIENCE'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: context.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Set minimum age requirement for viewers',
                        style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _buildAgeChip('all', 'All Ages'),
                          const SizedBox(width: 6),
                          _buildAgeChip('13+', '13+ Teens'),
                          const SizedBox(width: 6),
                          _buildAgeChip('16+', '16+'),
                          const SizedBox(width: 6),
                          _buildAgeChip('18+', '18+ Mature'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 2. Who Can Watch (Privacy)
                _buildSectionHeader('WHO CAN WATCH THIS REEL'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: context.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: context.border),
                  ),
                  child: Column(
                    children: [
                      _buildRadioTile('public', 'Public', 'Anyone on Oneova can discover and watch', Icons.public),
                      Divider(color: context.border, height: 1),
                      _buildRadioTile('followers', 'Followers Only', 'Only approved followers can view', Icons.people_outline),
                      Divider(color: context.border, height: 1),
                      _buildRadioTile('private', 'Only Me (Private)', 'Only visible to you in your private studio', Icons.lock_outline),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 3. Interaction Controls
                _buildSectionHeader('INTERACTION CONTROLS'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: context.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: context.border),
                  ),
                  child: Column(
                    children: [
                      _buildSwitchTile('Allow Comments', 'Permit viewers to comment on this reel', _allowComments, (v) => setState(() => _allowComments = v)),
                      Divider(color: context.border, height: 1),
                      _buildSwitchTile('Allow Duet', 'Let creators make side-by-side duets with your video', _allowDuet, (v) => setState(() => _allowDuet = v)),
                      Divider(color: context.border, height: 1),
                      _buildSwitchTile('Allow Stitch', 'Let creators clip up to 5s into their own reels', _allowStitch, (v) => setState(() => _allowStitch = v)),
                      Divider(color: context.border, height: 1),
                      _buildSwitchTile('Allow High-Res Downloads', 'Allow viewers to download master copy to their device', _allowDownload, (v) => setState(() => _allowDownload = v)),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 4. Content Disclosures
                _buildSectionHeader('CONTENT DISCLOSURES'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: context.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: context.border),
                  ),
                  child: Column(
                    children: [
                      _buildSwitchTile(
                        'AI-Generated Content Label',
                        'Displays transparent "AI-Generated" badge required by safety standards',
                        _isAiGenerated,
                        (v) => setState(() => _isAiGenerated = v),
                      ),
                      Divider(color: context.border, height: 1),
                      _buildSwitchTile(
                        'Paid Partnership / Branded',
                        'Displays "Paid Partnership" disclosure banner above caption',
                        _isBrandedContent,
                        (v) => setState(() => _isBrandedContent = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 5. Geo-Radius Tier & Location
                _buildSectionHeader('GEO DISCOVERY & REACH'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: context.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Algorithmic Distribution Radius', style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildGeoChip('local_10km', 'Local 10km'),
                          const SizedBox(width: 6),
                          _buildGeoChip('city_50km', 'City 50km'),
                          const SizedBox(width: 6),
                          _buildGeoChip('regional', 'Regional'),
                          const SizedBox(width: 6),
                          _buildGeoChip('global', 'Global 🌍'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _locationController,
                        style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(Icons.location_on_outlined, size: 18),
                          hintText: 'Add location (e.g. Nairobi, Kenya)',
                          hintStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            borderSide: BorderSide(color: context.border),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _linkController,
                        style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(Icons.link_rounded, size: 18),
                          hintText: 'Add an action link (https://...)',
                          hintStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            borderSide: BorderSide(color: context.border),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.inter(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: context.textMuted,
      ),
    );
  }

  Widget _buildAgeChip(String code, String label) {
    final isSelected = _ageRestriction == code;
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _ageRestriction = code);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.brandBlue : context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: isSelected ? AppColors.brandBlue : context.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.white : context.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGeoChip(String code, String label) {
    final isSelected = _geoRadiusTier == code;
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _geoRadiusTier = code);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.brandPink : context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: isSelected ? AppColors.brandPink : context.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.white : context.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRadioTile(String code, String title, String subtitle, IconData icon) {
    final isSelected = _privacy == code;
    return ListTile(
      dense: true,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _privacy = code);
      },
      leading: Icon(icon, size: 20, color: isSelected ? AppColors.brandBlue : context.textSecondary),
      title: Text(
        title,
        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(fontSize: 11, color: context.textMuted),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, size: 18, color: AppColors.brandBlue)
          : const Icon(Icons.circle_outlined, size: 18, color: Colors.grey),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      dense: true,
      title: Text(
        title,
        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(fontSize: 11, color: context.textMuted),
      ),
      activeThumbColor: AppColors.brandBlue,
      value: value,
      onChanged: (v) {
        HapticFeedback.lightImpact();
        onChanged(v);
      },
    );
  }
}
