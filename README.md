# avanda

Flutter client for [Avanda](https://github.com/avandajs) backends. You describe
the data you want as a service query, and the client serialises it, sends it over
HTTP, and unwraps the response. The same query can be subscribed to over a
websocket that reconnects on its own.

## Install

```yaml
dependencies:
  avanda: ^0.2.0
```

## Configure

Set the root URL once, before the first request:

```dart
import 'package:avanda/avanda.dart';

Avanda.setConfig(AvandaConfig(rootUrl: 'https://api.example.com/'));
Avanda.setHeaders({'Authorization': 'Bearer $token'});
```

`setHeaders` merges into whatever is already there, so you can call it again
after a login to replace just the token. Both the config and the headers are
static and shared by every query.

`AvandaConfig` also takes `wsUrl` if live subscriptions live on a different host,
`secureWebSocket: true` to use `wss://`, and `debugMode: true` to log raw
response bodies.

## Querying

A query names a service and a function on it, then the columns to return:

```dart
var response = await Avanda()
    .service('Car/getAllByPage')
    .page(2)
    .select(['id', 'model']);
```

`select` requests the service's `get` function and `selectAll` requests `getAll`.
For anything else, name it with `func`:

```dart
Avanda().service('Car').func('getArchived').select(['id']);
```

### Filtering

Pass a map to `where` for equality on several columns at once:

```dart
Avanda().service('Car').where({'available': true, 'year': 2024});
```

Pass a column name to compare it with an operator:

```dart
Avanda().service('Car').where('year').greaterThan(2020);
```

The available operators are `greaterThan`, `lessThan`, `equals`, `notEquals`,
`isLike`, `isNotLike`, `isNull` and `isNotNull`. `ref(id)` is shorthand for
filtering on `id`, and `search(column, keyword)` runs a keyword search.

### Nesting services

Any query can be used as a column of another, which fetches it as a sub-service.
Use `as` to name the key it arrives under:

```dart
var owner = Avanda().service('Owner').select(['id', 'name']);

var cars = await Avanda()
    .service('Car/getAll')
    .select(['id', 'model', owner.as('owner')]);
```

Nesting has no depth limit.

## Reading responses

```dart
var response = await Avanda().service('Car/getAllByPage').select(['id']);

response.getData<List>();     // the payload
response.getMsg();            // the server's message
response.getStatus();         // the status code from the response envelope
response.getCurrentPage();
response.getTotalPages();
response.getPerPage();
response.isError();
```

## Writing

```dart
await Avanda().service('Car/create').set({'model': 'Corolla'});
await Avanda().service('Car/edit').ref(7).update({'model': 'Camry'});
await Avanda().service('Car/remove').ref(7).delete();
```

`post` is an alias for `set`. `update` posts the same payload with a
`_method=PATCH` override.

## Errors

A non-2xx status in the response envelope throws a subclass of
`RequestException`, and the parsed response is available on it:

```dart
import 'package:avanda/exceptions/request_exception.dart';

try {
  await Avanda().service('Car/getAll').select(['id']);
} on RequestException catch (e) {
  print(e.getResponse().msg);
}
```

The mapped statuses are 400, 401, 403, 404, 405 and 500. A connection that never
reached the server throws `InternetNetworkError`. Any other error status is
returned as a normal response instead of throwing, so check `isError()` if you
talk to a service that uses other codes.

## Live subscriptions

`watch` opens a websocket for the same query and streams results as they change:

```dart
var stream = await Avanda().service('Car/watchAll').watch();

stream?.listen((response) {
  print(response.getData());
});
```

The socket looks after itself. It pings periodically so a connection that died
without closing — a sleeping radio, an expired NAT mapping — is noticed rather
than leaving you silently disconnected, and it redials with an exponential
backoff until it gets back. The query travels in the URL, so the subscription is
re-established automatically; you may still miss events that occurred during the
gap.

Because reconnects are handled for you, the thing worth reacting to is the
status, not the disconnect:

```dart
stream?.statusChanges.listen((status) {
  if (status == WSStatus.reconnecting) showOfflineBanner();
  if (status == WSStatus.connected) hideOfflineBanner();
});
```

`statusChanges` emits the current status first, so subscribing late still tells
you where things stand. The states are `connecting`, `connected`, `reconnecting`
and `closed`.

To send on the socket, use `send`. Messages handed over while the connection is
down are queued and flushed on reconnect:

```dart
await stream?.send({'filter': 'available'});
```

When you are finished, `close` shuts the socket down and stops reconnecting:

```dart
await stream?.close();
```

`onClosed` reports your own close, `onServerClosed` reports one you did not ask
for, and `onError` receives socket errors.

## Known limitations

* Only one operator filter applies per query. Chaining
  `.where('a').equals(1).andWhere('b').equals(2)` keeps just the last condition.
* `andWhere` with a map merges raw entries rather than wrapping them the way
  `where` does, producing a different filter shape.
* `disableAutoLink()` has no effect on the serialised query.
* `watch` derives the socket scheme from `AvandaConfig.secureWebSocket` rather
  than from the root URL, and ignores any path on it. Set `wsUrl` explicitly if
  your API is not served from the host root.

## License

See [LICENSE](LICENSE).
