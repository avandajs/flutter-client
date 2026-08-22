import 'package:avanda/response.dart';
import 'package:avanda/types/ResponseStruct.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ResponseStruct.fromJson', () {
    test('maps the server field names onto the struct', () {
      final struct = ResponseStruct.fromJson({
        'msg': 'Fetched successfully',
        'data': [
          {'id': 1}
        ],
        'status_code': 200,
        'current_page': 2,
        'per_page': 15,
        'total_pages': 4,
      });

      expect(struct.msg, 'Fetched successfully');
      expect(struct.data, [
        {'id': 1}
      ]);
      expect(struct.status, 200);
      expect(struct.currentPage, 2);
      expect(struct.perPage, 15);
      expect(struct.totalPages, 4);
    });

    test('falls back to status 0 when the server omits status_code', () {
      expect(ResponseStruct.fromJson({'msg': 'hi'}).status, 0);
    });

    test('falls back to a single first page when pagination is omitted', () {
      final struct = ResponseStruct.fromJson({});
      expect(struct.currentPage, 1);
      expect(struct.perPage, 1);
      expect(struct.totalPages, 1);
    });

    test('leaves msg and data null when absent', () {
      final struct = ResponseStruct.fromJson({'status_code': 204});
      expect(struct.msg, isNull);
      expect(struct.data, isNull);
    });

    test('never populates networkMsg, which only makes sense locally', () {
      expect(ResponseStruct.fromJson({'network_msg': 'offline'}).networkMsg,
          isNull);
    });

    test('preserves a scalar data payload', () {
      expect(ResponseStruct.fromJson({'data': 42}).status, 0);
      expect(ResponseStruct.fromJson({'data': 42}).data, 42);
    });
  });

  group('ResponseStruct constructor defaults', () {
    test('defaults differ from the fromJson defaults for perPage', () {
      // Documents a real inconsistency: the constructor uses 0, fromJson uses 1.
      expect(ResponseStruct().perPage, 0);
      expect(ResponseStruct.fromJson({}).perPage, 1);
    });

    test('defaults to the first page', () {
      final struct = ResponseStruct();
      expect(struct.currentPage, 1);
      expect(struct.totalPages, 1);
    });

    test(
        'KNOWN BUG: the `= 0` initializer on status is dead, so a default '
        'struct has a null status', () {
      // `ResponseStruct({this.status})` always assigns the parameter, so the
      // field initializer never applies and getStatus() would throw.
      expect(ResponseStruct().status, isNull);
      expect(() => Response(ResponseStruct()).getStatus(),
          throwsA(isA<TypeError>()));
    });
  });

  group('Response accessors', () {
    Response responseWith(Map<String, dynamic> json) =>
        Response(ResponseStruct.fromJson(json));

    test('exposes the raw struct it wraps', () {
      final struct = ResponseStruct.fromJson({'status_code': 200});
      expect(Response(struct).rawResponse, same(struct));
    });

    test('getMsg returns the server message', () {
      expect(responseWith({'msg': 'Created'}).getMsg(), 'Created');
    });

    test('getMsg throws when the server sent no message', () {
      expect(() => responseWith({'status_code': 200}).getMsg(),
          throwsA(isA<TypeError>()));
    });

    test('getStatus returns the status code', () {
      expect(responseWith({'status_code': 201}).getStatus(), 201);
    });

    test('getData returns the payload', () {
      expect(responseWith({'data': [1, 2, 3]}).getData(), [1, 2, 3]);
    });

    test('getData casts to the requested type', () {
      final response = responseWith({
        'data': {'id': 1}
      });
      expect(response.getData<Map<String, dynamic>>(), {'id': 1});
    });

    test('getData throws when the payload does not match the requested type',
        () {
      expect(() => responseWith({'data': 'not a list'}).getData<List>(),
          throwsA(isA<TypeError>()));
    });

    test('setData overwrites the payload and returns the response for chaining',
        () {
      final response = responseWith({'data': 1});
      expect(response.setData('replaced'), same(response));
      expect(response.getData(), 'replaced');
    });

    test('pagination accessors read through to the struct', () {
      final response = responseWith({
        'current_page': 3,
        'per_page': 20,
        'total_pages': 9,
      });

      expect(response.getCurrentPage(), 3);
      expect(response.getPerPage(), 20);
      expect(response.getTotalPages(), 9);
    });

    test('getNetworkErrorMsg is null for a server response', () {
      expect(responseWith({'status_code': 200}).getNetworkErrorMsg(), isNull);
    });

    test('getNetworkErrorMsg surfaces a locally set network message', () {
      final struct = ResponseStruct.fromJson({'msg': 'Connection refused'});
      struct.networkMsg = 'Connection refused';
      expect(Response(struct).getNetworkErrorMsg(), 'Connection refused');
    });
  });

  group('Response.isError', () {
    Response withStatus(int status) =>
        Response(ResponseStruct.fromJson({'status_code': status}));

    test('treats 0 as an error because it signals no server reply', () {
      expect(withStatus(0).isError(), isTrue);
    });

    test('treats 2xx as success', () {
      expect(withStatus(200).isError(), isFalse);
      expect(withStatus(201).isError(), isFalse);
    });

    test('puts the success/failure boundary between 299 and 300', () {
      expect(withStatus(299).isError(), isFalse);
      expect(withStatus(300).isError(), isTrue);
    });

    test('treats 4xx and 5xx as errors', () {
      expect(withStatus(400).isError(), isTrue);
      expect(withStatus(404).isError(), isTrue);
      expect(withStatus(500).isError(), isTrue);
    });
  });
}
