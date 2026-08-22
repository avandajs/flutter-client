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

  /// Upper bound on messages held while the socket is down.
  int maxPendingMessages;

  StreamController<String> streamController = StreamController.broadcast();

  WebSocket? channel;

  /// Close code of the socket that most recently went away. Kept after the
  /// socket reference is dropped so callers can still report why it ended.
  int? closeCode;

  WSStatus status = WSStatus.connecting;

  final StreamController<WSStatus> _statusController =
      StreamController.broadcast();
  final List<String> _pending = [];
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
    } finally {
      // Cleared before the handlers are attached, so a drop that lands during
      // registration schedules a fresh attempt instead of being swallowed.
      _connecting = false;
    }

    if (socket == null) return;
    broadcastNotifications(socket);
  }

  /// Dials until it succeeds, waiting out [_backoff] between attempts. Returns
  /// null once [closeWs] has been called.
  Future<WebSocket?> connectWs() async {
    while (!wsClosed) {
      _setStatus(_everConnected ? WSStatus.reconnecting : WSStatus.connecting);

      if (_attempt > 0) {
        await Future.delayed(_backoff());
        if (wsClosed) return null;
      }

      try {
        var socket = await WebSocket.connect(wsUrl, headers: headers);
        if (wsClosed) {
          await socket.close();
          return null;
        }
        return socket;
      } catch (_) {
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

  /// Queues [message] while the socket is down so it survives a reconnect
  /// instead of being dropped on the floor.
  send(String message) {
    if (wsClosed) return;

    var socket = channel;
    if (socket == null) {
      if (_pending.length >= maxPendingMessages) _pending.removeAt(0);
      _pending.add(message);
      return;
    }

    socket.add(message);
  }

  closeWs() async {
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
      await socket.close(WebSocketStatus.normalClosure);
      closeCode = socket.closeCode ?? WebSocketStatus.normalClosure;
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

    var queued = List<String>.from(_pending);
    _pending.clear();
    for (var message in queued) {
      channel?.add(message);
    }
  }
}
