import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/agent_workspace/ova_agent_models.dart';

void main() {
  group('OvaAgentModels Firestore sync serialization', () {
    test('OvaAgentSession round-trips mode, effort, fullComputerAccess, plan, and metadata', () {
      final now = DateTime.utc(2026, 11, 5, 1, 30);
      final session = OvaAgentSession(
        id: 'sess_100',
        title: 'Inspect Mac Studio & NLE export',
        agentMode: OvaAgentMode.computerUse,
        effort: OvaAgentEffort.deepThink,
        fullComputerAccess: false,
        status: 'running_tools',
        activeSubagent: 'Computer Use Agent',
        plan: const [
          OvaAgentPlanStep(
            id: 'p1',
            title: 'Inspect active macOS foreground app',
            status: OvaPlanStepStatus.completed,
          ),
          OvaAgentPlanStep(
            id: 'p2',
            title: 'Check disk space before 4K ProRes export',
            status: OvaPlanStepStatus.inProgress,
          ),
        ],
        lastPreview: 'Checking disk headroom...',
        originDevice: 'mobile',
        deviceId: 'desktop_u1_imac',
        computerName: 'imacs-iMac.local',
        turnCount: 2,
        pinned: true,
        updatedAtMs: now.millisecondsSinceEpoch,
        createdAt: now,
        updatedAt: now,
      );

      final map = session.toFirestoreMap();
      final decoded = OvaAgentSession.fromMap('sess_100', map);

      expect(decoded.id, 'sess_100');
      expect(decoded.agentMode, OvaAgentMode.computerUse);
      expect(decoded.effort, OvaAgentEffort.deepThink);
      expect(decoded.fullComputerAccess, isFalse);
      expect(decoded.status, 'running_tools');
      expect(decoded.pinned, isTrue);
      expect(decoded.plan.length, 2);
      expect(decoded.plan.first.status, OvaPlanStepStatus.completed);
      expect(decoded.plan.last.status, OvaPlanStepStatus.inProgress);
    });

    test('OvaAgentTurn round-trips thinking steps, full computer-use tools, and artifacts', () {
      final now = DateTime.utc(2026, 11, 5, 1, 35);
      final turn = OvaAgentTurn(
        id: 'turn_200',
        createdAtMs: now.millisecondsSinceEpoch,
        role: 'assistant',
        originDevice: 'mac',
        authorLabel: 'Computer Use Agent',
        text: 'Captured screen context and moved cursor.',
        status: 'awaiting_approval',
        thinkingSteps: const [
          'Checked foreground window and display coordinates.',
          'Prepared mouse click & AppleScript automation.',
        ],
        thinkingDurationMs: 1420,
        subagent: const OvaSubagentBadge(
          id: 'computer_use',
          label: 'Computer Use Agent',
          role: 'Full macOS automation',
        ),
        toolCalls: const [
          OvaAgentToolCall(
            id: 'tc_1',
            name: 'mouse_action',
            title: 'Click Safari address bar',
            args: {'action': 'click', 'x': 420, 'y': 86},
            requiresApproval: true,
            status: OvaToolCallStatus.awaitingApproval,
          ),
          OvaAgentToolCall(
            id: 'tc_2',
            name: 'capture_screen_context',
            title: 'Capture active windows',
            args: {'includeScreenshot': true},
            requiresApproval: false,
            status: OvaToolCallStatus.completed,
          ),
        ],
        artifacts: const [
          OvaAgentArtifact(
            id: 'art_1',
            title: 'Verify Script',
            kind: 'script',
            language: 'bash',
            content: '#!/usr/bin/env zsh\necho "Ready"',
          ),
        ],
        followUps: const ['Approve & run check', 'Inspect active window'],
        createdAt: now,
      );

      final map = turn.toFirestoreMap();
      final decoded = OvaAgentTurn.fromMap('turn_200', map);

      expect(decoded.hasPendingApprovals, isTrue);
      expect(decoded.thinkingSteps.length, 2);
      expect(decoded.thinkingDurationMs, 1420);
      expect(decoded.subagent?.label, 'Computer Use Agent');
      expect(decoded.toolCalls.first.icon, Icons.mouse_rounded);
      expect(decoded.toolCalls.last.icon, Icons.screenshot_monitor_rounded);
      expect(decoded.artifacts.single.language, 'bash');
      expect(decoded.followUps.length, 2);
    });

    test('Wispr targets and workspace view modes expose crisp labels', () {
      expect(OvaWisprTarget.macCursor.shortLabel, 'Mac Cursor');
      expect(OvaWorkspaceViewMode.wisprStudio.label, 'Wispr Flow');
      expect(OvaWorkspaceViewMode.inputDeck.label, 'Input Deck');
    });

    test('OvaAgentMemory serializes and deserializes accurately across mobile & mac', () {
      final now = DateTime.utc(2026, 11, 5, 2, 0);
      final mem = OvaAgentMemory(
        id: 'mem_1',
        key: 'preferred_editor',
        content: 'Visual Studio Code with Flutter & AGY extensions',
        originDevice: 'mac',
        updatedAt: now,
      );

      final map = mem.toMap();
      final decoded = OvaAgentMemory.fromMap('mem_1', map);

      expect(decoded.id, 'mem_1');
      expect(decoded.key, 'preferred_editor');
      expect(decoded.content, 'Visual Studio Code with Flutter & AGY extensions');
      expect(decoded.originDevice, 'mac');
      expect(decoded.updatedAt.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
    });

    test('OvaAgentToolCall assigns appropriate icons for computer control and memories', () {
      const callManageApp = OvaAgentToolCall(
        id: 'c1',
        name: 'manage_app',
        title: 'Manage App',
        args: {'action': 'activate', 'app_name': 'Safari'},
      );
      expect(callManageApp.icon, Icons.launch_rounded);

      const callMenu = OvaAgentToolCall(
        id: 'c2',
        name: 'navigate_app_menu',
        title: 'Menu Action',
        args: {'app_name': 'Safari', 'menu_bar_item': 'File', 'menu_item': 'New Window'},
      );
      expect(callMenu.icon, Icons.menu_open_rounded);

      const callHotkey = OvaAgentToolCall(
        id: 'c3',
        name: 'press_hotkey',
        title: 'Hotkey',
        args: {'keys': 'cmd+s'},
      );
      expect(callHotkey.icon, Icons.keyboard_command_key_rounded);

      const callSaveMem = OvaAgentToolCall(
        id: 'c4',
        name: 'save_memory',
        title: 'Save Memory',
        args: {'key': 'project_root', 'content': '/Users/imac/Projects'},
      );
      expect(callSaveMem.icon, Icons.psychology_rounded);
    });
  });
}
