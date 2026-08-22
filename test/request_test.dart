import 'dart:convert';

import 'package:avanda/avanda.dart';
import 'package:avanda/exceptions/Internal_server_error.dart';
import 'package:avanda/exceptions/access_forbidden_error.dart';
import 'package:avanda/exceptions/bad_request_error.dart';
import 'package:avanda/exceptions/file_not_found_error.dart';
import 'package:avanda/exceptions/internet_network_error.dart';
import 'package:avanda/exceptions/method_not_allowed_error.dart';
import 'package:avanda/exceptions/request_exception.dart';
import 'package:avanda/exceptions/unauthorized_error.dart';
import 'package:avanda/response.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'test_helpers.dart';

void main() {
  /// Requests captured by the mock client during the last [send] call.
  late List<http.Request> sent;

  setUp(() {
    resetAvandaStatics();
    Avanda.setConfig(AvandaConfig(rootUrl: 'http://api.test:4000/'));
    sent = [];
  });

  /// Runs [body] with every `http` call intercepted, so no socket is opened.
  /// [respond] builds the fake server reply for each captured request.
  Future<T> send<T>(
    Future<T> Function() body, {
    http.Response Function(http.Request request)? respond,
    Object Function(http.Request request)? failWith,
  }) {
    final client = MockClient((request) async {
      sent.add(request);
      if (failWith != null) throw failWith(request);
      return respond?.call(request) ??
          http.Response(jsonEncode({'status_code': 200, 'msg': 'ok'}), 200);
    });

    return http.runWithClient(body, () => client);
  }

  /// A server reply in the envelope `ResponseStruct.fromJson` expects.
  http.Response envelope(int statusCode, {String? msg, Object? data}) =>
      http.Response(
        jsonEncode({'status_code': statusCode, 'msg': msg, 'data': data}),
        200,
      );

  group('configuration guard', () {
    test('makeRequest throws when no root url is configured', () {
      Avanda.setConfig(AvandaConfig(rootUrl: null));

      expect(
        Avanda().service('User/getAll').get(),
        throwsA('Specify the server root URL in Avanda.setConfig() function'),
      );
    });
  });

  group('url construction', () {
    test('appends the serialized query tree to the root url', () async {
      await send(() => Avanda().service('User/getAll').select(['id']).get());

      final url = sent.single.url;
      expect(url.scheme, 'http');
      expect(url.host, 'api.test');
      expect(url.port, 4000);
      expect(url.path, '/');

      expect(queryParamOf(url), containsPair('n', 'User'));
      expect(queryParamOf(url), containsPair('f', 'get'));
      expect(queryParamOf(url), containsPair('c', ['id']));
    });

    test('percent-encodes the JSON so the url stays parseable', () async {
      await send(() => Avanda().service('User').where({'name': 'a b'}).get());

      // Raw braces and quotes must not survive into the request line.
      expect(sent.single.url.toString(), isNot(contains('{')));
      expect(queryParamOf(sent.single.url)['ft'], {
        'name': {'vl': 'a b', 'op': '='}
      });
    });

    test('forwards the static headers on every request', () async {
      Avanda.setHeaders({'Authorization': 'Bearer tok', 'X-Tenant': 'acme'});

      await send(() => Avanda().service('User').get());

      expect(sent.single.headers, containsPair('Authorization', 'Bearer tok'));
      expect(sent.single.headers, containsPair('X-Tenant', 'acme'));
    });
  });

  group('http verbs', () {
    test('get issues a GET with no body', () async {
      await send(() => Avanda().service('User/getAll').get());

      expect(sent.single.method, 'GET');
      expect(sent.single.body, isEmpty);
    });

    test('delete issues a DELETE', () async {
      await send(() => Avanda().service('User/remove').ref(7).delete());

      expect(sent.single.method, 'DELETE');
      expect(queryParamOf(sent.single.url)['ft'], {
        'id': {'vl': 7, 'op': '='}
      });
    });

    test('set issues a POST with a form-encoded body', () async {
      await send(() =>
          Avanda().service('User/create').set({'name': 'wale', 'age': 30}));

      expect(sent.single.method, 'POST');
      expect(sent.single.bodyFields, {'name': 'wale', 'age': '30'});
      expect(sent.single.headers['content-type'],
          startsWith('application/x-www-form-urlencoded'));
    });

    test('post delegates to set', () async {
      await send(() => Avanda().service('User/create').post({'name': 'wale'}));

      expect(sent.single.method, 'POST');
      expect(sent.single.bodyFields, {'name': 'wale'});
    });

    test('update posts with the _method=PATCH override', () async {
      await send(() =>
          Avanda().service('User/edit').ref(7).update({'name': 'wale'}));

      expect(sent.single.method, 'POST');
      expect(sent.single.url.queryParameters['_method'], 'PATCH');
      expect(sent.single.bodyFields, {'name': 'wale'});
    });

    test('data() supplies the body without sending it immediately', () async {
      final query = Avanda().service('User/create').data({'name': 'wale'});
      expect(sent, isEmpty);

      // `data` feeds `watch`; `set` still takes its own values.
      await send(() => query.set({'name': 'other'}));
      expect(sent.single.bodyFields, {'name': 'other'});
    });
  });

  group('successful responses', () {
    test('returns a Response wrapping the decoded envelope', () async {
      final response = await send(
        () => Avanda().service('User/getAll').get(),
        respond: (_) => envelope(200, msg: 'Fetched', data: [
          {'id': 1}
        ]),
      );

      expect(response, isA<Response>());
      expect(response.getStatus(), 200);
      expect(response.getMsg(), 'Fetched');
      expect(response.getData(), [
        {'id': 1}
      ]);
      expect(response.isError(), isFalse);
    });

    test('carries pagination metadata through', () async {
      final response = await send(
        () => Avanda().service('User/getAllByPage').page(2).get(),
        respond: (_) => http.Response(
          jsonEncode({
            'status_code': 200,
            'current_page': 2,
            'per_page': 15,
            'total_pages': 7,
          }),
          200,
        ),
      );

      expect(response.getCurrentPage(), 2);
      expect(response.getPerPage(), 15);
      expect(response.getTotalPages(), 7);
    });

    test('trusts the envelope status over the transport status', () async {
      // The library ignores httpResponse.statusCode entirely.
      final response = await send(
        () => Avanda().service('User').get(),
        respond: (_) => http.Response(jsonEncode({'status_code': 200}), 500),
      );

      expect(response.getStatus(), 200);
    });
  });

  group('error envelope mapping', () {
    final expected = <int, Matcher>{
      400: isA<BadRequestError>(),
      401: isA<UnauthorizedAccess>(),
      403: isA<AccessForbiddenError>(),
      404: isA<FileNotFoundError>(),
      405: isA<MethodNotAllowedError>(),
      500: isA<InternalServerError>(),
    };

    expected.forEach((status, matcher) {
      test('status $status throws the matching RequestException', () {
        expect(
          send(
            () => Avanda().service('User').get(),
            respond: (_) => envelope(status, msg: 'failed'),
          ),
          throwsA(allOf(isA<RequestException>(), matcher)),
        );
      });
    });

    test('the thrown exception carries the server response', () async {
      try {
        await send(
          () => Avanda().service('User').get(),
          respond: (_) => envelope(404, msg: 'No such user'),
        );
        fail('expected a FileNotFoundError');
      } on RequestException catch (e) {
        expect(e.getResponse().msg, 'No such user');
        expect(e.getResponse().status, 404);
      }
    });

    test('does not throw for a 2xx envelope', () {
      expect(
        send(
          () => Avanda().service('User').get(),
          respond: (_) => envelope(201, msg: 'Created'),
        ),
        completes,
      );
    });

    test(
        'KNOWN BUG: an unmapped error status is returned instead of raising '
        'UnknownError', () async {
      final response = await send(
        () => Avanda().service('User').get(),
        respond: (_) => envelope(418, msg: 'teapot'),
      );

      // `errors` has no 418 key, so the containsKey check short-circuits and
      // UnknownError is unreachable. Callers must check isError() themselves.
      expect(response.getStatus(), 418);
      expect(response.isError(), isTrue);
    });

    test('KNOWN BUG: status 0 is mapped but never thrown, since 0 < 300',
        () async {
      final response = await send(
        () => Avanda().service('User').get(),
        respond: (_) => http.Response(jsonEncode({'msg': 'no status'}), 200),
      );

      expect(response.getStatus(), 0);
      expect(response.isError(), isTrue);
    });
  });

  group('transport failures', () {
    test('a socket failure becomes InternetNetworkError', () {
      expect(
        send(
          () => Avanda().service('User').get(),
          failWith: (_) => http.ClientException('Connection refused'),
        ),
        throwsA(isA<InternetNetworkError>()),
      );
    });

    test('the network error message is preserved on the exception', () async {
      try {
        await send(
          () => Avanda().service('User').get(),
          failWith: (_) => http.ClientException('Connection refused'),
        );
        fail('expected an InternetNetworkError');
      } on InternetNetworkError catch (e) {
        expect(e.getResponse().msg, contains('Connection refused'));
      }
    });

    test('a malformed body surfaces as a FormatException, not a Response', () {
      expect(
        send(
          () => Avanda().service('User').get(),
          respond: (_) => http.Response('<html>502 Bad Gateway</html>', 502),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
