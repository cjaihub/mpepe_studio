// LIVE STUDIO v2 — Game Live media hook.
//
// [StudioRoomPort] (integrator-owned) has no game-stream method, so rooms that
// support the game-friendly capture implement this small interface too.
// Callers go through [startGameStreamOn], which falls back to the table
// screen share on rooms that don't.

import '../contracts/studio_ports.dart';

abstract class StudioGameStreamPort {
  /// Starts (or keeps) the host's screen share with game-friendly capture and
  /// makes sure the mic stays published. Safe to call when already streaming.
  Future<void> startGameStream();
}

/// Starts the game stream on [room], falling back to the table screen share.
Future<void> startGameStreamOn(StudioRoomPort room) => room is StudioGameStreamPort
    ? (room as StudioGameStreamPort).startGameStream()
    : room.startTableScreenShare();
