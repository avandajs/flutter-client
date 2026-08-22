## 0.2.0

Reliability release for the websocket layer, plus the first test suite.

### Breaking

* `AvandaStream.onError` now takes `Function(Object error)?` and is called with
  the error. It was previously invoked with no arguments, so any handler that
  declared a parameter threw `NoSuchMethodError`.
* Removed the unused `Avanda.channel` field. It was never initialised, so
  reading it always threw `LateInitializationError`.
* Dropped the `class_to_map` and `web_socket_channel` dependencies. Neither was
  used; the socket runs on `dart:io`.

### Fixed

* Reconnects no longer multiply. A dropped socket was reported by both
  `channel.done` and the stream subscription, and each reconnect registered both
  handlers again, so live sockets doubled on every disconnect.
* Half-open connections are now detected. A ping interval is applied to the
  socket, so a sleeping radio or an expired NAT mapping surfaces as a normal
  disconnect instead of leaving the client silently dead.
* Reconnect attempts back off exponentially with jitter instead of retrying on a
  flat 10 second timer, and stop when the stream is closed. A retry loop could
  previously outlive `close()` and leak a socket.
* A server that accepts and then immediately drops no longer causes a hot
  redial loop.
* `close()` now closes the inbound stream, so `onClosed` and `onServerClosed`
  actually fire. `onServerClosed` reports the real close code instead of `0`.
* Messages passed to `AvandaStream.send` while the socket is down are queued and
  flushed on reconnect instead of being silently discarded.
* `Avanda.addCustomFilter` used a JavaScript truthiness check, which threw a
  `TypeError` on every call. This made `greaterThan`, `lessThan`, `equals`,
  `notEquals`, `isNull`, `isNotNull`, `isLike` and `isNotLike` unusable.
* `ResponseStruct.fromJson` now reads `total_pages`, so `getTotalPages()`
  reports the server's value instead of always returning 1.
* Removed a stray `dart:ffi` import from `Service`, and `Service.al` is no
  longer nullable.

### Added

* `WSStatus` and `AvandaStream.statusChanges`, for distinguishing a transient
  reconnect from a closed connection. Late subscribers receive the current
  status before subsequent changes.
* A test suite covering the query builder, the HTTP layer, response parsing and
  the websocket reconnect behaviour.
* An `example/` directory. The scratch `lib/main.dart`, which shipped a
  hardcoded address to consumers, has been removed.

## 0.1.5 and earlier

See the commit history at
<https://github.com/avandajs/flutter-client/commits/main>.
