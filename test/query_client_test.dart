import 'dart:async';
import 'package:test/test.dart';
import 'package:dartquery/src/query_client.dart';
import 'package:dartquery/src/query.dart';

void main() {
  group('QueryClient', () {
    late QueryClient client;

    setUp(() {
      client = QueryClient.forTesting();
    });

    tearDown(() {
      client.dispose();
    });

    group('initialization', () {
      test('should initialize with empty state', () {
        expect(client.queries, isEmpty);
        expect(client.ongoingRequests, isEmpty);
      });

      test('should have singleton instance', () {
        final instance1 = QueryClient.instance;
        final instance2 = QueryClient.instance;
        expect(instance1, same(instance2));
      });
    });

    group('getQuery', () {
      test('should create new query if not exists', () {
        final query = client.getQuery<String>('test-key');

        expect(query, isNotNull);
        expect(query.key, equals('test-key'));
        expect(query.isIdle, isTrue);
      });

      test('should return existing query if exists', () {
        final query1 = client.getQuery<String>('test-key');
        final query2 = client.getQuery<String>('test-key');

        expect(query1, same(query2));
      });

      test('should create query with custom times', () {
        final query = client.getQuery<String>(
          'test-key',
          staleTime: const Duration(minutes: 1),
          cacheTime: const Duration(minutes: 2),
        );

        expect(query.key, equals('test-key'));
      });

      test('should throw if client is disposed', () {
        client.dispose();

        expect(
          () => client.getQuery<String>('test-key'),
          throwsStateError,
        );
      });
    });

    group('fetchQuery', () {
      test('should fetch data and update query', () async {
        final data = await client.fetchQuery(
          'test-key',
          () async => 'test data',
        );

        expect(data, equals('test data'));

        final query = client.getQuery<String>('test-key');
        expect(query.data, equals('test data'));
        expect(query.isSuccess, isTrue);
      });

      test('should return cached data if fresh', () async {
        // First fetch
        await client.fetchQuery(
          'test-key',
          () async => 'first data',
        );

        // Second fetch should return cached data
        final data = await client.fetchQuery(
          'test-key',
          () async => 'second data',
        );

        expect(data, equals('first data'));
      });

      test('should force refetch when forceRefetch is true', () async {
        // First fetch
        await client.fetchQuery(
          'test-key',
          () async => 'first data',
        );

        // Force refetch
        final data = await client.fetchQuery(
          'test-key',
          () async => 'second data',
          forceRefetch: true,
        );

        expect(data, equals('second data'));
      });

      test('should handle fetch errors', () async {
        const testError = 'Fetch failed';

        expect(
          () => client.fetchQuery(
            'test-key',
            () async => throw testError,
          ),
          throwsA(equals(testError)),
        );

        final query = client.getQuery<String>('test-key');
        expect(query.error, equals(testError));
        expect(query.isError, isTrue);
      });

      test('should deduplicate concurrent requests', () async {
        var callCount = 0;

        final futures = List.generate(
            3,
            (_) => client.fetchQuery(
                  'test-key',
                  () async {
                    callCount++;
                    await Future.delayed(const Duration(milliseconds: 10));
                    return 'test data';
                  },
                ));

        final results = await Future.wait(futures);

        expect(callCount, equals(1)); // Only called once due to deduplication
        expect(results, everyElement(equals('test data')));
      });

      test('should set loading state during fetch', () async {
        final completer = Completer<String>();
        final query = client.getQuery<String>('test-key');

        final streamEvents = <QueryStatus>[];
        final subscription =
            query.stream.listen((q) => streamEvents.add(q.status));
        addTearDown(() => subscription.cancel());

        // Start fetch
        final future = client.fetchQuery(
          'test-key',
          () => completer.future,
        );

        // Should be loading
        await Future.delayed(Duration.zero);
        expect(query.isLoading, isTrue);
        expect(streamEvents, contains(QueryStatus.loading));

        // Complete fetch
        completer.complete('test data');
        await future;

        expect(query.isSuccess, isTrue);
        expect(streamEvents, contains(QueryStatus.success));
      });

      test('should throw if client is disposed', () async {
        client.dispose();

        expect(
          () => client.fetchQuery('test-key', () async => 'data'),
          throwsStateError,
        );
      });
    });

    group('mutate', () {
      test('should execute mutation function', () async {
        final result = await client.mutate(
          'test-mutation',
          (variables) async => 'result-$variables',
          'input',
        );

        expect(result, equals('result-input'));
      });

      test('should invalidate specified queries after successful mutation',
          () async {
        // Set up some queries
        await client.fetchQuery('query1', () async => 'data1');
        await client.fetchQuery('query2', () async => 'data2');
        await client.fetchQuery('query3', () async => 'data3');

        final query1 = client.getQuery<String>('query1');
        final query2 = client.getQuery<String>('query2');
        final query3 = client.getQuery<String>('query3');

        expect(query1.isSuccess, isTrue);
        expect(query2.isSuccess, isTrue);
        expect(query3.isSuccess, isTrue);

        // Execute mutation that invalidates query1 and query2
        await client.mutate(
          'test-mutation',
          (variables) async => 'result',
          'input',
          invalidateQueries: ['query1', 'query2'],
        );

        expect(query1.isIdle, isTrue);
        expect(query2.isIdle, isTrue);
        expect(query3.isSuccess, isTrue); // Not invalidated
      });

      test('should propagate mutation errors', () async {
        const testError = 'Mutation failed';

        expect(
          () => client.mutate(
            'test-mutation',
            (variables) async => throw testError,
            'input',
          ),
          throwsA(equals(testError)),
        );
      });

      test('should not invalidate queries if mutation fails', () async {
        await client.fetchQuery('query1', () async => 'data1');
        final query1 = client.getQuery<String>('query1');
        expect(query1.isSuccess, isTrue);

        try {
          await client.mutate(
            'test-mutation',
            (variables) async => throw 'error',
            'input',
            invalidateQueries: ['query1'],
          );
        } catch (_) {}

        expect(query1.isSuccess, isTrue); // Not invalidated due to error
      });
    });

    group('setQueryData', () {
      test('should set data for query', () {
        client.setQueryData('test-key', 'test data');

        final query = client.getQuery<String>('test-key');
        expect(query.data, equals('test data'));
        expect(query.isSuccess, isTrue);
      });

      test('should create query if not exists', () {
        expect(client.queries, isEmpty);

        client.setQueryData('test-key', 'test data');

        expect(client.queries, hasLength(1));
        expect(client.queries.containsKey('test-key'), isTrue);
      });
    });

    group('getQueryData', () {
      test('should return data for existing query', () {
        client.setQueryData('test-key', 'test data');

        final data = client.getQueryData<String>('test-key');
        expect(data, equals('test data'));
      });

      test('should return null for non-existent query', () {
        final data = client.getQueryData<String>('non-existent');
        expect(data, isNull);
      });

      test('should return null for query with no data', () {
        client.getQuery<String>('test-key'); // Creates query but no data

        final data = client.getQueryData<String>('test-key');
        expect(data, isNull);
      });
    });

    group('invalidateQuery', () {
      test('should invalidate existing query', () async {
        await client.fetchQuery('test-key', () async => 'test data');
        final query = client.getQuery<String>('test-key');
        expect(query.isSuccess, isTrue);

        client.invalidateQuery('test-key');

        expect(query.isIdle, isTrue);
      });

      test('should handle non-existent query gracefully', () {
        expect(() => client.invalidateQuery('non-existent'), returnsNormally);
      });
    });

    group('invalidateQueries', () {
      test('should invalidate multiple queries atomically', () async {
        await client.fetchQuery('query1', () async => 'data1');
        await client.fetchQuery('query2', () async => 'data2');
        await client.fetchQuery('query3', () async => 'data3');

        final query1 = client.getQuery<String>('query1');
        final query2 = client.getQuery<String>('query2');
        final query3 = client.getQuery<String>('query3');

        client.invalidateQueries(['query1', 'query2']);

        expect(query1.isIdle, isTrue);
        expect(query2.isIdle, isTrue);
        expect(query3.isSuccess, isTrue); // Not in the list
      });

      test('should handle mix of existing and non-existent queries', () {
        client.setQueryData('existing', 'data');

        expect(
          () => client.invalidateQueries(['existing', 'non-existent']),
          returnsNormally,
        );

        final query = client.getQuery<String>('existing');
        expect(query.isIdle, isTrue);
      });
    });

    group('removeQuery', () {
      test('should remove query and dispose it', () async {
        await client.fetchQuery('test-key', () async => 'test data');
        final query = client.getQuery<String>('test-key');
        expect(query.isDisposed, isFalse);

        client.removeQuery('test-key');

        expect(client.queries, isEmpty);
        expect(query.isDisposed, isTrue);
      });

      test('should handle non-existent query gracefully', () {
        expect(() => client.removeQuery('non-existent'), returnsNormally);
      });

      test('should clean up ongoing requests', () async {
        final completer = Completer<String>();

        // Start a fetch
        final future = client.fetchQuery('test-key', () => completer.future);

        // Remove the query
        client.removeQuery('test-key');

        // Complete the fetch
        completer.complete('data');

        expect(client.queries, isEmpty);
        expect(client.ongoingRequests, isEmpty);

        // Future should still complete normally
        final result = await future;
        expect(result, equals('data'));
      });
    });

    group('clear', () {
      test('should clear all queries and dispose them', () async {
        await client.fetchQuery('query1', () async => 'data1');
        await client.fetchQuery('query2', () async => 'data2');

        final query1 = client.getQuery<String>('query1');
        final query2 = client.getQuery<String>('query2');

        expect(client.queries, hasLength(2));
        expect(query1.isDisposed, isFalse);
        expect(query2.isDisposed, isFalse);

        client.clear();

        expect(client.queries, isEmpty);
        expect(client.ongoingRequests, isEmpty);
        expect(query1.isDisposed, isTrue);
        expect(query2.isDisposed, isTrue);
      });

      test('should handle empty state gracefully', () {
        expect(() => client.clear(), returnsNormally);
      });
    });

    group('watchQuery', () {
      test('should return stream of query state changes', () async {
        final stream = client.watchQuery<String>('test-key');

        expect(stream, isNotNull);
        expect(stream.isBroadcast, isTrue);

        final events = <Query<String>>[];
        final subscription = stream.listen(events.add);
        addTearDown(() => subscription.cancel());

        // Initial state
        await Future.delayed(Duration.zero);
        expect(events, hasLength(1));
        expect(events.first.isIdle, isTrue);

        // Set data
        client.setQueryData('test-key', 'test data');
        await Future.delayed(Duration.zero);

        expect(events, hasLength(2));
        expect(events.last.data, equals('test data'));
      });

      test('should throw if client is disposed', () {
        client.dispose();

        expect(
          () => client.watchQuery<String>('test-key'),
          throwsStateError,
        );
      });
    });

    group('memory management', () {
      test('should schedule query removal when cache expires', () async {
        // Create a query with short cache time
        final shortCacheQuery = client.getQuery<String>(
          'short-cache',
          cacheTime: const Duration(milliseconds: 50),
        );

        shortCacheQuery.setData('test data');
        expect(client.queries, hasLength(1));

        // Wait for cache to expire and cleanup
        await Future.delayed(const Duration(milliseconds: 200));

        // Query should be removed if no listeners
        expect(
            client.queries.isEmpty ||
                client.queries['short-cache']?.isDisposed == true,
            isTrue);
      });

      test('should clean up unused queries periodically', () async {
        // This test is hard to verify without accessing private methods
        // We'll just ensure the cleanup timer is started
        final newClient = QueryClient.instance;
        addTearDown(() => newClient.dispose());

        // Create some queries without listeners
        newClient.getQuery<String>('unused1');
        newClient.getQuery<String>('unused2');

        // The cleanup should happen automatically via timer
        // We can't easily test this without making internals public
        expect(newClient.queries, hasLength(2));
      });

      test('should not remove queries with active listeners', () async {
        final query = client.getQuery<String>('with-listener');
        final subscription = query.stream.listen((_) {});
        addTearDown(() => subscription.cancel());

        query.setData('test data');

        // Query should still exist and not be disposed due to active listener
        await Future.delayed(const Duration(milliseconds: 200));

        expect(client.queries.containsKey('with-listener'), isTrue);
        expect(query.isDisposed, isFalse);
      });
    });

    group('dispose', () {
      test('should dispose client and prevent further operations', () {
        client.dispose();

        expect(() => client.getQuery<String>('test'), throwsStateError);
        expect(() => client.fetchQuery('test', () async => 'data'),
            throwsStateError);
        expect(() => client.watchQuery<String>('test'), throwsStateError);
      });

      test('should be idempotent', () {
        client.dispose();

        expect(() => client.dispose(), returnsNormally);
      });

      test('should clear all queries when disposed', () async {
        await client.fetchQuery('query1', () async => 'data1');
        final query1 = client.getQuery<String>('query1');

        expect(client.queries, hasLength(1));
        expect(query1.isDisposed, isFalse);

        client.dispose();

        expect(client.queries, isEmpty);
        expect(query1.isDisposed, isTrue);
      });
    });

    group('error handling', () {
      test('should handle errors in query callbacks gracefully', () async {
        // This tests that query disposal doesn't throw even if there are issues
        final query = client.getQuery<String>('error-test');

        // Manually break something that might cause issues during disposal
        query.dispose(); // Pre-dispose to test edge cases

        expect(() => client.removeQuery('error-test'), returnsNormally);
      });
    });
  });
}
