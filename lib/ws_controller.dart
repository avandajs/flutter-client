import 'dart:async';
import 'dart:io';
import 'dart:math';

/// Lifecycle of the underlying socket, so callers can tell a transient
/// reconnect apart from a connection that is gone for good.
enum WSStatus { connecting, connected, reconnecting, closed }

class WSController {
  String wsUrl;
  Map<String, dynamic>? headers;
  bool wsClosed = false;

  /// Interval between ping frames. `dart:io` drops the socket when a ping goes
  /// unanswered, which is the only way to notice a half-open connection: a
  /// sleeping radio or an expired NAT mapping leaves the socket looking open
  /// forever, so nothing else would ever report the disconnect.
  Duration pingInterval;

  /// Reconnect delay bounds. The delay doubles per failed attempt up to
  /// [maxBackoff].
  Duration minBackoff;
  Duration maxBackoff;

  /// How long a connection must survive before the backoff counter resets. A
  /// server that accepts and then immediately drops would otherwise put the
  /// client in a hot redial loop.
  Duration stableAfter;

  /// Upper bound on messages held while the socket is down. Not applied in
  /// [session] mode, where dropping the oldest frame would corrupt the session.
  int maxPendingMessages;

  /// Whether a dropped socket is redialled. When false the controller closes
  /// for good on the first drop or failed dial.
  bool reconnect;

  /// Session mode, for streams where each connection is a fresh server-side
  /// session. Frames are only queued until the first connection opens; while
  /// the socket is down they are discarded, so nothing from an old session is
  /// replayed into a new one. A failed first dial closes the controller with
  /// the error instead of retrying, so callers can fall back immediately.
  bool session;

  /// Per-dial limit. Null waits for as long as the platform does.
  Duration? connectTimeout;

  StreamController<String> streamController = StreamController.broadcast();

  WebSocket? channel;

  /// Close code of the socket that most recently went away. Kept after the
  /// socket reference is dropped so callers can still report why it ended.
  int? closeCode;

  WSStatus status = WSStatus.connecting;

  final StreamController<WSStatus> _statusController =
      StreamController.broadcast();
  final List<Object> _pending = [];
  final Random _random = Random();

  StreamSubscription? _subscription;
  DateTime? _connectedAt;
  bool _everConnected = false;
  bool _connecting = false;
  int _attempt = 0;

  WSController({
    required this.wsUrl,
    this.headers,
    this.pingInterval = const Duration(seconds: 20),
    this.minBackoff = const Duration(seconds: 1),
    this.maxBackoff = const Duration(seconds: 30),
    this.stableAfter = const Duration(seconds: 5),
    this.maxPendingMessages = 64,
    this.reconnect = true,
    this.session = false,
    this.connectTimeout,
  }) {
    connect();
  }

  connect() {
    initWebSocketConnection();
    return this;
  }

  /// The current status followed by every later change, so a listener that
  /// subscribes after the fact still learns where the connection stands.
  Stream<WSStatus> get statusChanges async* {
    yield status;
    yield* _statusController.stream;
  }

  initWebSocketConnection() async {
    // A single drop reports through both onDone and onError, and a redial can
    // be requested while one is already running. Collapsing every trigger onto
    // one attempt is what stops reconnects from multiplying.
    if (wsClosed || _connecting) return;

    _connecting = true;
    WebSocket? socket;
    try {
      socket = await connectWs();
    } catch (e) {
      // connectWs only throws when it has given up, which ends the controller.
      if (!streamController.isClosed) streamController.addError(e);
      await closeWs();
      return;
    } finally {
      // Cleared before the handlers are attached, so a drop that lands during
      // registration schedules a fresh attempt instead of being swallowed.
      _connecting = false;
    }

    if (socket == null) return;
    broadcastNotifications(socket);
  }

  /// Dials until it succeeds, waiting out [_backoff] between attempts. Returns
  /// null once [closeWs] has been called, and rethrows the dial error when
  /// [reconnect] is off or a [session] could not open its first connection.
  Future<WebSocket?> connectWs() async {
    while (!wsClosed) {
      _setStatus(_everConnected ? WSStatus.reconnecting : WSStatus.connecting);

      if (_attempt > 0) {
        await Future.delayed(_backoff());
        if (wsClosed) return null;
      }

      try {
        var dial = WebSocket.connect(wsUrl, headers: headers);
        var socket = connectTimeout == null
            ? await dial
            : await dial.timeout(connectTimeout!, onTimeout: () {
                // The dial keeps running past the timeout, so whatever it
                // eventually opens has to be closed rather than leaked.
                dial.then<void>((opened) => opened.close(), onError: (_) {});
                throw TimeoutException(
                    'WebSocket connect timed out', connectTimeout);
              });
        if (wsClosed) {
          await socket.close();
          return null;
        }
        return socket;
      } catch (_) {
        if (!reconnect || (session && !_everConnected)) rethrow;
        _attempt++;
      }
    }
    return null;
  }

  broadcastNotifications(WebSocket socket) {
    socket.pingInterval = pingInterval;

    channel = socket;
    _connectedAt = DateTime.now();
    _everConnected = true;

    _subscription = socket.listen(
      (streamData) {
        if (streamData is String && !streamController.isClosed) {
          streamController.add(streamData);
        }
      },
      onDone: _onDisconnected,
      onError: (e) {
        if (!streamController.isClosed) streamController.addError(e);
        _onDisconnected();
      },
      cancelOnError: true,
    );

    _setStatus(WSStatus.connected);
    _flushPending();
  }

  /// Sends [message] as a text frame, queueing it while the socket is down so
  /// it survives a reconnect instead of being dropped on the floor.
  send(String message) {
    _add(message);
  }

  /// Sends [bytes] as a binary frame, queued in order with [send].
  sendBytes(List<int> bytes) {
    _add(bytes);
  }

  _add(Object frame) {
    if (wsClosed) return;

    var socket = channel;
    if (socket == null) {
      if (session) {
        if (_everConnected) return;
      } else if (_pending.length >= maxPendingMessages) {
        _pending.removeAt(0);
      }
      _pending.add(frame);
      return;
    }

    socket.add(frame);
  }

  closeWs([int code = WebSocketStatus.normalClosure]) async {
    if (wsClosed) return;
    wsClosed = true;
    _pending.clear();

    await _subscription?.cancel();
    _subscription = null;

    var socket = channel;
    if (socket != null) {
      // An explicit code lets the server tell a clean goodbye from an abrupt
      // drop. dart:io only reports a code the peer echoed back, so fall back to
      // the closure we asked for.
      await socket.close(code);
      closeCode = socket.closeCode ?? code;
    }
    channel = null;

    _setStatus(WSStatus.closed);

    // Closing the inbound stream is what lets AvandaStream report the close to
    // its listener; leaving it open left onDone unreachable.
    await streamController.close();
    await _statusController.close();
  }

  void _onDisconnected() {
    _subscription?.cancel();
    _subscription = null;

    closeCode = channel?.closeCode;
    channel = null;

    if (wsClosed) return;

    if (!reconnect) {
      closeWs();
      return;
    }

    // A connection that barely lasted counts as a failed attempt so the
    // backoff keeps growing; one that was healthy redials immediately.
    var uptime = _connectedAt == null
        ? Duration.zero
        : DateTime.now().difference(_connectedAt!);
    _attempt = uptime >= stableAfter ? 0 : _attempt + 1;
    _connectedAt = null;

    initWebSocketConnection();
  }

  Duration _backoff() {
    // The exponent is capped so a long outage cannot overflow it.
    var exponent = min(_attempt - 1, 20);
    var ceiling = min(minBackoff.inMilliseconds * pow(2, exponent).toInt(),
        maxBackoff.inMilliseconds);

    // Full jitter, so a fleet of clients does not retry a restarted server in
    // lockstep.
    return Duration(milliseconds: _random.nextInt(ceiling + 1));
  }

  _setStatus(WSStatus next) {
    if (status == next) return;
    status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }

  _flushPending() {
    if (_pending.isEmpty) return;

    var queued = List<Object>.from(_pending);
    _pending.clear();
    for (var message in queued) {
      channel?.add(message);
    }
  }
}
