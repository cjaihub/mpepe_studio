import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class NativePluginServer {
  static final NativePluginServer _instance = NativePluginServer._internal();
  factory NativePluginServer() => _instance;
  NativePluginServer._internal();

  HttpServer? _server;
  final List<WebSocketChannel> _connectedClients = [];

  Future<void> start({int port = 8080}) async {
    // Only run on desktop platforms or during testing
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      debugPrint("NativePluginServer: Skipping start on mobile/web platform.");
      return;
    }

    if (_server != null) return;

    var handler = webSocketHandler((WebSocketChannel webSocket, String? protocol) {
      debugPrint("NativePluginServer: Client connected with protocol $protocol");
      _connectedClients.add(webSocket);

      webSocket.stream.listen((message) {
        debugPrint("NativePluginServer received: $message");
        _handleIncomingMessage(message, webSocket);
      }, onDone: () {
        debugPrint("NativePluginServer: Client disconnected.");
        _connectedClients.remove(webSocket);
      }, onError: (error) {
        debugPrint("NativePluginServer: Client error: $error");
        _connectedClients.remove(webSocket);
      });
    });

    try {
      _server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, port);
      debugPrint("NativePluginServer: Listening on ws://${_server!.address.host}:${_server!.port}");
    } catch (e) {
      debugPrint("NativePluginServer: Failed to start server: $e");
    }
  }

  Future<void> stop() async {
    for (var client in _connectedClients) {
      client.sink.close();
    }
    _connectedClients.clear();
    await _server?.close(force: true);
    _server = null;
    debugPrint("NativePluginServer: Server stopped.");
  }

  void broadcastCommand(String command, Map<String, dynamic> payload) {
    if (_connectedClients.isEmpty) {
      debugPrint("NativePluginServer: No clients connected to receive command.");
      return;
    }

    final message = jsonEncode({
      "type": "command",
      "command": command,
      "payload": payload,
      "timestamp": DateTime.now().toIso8601String()
    });

    for (var client in _connectedClients) {
      client.sink.add(message);
    }
    debugPrint("NativePluginServer: Broadcasted $command");
  }

  void _handleIncomingMessage(dynamic message, WebSocketChannel client) {
    try {
      final data = jsonDecode(message as String);
      // Process incoming status updates or data from the desktop software
      debugPrint("Processed data from plugin: $data");
    } catch (e) {
      debugPrint("NativePluginServer: Error processing message: $e");
    }
  }
}
