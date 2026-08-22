import 'package:avanda/avanda.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  setUp(resetAvandaStatics);

  group('Avanda.column', () {
    test('accepts word characters, underscores and the wildcard', () {
      expect(Avanda.column('name'), 'name');
      expect(Avanda.column('first_name'), 'first_name');
      expect(Avanda.column('address2'), 'address2');
      expect(Avanda.column('*'), '*');
    });

    test('rejects anything that could break out of a column position', () {
      for (final bad in [
        'user.name',
        'first name',
        'first-name',
        'id;DROP TABLE users',
        'count(*)',
        "name'",
      ]) {
        expect(() => Avanda.column(bad), throwsA('Invalid column name'),
            reason: 'expected "$bad" to be rejected');
      }
    });

    test('col is an alias for column', () {
      expect(Avanda.col('name'), 'name');
      expect(() => Avanda.col('a b'), throwsA('Invalid column name'));
    });
  });

  group('service', () {
    test('uses the whole string as the service name when there is no slash',
        () {
      final query = Avanda().service('User');
      expect(query.queryTree.n, 'User');
      expect(query.queryTree.f, isNull);
    });

    test('splits "Service/function" into name and function', () {
      final query = Avanda().service('User/getAllByPage');
      expect(query.queryTree.n, 'User');
      expect(query.queryTree.f, 'getAllByPage');
    });

    test('is chainable', () {
      final query = Avanda();
      expect(query.service('User'), same(query));
    });
  });

  group('guards against a missing service', () {
    test('toLink throws', () {
      expect(() => Avanda().toLink(), throwsA('Service not specified'));
    });

    test('select and selectAll throw', () {
      expect(() => Avanda().select(['id']),
          throwsA('Specify service to select from'));
      expect(() => Avanda().selectAll(['id']),
          throwsA('Specify service to select from'));
    });

    test('func throws', () {
      expect(() => Avanda().func('custom'),
          throwsA('Specify service to select from'));
    });

    test('fetch throws', () {
      expect(() => Avanda().fetch(['id']),
          throwsA('Specify service to fetch from'));
    });

    test('as throws', () {
      expect(() => Avanda().as('u'),
          throwsA('Specify service to apply alias to'));
    });

    test('andWhere throws', () {
      expect(() => Avanda().andWhere({'id': 1}),
          throwsA('Specify service to apply where clause on'));
    });

    test('params and data throw', () {
      expect(() => Avanda().params({'id': 1}),
          throwsA('Specify service to bind param to'));
      expect(() => Avanda().data({'id': 1}),
          throwsA('Specify service to bind param to'));
    });

    test('set, post and update throw', () {
      expect(Avanda().set({'a': 1}),
          throwsA('Specify service to send request to'));
      expect(Avanda().post({'a': 1}),
          throwsA('Specify service to send request to'));
      expect(Avanda().update({'a': 1}),
          throwsA('Specify service to send request to'));
    });

    test('watch throws', () {
      expect(Avanda().watch(), throwsA('Specify service to send request to'));
    });
  });

  group('toLink serialization', () {
    test('emits every key the server protocol expects', () {
      final link = linkOf(Avanda().service('User'));
      expect(
        link.keys,
        containsAll(['n', 'f', 'c', 'a', 'al', 'p', 'pr', 'ft', 'q']),
      );
    });

    test('a bare service serializes with protocol defaults', () {
      expect(linkOf(Avanda().service('User')), {
        'n': 'User',
        'f': null,
        'c': <dynamic>[],
        'a': null,
        'al': true,
        'p': 1,
        'pr': <String, dynamic>{},
        'ft': <String, dynamic>{},
        'q': <String, dynamic>{},
      });
    });

    test('select requests the "get" function with the given columns', () {
      final link = linkOf(Avanda().service('User').select(['id', 'name']));
      expect(link['f'], 'get');
      expect(link['c'], ['id', 'name']);
    });

    test('selectAll requests the "getAll" function', () {
      final link = linkOf(Avanda().service('User').selectAll(['id']));
      expect(link['f'], 'getAll');
      expect(link['c'], ['id']);
    });

    test('an explicit service function survives select', () {
      // select overwrites `f`, so the function has to be set afterwards.
      final query = Avanda().service('User/ignored');
      query.select(['id']);
      query.func('custom');
      expect(linkOf(query)['f'], 'custom');
    });

    test('select validates every column name', () {
      expect(() => Avanda().service('User').select(['id', 'bad name']),
          throwsA('Invalid column name'));
    });

    test('non-string columns are passed through unvalidated', () {
      final link = linkOf(Avanda().service('User').select(['id', 42]));
      expect(link['c'], ['id', 42]);
    });

    test('page sets the requested page', () {
      expect(linkOf(Avanda().service('User').page(3))['p'], 3);
    });

    test('search records the column and keyword', () {
      final link = linkOf(Avanda().service('User').search('name', 'wale'));
      expect(link['q'], {'c': 'name', 'k': 'wale'});
    });

    test('search validates the column name', () {
      expect(() => Avanda().service('User').search('na me', 'wale'),
          throwsA('Invalid column name'));
    });

    test('params are attached verbatim', () {
      final link = linkOf(Avanda().service('User').params({'token': 'abc'}));
      expect(link['pr'], {'token': 'abc'});
    });
  });

  group('filters', () {
    test('where with a map wraps each entry as an equality filter', () {
      final link = linkOf(Avanda().service('User').where({'id': 3}));
      expect(link['ft'], {
        'id': {'vl': 3, 'op': '='}
      });
    });

    test('where with a map replaces any previously built filters', () {
      final query = Avanda().service('User');
      query.where({'id': 3});
      query.where({'name': 'wale'});
      expect(linkOf(query)['ft'], {
        'name': {'vl': 'wale', 'op': '='}
      });
    });

    test('objToFilter converts a plain map into protocol filters', () {
      expect(Avanda().objToFilter({'a': 1, 'b': 'two'}), {
        'a': {'vl': 1, 'op': '='},
        'b': {'vl': 'two', 'op': '='},
      });
    });

    test('ref filters on the id column', () {
      expect(linkOf(Avanda().service('User').ref(7))['ft'], {
        'id': {'vl': 7, 'op': '='}
      });
    });

    test('ref merges into existing filters', () {
      final query = Avanda().service('User');
      query.where({'active': true});
      query.ref(7);
      expect(linkOf(query)['ft'], {
        'active': {'vl': true, 'op': '='},
        'id': {'vl': 7, 'op': '='},
      });
    });
  });

  group('comparison operators', () {
    test('each operator emits its protocol operator token', () {
      final cases = <String, Avanda Function(Avanda)>{
        '>': (q) => q.greaterThan(5),
        '<': (q) => q.lessThan(5),
        '==': (q) => q.equals(5),
        '!=': (q) => q.notEquals(5),
        'LIKES': (q) => q.isLike(5),
        'NOT-LIKES': (q) => q.isNotLike(5),
      };

      cases.forEach((op, apply) {
        final query = Avanda().service('User');
        query.where('age');
        apply(query);
        expect(linkOf(query)['ft'], {
          'age': {'vl': 5, 'op': op}
        }, reason: 'operator $op');
      });
    });

    test('null checks carry a null value', () {
      final isNull = Avanda().service('User');
      isNull.where('deleted_at');
      isNull.isNull();
      expect(linkOf(isNull)['ft'], {
        'deleted_at': {'vl': null, 'op': 'NULL'}
      });

      final isNotNull = Avanda().service('User');
      isNotNull.where('deleted_at');
      isNotNull.isNotNull();
      expect(linkOf(isNotNull)['ft'], {
        'deleted_at': {'vl': null, 'op': 'NOTNULL'}
      });
    });

    test('throws when no column was selected first', () {
      expect(() => Avanda().service('User').equals(5),
          throwsA('Specify column to compare 5 with'));
    });

    test('throws when the column was selected but no service was', () {
      final query = Avanda();
      query.where('age');
      expect(() => query.equals(5),
          throwsA('Specify service to apply where clauses'));
    });

    test('the pending column is consumed, so two operators cannot chain', () {
      final query = Avanda().service('User');
      query.where('age');
      query.greaterThan(5);
      expect(() => query.lessThan(10),
          throwsA('Specify column to compare 10 with'));
    });

    test(
        'KNOWN BUG: a second operator filter discards the first because '
        '`accumulate` is never enabled', () {
      final query = Avanda().service('User');
      query.where('age');
      query.greaterThan(5);
      query.andWhere('name');
      query.equals('wale');

      // Intended behaviour is both filters; `addCustomFilter` only keeps the
      // last one. Update this test if `accumulate` is ever wired up.
      expect(linkOf(query)['ft'], {
        'name': {'vl': 'wale', 'op': '=='}
      });
    });
  });

  group('andWhere', () {
    test('with a string stages the column for the next operator', () {
      final query = Avanda().service('User');
      query.andWhere('age');
      query.greaterThan(18);
      expect(linkOf(query)['ft'], {
        'age': {'vl': 18, 'op': '>'}
      });
    });

    test(
        'KNOWN BUG: with a map it merges raw entries instead of wrapping them '
        'like `where` does', () {
      final query = Avanda().service('User');
      query.where({'id': 3});
      query.andWhere({'name': 'wale'});

      expect(linkOf(query)['ft'], {
        'id': {'vl': 3, 'op': '='},
        // Should be {'vl': 'wale', 'op': '='} to match `where`.
        'name': 'wale',
      });
    });
  });

  group('nested services', () {
    test('a nested Avanda query is inlined as a sub-service', () {
      final owner = Avanda().service('Owner').select(['id', 'name']);
      final link = linkOf(Avanda().service('Car').select(['id', owner]));

      expect(link['c'][0], 'id');
      expect(link['c'][1]['n'], 'Owner');
      expect(link['c'][1]['f'], 'get');
      expect(link['c'][1]['c'], ['id', 'name']);
    });

    test('as() returns the underlying Service carrying the alias', () {
      final owner = Avanda().service('Owner').select(['id']);
      final aliased = owner.as('primaryOwner');

      expect(aliased, same(owner.queryTree));
      expect(aliased.a, 'primaryOwner');
    });

    test('an aliased sub-service keeps its alias when nested', () {
      final owner = Avanda().service('Owner').select(['id']);
      final link =
          linkOf(Avanda().service('Car').select(['id', owner.as('theOwner')]));

      expect(link['c'][1]['a'], 'theOwner');
      expect(link['a'], isNull, reason: 'the parent has no alias');
    });

    test('nesting survives more than one level', () {
      final wheel = Avanda().service('Wheel').select(['id']);
      final car = Avanda().service('Car').select(['id', wheel]);
      final link = linkOf(Avanda().service('Owner').select(['id', car]));

      expect(link['c'][1]['n'], 'Car');
      expect(link['c'][1]['c'][1]['n'], 'Wheel');
    });

    test('each Avanda instance owns its own query tree', () {
      final a = Avanda().service('A').page(2);
      final b = Avanda().service('B');

      expect(a.queryTree.n, 'A');
      expect(b.queryTree.n, 'B');
      expect(b.queryTree.p, 1, reason: 'page(2) on `a` must not leak into `b`');
    });
  });

  group('autoLink', () {
    test('defaults to enabled', () {
      expect(Avanda().queryTree.al, isTrue);
    });

    test('disableAutoLink flips the flag on the query tree', () {
      expect(Avanda().service('User').disableAutoLink().queryTree.al, isFalse);
    });

    test('KNOWN BUG: toLink forces al back to true, so disableAutoLink is lost',
        () {
      final query = Avanda().service('User').disableAutoLink();
      expect(linkOf(query)['al'], isTrue);
    });
  });

  group('static configuration', () {
    test('setConfig replaces the config wholesale', () {
      Avanda.setConfig(AvandaConfig(
        rootUrl: 'http://api.test/',
        secureWebSocket: true,
        wsUrl: 'http://ws.test/',
      ));

      expect(Avanda.config.rootUrl, 'http://api.test/');
      expect(Avanda.config.secureWebSocket, isTrue);
      expect(Avanda.config.wsUrl, 'http://ws.test/');
    });

    test('AvandaConfig defaults to an insecure socket and no ws url', () {
      final config = AvandaConfig(rootUrl: 'http://api.test/');
      expect(config.secureWebSocket, isFalse);
      expect(config.wsUrl, isNull);
      expect(config.debugMode, isFalse);
    });

    test('setGraphRoot updates only the root url', () {
      Avanda.setConfig(
          AvandaConfig(rootUrl: 'http://old.test/', secureWebSocket: true));
      Avanda.setGraphRoot('http://new.test/');

      expect(Avanda.config.rootUrl, 'http://new.test/');
      expect(Avanda.config.secureWebSocket, isTrue);
    });

    test('setHeaders seeds the headers when empty', () {
      Avanda.setHeaders({'Authorization': 'Bearer a'});
      expect(Avanda.headers, {'Authorization': 'Bearer a'});
    });

    test('setHeaders merges into existing headers and overwrites collisions',
        () {
      Avanda.setHeaders({'Authorization': 'Bearer a', 'X-Trace': '1'});
      Avanda.setHeaders({'Authorization': 'Bearer b'});

      expect(Avanda.headers, {'Authorization': 'Bearer b', 'X-Trace': '1'});
    });

    test('headers are shared by every instance', () {
      Avanda.setHeaders({'X-Tenant': 'acme'});
      expect(Avanda.headers, containsPair('X-Tenant', 'acme'));
      // Documents the global coupling that `resetAvandaStatics` works around.
      expect(Avanda.headers, same(Avanda.headers));
    });
  });

  group('stringifyPayload', () {
    test('returns an empty map for a null payload', () {
      expect(Avanda().stringifyPayload(null), <dynamic, dynamic>{});
    });

    test('stringifies every value so it can be form-encoded', () {
      expect(
        Avanda().stringifyPayload({'age': 30, 'active': true, 'name': 'wale'}),
        {'age': '30', 'active': 'true', 'name': 'wale'},
      );
    });

    test('flattens nested structures with toString', () {
      expect(
        Avanda().stringifyPayload({'tags': ['a', 'b']}),
        {'tags': '[a, b]'},
      );
    });
  });
}
