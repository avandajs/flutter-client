import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// An in-process websocket server, so the reconnect logic can be exercised
/// against real sockets without reaching the network.
class FakeWsServer {
  FakeWsServer._(this._server);

  final HttpServer _server;

  /// Currently connected sockets, newest last.
  final List<WebSocket> sockets = [];

  /// Everything any client has sent, in arrival order.
  final List<String> received = [];

  /// Total upgrades accepted since start. Reconnect bugs show up here as a
  /// count that climbs faster than the number of drops.
  int upgrades = 0;

  /// Every dial attempt, including refused ones, so tests can tell "still
  /// retrying" from "never tried".
  int requests = 0;

  /// When true the handshake is refused, which makes `WebSocket.connect` throw
  /// on the client side.
  bool rejectUpgrades = false;

  static Future<FakeWsServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeWsServer._(server);

    server.listen((request) async {
      fake.requests++;

      if (fake.rejectUpgrades) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }

      final socket = await WebSocketTransformer.upgrade(request);
      fake.upgrades++;
      fake.sockets.add(socket);

      socket.listen(
        (data) {
          if (data is String) fake.received.add(data);
        },
        onDone: () => fake.sockets.remove(socket),
        onError: (_) => fake.sockets.remove(socket),
        cancelOnError: true,
      );
    });

    return fake;
  }

  String get url => 'ws://${_server.address.address}:${_server.port}/watch';

  /// The url of a port nothing is listening on, for failure-path tests.
  static String get unreachableUrl => 'ws://127.0.0.1:1/watch';

  void broadcast(String message) {
    for (final socket in List<WebSocket>.from(sockets)) {
      socket.add(message);
    }
  }

  /// Drops the newest connection the way a network blip would.
  Future<void> dropNewest() async {
    if (sockets.isEmpty) return;
    await sockets.last.close();
  }

  Future<void> stop() async {
    for (final socket in List<WebSocket>.from(sockets)) {
      await socket.close();
    }
    sockets.clear();
    await _server.close(force: true);
  }
}

/// Polls until [condition] holds, so tests settle on real progress rather than
/// on a fixed sleep.
Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(reason ?? 'condition was still false after $timeout');
    }
    await Future.delayed(const Duration(milliseconds: 5));
  }
}
