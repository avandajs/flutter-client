import 'dart:convert';

import 'package:avanda/types/Query.dart';
import 'package:avanda/types/Service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Service bareService() => Service(ft: {}, c: [], p: 1, pr: {});

  group('Service.toJson', () {
    test('emits the full protocol envelope', () {
      expect(bareService().toJson(), {
        'n': null,
        'f': null,
        'c': <dynamic>[],
        'a': null,
        'al': true,
        'p': 1,
        'pr': <dynamic, dynamic>{},
        'ft': <dynamic, dynamic>{},
        'q': <dynamic, dynamic>{},
      });
    });

    test('serializes the populated fields under their short keys', () {
      final service = Service(
        n: 'User',
        f: 'getAll',
        a: 'users',
        al: false,
        c: ['id', 'name'],
        p: 3,
        pr: {'token': 'abc'},
        ft: {
          'id': {'vl': 1, 'op': '='}
        },
        q: Query(c: 'name', k: 'wale'),
      );

      expect(service.toJson(), {
        'n': 'User',
        'f': 'getAll',
        'c': ['id', 'name'],
        'a': 'users',
        'al': false,
        'p': 3,
        'pr': {'token': 'abc'},
        'ft': {
          'id': {'vl': 1, 'op': '='}
        },
        'q': {'c': 'name', 'k': 'wale'},
      });
    });

    test('autoLink defaults to true', () {
      expect(bareService().toJson()['al'], isTrue);
    });

    test('a null query becomes an empty map rather than null', () {
      expect(bareService().toJson()['q'], <dynamic, dynamic>{});
    });

    test('recursively serializes nested services in the column list', () {
      final child = Service(n: 'Owner', f: 'get', ft: {}, c: ['id'], p: 1, pr: {});
      final parent =
          Service(n: 'Car', f: 'get', ft: {}, c: ['id', child], p: 1, pr: {});

      final json = parent.toJson();
      expect(json['c'][0], 'id');
      expect(json['c'][1], isA<Map>());
      expect(json['c'][1]['n'], 'Owner');
      expect(json['c'][1]['c'], ['id']);
    });

    test('leaves non-Service columns untouched', () {
      final service = bareService()..c = ['id', 42, null];
      expect(service.toJson()['c'], ['id', 42, null]);
    });

    test('nests to arbitrary depth', () {
      final level3 = Service(n: 'C', ft: {}, c: ['id'], p: 1, pr: {});
      final level2 = Service(n: 'B', ft: {}, c: [level3], p: 1, pr: {});
      final level1 = Service(n: 'A', ft: {}, c: [level2], p: 1, pr: {});

      expect(level1.toJson()['c'][0]['c'][0]['n'], 'C');
    });

    test('is json encodable end to end', () {
      final service = Service(
        n: 'User',
        f: 'get',
        ft: {},
        c: [
          'id',
          Service(n: 'Post', ft: {}, c: ['title'], p: 1, pr: {})
        ],
        p: 1,
        pr: {},
        q: Query(c: 'name', k: 'wale'),
      );

      final decoded = jsonDecode(jsonEncode(service)) as Map<String, dynamic>;
      expect(decoded['n'], 'User');
      expect(decoded['c'][1]['n'], 'Post');
      expect(decoded['q'], {'c': 'name', 'k': 'wale'});
    });
  });

  group('Query.toJson', () {
    test('serializes the column and keyword', () {
      expect(Query(c: 'name', k: 'wale').toJson(), {'c': 'name', 'k': 'wale'});
    });

    test('keeps null fields so the shape stays stable', () {
      expect(Query().toJson(), {'c': null, 'k': null});
    });
  });
}
