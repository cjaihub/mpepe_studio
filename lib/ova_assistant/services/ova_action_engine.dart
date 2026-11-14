import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../backend/ai_brain_service.dart';
import '../models/ova_context_model.dart';
import 'ova_native_service.dart';
import 'ova_context_service.dart';

final ovaActionEngineProvider = Provider<OvaActionEngine>((ref) {
  final native = ref.read(ovaNativeServiceProvider);
  final contextNotifier = ref.read(ovaContextProvider.notifier);
  final aiBrain = ref.watch(aiBrainProvider);
  return OvaActionEngine(native, contextNotifier, aiBrain: aiBrain);
});

class OvaActionEngine {
  final OvaNativeService _native;
  final OvaContextNotifier _contextNotifier;
  final AIBrainService? aiBrain;

  OvaActionEngine(
    this._native,
    this._contextNotifier, {
    this.aiBrain,
  });

  /// Default contextual quick action chips as shown in the screenshot
  List<ContextChip> getSuggestedChips() {
    return [
      const ContextChip(
        id: 'chip_whatsapp_photo',
        icon: Icons.call_end_outlined, // Phone/WhatsApp icon matching screenshot
        label: 'Send my recent photo to mom on Wh...',
        prompt: 'Send my recent photo to mom on WhatsApp',
      ),
      const ContextChip(
        id: 'chip_safari',
        icon: Icons.article_outlined, // "NEW" card icon matching screenshot
        prefixBadge: 'NEW',
        label: 'Plan a budget-friendly safari',
        prompt: 'Plan a budget-friendly safari',
      ),
      const ContextChip(
        id: 'chip_whatsapp_status',
        icon: Icons.call_end_outlined, // Phone/WhatsApp icon matching screenshot
        label: 'Check status updates on WhatsApp',
        prompt: 'Check status updates on WhatsApp',
      ),
      const ContextChip(
        id: 'chip_workstation_control',
        icon: Icons.desktop_mac_rounded,
        prefixBadge: 'PRO',
        label: 'Remote Workstation: Command & Automate',
        prompt: 'Remote Workstation automation and controls',
      ),
    ];
  }

  /// Evaluates and handles user command or message
  Future<OvaChatMessage> processCommand({
    required String prompt,
    required AssistantPersona persona,
    required PhoneContextState context,
  }) async {
    final lower = prompt.toLowerCase().trim();

    // 0. Studio Tool & AI Automation Dispatcher (Strictly restricted to Authenticated Users)
    _StudioCommandTarget? targetTool;
    if (lower.contains('pip') || lower.contains('picture in picture') || (lower.contains('reaction') && lower.contains('cam'))) {
      targetTool = const _StudioCommandTarget(
        title: 'PiP Studio',
        description: 'Simultaneous dual-camera reaction workstation with floating window.',
        route: '/create/camera?mode=pip',
        iconName: 'pip',
      );
    } else if (lower.contains('live') || lower.contains('go live') || lower.contains('cinema stage') || lower.contains('broadcast')) {
      targetTool = const _StudioCommandTarget(
        title: 'Cinema Live Stage',
        description: 'Multi-scene ultra-low latency live broadcast engine.',
        route: '/live/setup',
        iconName: 'live',
      );
    } else if (lower.contains('retouch') || (lower.contains('edit') && lower.contains('photo')) || lower.contains('photo studio') || lower.contains('enhance photo')) {
      targetTool = const _StudioCommandTarget(
        title: 'Photo Studio',
        description: 'RAW photo editing, HSL color wheels, and facial retouching.',
        route: '/photo/studio',
        iconName: 'photo',
      );
    } else if (lower.contains('control pc') || lower.contains('connect pc') || lower.contains('remote pc') || lower.contains('remote control')) {
      targetTool = const _StudioCommandTarget(
        title: 'Control PC',
        description: 'Wireless computer mouse, keyboard, and timeline actuation.',
        route: '/connect',
        iconName: 'pc',
      );
    } else if (lower.contains('caption') || lower.contains('subtitle')) {
      targetTool = const _StudioCommandTarget(
        title: 'Auto Captions',
        description: 'AI-generated kinetic animated subtitles synchronized to speech.',
        route: '/create/studio',
        iconName: 'captions',
      );
    } else if (lower.contains('avatar') || (lower.contains('ai') && lower.contains('brand')) || lower.contains('virtual presenter')) {
      targetTool = const _StudioCommandTarget(
        title: 'AI Brand Avatars',
        description: 'Hyper-realistic AI presenters generated from prompt scripts.',
        route: '/ai_studio?mode=avatars',
        iconName: 'avatar',
      );
    } else if (lower.contains('studio') || (lower.contains('create') && lower.contains('video'))) {
      targetTool = const _StudioCommandTarget(
        title: 'Oneova Studio',
        description: 'All-in-one executive studio production suite.',
        route: 'modal://studio',
        iconName: 'studio',
      );
    }

    if (targetTool != null) {
      final user = FirebaseAuth.instance.currentUser;
      final isAuthenticated = user != null && !user.isAnonymous;

      if (!isAuthenticated) {
        return OvaChatMessage(
          id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          text: '🔒 Studio Pro & Remote Automation are restricted to authenticated Oneova creators. Please sign in to your Oneova account to launch ${targetTool.title}.',
          timestamp: DateTime.now(),
          actionType: 'auth_required',
          actionData: {
            'toolTitle': targetTool.title,
            'route': targetTool.route,
          },
        );
      }

      return OvaChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: 'Creator authorized. Preparing ${targetTool.title} for your production session. Tap below to launch:',
        timestamp: DateTime.now(),
        actionType: 'studio_launch',
        actionData: {
          'toolTitle': targetTool.title,
          'description': targetTool.description,
          'route': targetTool.route,
          'iconName': targetTool.iconName,
        },
      );
    }

    // 0.5. Remote Workstation automation and commands
    if (lower.contains('workstation') || lower.contains('desktop command') || lower.contains('render timeline') || lower.contains('lock computer') || lower.contains('sync project')) {
      return OvaChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: "🖥️ **Oneova Remote Workstation AI Agent**\nReady to command your paired computer. Select an automation action or launch live 60fps mirror view with precision trackpad & touch gestures:",
        timestamp: DateTime.now(),
        actionType: 'studio_launch',
        actionData: {
          'toolTitle': 'Remote Workstation',
          'description': 'Mobile workstation control with InteractiveViewer pan/zoom & biometric unlock.',
          'route': '/connect',
          'iconName': 'pc',
        },
      );
    }

    // 1. Send recent photo to mom on WhatsApp
    if (lower.contains('photo') && (lower.contains('mom') || lower.contains('whatsapp'))) {
      final photo = context.recentPhotos.isNotEmpty ? context.recentPhotos.first : null;
      return OvaChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: "I found your recent photo \"${photo?.title ?? 'Studio Portrait'}\". Here's the preview to send to Mom on WhatsApp:",
        timestamp: DateTime.now(),
        actionType: 'whatsapp_send',
        actionData: {
          'recipientName': 'Mom ❤️',
          'phoneNumber': '+254712345678',
          'photoTitle': photo?.title ?? 'Studio Portrait',
          'photoPath': photo?.assetOrUrl ?? 'assets/images/oneova_logo.jpg',
          'timeAgo': photo?.timeAgo ?? 'Just now',
          'defaultMessage': 'Hi Mom! Here is the latest photo from our studio session 📸',
        },
      );
    }

    // 2. Plan a budget-friendly safari
    if (lower.contains('safari') || (lower.contains('plan') && lower.contains('budget'))) {
      return OvaChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: "Here is a hand-crafted, budget-friendly 3-Day Safari plan for Masai Mara & Lake Nakuru:",
        timestamp: DateTime.now(),
        actionType: 'safari_plan',
        actionData: {
          'title': '3-Day Mara & Rift Valley Expedition',
          'budget': '\$280 / person',
          'groupSize': 'Shared 4x4 Safari Land Cruiser (4-6 pax)',
          'days': [
            {
              'day': 'Day 1',
              'title': 'Nairobi to Masai Mara via Great Rift Valley',
              'details': 'Early pickup at 6:30 AM. Scenic viewpoint stop, arrive at eco-camp for lunch. Afternoon golden-hour game drive.',
            },
            {
              'day': 'Day 2',
              'title': 'Full Day Big Five & Mara River Crossing',
              'details': 'Sunrise game drive, tracking lion prides, cheetahs, and elephants. Picnic lunch by the river with hippos.',
            },
            {
              'day': 'Day 3',
              'title': 'Lake Nakuru Flamingos & Return to Nairobi',
              'details': 'Early bird drive in Nakuru, rhino sanctuary visit, return to Nairobi by 5:00 PM.',
            },
          ],
          'budgetTips': [
            'Book mid-week to save 30% on park entry permits.',
            'Opt for tented eco-camps outside the main gate.',
            'Bring your own refillable water flasks & binoculars.',
          ],
        },
      );
    }

    // 3. Check status updates on WhatsApp
    if (lower.contains('status') || (lower.contains('check') && lower.contains('whatsapp'))) {
      return OvaChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: "You have ${context.whatsappStatuses.length} recent status updates on WhatsApp. Here is a quick snapshot:",
        timestamp: DateTime.now(),
        actionType: 'whatsapp_status',
        actionData: {
          'statuses': context.whatsappStatuses.map((s) => {
            'name': s.contactName,
            'time': s.timeAgo,
            'preview': s.previewText,
          }).toList(),
        },
      );
    }

    // 4. Open Camera / Photos
    if (lower.contains('camera') || lower.contains('take photo')) {
      await _native.openCamera();
      return OvaChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: "Launching your camera now. Say cheese! 📸",
        timestamp: DateTime.now(),
        actionType: 'phone_control',
        actionData: {'action': 'camera', 'status': 'launched'},
      );
    }

    // 5. Open YouTube or other apps
    if (lower.contains('youtube')) {
      await _native.launchApp('youtube');
      return OvaChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: "Opening YouTube for you right now.",
        timestamp: DateTime.now(),
        actionType: 'phone_control',
        actionData: {'action': 'youtube', 'status': 'launched'},
      );
    }

    // 6. Device status inquiry ("what's going on", "battery", "phone status")
    if (lower.contains("what's going on") || lower.contains("status") || lower.contains("battery")) {
      await _contextNotifier.refresh();
      return OvaChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: "Here is what's happening on your phone right now:\n\n"
              "• Battery: ${(context.batteryLevel * 100).toInt()}%${context.isCharging ? ' (Charging)' : ''}\n"
              "• Network: ${context.networkType}\n"
              "• WhatsApp: ${context.unreadWhatsAppCount} unread status updates\n"
              "• Notifications: ${context.unreadNotificationsCount} alerts waiting\n"
              "• Recent Photo: \"${context.recentPhotos.firstOrNull?.title ?? 'Studio Portrait'}\" (${context.recentPhotos.firstOrNull?.timeAgo ?? 'Recent'})",
        timestamp: DateTime.now(),
      );
    }

    // 7. Live AI Brain Query (Gemini / OpenRouter Claude / GPT-4o)
    final brain = aiBrain;
    if (brain != null && brain.hasApiKey) {
      try {
        final phoneContextSummary = "Current Phone Context:\n"
            "- Battery: ${(context.batteryLevel * 100).toInt()}% ${context.isCharging ? '(Charging)' : ''}\n"
            "- Network: ${context.networkType}\n"
            "- Unread WhatsApp: ${context.unreadWhatsAppCount}\n"
            "- Unread Notifications: ${context.unreadNotificationsCount}\n"
            "- Recent Photos: ${context.recentPhotos.map((p) => p.title).join(', ')}\n"
            "- Active Persona: ${persona.name} (${persona.tagline})";

        final userPrompt = [
          {
            "role": "user",
            "content": prompt,
          }
        ];

        final aiRes = await brain.processRequest(
          userPrompt,
          userContextPrompt: phoneContextSummary,
        );

        if (aiRes is AiTextResponse && aiRes.text.trim().isNotEmpty && !aiRes.text.startsWith('Error:')) {
          return OvaChatMessage(
            id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
            isUser: false,
            text: aiRes.text.trim(),
            timestamp: DateTime.now(),
          );
        }
      } catch (e) {
        debugPrint('[OvaActionEngine] AI call error: $e');
      }
    }

    // 8. General Persona fallback response
    String reply;
    switch (persona.id) {
      case AssistantPersonaId.oneova:
        reply = "I'm right here with you! Oneova — the reason you matter. Whether you want to send photos, check messages, or organize your studio, just command me.";
        break;
      case AssistantPersonaId.ova:
        reply = "Ova Studio Engine is active and connected to your device. Ready to execute phone automation or content workflows whenever you are.";
        break;
      case AssistantPersonaId.onyx:
        reply = "Analyzing your request. I can optimize your phone workflow, plan itineraries, or coordinate tasks across your apps seamlessly.";
        break;
    }

    return OvaChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      isUser: false,
      text: reply,
      timestamp: DateTime.now(),
    );
  }

  /// Sends the photo to WhatsApp via native service
  Future<bool> sendPhotoToWhatsApp({
    required String phoneNumber,
    required String message,
  }) async {
    return await _native.openWhatsApp(
      phone: phoneNumber,
      message: message,
    );
  }
}

class _StudioCommandTarget {
  final String title;
  final String description;
  final String route;
  final String iconName;

  const _StudioCommandTarget({
    required this.title,
    required this.description,
    required this.route,
    required this.iconName,
  });
}
