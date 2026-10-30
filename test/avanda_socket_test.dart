import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:avanda/avanda.dart';
import 'package:avanda/response.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ws_server.dart';
import 'test_helpers.dart';

void main() {
  late FakeWsServer server;
  final sockets = <AvandaSocket>[];
  final streams = <AvandaStream>[];

  setUp(() async {
    resetAvandaStatics();
    server = await FakeWsServer.start();
    final url = Uri.parse(server.url);
    Avanda.setConfig(AvandaConfig(rootUrl: 'http://${url.host}:${url.port}'));
  });

  tearDown(() async {
    for (final socket in sockets) {
      await socket.close();
    }
    sockets.clear();
    for (final stream in streams) {
      await stream.close();
    }
    streams.clear();
    await server.stop();
    resetAvandaStatics();
  });

  AvandaSocket open({
    bool reconnect = false,
    Duration connectTimeout = const Duration(seconds: 5),
  }) {
    final socket = Avanda()
        .service('Voice/transcribe')
        .params({'lang': 'en'}).stream(
            reconnect: reconnect, connectTimeout: connectTimeout);
    sockets.add(socket);
    return socket;
  }

  Future<AvandaStream> watch() async {
    final stream = (await Avanda().service('Car/watchAll').watch())!;
    streams.add(stream);
    return stream;
  }

  group('stream()', () {
    test('dials the same URL and headers as watch()', () async {
      Avanda.setHeaders({'Authorization': 'Bearer tok'});

      sockets.add(Avanda()
          .service('Voice/transcribe')
          .params({'lang': 'en'}).data({'session': 1}).stream());
      await waitUntil(() => server.dials.length == 1);
      streams.add((await Avanda()
          .service('Voice/transcribe')
          .params({'lang': 'en'}).data({'session': 1}).watch())!);
      await waitUntil(() => server.dials.length == 2);

      final streamDial = server.dials.first;
      final watchDial = server.dials.last;
      expect(streamDial.uri, watchDial.uri);
      expect(streamDial.uri.path, '/watch');
      expect(jsonDecode(streamDial.uri.queryParameters['query']!),
          containsPair('pr', {'lang': 'en'}));
      expect(jsonDecode(streamDial.uri.queryParameters['data']!),
          {'session': 1});
      expect(streamDial.headers.value('authorization'), 'Bearer tok');
    });

    test('delivers text and binary frames in order, including queued ones',
        () async {
      final socket = open();

      socket.send({'type': 'start'});
      socket.sendBytes(Uint8List.fromList([1, 2, 3]));
      socket.sendBytes(Uint8List.fromList([4, 5]));

      await waitUntil(() => server.frames.length == 3);
      socket.sendBytes(Uint8List.fromList([6]));
      socket.send({'type': 'end'});

      await waitUntil(() => server.frames.length == 5);
      expect(server.frames, [
        '{"type":"start"}',
        [1, 2, 3],
        [4, 5],
        [6],
        '{"type":"end"}',
      ]);
      expect(server.frames[1], isA<List<int>>(),
          reason: 'bytes must travel as a binary frame');
    });

    test('decodes server text frames into Response objects', () async {
      final socket = open();
      final reply = socket.messages.first;

      await waitUntil(() => server.sockets.isNotEmpty);
      server.broadcast(jsonEncode({'status_code': 200, 'data': 'hello'}));

      final Response response = await reply;
      expect(response.getStatus(), 200);
      expect(response.getData(), 'hello');
    });

    test('statusChanges replays the current status, then each change',
        () async {
      final socket = open();
      await waitUntil(() => socket.controller.status == WSStatus.connected);

      final seen = <WSStatus>[];
      socket.statusChanges.listen(seen.add);
      await socket.close();

      await waitUntil(() => seen.length == 2);
      expect(seen, [WSStatus.connected, WSStatus.closed]);
    });

    test('a server drop ends the stream with no reconnect and no replay',
        () async {
      final socket = open();
      var done = false;
      socket.messages.listen(null, onDone: () => done = true);

      socket.send({'n': 1});
      await waitUntil(() => server.frames.length == 1);

      await server.dropNewest();
      await waitUntil(() => done, reason: 'messages never completed');
      expect(socket.controller.status, WSStatus.closed);

      socket.send({'n': 2});
      socket.sendBytes(Uint8List.fromList([9]));

      await Future.delayed(const Duration(milliseconds: 200));
      expect(server.upgrades, 1, reason: 'a dropped stream must not redial');
      expect(server.frames, ['{"n":1}']);
    });

    test('reconnect: true redials but replays nothing', () async {
      final socket = open(reconnect: true);
      await waitUntil(() => socket.controller.status == WSStatus.connected);

      socket.send({'n': 1});
      await waitUntil(() => server.frames.length == 1);

      // Sent from the status listener so it lands while the socket is down,
      // before the redial can complete.
      socket.statusChanges.listen((status) {
        if (status == WSStatus.reconnecting) {
          socket.send({'n': 'lost'});
          socket.sendBytes(Uint8List.fromList([9]));
        }
      });

      await server.dropNewest();
      await waitUntil(() => server.upgrades == 2);
      await waitUntil(() => socket.controller.status == WSStatus.connected);

      socket.send({'n': 2});
      await waitUntil(() => server.frames.length >= 2);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(server.frames, ['{"n":1}', '{"n":2}']);
    });

    test('closeCode reports 4401 when middleware rejects the connection',
        () async {
      server.closeOnUpgrade = 4401;
      final socket = open();
      var done = false;
      socket.messages.listen(null, onDone: () => done = true);

      await waitUntil(() => done);
      expect(socket.closeCode, 4401);
      expect(socket.controller.status, WSStatus.closed);
    });

    test('closeCode falls back to the code close() asked for', () async {
      final socket = open();
      await waitUntil(() => socket.controller.status == WSStatus.connected);

      await socket.close(4000);
      expect(socket.closeCode, 4000);
    });

    test('a failed first connection errors messages and closes', () async {
      Avanda.setConfig(AvandaConfig(rootUrl: 'http://127.0.0.1:1'));
      final socket = open();

      final errors = <Object>[];
      final done = Completer<void>();
      socket.messages.listen(null,
          onError: errors.add, onDone: done.complete);

      await done.future.timeout(const Duration(seconds: 5));
      expect(errors, hasLength(1));
      expect(socket.controller.status, WSStatus.closed);
      expect(await socket.statusChanges.toList(), [WSStatus.closed]);
    });

    test('a connect timeout errors messages and closes', () async {
      server.stallUpgrades = true;
      final socket = open(connectTimeout: const Duration(milliseconds: 200));

      final errors = <Object>[];
      final done = Completer<void>();
      socket.messages.listen(null,
          onError: errors.add, onDone: done.complete);

      await done.future.timeout(const Duration(seconds: 2));
      expect(errors.single, isA<TimeoutException>());
      expect(socket.controller.status, WSStatus.closed);
      expect(server.requests, 1, reason: 'a timed-out stream must not retry');
    });

    test('applies the ping interval', () async {
      final socket = open();
      await waitUntil(() => socket.controller.channel != null);
      expect(socket.controller.channel!.pingInterval,
          socket.controller.pingInterval);
    });
  });

  group('watch() is unchanged', () {
    test('reconnects after a drop and replays what was sent meanwhile',
        () async {
      final stream = await watch();
      await waitUntil(() => stream.controller.status == WSStatus.connected);

      final seen = <WSStatus>[];
      stream.statusChanges.listen((status) {
        seen.add(status);
        if (status == WSStatus.reconnecting) stream.send({'n': 'queued'});
      });

      await server.dropNewest();
      await waitUntil(() => server.upgrades == 2);
      await waitUntil(() => server.received.isNotEmpty,
          reason: 'the pending message was not replayed');

      expect(server.received, ['{"n":"queued"}']);
      expect(seen.take(3),
          [WSStatus.connected, WSStatus.reconnecting, WSStatus.connected]);
    });

    test('keeps retrying when the first dial fails', () async {
      server.rejectUpgrades = true;
      final stream = await watch();

      await waitUntil(() => server.requests >= 2,
          timeout: const Duration(seconds: 5));
      expect(stream.controller.wsClosed, isFalse);
      expect(stream.controller.status, isNot(WSStatus.closed));
    });
  });
}
