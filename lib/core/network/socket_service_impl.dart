import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import 'socket_service.dart';

class SocketServiceImpl implements SocketService {
  io.Socket? _socket;
  bool _connected = false;

  final _eventController = StreamController<SocketEvent>.broadcast();
  final _bookingStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _paymentController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _newBookingController =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Future<void> connect(String token) async {
    if (_connected) return;

    final baseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://api.katisha.today/api',
    );
    final serverUrl = baseUrl.replaceAll('/api', '');

    _socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionAttempts(10)
          .build(),
    );

    _socket!.onConnect((_) {
      _connected = true;
    });

    _socket!.onDisconnect((_) {
      _connected = false;
    });

    _socket!.on('booking:status', (data) {
      if (data is Map<String, dynamic>) {
        _bookingStatusController.add(data);
        _eventController.add(SocketEvent(name: 'booking:status', data: data));
      }
    });

    _socket!.on('payment:confirmed', (data) {
      if (data is Map<String, dynamic>) {
        _paymentController.add(data);
        _eventController.add(SocketEvent(name: 'payment:confirmed', data: data));
      }
    });

    _socket!.on('notification', (data) {
      if (data is Map<String, dynamic>) {
        _eventController.add(SocketEvent(name: 'notification', data: data));
      }
    });

    _socket!.on('new_booking', (data) {
      if (data is Map<String, dynamic>) {
        _newBookingController.add(data);
        _eventController.add(SocketEvent(name: 'new_booking', data: data));
      }
    });

    _socket!.onError((error) {
      _eventController.addError(error);
    });
  }

  @override
  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connected = false;
  }

  @override
  bool get isConnected => _connected;

  @override
  Stream<SocketEvent> get onEvent => _eventController.stream;

  @override
  Stream<Map<String, dynamic>> get onBookingStatusChanged =>
      _bookingStatusController.stream;

  @override
  Stream<Map<String, dynamic>> get onPaymentConfirmed =>
      _paymentController.stream;

  @override
  Stream<Map<String, dynamic>> get onNewBooking =>
      _newBookingController.stream;

  @override
  void emit(String event, dynamic data) {
    _socket?.emit(event, data);
  }

  @override
  void joinRoom(String room) {
    _socket?.emit('join', {'room': room});
  }

  @override
  void leaveRoom(String room) {
    _socket?.emit('leave', {'room': room});
  }

  void dispose() {
    disconnect();
    _eventController.close();
    _bookingStatusController.close();
    _paymentController.close();
    _newBookingController.close();
  }
}
