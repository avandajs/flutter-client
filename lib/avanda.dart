library avanda;

import 'dart:async';
import 'dart:convert';
import 'package:avanda/exceptions/Internal_server_error.dart';
import 'package:avanda/exceptions/access_forbidden_error.dart';
import 'package:avanda/exceptions/bad_request_error.dart';
import 'package:avanda/exceptions/file_not_found_error.dart';
import 'package:avanda/exceptions/internet_network_error.dart';
import 'package:avanda/exceptions/method_not_allowed_error.dart';
import 'package:avanda/exceptions/request_exception.dart';
import 'package:avanda/exceptions/unauthorized_error.dart';
import 'package:avanda/exceptions/unknown_error.dart';
import 'package:avanda/response.dart';
import 'package:avanda/types/Query.dart';
import 'package:avanda/types/ResponseStruct.dart';
import 'package:avanda/types/Service.dart';
import 'package:avanda/ws_controller.dart';
import 'package:http/http.dart' as http;

// WSStatus is part of the public API via AvandaStream.statusChanges, so it has
// to be reachable from this entry point.
export 'package:avanda/ws_controller.dart' show WSController, WSStatus;

typedef WatchCallback = Function(Response response);
typedef ErrorCallback = Function(Response response);
typedef CloseEventFnc = Function();
typedef CloseFnc = Function();
//void onData(T event)?,
//       {Function? onError, void onDone()?, bool? cancelOnError}

enum RequestMethods { get, delete, post }

class AvandaConfig {
  bool secureWebSocket = false;
  bool debugMode = false;
  String? rootUrl;
  String? wsUrl;
  AvandaConfig(
      {required this.rootUrl, this.secureWebSocket = false, this.wsUrl});
}

class AvandaStream {
  Stream<Response> stream;
  StreamSink<String> wsSink;
  CloseEventFnc? _onServerClosed; //Function? onError, void onDone()?
  CloseEventFnc? _onClosed; //Function? onError, void onDone()?
  Function(Object error)? _onError;
  bool closed = false;
  WSController controller;

  AvandaStream(
      {required this.stream, required this.wsSink, required this.controller});

  StreamSubscription<Response> listen(void Function(Response event) onData) {
    return stream.listen(
      onData,
      onDone: () {
        if (!closed && _onServerClosed != null) {
          _onServerClosed!();
        }
      },
      onError: (error) {
        if (_onError != null) _onError!(error);
      },
    );
  }

  /// Emits the current connection state and every later change, so callers can
  /// show a reconnecting indicator instead of guessing from a silent stream.
  Stream<WSStatus> get statusChanges => controller.statusChanges;

  Future<AvandaStream> close() async {
    closed = true;
    await controller.closeWs();
    if (closed && _onClosed != null) {
      _onClosed!();
    }
    return this;
  }

  Future<AvandaStream> onServerClosed(Function(int? code)? onClosed) async {
    if (!closed && onClosed != null) {
      _onServerClosed = () {
        onClosed(controller.closeCode);
      };
    }
    return this;
  }

  Future<AvandaStream> onError(Function(Object error)? onError) async {
    if (!closed && onError != null) {
      _onError = onError;
    }
    return this;
  }

  Future<AvandaStream> onClosed(Function([int? code])? onClosed) async {
    if (onClosed != null) {
      _onClosed = () {
        onClosed(controller.closeCode);
      };
    }
    return this;
  }

  Future<AvandaStream> send(Map<String, dynamic> data) async {
    controller.send(jsonEncode(data));
    return this;
  }
}

class Avanda {
  static String endpoint = "/";

  Service queryTree = Service(ft: {}, c: [], p: 1, pr: {}, al: true);
  static AvandaConfig config =
      AvandaConfig(rootUrl: null, secureWebSocket: false);
  static Map<String, String> headers = {};

  bool autoLink = true;

  dynamic lastCol;
  bool accumulate = false;

  Map<dynamic, dynamic>? postData;

  static setHeaders(Map<String, String> newHeaders) {
    if (headers.isEmpty) {
      headers = newHeaders;
    } else {
      headers.addAll(newHeaders);
    }
  }

  static setGraphRoot(String root) {
    Avanda.config.rootUrl = root;
  }

  static setConfig(AvandaConfig config) {
    Avanda.config = config;
  }

  static column(String column) {
    RegExp pattern = RegExp(r'[^\w\_\*]+');
    if (pattern.hasMatch(column)) {
      throw "Invalid column name";
    }
    return column;
  }

  Future<dynamic> file(event) async {}

  static validColOnly(String column) {
    RegExp pattern = RegExp(r'!/([\w._]+|\*)/');
    if (pattern.hasMatch(column)) {
      throw "Invalid column name";
    }
    return column;
  }

  static col(String column) {
    return Avanda.column(column);
  }

  Avanda disableAutoLink() {
    queryTree.al = false;
    return this;
  }

  Avanda service(String name) {
    List tokens = name.split("/");
    queryTree.f = tokens.length > 1 ? tokens[1] : null;
    queryTree.n = tokens[0];
    return this;
  }

  Avanda where(dynamic conditions) {
    if (conditions is Map) {
      queryTree.ft = objToFilter(conditions);
    } else if (conditions is String) {
      lastCol = conditions;
    }
    return this;
  }

  Map objToFilter(Map obj) {
    Map filters = {};

    for (String k in obj.keys) {
      filters[k] = {'vl': obj[k], 'op': "="};
    }
    //
    return filters;
  }

  Avanda andWhere(dynamic conditions) {
    if (queryTree.n == null) {
      throw 'Specify service to apply where clause on';
    }

    if (conditions is Map) {
      queryTree.ft = {...queryTree.ft, ...conditions};
    } else if (conditions is String) {
      lastCol = conditions;
    }
    return this;
  }

  Avanda greaterThan(int value) {
    return addCustomFilter(value, ">");
  }

  Avanda lessThan(int value) {
    return addCustomFilter(value, "<");
  }

  Avanda equals(dynamic value) {
    return addCustomFilter(value, "==");
  }

  Avanda notEquals(dynamic value) {
    return addCustomFilter(value, "!=");
  }

  Avanda isNull() {
    return addCustomFilter(null, "NULL");
  }

  Avanda isNotNull() {
    return addCustomFilter(null, "NOTNULL");
  }

  Avanda isLike(dynamic value) {
    return addCustomFilter(value, "LIKES");
  }

  Avanda isNotLike(value) {
    return addCustomFilter(value, "NOT-LIKES");
  }

  Avanda addCustomFilter(dynamic value, String operator) {
    if (lastCol == null) {
      throw "Specify column to compare $value with";
    }
    Map filter = {
      lastCol: {'vl': value, 'op': operator}
    };

    if (queryTree.n == null) {
      throw 'Specify service to apply where clauses';
    }

    queryTree.ft = {...(accumulate ? queryTree.ft : {}), ...filter};

    lastCol = null;
    accumulate = false;

    return this;
  }

  Avanda ref(int id) {
    queryTree.ft = {
      ...queryTree.ft,
      ...objToFilter({'id': id})
    };
    return this;
  }

  Avanda page(int page) {
    queryTree.p = page;
    return this;
  }

  Avanda search(String col, String keyword) {
    queryTree.q = Query(c: Avanda.column(col), k: keyword);
    return this;
  }

  Avanda select(List columns) {
    if (queryTree.n == null) {
      throw 'Specify service to select from';
    }
    queryTree.f = "get";
    fetch(columns);
    return this;
  }

  Avanda selectAll(List columns) {
    if (queryTree.n == null) {
      throw 'Specify service to select from';
    }
    queryTree.f = "getAll";
    fetch(columns);
    return this;
  }

  Avanda func(String func) {
    if (queryTree.n == null) {
      throw 'Specify service to select from';
    }
    queryTree.f = func;
    return this;
  }

  Avanda fetch(List columns) {
    if (queryTree.n == null) {
      throw "Specify service to fetch from";
    }

    queryTree.c = columns.map((column) {
      if (column is Avanda) {
        return column.queryTree;
      }
      return column is String ? Avanda.column(column) : column;
    }).toList();

    return this;
  }

  Service as(String alias) {
    if (queryTree.n == null) {
      throw 'Specify service to apply alias to';
    }
    queryTree.a = alias;
    return queryTree;
  }

  String toLink() {
    if (queryTree.n == null) {
      throw "Service not specified";
    }
    queryTree.al = true;
    return jsonEncode(queryTree);
  }

  stringifyPayload(Map<dynamic, dynamic>? payload) {
    if (payload == null) {
      return {};
    }

    return payload.map((key, value) => MapEntry(key, value.toString()));
  }

  Future<Response> makeRequest({
    endpoint,
    required RequestMethods method,
    Map<dynamic, dynamic>? params,
  }) async {
    if (Avanda.config.rootUrl == null) {
      throw "Specify the server root URL in Avanda.setConfig() function";
    }

    http.Response httpResponse;

    params = stringifyPayload(params);

    endpoint = Avanda.config.rootUrl! + '?query=' + endpoint;

    print(endpoint);

    try {
      switch (method) {
        case RequestMethods.get:
          httpResponse = await http.get(
            Uri.parse(endpoint),
            headers: headers,
          );
          break;
        case RequestMethods.post:
          httpResponse = await http.post(
            Uri.parse(endpoint),
            headers: headers,
            body: params,
          );
          break;
        case RequestMethods.delete:
          httpResponse = await http.delete(
            Uri.parse(endpoint),
            headers: headers,
            body: params,
          );
          break;
      }
    } catch (e) {
      throw InternetNetworkError(
          ResponseStruct.fromJson({'msg': e.toString()}));
    }
    if (Avanda.config.debugMode) {
      print(httpResponse.body);
    }

    var response = ResponseStruct.fromJson(jsonDecode(httpResponse.body));

    Map<int, RequestException> errors = {
      404: FileNotFoundError(response),
      400: BadRequestError(response),
      500: InternalServerError(response),
      403: AccessForbiddenError(response),
      401: UnauthorizedAccess(response),
      405: MethodNotAllowedError(response),
      0: InternetNetworkError(response),
    };

    if (errors.containsKey(response.status) &&
        (response.status ?? 500) >= 300) {
      throw errors[response.status] ?? UnknownError(response);
    }

    return Response(response);
  }

  Future<Response> get() async {
    var link = toLink();
    return await makeRequest(endpoint: link, method: RequestMethods.get);
  }

  Future<Response> post(Map<dynamic, dynamic> values) async {
    return await set(values);
  }

  Future<Response> delete() async {
    var link = toLink();
    return await makeRequest(endpoint: link, method: RequestMethods.delete);
  }

  Future<Response> set(Map<dynamic, dynamic> values) async {
    if (queryTree.n == null) {
      throw "Specify service to send request to";
    }
    postData = values;

    String link = toLink();

    return await makeRequest(
      endpoint: link,
      method: RequestMethods.post,
      params: postData,
    );
  }

  Future<Response> update(Map<dynamic, dynamic> values) async {
    if (queryTree.n == null) {
      throw 'Specify service to send request to';
    }

    postData = values;

    String link = toLink() + '&_method=PATCH';
    return await makeRequest(
        endpoint: link, method: RequestMethods.post, params: postData);
  }

  Avanda params(Map params) {
    if (queryTree.n == null) {
      throw 'Specify service to bind param to';
    }
    queryTree.pr = params;
    return this;
  }

  Avanda data(Map data) {
    if (queryTree.n == null) {
      throw 'Specify service to bind param to';
    }
    postData = data;
    return this;
  }

  Future<AvandaStream?> watch([WatchCallback? callback]) async {
    if (queryTree.n == null) {
      throw "Specify service to send request to";
    }

    var uri = (Avanda.config.wsUrl ?? Avanda.config.rootUrl);

    if (uri == null) {
      throw "Specify the server root URL in Avanda.setConfig() function";
    }

    String link = toLink();

    var url = Uri.parse(uri);

    var endpoint =
        (Avanda.config.secureWebSocket == true ? 'wss://' : 'ws://') + url.host;

    if (url.hasPort) {
      endpoint += (':' + url.port.toString());
    }
    endpoint += '/watch?query=' + link;

    if (postData != null && postData!.isNotEmpty) {
      endpoint += '&data=' + jsonEncode(postData);
    }

    var controller = WSController(wsUrl: endpoint, headers: headers);
    var streamController = controller.streamController;

    var stream = AvandaStream(
      stream: streamController.stream
          .map((event) => Response(ResponseStruct.fromJson(jsonDecode(event)))),
      wsSink: streamController.sink,
      controller: controller,
    );

    return stream;
  }
}
