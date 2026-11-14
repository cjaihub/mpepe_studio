import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/ova_assistant/services/ova_task_center.dart';

void main() {
  final now = DateTime.now();

  test('nothing running', () {
    expect(const OvaTaskState().progressReport(), 'Nothing is running in the background right now.');
  });

  test('running task names its step and count; recent finish is reported', () {
    final s = OvaTaskState(tasks: [
      OvaTask(
        id: 'a',
        title: 'Export your reel',
        source: 'ova',
        startedAt: now.subtract(const Duration(minutes: 3)),
        steps: const [
          OvaTaskStep('Agent · render video', Icons.bolt, OvaStepStatus.done),
          OvaTaskStep('Agent · upload to your feed', Icons.bolt, OvaStepStatus.running),
        ],
      ),
      OvaTask(
        id: 'b',
        title: 'Reply to shop chats',
        source: 'ai_lab',
        status: OvaTaskStatus.done,
        summary: 'Answered 4 buyers',
        startedAt: now.subtract(const Duration(minutes: 9)),
        finishedAt: now.subtract(const Duration(minutes: 2)),
      ),
      OvaTask(id: 'me', title: 'what is happening', source: 'ova', startedAt: now),
    ]);
    final r = s.progressReport(exceptId: 'me');
    expect(r, contains('Export your reel is upload to your feed, step 2 of 2, running 3 minutes.'));
    expect(r, contains('Reply to shop chats finished: Answered 4 buyers'));
    expect(r, isNot(contains('what is happening')));
    expect(s.progressContext(exceptId: 'me'), contains('- Export your reel [running: upload to your feed]'));
  });
}
