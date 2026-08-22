import 'package:avanda/ws_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ws_server.dart';

void main() {
  late FakeWsServer server;
  final controllers = <WSController>[];

  setUp(() async {
    server = await FakeWsServer.start();
  });

  tearDown(() async {
    for (final controller in controllers) {
      await controller.closeWs();
    }
    controllers.clear();
    await server.stop();
  });

  /// Builds a controller with test-sized timings and registers it for teardown.
  WSController controllerFor(
    String url, {
    Duration minBackoff = const Duration(milliseconds: 5),
    Duration maxBackoff = const Duration(milliseconds: 20),
    Duration stableAfter = Duration.zero,
    Duration pingInterval = const Duration(seconds: 20),
    int maxPendingMessages = 64,
  }) {
    final controller = WSController(
      wsUrl: url,
      minBackoff: minBackoff,
      maxBackoff: maxBackoff,
      stableAfter: stableAfter,
      pingInterval: pingInterval,
      maxPendingMessages: maxPendingMessages,
    );
    controllers.add(controller);
    return controller;
  }

  group('connecting', () {
    test('opens a socket and reports connected', () async {
      final controller = controllerFor(server.url);

      await waitUntil(() => controller.status == WSStatus.connected);
      expect(server.upgrades, 1);
      expect(controller.channel, isNotNull);
    });

    test('forwards server messages onto the stream', () async {
      final controller = controllerFor(server.url);
      final received = <String>[];
      controller.streamController.stream.listen(received.add);

      await waitUntil(() => server.sockets.isNotEmpty);
      server.broadcast('{"msg":"hello"}');

      await waitUntil(() => received.isNotEmpty);
      expect(received, ['{"msg":"hello"}']);
    });

    test('applies the ping interval so half-open sockets are detected',
        () async {
      final controller = controllerFor(
        server.url,
        pingInterval: const Duration(seconds: 7),
      );

      await waitUntil(() => controller.channel != null);
      expect(controller.channel!.pingInterval, const Duration(seconds: 7));
    });
  });

  group('reconnecting', () {
    test('reconnects after the server drops the socket', () async {
      final controller = controllerFor(server.url);
      await waitUntil(() => controller.status == WSStatus.connected);

      await server.dropNewest();

      await waitUntil(() => server.upgrades == 2);
      await waitUntil(() => controller.status == WSStatus.connected);
      expect(controller.channel, isNotNull);
    });

    test(
        'REGRESSION: a drop causes exactly one reconnect, not a doubling storm',
        () async {
      final controller = controllerFor(server.url);
      await waitUntil(() => controller.status == WSStatus.connected);

      // The old implementation reconnected from both `channel.done` and the
      // subscription's `onDone`, so sockets doubled on every drop: 2, then 4,
      // then 8. Three drops must leave exactly four upgrades and one live
      // socket.
      for (var drop = 1; drop <= 3; drop++) {
        await server.dropNewest();
        await waitUntil(() => server.upgrades == drop + 1);
        await waitUntil(() => controller.status == WSStatus.connected);
      }

      expect(server.upgrades, 4);

      // Give any stray reconnect chain time to surface before asserting.
      await Future.delayed(const Duration(milliseconds: 200));
      expect(server.upgrades, 4, reason: 'extra sockets were opened');
      expect(server.sockets.length, 1, reason: 'stale sockets were left open');
    });

    test('keeps delivering messages after a reconnect', () async {
      final controller = controllerFor(server.url);
      final received = <String>[];
      controller.streamController.stream.listen(received.add);

      await waitUntil(() => server.sockets.isNotEmpty);
      server.broadcast('before');
      await waitUntil(() => received.length == 1);

      await server.dropNewest();
      await waitUntil(() => server.upgrades == 2);
      await waitUntil(() => controller.status == WSStatus.connected);

      server.broadcast('after');
      await waitUntil(() => received.length == 2);
      expect(received, ['before', 'after']);
    });

    test('retries a refused handshake until it succeeds', () async {
      server.rejectUpgrades = true;
      final controller = controllerFor(server.url);

      // More than one refused dial proves the backoff loop is actually looping.
      await waitUntil(() => server.requests >= 2);
      expect(controller.channel, isNull);
      expect(server.upgrades, 0);

      server.rejectUpgrades = false;
      await waitUntil(() => controller.status == WSStatus.connected,
          reason: 'controller never recovered once the server accepted again');
      expect(server.upgrades, 1);
    });

    test('keeps retrying an unreachable server without giving up', () async {
      final controller = controllerFor(FakeWsServer.unreachableUrl);

      await Future.delayed(const Duration(milliseconds: 150));

      expect(controller.channel, isNull);
      expect(controller.wsClosed, isFalse,
          reason: 'the controller must stay alive and keep trying');
    });

    test('records the close code of a socket that went away', () async {
      final controller = controllerFor(server.url);
      await waitUntil(() => controller.status == WSStatus.connected);

      await server.dropNewest();
      await waitUntil(() => controller.closeCode != null);

      expect(controller.closeCode, isNotNull);
    });

    test('reports normal closure after a deliberate close', () async {
      final controller = controllerFor(server.url);
      await waitUntil(() => controller.status == WSStatus.connected);

      await controller.closeWs();
      expect(controller.closeCode, 1000);
    });
  });

  group('status changes', () {
    test('replays the current status to a late subscriber', () async {
      final controller = controllerFor(server.url);
      await waitUntil(() => controller.status == WSStatus.connected);

      expect(await controller.statusChanges.first, WSStatus.connected);
    });

    test('reports reconnecting between two connected states', () async {
      final controller = controllerFor(server.url);
      await waitUntil(() => controller.status == WSStatus.connected);

      final seen = <WSStatus>[];
      controller.statusChanges.listen(seen.add);

      await server.dropNewest();
      await waitUntil(() => seen.length >= 3);

      expect(seen.take(3),
          [WSStatus.connected, WSStatus.reconnecting, WSStatus.connected]);
    });

    test('reports closed when shut down', () async {
      final controller = controllerFor(server.url);
      await waitUntil(() => controller.status == WSStatus.connected);

      await controller.closeWs();
      expect(controller.status, WSStatus.closed);
    });
  });

  group('sending', () {
    test('delivers a message on a live socket', () async {
      final controller = controllerFor(server.url);
      await waitUntil(() => controller.status == WSStatus.connected);

      controller.send('ping');

      await waitUntil(() => server.received.isNotEmpty);
      expect(server.received, ['ping']);
    });

    test('buffers while disconnected and flushes on reconnect', () async {
      final controller = controllerFor(server.url);
      await waitUntil(() => controller.status == WSStatus.connected);

      // Refusing the handshake holds the outage open; reconnects are otherwise
      // fast enough that there is no observable disconnected window.
      server.rejectUpgrades = true;
      await server.dropNewest();
      await waitUntil(() => controller.channel == null);

      // Previously this went to `channel?.add(...)` and vanished silently.
      controller.send('queued-1');
      controller.send('queued-2');

      server.rejectUpgrades = false;
      await waitUntil(() => server.received.length == 2,
          reason: 'buffered messages were never flushed');
      expect(server.received, ['queued-1', 'queued-2']);
    });

    test('drops the oldest message once the buffer is full', () async {
      final controller = controllerFor(server.url, maxPendingMessages: 2);
      await waitUntil(() => controller.status == WSStatus.connected);

      server.rejectUpgrades = true;
      await server.dropNewest();
      await waitUntil(() => controller.channel == null);

      controller.send('one');
      controller.send('two');
      controller.send('three');

      server.rejectUpgrades = false;
      await waitUntil(() => server.received.length == 2);
      expect(server.received, ['two', 'three']);
    });

    test('ignores sends after close instead of buffering forever', () async {
      final controller = controllerFor(server.url);
      await waitUntil(() => controller.status == WSStatus.connected);

      await controller.closeWs();
      controller.send('too late');

      await Future.delayed(const Duration(milliseconds: 100));
      expect(server.received, isEmpty);
      expect(server.upgrades, 1);
    });
  });

  group('closing', () {
    test('stops reconnecting for good', () async {
      final controller = controllerFor(server.url);
      await waitUntil(() => controller.status == WSStatus.connected);

      await controller.closeWs();
      final upgradesAtClose = server.upgrades;

      await Future.delayed(const Duration(milliseconds: 200));
      expect(server.upgrades, upgradesAtClose);
      expect(controller.channel, isNull);
    });

    test('closes the inbound stream so listeners see onDone', () async {
      final controller = controllerFor(server.url);
      await waitUntil(() => controller.status == WSStatus.connected);

      var done = false;
      controller.streamController.stream.listen(null, onDone: () => done = true);

      await controller.closeWs();
      await waitUntil(() => done,
          reason: 'closeWs left the inbound stream open');
    });

    test('stops the retry loop when closed mid-dial', () async {
      server.rejectUpgrades = true;
      final controller = controllerFor(server.url);

      await waitUntil(() => server.requests >= 2);
      await controller.closeWs();
      server.rejectUpgrades = false;

      // The dial already in flight may still land, so what matters is that the
      // count settles instead of climbing.
      await Future.delayed(const Duration(milliseconds: 150));
      final settled = server.requests;
      await Future.delayed(const Duration(milliseconds: 150));

      expect(server.requests, settled,
          reason: 'an in-flight retry loop outlived closeWs');
      expect(controller.channel, isNull);
    });

    test('is safe to call twice', () async {
      final controller = controllerFor(server.url);
      await waitUntil(() => controller.status == WSStatus.connected);

      await controller.closeWs();
      await controller.closeWs();

      expect(controller.wsClosed, isTrue);
    });
  });
}
