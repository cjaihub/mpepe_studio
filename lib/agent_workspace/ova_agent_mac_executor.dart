import 'dart:async';
import 'dart:io';

import '../backend/native_plugin_server.dart';
import '../desktop_agent/desktop_firebase_rest_client.dart';
import '../desktop_agent/macos_mouse_ffi.dart';
import 'ova_agent_models.dart';

class OvaMacToolExecutionResult {
  final bool ok;
  final String output;
  final int exitCode;
  final int durationMs;

  const OvaMacToolExecutionResult({
    required this.ok,
    required this.output,
    this.exitCode = 0,
    required this.durationMs,
  });
}

/// Executes full-access or supervised macOS computer-use primitives (mouse,
/// keyboard, Wispr instant paste, AppleScript, screen/window perception,
/// clipboard, filesystem, shell, system controls & NLE bridge) and syncs
/// structured results in real time across Desktop and Mobile.
class OvaAgentMacExecutor {
  OvaAgentMacExecutor._();
  static final OvaAgentMacExecutor instance = OvaAgentMacExecutor._();

  Future<void> Function(String combo)? onSendHotkey;
  Future<void> Function(String text)? onTypeText;
  Future<String?> Function()? onGetActiveWindow;
  void Function(String logEntry)? onAuditLog;

  static String expandHomePath(String rawPath) {
    final trimmed = rawPath.trim();
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    if (trimmed.isEmpty || trimmed == '~') return home;
    if (trimmed.startsWith('~/')) {
      return '$home/${trimmed.substring(2)}';
    }
    return trimmed;
  }

  Future<OvaMacToolExecutionResult> execute(OvaAgentToolCall call) async {
    final sw = Stopwatch()..start();
    if (!Platform.isMacOS) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'Workstation tool "${call.name}" requires an online macOS agent.',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }

    onAuditLog?.call('Agent Tool • ${call.name}');

    try {
      switch (call.name) {
        case 'inspect_workstation':
          return await _inspectWorkstation(sw);
        case 'capture_screen_context':
          return await _captureScreenContext(call.args, sw);
        case 'list_open_windows':
          return await _listOpenWindows(sw);
        case 'open_mac_app':
          return await _openMacApp(call.args, sw);
        case 'manage_app':
          return await _manageApp(call.args, sw);
        case 'navigate_app_menu':
          return await _navigateAppMenu(call.args, sw);
        case 'click_ui_element':
          return await _clickUiElement(call.args, sw);
        case 'press_hotkey':
          return await _pressHotkey(call.args, sw);
        case 'manage_computer_system':
          return await _manageComputerSystem(call.args, sw);
        case 'save_memory':
          return await _saveMemory(call.args, sw);
        case 'recall_memories':
          return await _recallMemories(call.args, sw);
        case 'delete_memory':
          return await _deleteMemory(call.args, sw);
        case 'mouse_action':
          return await _mouseAction(call.args, sw);
        case 'keyboard_action':
          return await _keyboardAction(call.args, sw);
        case 'clipboard_action':
          return await _clipboardAction(call.args, sw);
        case 'run_applescript':
          return await _runAppleScript(call.args, sw);
        case 'system_control':
          return await _systemControl(call.args, sw);
        case 'list_workspace_files':
          return await _listWorkspaceFiles(call.args, sw);
        case 'read_file_snippet':
          return await _readFileSnippet(call.args, sw);
        case 'nle_bridge_action':
          return await _nleBridgeAction(call.args, sw);
        case 'send_mac_hotkey':
          return await _sendHotkey(call.args, sw);
        case 'type_on_workstation':
          return await _typeText(call.args, sw);
        case 'run_terminal_command':
          return await _runTerminalCommand(call.args, sw);
        case 'write_workspace_file':
          return await _writeWorkspaceFile(call.args, sw);
        case 'power_workstation':
          return await _powerWorkstation(call.args, sw);
        case 'search_web':
          return await _searchWeb(call.args, sw);
        case 'search_workspace':
          return await _searchWorkspace(call.args, sw);
        default:
          sw.stop();
          return OvaMacToolExecutionResult(
            ok: false,
            output: 'Unsupported tool: ${call.name}',
            exitCode: 1,
            durationMs: sw.elapsedMilliseconds,
          );
      }
    } catch (e) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'Tool error (${call.name}): $e',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  Future<OvaMacToolExecutionResult> _inspectWorkstation(Stopwatch sw) async {
    String activeApp = (await onGetActiveWindow?.call()) ?? '';
    if (activeApp.isEmpty) {
      activeApp = (await MacOSMouseController.getActiveAppName()) ?? '';
    }
    final bounds = MacOSMouseController.getMainDisplayBounds();
    final cursor = MacOSMouseController.getCursorPosition();
    final uptimeRes = await Process.run('uptime', const []);
    final dfRes = await Process.run('df', const ['-h', '/']);
    final appsRes = await Process.run(
      'zsh',
      const [
        '-lc',
        r"ps -axo comm= | awk -F/ '{print $NF}' | sort -u | grep -Ei 'Finder|Xcode|Code|Cursor|Final Cut|Premiere|Resolve|Logic|Safari|Chrome|Notes|Terminal|OneOva' | head -n 20",
      ],
    );

    final buf = StringBuffer()
      ..writeln('Host: ${Platform.localHostname}')
      ..writeln('OS: ${Platform.operatingSystem} (${Platform.operatingSystemVersion})')
      ..writeln('CPU Cores: ${Platform.numberOfProcessors}')
      ..writeln('Main Display: ${bounds.width}x${bounds.height}')
      ..writeln(
        'Cursor Position: (${cursor.x.toStringAsFixed(0)}, ${cursor.y.toStringAsFixed(0)})',
      )
      ..writeln('Foreground App: ${activeApp.isEmpty ? "Desktop" : activeApp}')
      ..writeln('Uptime / Load: ${uptimeRes.stdout.toString().trim()}')
      ..writeln('\nDisk (/):')
      ..writeln(dfRes.stdout.toString().trim());

    final runningNotable = appsRes.stdout.toString().trim();
    if (runningNotable.isNotEmpty) {
      buf
        ..writeln('\nActive Studio & Dev Processes:')
        ..writeln(runningNotable);
    }

    sw.stop();
    return OvaMacToolExecutionResult(
      ok: true,
      output: _truncate(buf.toString()),
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _captureScreenContext(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final bounds = MacOSMouseController.getMainDisplayBounds();
    final cursor = MacOSMouseController.getCursorPosition();
    final activeApp =
        (await MacOSMouseController.getActiveAppName()) ?? 'Desktop';
    final clip = await MacOSMouseController.readClipboard();
    final clipPreview = clip.trim().isEmpty
        ? '(empty)'
        : (clip.length > 260 ? '${clip.substring(0, 260)}…' : clip.trim());

    final windowsRes = await Process.run('osascript', const [
      '-e',
      'tell application "System Events" to get {name, title of windows} of (every application process whose visible is true)',
    ]);

    String snapNote = '';
    if (args['includeScreenshot'] != false) {
      final snapPath =
          '${Directory.systemTemp.path}/oneova_agent_screen_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final sc = await Process.run(
        'screencapture',
        ['-x', '-t', 'jpg', snapPath],
      );
      if (sc.exitCode == 0 && await File(snapPath).exists()) {
        final sz = await File(snapPath).length();
        snapNote =
            'Captured live screen frame (${_formatBytes(sz)}) at $snapPath.';
        unawaited(
          Future<void>.delayed(const Duration(seconds: 30), () async {
            try {
              await File(snapPath).delete();
            } catch (_) {}
          }),
        );
      } else {
        snapNote = 'Screen snapshot metadata collected via System Events.';
      }
    }

    final buf = StringBuffer()
      ..writeln('Foreground App: $activeApp')
      ..writeln('Display Resolution: ${bounds.width}x${bounds.height}')
      ..writeln(
        'Mouse Coordinates: (${cursor.x.toStringAsFixed(0)}, ${cursor.y.toStringAsFixed(0)})',
      )
      ..writeln('Clipboard Preview: $clipPreview');
    if (snapNote.isNotEmpty) {
      buf.writeln('Snapshot: $snapNote');
    }
    final winOut = windowsRes.stdout.toString().trim();
    if (winOut.isNotEmpty) {
      buf
        ..writeln('\nVisible Application Windows:')
        ..writeln(winOut);
    }

    sw.stop();
    return OvaMacToolExecutionResult(
      ok: true,
      output: _truncate(buf.toString()),
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _listOpenWindows(Stopwatch sw) async {
    const script = '''
set outputLines to {}
tell application "System Events"
  repeat with proc in (every application process whose background only is false)
    set procName to name of proc
    try
      set winNames to name of every window of proc
      if (count of winNames) > 0 then
        repeat with w in winNames
          set end of outputLines to procName & " :: " & (w as text)
        end repeat
      else
        set end of outputLines to procName & " :: (running, no titled window)"
      end if
    end try
  end repeat
end tell
set AppleScript's text item delimiters to linefeed
return outputLines as text
''';
    final res = await Process.run('osascript', ['-e', script]);
    sw.stop();
    final out = res.stdout.toString().trim();
    return OvaMacToolExecutionResult(
      ok: res.exitCode == 0,
      output: out.isNotEmpty
          ? _truncate(out)
          : 'No visible windows reported (${res.stderr.toString().trim()}).',
      exitCode: res.exitCode,
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _openMacApp(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final url = (args['url'] ?? '').toString().trim();
    final appName = (args['appName'] ?? args['app'] ?? '').toString().trim();

    ProcessResult res;
    if (url.isNotEmpty && appName.isNotEmpty) {
      res = await Process.run('open', ['-a', appName, url]);
    } else if (url.isNotEmpty) {
      res = await Process.run('open', [url]);
    } else {
      final target = appName.isEmpty ? 'Finder' : appName;
      res = await Process.run('open', ['-a', target]);
    }
    sw.stop();
    final ok = res.exitCode == 0;
    return OvaMacToolExecutionResult(
      ok: ok,
      output: ok
          ? 'Focused / opened "${appName.isNotEmpty ? appName : url}" on ${Platform.localHostname}.'
          : 'Could not open target: ${res.stderr.toString().trim()}',
      exitCode: res.exitCode,
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _mouseAction(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final action = (args['action'] ?? 'click').toString().trim().toLowerCase();
    final x = (args['x'] as num?)?.toDouble();
    final y = (args['y'] as num?)?.toDouble();
    final dx = (args['dx'] as num?)?.toDouble() ?? 0.0;
    final dy = (args['dy'] as num?)?.toDouble() ?? 0.0;

    switch (action) {
      case 'move_to':
        if (x != null && y != null) {
          MacOSMouseController.moveTo(x, y);
        }
      case 'move_by':
        MacOSMouseController.moveBy(dx, dy);
      case 'click':
        if (x != null && y != null) {
          MacOSMouseController.clickAt(x, y);
        } else {
          MacOSMouseController.click();
        }
      case 'double_click':
        if (x != null && y != null) {
          MacOSMouseController.clickAt(x, y, doubleClick: true);
        } else {
          MacOSMouseController.doubleClick();
        }
      case 'right_click':
        if (x != null && y != null) {
          MacOSMouseController.clickAt(x, y, right: true);
        } else {
          MacOSMouseController.rightClick();
        }
      case 'drag_to':
        if (x != null && y != null) {
          await MacOSMouseController.dragTo(x, y);
        }
      case 'scroll':
        MacOSMouseController.scroll(dy != 0 ? dy : -120);
      default:
        MacOSMouseController.click();
    }

    final pos = MacOSMouseController.getCursorPosition();
    sw.stop();
    return OvaMacToolExecutionResult(
      ok: true,
      output:
          'Executed mouse_action "$action" • cursor now at (${pos.x.toStringAsFixed(0)}, ${pos.y.toStringAsFixed(0)}).',
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _keyboardAction(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final action =
        (args['action'] ?? 'paste_text').toString().trim().toLowerCase();
    final text = (args['text'] ?? '').toString();
    final combo = (args['combo'] ?? '').toString().trim();
    final key = (args['key'] ?? '').toString().trim();
    final pressEnter = args['pressEnter'] == true;

    if (action == 'hotkey' && combo.isNotEmpty) {
      await MacOSMouseController.sendHotkey(combo);
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: true,
        output: 'Dispatched shortcut "$combo" on ${Platform.localHostname}.',
        durationMs: sw.elapsedMilliseconds,
      );
    }

    if (action == 'key_tap' && key.isNotEmpty) {
      await MacOSMouseController.tapKey(key);
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: true,
        output: 'Tapped key "$key" on ${Platform.localHostname}.',
        durationMs: sw.elapsedMilliseconds,
      );
    }

    if (action == 'type_keys' && text.isNotEmpty) {
      await MacOSMouseController.typeString(text);
      if (pressEnter) await MacOSMouseController.tapKey('enter');
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: true,
        output: 'Typed ${text.length} chars into active macOS window.',
        durationMs: sw.elapsedMilliseconds,
      );
    }

    await MacOSMouseController.pasteTextInstant(
      text,
      pressEnter: pressEnter,
    );
    sw.stop();
    return OvaMacToolExecutionResult(
      ok: true,
      output:
          'Injected ${text.length} chars instantaneously into focused Mac cursor${pressEnter ? " + Return" : ""}.',
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _clipboardAction(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final action = (args['action'] ?? 'read').toString().toLowerCase();
    if (action == 'write') {
      final text = (args['text'] ?? '').toString();
      final ok = await MacOSMouseController.writeClipboard(text);
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: ok,
        output: ok
            ? 'Copied ${text.length} chars to macOS clipboard.'
            : 'Failed to write clipboard.',
        exitCode: ok ? 0 : 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }
    final content = await MacOSMouseController.readClipboard();
    sw.stop();
    return OvaMacToolExecutionResult(
      ok: true,
      output: content.isEmpty
          ? '(Clipboard is currently empty)'
          : _truncate(content),
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _runAppleScript(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final script = (args['script'] ?? '').toString().trim();
    if (script.isEmpty) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'Missing AppleScript source.',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }
    final res = await Process.run('osascript', ['-e', script])
        .timeout(const Duration(seconds: 20));
    sw.stop();
    final out = res.stdout.toString().trim();
    final err = res.stderr.toString().trim();
    return OvaMacToolExecutionResult(
      ok: res.exitCode == 0,
      output: _truncate(
        [
          if (out.isNotEmpty) out,
          if (err.isNotEmpty) 'stderr: $err',
          if (out.isEmpty && err.isEmpty)
            'AppleScript completed (exit ${res.exitCode}).',
        ].join('\n'),
      ),
      exitCode: res.exitCode,
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _systemControl(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final action =
        (args['action'] ?? 'wake_display').toString().trim().toLowerCase();
    final val = ((args['value'] as num?)?.toInt() ?? 50).clamp(0, 100);
    final query = (args['query'] ?? '').toString().trim();

    switch (action) {
      case 'set_volume':
        await Process.run(
            'osascript', ['-e', 'set volume output volume $val']);
        sw.stop();
        return OvaMacToolExecutionResult(
          ok: true,
          output: 'Set macOS output volume to $val%.',
          durationMs: sw.elapsedMilliseconds,
        );
      case 'mute_toggle':
        final res = await Process.run('osascript', const [
          '-e',
          'set curMute to output muted of (get volume settings)\nset volume output muted (not curMute)\nreturn (not curMute)',
        ]);
        sw.stop();
        return OvaMacToolExecutionResult(
          ok: res.exitCode == 0,
          output: 'Toggled macOS audio mute (${res.stdout.toString().trim()}).',
          exitCode: res.exitCode,
          durationMs: sw.elapsedMilliseconds,
        );
      case 'media_play_pause':
        await Process.run('osascript', const [
          '-e',
          'try\ntell application "Music" to playpause\nend try',
        ]);
        sw.stop();
        return OvaMacToolExecutionResult(
          ok: true,
          output: 'Dispatched macOS media Play/Pause.',
          durationMs: sw.elapsedMilliseconds,
        );
      case 'media_next':
        await Process.run('osascript', const [
          '-e',
          'try\ntell application "Music" to next track\nend try',
        ]);
        sw.stop();
        return OvaMacToolExecutionResult(
          ok: true,
          output: 'Skipped to next media track.',
          durationMs: sw.elapsedMilliseconds,
        );
      case 'media_prev':
        await Process.run('osascript', const [
          '-e',
          'try\ntell application "Music" to previous track\nend try',
        ]);
        sw.stop();
        return OvaMacToolExecutionResult(
          ok: true,
          output: 'Returned to previous media track.',
          durationMs: sw.elapsedMilliseconds,
        );
      case 'screenshot_to_desktop':
        final target = expandHomePath(
          '~/Desktop/Oneova_Capture_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        final sc = await Process.run('screencapture', ['-x', target]);
        sw.stop();
        return OvaMacToolExecutionResult(
          ok: sc.exitCode == 0,
          output: sc.exitCode == 0
              ? 'Saved full-resolution macOS screenshot to $target.'
              : 'Screenshot failed: ${sc.stderr}',
          exitCode: sc.exitCode,
          durationMs: sw.elapsedMilliseconds,
        );
      case 'spotlight_search':
        await MacOSMouseController.sendHotkey('cmd+space');
        if (query.isNotEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 180));
          await MacOSMouseController.pasteTextInstant(query);
        }
        sw.stop();
        return OvaMacToolExecutionResult(
          ok: true,
          output:
              'Opened macOS Spotlight${query.isNotEmpty ? ' with "$query"' : ''}.',
          durationMs: sw.elapsedMilliseconds,
        );
      case 'sleep_display':
        return _powerWorkstation({'action': 'sleep_display'}, sw);
      case 'wake_display':
      default:
        return _powerWorkstation({'action': 'wake_display'}, sw);
    }
  }

  Future<OvaMacToolExecutionResult> _listWorkspaceFiles(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final targetPath = expandHomePath((args['path'] ?? '~').toString());
    final dir = Directory(targetPath);
    if (!await dir.exists()) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'Directory does not exist: $targetPath',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }

    final entities = await dir.list(followLinks: false).take(80).toList();
    final rows = <String>[];
    for (final entity in entities) {
      final stat = await entity.stat();
      final name = entity.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .lastOrNull ??
          entity.path;
      final isDir = stat.type == FileSystemEntityType.directory;
      final sizeLabel = isDir ? '<DIR>' : _formatBytes(stat.size);
      rows.add(
          '${isDir ? "d" : "-"}  ${sizeLabel.padLeft(9)}  $name${isDir ? "/" : ""}');
    }
    rows.sort();

    sw.stop();
    return OvaMacToolExecutionResult(
      ok: true,
      output:
          'Directory: $targetPath (${rows.length} items)\n${rows.join('\n')}',
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _readFileSnippet(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final filePath = expandHomePath((args['path'] ?? '').toString());
    final maxLines =
        ((args['maxLines'] as num?)?.toInt() ?? 120).clamp(10, 250);
    final file = File(filePath);
    if (!await file.exists()) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'File not found: $filePath',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }

    final stat = await file.stat();
    if (stat.size > 2 * 1024 * 1024) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output:
            'File is larger than 2 MB (${_formatBytes(stat.size)}). Use run_terminal_command with head/grep for large binaries.',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }

    final lines = await file.readAsLines();
    final slice = lines.take(maxLines).toList();
    final numbered = <String>[
      for (var i = 0; i < slice.length; i++)
        '${(i + 1).toString().padLeft(4)}: ${slice[i]}',
    ];
    if (lines.length > maxLines) {
      numbered.add('... (${lines.length - maxLines} more lines)');
    }

    sw.stop();
    return OvaMacToolExecutionResult(
      ok: true,
      output: _truncate(
          'File: $filePath (${lines.length} lines)\n${numbered.join('\n')}'),
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _nleBridgeAction(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final action = (args['action'] ?? 'play_pause').toString().trim();
    NativePluginServer().broadcastCommand(action, args);

    final combo = switch (action) {
      'save_project' => 'cmd+s',
      'export_timeline' => 'cmd+e',
      'fullscreen' => 'cmd+ctrl+f',
      'add_marker' => 'm',
      'blade_cut' => 'cmd+b',
      'undo' => 'cmd+z',
      _ => 'space',
    };
    if (onSendHotkey != null) {
      await onSendHotkey!(combo);
    } else {
      await MacOSMouseController.sendHotkey(combo);
    }
    sw.stop();
    return OvaMacToolExecutionResult(
      ok: true,
      output:
          'Broadcasted NLE action "$action" over ws://127.0.0.1:8080 and dispatched "$combo".',
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _sendHotkey(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final combo = (args['combo'] ?? '').toString().trim();
    if (combo.isEmpty) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'Missing shortcut combo.',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }
    if (onSendHotkey != null) {
      await onSendHotkey!(combo);
    } else {
      await MacOSMouseController.sendHotkey(combo);
    }
    sw.stop();
    return OvaMacToolExecutionResult(
      ok: true,
      output: 'Dispatched shortcut "$combo" on ${Platform.localHostname}.',
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _typeText(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final text = (args['text'] ?? '').toString();
    await MacOSMouseController.pasteTextInstant(
      text,
      pressEnter: args['pressEnter'] == true,
    );
    sw.stop();
    return OvaMacToolExecutionResult(
      ok: true,
      output:
          'Injected ${text.length} characters instantaneously into active macOS window.',
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _runTerminalCommand(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final command = (args['command'] ?? '').toString().trim();
    if (command.isEmpty) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'Empty shell command.',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }
    final cwd = expandHomePath((args['cwd'] ?? '~').toString());
    final res = await Process.run(
      'zsh',
      ['-lc', command],
      workingDirectory: await Directory(cwd).exists() ? cwd : null,
    ).timeout(const Duration(seconds: 30));

    final stdoutStr = res.stdout.toString().trim();
    final stderrStr = res.stderr.toString().trim();
    final combined = [
      '\$ $command',
      if (stdoutStr.isNotEmpty) stdoutStr,
      if (stderrStr.isNotEmpty) 'stderr:\n$stderrStr',
      '[exit ${res.exitCode}]',
    ].join('\n');

    sw.stop();
    return OvaMacToolExecutionResult(
      ok: res.exitCode == 0,
      output: _truncate(combined),
      exitCode: res.exitCode,
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _writeWorkspaceFile(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final path = expandHomePath((args['path'] ?? '').toString());
    final content = (args['content'] ?? '').toString();
    if (path.isEmpty) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'Target file path is required.',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    sw.stop();
    return OvaMacToolExecutionResult(
      ok: true,
      output: 'Wrote ${content.length} chars to $path.',
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _powerWorkstation(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final action = (args['action'] ?? 'sleep_display').toString();
    final res = action == 'wake_display'
        ? await Process.run('caffeinate', const ['-u', '-t', '2'])
        : await Process.run('pmset', const ['displaysleepnow']);
    sw.stop();
    return OvaMacToolExecutionResult(
      ok: res.exitCode == 0,
      output: 'Executed power action "$action" (exit ${res.exitCode}).',
      exitCode: res.exitCode,
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _searchWeb(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final query = (args['query'] ?? args['q'] ?? '').toString().trim();
    if (query.isEmpty) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'Missing search query.',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }

    try {
      final encoded = Uri.encodeQueryComponent(query);
      final res = await Process.run(
        'curl',
        [
          '-sL',
          '--max-time',
          '10',
          '-A',
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
          'https://html.duckduckgo.com/html/?q=$encoded',
        ],
      );

      final rawHtml = (res.stdout ?? '').toString();
      final snippetRegex =
          RegExp(r'<a class="result__snippet[^>]*>(.*?)<\/a>', dotAll: true);
      final urlRegex =
          RegExp(r'<a class="result__url[^>]*>(.*?)<\/a>', dotAll: true);

      final matches = snippetRegex.allMatches(rawHtml).take(6).toList();
      final urlMatches = urlRegex.allMatches(rawHtml).take(6).toList();

      final snippets = <String>[];
      for (var i = 0; i < matches.length; i++) {
        final text = matches[i]
                .group(1)
                ?.replaceAll(RegExp(r'<[^>]*>'), '')
                .replaceAll('&quot;', '"')
                .replaceAll('&amp;', '&')
                .replaceAll('&#x27;', "'")
                .trim() ??
            '';
        final url = i < urlMatches.length
            ? urlMatches[i]
                    .group(1)
                    ?.replaceAll(RegExp(r'<[^>]*>'), '')
                    .trim() ??
                ''
            : '';
        if (text.isNotEmpty) {
          snippets.add(
            '• ${url.isNotEmpty ? "[$url] " : ""}$text',
          );
        }
      }

      sw.stop();
      if (snippets.isNotEmpty) {
        return OvaMacToolExecutionResult(
          ok: true,
          output:
              'Top web search results for "$query":\n\n${snippets.join("\n\n")}',
          durationMs: sw.elapsedMilliseconds,
        );
      }

      return OvaMacToolExecutionResult(
        ok: true,
        output:
            'Search performed for "$query". No direct snippet parsed from web fallback.',
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'Search web notice: $e',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  Future<OvaMacToolExecutionResult> _searchWorkspace(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final query = (args['query'] ?? args['q'] ?? '').toString().trim();
    if (query.isEmpty) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'Missing search query.',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }

    try {
      final subpath = (args['path'] ?? '').toString().trim();
      final targetDir = subpath.isNotEmpty
          ? Directory(expandHomePath(subpath)).path
          : Directory.current.path;

      final res = await Process.run(
        'grep',
        [
          '-rnI',
          '--max-count=6',
          '--exclude-dir=.git',
          '--exclude-dir=build',
          '--exclude-dir=.dart_tool',
          '--exclude-dir=node_modules',
          query,
          targetDir,
        ],
      );

      sw.stop();
      final out = (res.stdout ?? '').toString().trim();
      if (out.isNotEmpty) {
        return OvaMacToolExecutionResult(
          ok: true,
          output: _truncate('Matches in workspace for "$query":\n$out'),
          durationMs: sw.elapsedMilliseconds,
        );
      }

      return OvaMacToolExecutionResult(
        ok: true,
        output: 'No matches found in workspace for "$query".',
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'Search workspace error: $e',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  Future<OvaMacToolExecutionResult> _manageApp(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final action =
        (args['action'] ?? 'activate').toString().toLowerCase().trim();
    final appName =
        (args['app_name'] ?? args['appName'] ?? args['app'] ?? '').toString().trim();
    final bundleId =
        (args['bundle_id'] ?? args['bundleId'] ?? '').toString().trim();

    ProcessResult res;
    switch (action) {
      case 'list_running':
        res = await Process.run(
          'zsh',
          const [
            '-lc',
            r"ps -axo comm= | awk -F/ '{print $NF}' | sort -u | grep -v '^\s*$' | head -n 40",
          ],
        );
        sw.stop();
        return OvaMacToolExecutionResult(
          ok: res.exitCode == 0,
          output: (res.stdout ?? '').toString().trim(),
          exitCode: res.exitCode,
          durationMs: sw.elapsedMilliseconds,
        );
      case 'quit':
        if (appName.isEmpty) {
          sw.stop();
          return OvaMacToolExecutionResult(
            ok: false,
            output: 'Missing app_name to quit.',
            exitCode: 1,
            durationMs: sw.elapsedMilliseconds,
          );
        }
        res = await Process.run(
          'osascript',
          ['-e', 'tell application "$appName" to quit'],
        );
        break;
      case 'hide':
        if (appName.isEmpty) {
          sw.stop();
          return OvaMacToolExecutionResult(
            ok: false,
            output: 'Missing app_name to hide.',
            exitCode: 1,
            durationMs: sw.elapsedMilliseconds,
          );
        }
        res = await Process.run('osascript', [
          '-e',
          'tell application "Finder" to set visible of process "$appName" to false',
        ]);
        break;
      case 'launch':
      case 'activate':
      default:
        if (bundleId.isNotEmpty) {
          res = await Process.run('open', ['-b', bundleId]);
        } else if (appName.isNotEmpty) {
          res = await Process.run(
            'osascript',
            ['-e', 'tell application "$appName" to activate'],
          );
          if (res.exitCode != 0) {
            res = await Process.run('open', ['-a', appName]);
          }
        } else {
          sw.stop();
          return OvaMacToolExecutionResult(
            ok: false,
            output: 'Missing app_name or bundle_id.',
            exitCode: 1,
            durationMs: sw.elapsedMilliseconds,
          );
        }
        break;
    }
    sw.stop();
    final ok = res.exitCode == 0;
    return OvaMacToolExecutionResult(
      ok: ok,
      output: ok
          ? 'App "$appName" action "$action" completed successfully on ${Platform.localHostname}.'
          : 'Failed app action "$action" for "$appName": ${res.stderr.toString().trim()}',
      exitCode: res.exitCode,
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _navigateAppMenu(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final appName =
        (args['app_name'] ?? args['appName'] ?? '').toString().trim();
    final menuBarItem =
        (args['menu_bar_item'] ?? args['menuBarItem'] ?? '').toString().trim();
    final menuItem =
        (args['menu_item'] ?? args['menuItem'] ?? '').toString().trim();
    final subMenuItem =
        (args['sub_menu_item'] ?? args['subMenuItem'] ?? '').toString().trim();

    if (appName.isEmpty || menuBarItem.isEmpty || menuItem.isEmpty) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output:
            'Missing app_name, menu_bar_item, or menu_item for menu navigation.',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }

    final script = StringBuffer()
      ..writeln('tell application "$appName" to activate')
      ..writeln('tell application "System Events"')
      ..writeln('  tell process "$appName"');

    if (subMenuItem.isNotEmpty) {
      script.writeln(
          '    click menu item "$subMenuItem" of menu 1 of menu item "$menuItem" of menu "$menuBarItem" of menu bar 1');
    } else {
      script.writeln(
          '    click menu item "$menuItem" of menu "$menuBarItem" of menu bar 1');
    }
    script
      ..writeln('  end tell')
      ..writeln('end tell');

    final res = await Process.run('osascript', ['-e', script.toString()]);
    sw.stop();
    final ok = res.exitCode == 0;
    return OvaMacToolExecutionResult(
      ok: ok,
      output: ok
          ? 'Navigated to $appName > $menuBarItem > $menuItem${subMenuItem.isNotEmpty ? " > $subMenuItem" : ""} successfully.'
          : 'Could not click menu item in $appName: ${res.stderr.toString().trim()}',
      exitCode: res.exitCode,
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _clickUiElement(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final appName =
        (args['app_name'] ?? args['appName'] ?? '').toString().trim();
    final elementType =
        (args['element_type'] ?? args['elementType'] ?? 'button')
            .toString()
            .toLowerCase()
            .trim();
    final label = (args['element_label'] ?? args['label'] ?? args['name'] ?? '')
        .toString()
        .trim();
    final windowIdx = (args['window_index'] as num?)?.toInt() ?? 1;

    if (appName.isEmpty || label.isEmpty) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'Missing app_name or element_label.',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }

    final script = StringBuffer()
      ..writeln('tell application "$appName" to activate')
      ..writeln('tell application "System Events"')
      ..writeln('  tell process "$appName"');

    switch (elementType) {
      case 'button':
        script.writeln(
            '    click (first button whose name is "$label" or description is "$label") of window $windowIdx');
        break;
      case 'menu_item':
        script.writeln(
            '    click (first menu item whose name is "$label") of window $windowIdx');
        break;
      case 'text_field':
        script.writeln(
            '    set focused of (first text field whose description is "$label" or name is "$label") of window $windowIdx to true');
        break;
      case 'checkbox':
        script.writeln(
            '    click (first checkbox whose name is "$label") of window $windowIdx');
        break;
      case 'radio_button':
        script.writeln(
            '    click (first radio button whose name is "$label") of window $windowIdx');
        break;
      case 'tab':
        script.writeln(
            '    click (first radio button whose name is "$label" or description is "$label") of tab group 1 of window $windowIdx');
        break;
      default:
        script.writeln(
            '    click (first UI element whose name is "$label") of window $windowIdx');
        break;
    }

    script
      ..writeln('  end tell')
      ..writeln('end tell');

    final res = await Process.run('osascript', ['-e', script.toString()]);
    sw.stop();
    final ok = res.exitCode == 0;
    return OvaMacToolExecutionResult(
      ok: ok,
      output: ok
          ? 'Clicked $elementType "$label" in $appName (window $windowIdx).'
          : 'Could not interact with $elementType "$label" in $appName: ${res.stderr.toString().trim()}',
      exitCode: res.exitCode,
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _pressHotkey(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final combo =
        (args['keys'] ?? args['combo'] ?? args['hotkey'] ?? '').toString().trim();
    final repeat = (args['repeat'] as num?)?.toInt() ?? 1;

    if (combo.isEmpty) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'Missing hotkey keys.',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }

    for (int i = 0; i < repeat.clamp(1, 10); i++) {
      if (onSendHotkey != null) {
        await onSendHotkey!(combo);
      } else {
        await MacOSMouseController.sendHotkey(combo);
      }
      if (i < repeat - 1) {
        await Future.delayed(const Duration(milliseconds: 60));
      }
    }

    sw.stop();
    return OvaMacToolExecutionResult(
      ok: true,
      output:
          'Dispatched hotkey "$combo"${repeat > 1 ? " x$repeat" : ""} to active application.',
      exitCode: 0,
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _manageComputerSystem(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final action =
        (args['action'] ?? 'get_system_status').toString().toLowerCase().trim();
    final val = args['value'];
    final title = (args['title'] ?? 'Oneova Workstation').toString().trim();
    final message = (args['message'] ?? '').toString().trim();

    ProcessResult res;
    switch (action) {
      case 'set_volume':
        final vol = (val is num
                ? val.toInt()
                : int.tryParse(val.toString()) ?? 50)
            .clamp(0, 100);
        res = await Process.run(
            'osascript', ['-e', 'set volume output volume $vol']);
        break;
      case 'mute':
        res = await Process.run(
            'osascript', ['-e', 'set volume with output muted']);
        break;
      case 'unmute':
        res = await Process.run(
            'osascript', ['-e', 'set volume without output muted']);
        break;
      case 'notify':
        res = await Process.run('osascript', [
          '-e',
          'display notification "$message" with title "$title"',
        ]);
        break;
      case 'set_appearance':
        final isDark = val == 'dark' || val == true || val == 'Dark';
        res = await Process.run('osascript', [
          '-e',
          'tell application "System Events" to tell appearance preferences to set dark mode to ${isDark ? "true" : "false"}',
        ]);
        break;
      case 'sleep':
        res = await Process.run('pmset', ['sleepnow']);
        break;
      case 'get_system_status':
      default:
        final battRes = await Process.run('pmset', ['-g', 'batt']);
        final diskRes = await Process.run('df', ['-h', '/']);
        sw.stop();
        return OvaMacToolExecutionResult(
          ok: true,
          output: 'Battery:\n${battRes.stdout}\nDisk:\n${diskRes.stdout}',
          exitCode: 0,
          durationMs: sw.elapsedMilliseconds,
        );
    }
    sw.stop();
    final ok = res.exitCode == 0;
    return OvaMacToolExecutionResult(
      ok: ok,
      output: ok
          ? 'System action "$action" completed successfully.'
          : 'System action "$action" failed: ${res.stderr.toString().trim()}',
      exitCode: res.exitCode,
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<OvaMacToolExecutionResult> _saveMemory(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final key = (args['key'] ?? '').toString().trim();
    final content = (args['content'] ?? '').toString().trim();
    if (key.isEmpty || content.isEmpty) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'Missing key or content for memory.',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }

    try {
      final cloud = DesktopFirebaseRestClient.instance;
      final uid = cloud.currentUid;
      if (uid == null) {
        sw.stop();
        return OvaMacToolExecutionResult(
          ok: false,
          output: 'Sign in required to save persistent user memories.',
          exitCode: 1,
          durationMs: sw.elapsedMilliseconds,
        );
      }

      final now = DateTime.now();
      await cloud.addDocument('users/$uid/agent_memories', {
        'key': key,
        'content': content,
        'originDevice': 'mac',
        'updatedAt': now.toIso8601String(),
        'updatedAtMs': now.millisecondsSinceEpoch,
      });

      sw.stop();
      return OvaMacToolExecutionResult(
        ok: true,
        output:
            'Saved memory: "$key" -> "$content". Automatically synced across Mac and Mobile.',
        exitCode: 0,
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'Failed to save memory: $e',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  Future<OvaMacToolExecutionResult> _recallMemories(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    try {
      final cloud = DesktopFirebaseRestClient.instance;
      final uid = cloud.currentUid;
      if (uid == null) {
        sw.stop();
        return OvaMacToolExecutionResult(
          ok: false,
          output: 'Sign in required to recall memories.',
          exitCode: 1,
          durationMs: sw.elapsedMilliseconds,
        );
      }

      final docs =
          await cloud.listDocuments('users/$uid/agent_memories', pageSize: 30);
      final query = (args['query'] ?? '').toString().toLowerCase().trim();

      final list = docs.map((d) {
        final k = (d.data['key'] ?? '').toString();
        final c = (d.data['content'] ?? '').toString();
        return (id: d.id, key: k, content: c);
      }).where((m) {
        if (query.isEmpty) return true;
        return m.key.toLowerCase().contains(query) ||
            m.content.toLowerCase().contains(query);
      }).toList();

      sw.stop();
      if (list.isEmpty) {
        return OvaMacToolExecutionResult(
          ok: true,
          output: query.isEmpty
              ? 'No memories stored yet.'
              : 'No memories matching "$query".',
          exitCode: 0,
          durationMs: sw.elapsedMilliseconds,
        );
      }

      final buf = StringBuffer('Stored User Memories (${list.length}):\n');
      for (final m in list) {
        buf.writeln('- [${m.id}] ${m.key}: ${m.content}');
      }
      return OvaMacToolExecutionResult(
        ok: true,
        output: buf.toString(),
        exitCode: 0,
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'Failed to recall memories: $e',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  Future<OvaMacToolExecutionResult> _deleteMemory(
    Map<String, dynamic> args,
    Stopwatch sw,
  ) async {
    final memId =
        (args['memory_id'] ?? args['id'] ?? args['key'] ?? '').toString().trim();
    if (memId.isEmpty) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'Missing memory_id or key.',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }

    try {
      final cloud = DesktopFirebaseRestClient.instance;
      final uid = cloud.currentUid;
      if (uid == null) {
        sw.stop();
        return OvaMacToolExecutionResult(
          ok: false,
          output: 'Sign in required to delete memories.',
          exitCode: 1,
          durationMs: sw.elapsedMilliseconds,
        );
      }

      await cloud.deleteDocument('users/$uid/agent_memories/$memId');
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: true,
        output: 'Deleted memory "$memId".',
        exitCode: 0,
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return OvaMacToolExecutionResult(
        ok: false,
        output: 'Failed to delete memory: $e',
        exitCode: 1,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}K';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}M';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}G';
  }

  static String _truncate(String input, {int maxChars = 6000}) {
    if (input.length <= maxChars) return input;
    return '${input.substring(0, maxChars)}\n... [truncated ${input.length - maxChars} chars]';
  }
}
