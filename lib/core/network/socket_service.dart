import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Real-time events emitted by the Socket.IO service.
class SocketEvent {
  final String name;
  final dynamic data;

  const SocketEvent({required this.name, this.data});
}

/// Abstract interface for real-time Socket.IO communication.
abstract class SocketService {
  /// Connects to the backend Socket.IO server with the current auth token.
  Future<void> connect(String token);

  /// Disconnects from the server.
  void disconnect();

  /// Whether the socket is currently connected.
  bool get isConnected;

  /// Stream of all received events.
  Stream<SocketEvent> get onEvent;

  /// Stream of booking status change events.
  Stream<Map<String, dynamic>> get onBookingStatusChanged;

  /// Stream of payment confirmation events.
  Stream<Map<String, dynamic>> get onPaymentConfirmed;

  /// Stream of new booking events (for agents).
  Stream<Map<String, dynamic>> get onNewBooking;

  /// Emits a custom event to the server.
  void emit(String event, dynamic data);

  /// Joins a room for listening to user-specific events.
  void joinRoom(String room);

  /// Leaves a room.
  void leaveRoom(String room);
}

/// Riverpod provider for the SocketService. Must be overridden at startup.
final socketServiceProvider = Provider<SocketService>((ref) {
  throw UnimplementedError(
    'socketServiceProvider must be overridden at app startup.',
  );
});
