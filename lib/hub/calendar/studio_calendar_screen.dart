import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:calendar_view/calendar_view.dart';
import '../../backend/calendar_repository.dart';
import 'create_event_dialog.dart';

class StudioCalendarScreen extends ConsumerStatefulWidget {
  const StudioCalendarScreen({super.key});

  @override
  ConsumerState<StudioCalendarScreen> createState() => _StudioCalendarScreenState();
}

class _StudioCalendarScreenState extends ConsumerState<StudioCalendarScreen> {
  final EventController<EventModel> _eventController = EventController<EventModel>();
  final DateTime _currentMonth = DateTime.now();

  @override
  void dispose() {
    _eventController.dispose();
    super.dispose();
  }

  void _syncEvents(List<EventModel> events) {
    // We would need to manage adding/removing precisely, but for a simple sync,
    // clear and add all if it doesn't cause too much flicker.
    // In a real optimized system, we'd only add new ones or update.
    final existingEvents = _eventController.allEvents;
    for (final event in existingEvents) {
      _eventController.remove(event);
    }
    
    _eventController.addAll(
      events.map((e) => CalendarEventData<EventModel>(
        date: e.startTime,
        startTime: e.startTime,
        endTime: e.endTime,
        title: e.title,
        description: e.description,
        color: e.color,
        event: e,
      )).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(monthlyEventsProvider(_currentMonth));

    eventsAsync.whenData((events) {
      // Sync events when data arrives
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
           _syncEvents(events);
        }
      });
    });

    return CalendarControllerProvider<EventModel>(
      controller: _eventController,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Studio Calendar', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: Colors.black,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.add_box, color: Colors.orange),
              onPressed: () {
                showDialog(
                  context: context,
                  barrierColor: Colors.black.withValues(alpha: 0.8),
                  builder: (context) => Dialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: const EdgeInsets.all(16),
                    child: const CreateEventDialog(),
                  ),
                );
              },
            ),
          ],
        ),
        body: MonthView<EventModel>(
          controller: _eventController,
        ),
      ),
    );
  }
}
