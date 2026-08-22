import 'dart:convert';

import 'package:avanda/avanda.dart';
import 'package:avanda/response.dart';
import 'package:avanda/types/ResponseStruct.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ws_server.dart';

void main() {
  late FakeWsServer server;
  final streams = <AvandaStream>[];

  setUp(() async {
    server = await FakeWsServer.start();
  });

  tearDown(() async {
    for (final stream in streams) {
      await stream.close();
    }
    streams.clear();
    await server.stop();
  });

  /// Builds an AvandaStream the same way `Avanda.watch` does, but pointed at
  /// the in-process server and with test-sized reconnect timings.
  AvandaStream streamFor(String url) {
    final controller = WSController(
      wsUrl: url,
      minBackoff: const Duration(milliseconds: 5),
      maxBackoff: const Duration(milliseconds: 20),
      stableAfter: Duration.zero,
    );

    final stream = AvandaStream(
      stream: controller.streamController.stream
          .map((event) => Response(ResponseStruct.fromJson(jsonDecode(event)))),
      wsSink: controller.streamController.sink,
      controller: controller,
    );

    streams.add(stream);
    return stream;
  }

  test('decodes server frames into Response objects', () async {
    final stream = streamFor(server.url);
    final received = <Response>[];
    stream.listen(received.add);

    await waitUntil(() => server.sockets.isNotEmpty);
    server.broadcast(jsonEncode({'status_code': 200, 'data': 42}));

    await waitUntil(() => received.isNotEmpty);
    expect(received.single.getStatus(), 200);
    expect(received.single.getData(), 42);
  });

  test('keeps delivering across a reconnect', () async {
    final stream = streamFor(server.url);
    final received = <Response>[];
    stream.listen(received.add);

    await waitUntil(() => server.sockets.isNotEmpty);
    server.broadcast(jsonEncode({'status_code': 200, 'data': 'first'}));
    await waitUntil(() => received.length == 1);

    await server.dropNewest();
    await waitUntil(() => server.upgrades == 2);
    await waitUntil(() => stream.controller.status == WSStatus.connected);

    server.broadcast(jsonEncode({'status_code': 200, 'data': 'second'}));
    await waitUntil(() => received.length == 2);
    expect(received.map((r) => r.getData()), ['first', 'second']);
  });

  test('send survives an outage by buffering through the controller', () async {
    final stream = streamFor(server.url);
    await waitUntil(() => stream.controller.status == WSStatus.connected);

    server.rejectUpgrades = true;
    await server.dropNewest();
    await waitUntil(() => stream.controller.channel == null);

    await stream.send({'name': 'wale'});

    server.rejectUpgrades = false;
    await waitUntil(() => server.received.isNotEmpty);
    expect(jsonDecode(server.received.single), {'name': 'wale'});
  });

  test('statusChanges surfaces the reconnect to the caller', () async {
    final stream = streamFor(server.url);
    await waitUntil(() => stream.controller.status == WSStatus.connected);

    final seen = <WSStatus>[];
    stream.statusChanges.listen(seen.add);

    await server.dropNewest();
    await waitUntil(() => seen.length >= 3);

    expect(seen.take(3),
        [WSStatus.connected, WSStatus.reconnecting, WSStatus.connected]);
  });

  test('onClosed fires with the close code when the caller closes', () async {
    final stream = streamFor(server.url);
    await waitUntil(() => stream.controller.status == WSStatus.connected);

    int? reportedCode;
    var fired = false;
    await stream.onClosed(([int? code]) {
      fired = true;
      reportedCode = code;
    });

    await stream.close();

    expect(fired, isTrue);
    expect(reportedCode, 1000,
        reason: 'a caller-initiated close should report normal closure');
  });

  test('a caller close does not report itself as a server close', () async {
    final stream = streamFor(server.url);
    await waitUntil(() => stream.controller.status == WSStatus.connected);

    var serverClosedFired = false;
    await stream.onServerClosed((code) => serverClosedFired = true);
    stream.listen((_) {});

    await stream.close();
    await Future.delayed(const Duration(milliseconds: 50));

    expect(serverClosedFired, isFalse);
    expect(stream.closed, isTrue);
  });

  test('onError receives the error object', () async {
    final stream = streamFor(server.url);
    await waitUntil(() => stream.controller.status == WSStatus.connected);

    Object? reported;
    await stream.onError((error) => reported = error);
    stream.listen((_) {});

    // Previously `_onError` was invoked with no arguments, so any handler that
    // declared a parameter threw NoSuchMethodError instead of being called.
    stream.controller.streamController.addError('boom');

    await waitUntil(() => reported != null);
    expect(reported, 'boom');
  });

  test('close stops the reconnect loop', () async {
    final stream = streamFor(server.url);
    await waitUntil(() => stream.controller.status == WSStatus.connected);

    await stream.close();
    final upgradesAtClose = server.upgrades;

    await Future.delayed(const Duration(milliseconds: 200));
    expect(server.upgrades, upgradesAtClose);
    expect(stream.controller.status, WSStatus.closed);
  });
}
