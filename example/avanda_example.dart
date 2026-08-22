// ignore_for_file: avoid_print

import 'package:avanda/avanda.dart';
import 'package:avanda/exceptions/request_exception.dart';

Future<void> main() async {
  Avanda.setConfig(AvandaConfig(rootUrl: 'https://api.example.com/'));
  Avanda.setHeaders({'Authorization': 'Bearer <your-token>'});

  await fetchCars();
  await createCar();
  await watchCars();
}

/// A paginated read with a filter and a nested sub-service.
Future<void> fetchCars() async {
  var owner = Avanda().service('Owner').select(['id', 'name']);

  var query = Avanda().service('Car/getAllByPage').page(1);
  query.where({'available': true});
  query.select(['id', 'model', owner.as('owner')]);

  try {
    var response = await query.get();
    print('${response.getMsg()} (page ${response.getCurrentPage()} '
        'of ${response.getTotalPages()})');
    print(response.getData());
  } on RequestException catch (e) {
    print('Request failed: ${e.getResponse().msg}');
  }
}

/// A write. `update` sends the same payload with a PATCH override.
Future<void> createCar() async {
  try {
    var response =
        await Avanda().service('Car/create').set({'model': 'Corolla'});
    print('Created: ${response.getData()}');
  } on RequestException catch (e) {
    print('Request failed: ${e.getResponse().msg}');
  }
}

/// A live subscription. The socket reconnects on its own, so the only thing
/// worth reacting to is the status, not the disconnect.
Future<void> watchCars() async {
  var stream = await Avanda().service('Car/watchAll').watch();
  if (stream == null) return;

  stream.statusChanges.listen((status) {
    switch (status) {
      case WSStatus.connected:
        print('live');
        break;
      case WSStatus.reconnecting:
        print('reconnecting...');
        break;
      case WSStatus.connecting:
        print('connecting...');
        break;
      case WSStatus.closed:
        print('closed');
        break;
    }
  });

  await stream.onError((error) => print('Stream error: $error'));
  await stream.onClosed(([int? code]) => print('Closed with code $code'));

  stream.listen((response) => print(response.getData()));

  // Queued and flushed automatically if the socket happens to be down.
  await stream.send({'filter': 'available'});

  await Future.delayed(const Duration(minutes: 1));
  await stream.close();
}
