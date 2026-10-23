import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oneova/backend/remote_connect_service.dart';
import '../../shared/theme/app_theme.dart';

class DeviceInfoDialog extends StatelessWidget {
  final LinkedComputer computer;

  const DeviceInfoDialog({super.key, required this.computer});

  @override
  Widget build(BuildContext context) {
    final info = computer.systemInfo;
    final isMac = computer.os.toLowerCase().contains('mac') || computer.os.toLowerCase().contains('darwin');

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 350,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF262626), // Classic dark grey macOS style
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 40,
              spreadRadius: 10,
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Close Button row
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(
                      color: AppColors.brandBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: Color(0xFFD4AF37), // ONEROVA Gold style
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.neonGreen.withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Monitor Icon
            Icon(
              isMac ? Icons.desktop_mac : Icons.laptop_chromebook,
              size: 100,
              color: Colors.white.withValues(alpha: 0.9),
            ),
            const SizedBox(height: 16),
            Text(
              computer.name,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            ...[
            const SizedBox(height: 4),
            Text(
              info['os_version'] ?? computer.os,
              style: GoogleFonts.inter(
                color: Colors.white54,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 32),
            _buildInfoRow('Processor', info['processor'] ?? 'Unknown'),
            _buildInfoRow('Graphics', info['graphics'] ?? 'Unknown'),
            _buildInfoRow('Memory', info['memory'] ?? 'Unknown'),
            _buildInfoRow('Serial number', info['serial_number'] ?? 'Unknown'),
            _buildInfoRow(isMac ? 'macOS' : 'OS', info['os_version'] ?? 'Unknown'),
          ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'More Info...',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Regulatory Certification\n™ and © 1983-${DateTime.now().year} Onerova.\nAll Rights Reserved.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white30,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 7,
            child: Text(
              value,
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
