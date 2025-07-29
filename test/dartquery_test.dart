import 'dart:async';
import 'package:test/test.dart';
import 'package:dartquery/src/dartquery_core.dart';
import 'package:dartquery/src/query_client.dart';
import 'package:dartquery/src/query.dart';

void main() {
  group('DartQuery', () {
    late DartQuery dartQuery;
    
    setUp(() {
      // Use the singleton instance for each test
      dartQuery = DartQuery.instance;
    });
    
    tearDown(() {
      dartQuery.clear();
    });
    
    group('singleton', () {
      test('should provide singleton instance', () {
        final instance1 = DartQuery.instance;
        final instance2 = DartQuery.instance;
        
        expect(instance1, same(instance2));
      });
      
      test('should provide access to underlying client', () {
        final client = dartQuery.client;
        expect(client, isA<QueryClient>());
      });
    });
    
    group('put', () {
      test('should store data with key', () {
        dartQuery.put('test-key', 'test value');
        
        final data = dartQuery.get<String>('test-key');
        expect(data, equals('test value'));
      });
      
      test('should store different data types', () {
        dartQuery.put('string-key', 'string value');
        dartQuery.put('int-key', 42);
        dartQuery.put('map-key', {'nested': 'value'});
        dartQuery.put('list-key', [1, 2, 3]);
        
        expect(dartQuery.get<String>('string-key'), equals('string value'));
        expect(dartQuery.get<int>('int-key'), equals(42));
        expect(dartQuery.get<Map<String, String>>('map-key'), equals({'nested': 'value'}));
        expect(dartQuery.get<List<int>>('list-key'), equals([1, 2, 3]));
      });
      
      test('should overwrite existing data', () {
        dartQuery.put('test-key', 'first value');
        expect(dartQuery.get<String>('test-key'), equals('first value'));
        
        dartQuery.put('test-key', 'second value');
        expect(dartQuery.get<String>('test-key'), equals('second value'));
      });
      
      test('should trigger reactive updates', () async {
        final events = <Query<String>>[];
        final subscription = dartQuery.watch<String>('test-key').listen(events.add);
        addTearDown(() => subscription.cancel());
        
        // Initial state
        await Future.delayed(Duration.zero);
        expect(events, hasLength(1));
        expect(events.first.data, isNull);
        
        dartQuery.put('test-key', 'test value');
        
        await Future.delayed(Duration.zero);
        expect(events, hasLength(2));
        expect(events.last.data, equals('test value'));
      });
    });
    
    group('get', () {
      test('should return null for non-existent key', () {
        final data = dartQuery.get<String>('non-existent');
        expect(data, isNull);
      });
      
      test('should return stored data', () {
        dartQuery.put('test-key', 'test value');
        
        final data = dartQuery.get<String>('test-key');
        expect(data, equals('test value'));
      });
      
      test('should return correct type', () {
        dartQuery.put('string-key', 'string');
        dartQuery.put('int-key', 123);
        
        expect(dartQuery.get<String>('string-key'), isA<String>());
        expect(dartQuery.get<int>('int-key'), isA<int>());
      });
    });
    
    group('fetch', () {
      test('should fetch and cache data', () async {
        var callCount = 0;
        
        final data = await dartQuery.fetch(
          'async-key',
          () async {
            callCount++;
            return 'fetched data';
          },
        );
        
        expect(data, equals('fetched data'));
        expect(callCount, equals(1));
        
        // Second call should return cached data
        final cachedData = await dartQuery.fetch(
          'async-key',
          () async {
            callCount++;
            return 'new data';
          },
        );
        
        expect(cachedData, equals('fetched data'));
        expect(callCount, equals(1)); // Not called again
      });
      
      test('should force refetch when requested', () async {
        var callCount = 0;
        
        await dartQuery.fetch(
          'async-key',
          () async {
            callCount++;
            return 'first data';
          },
        );
        
        final data = await dartQuery.fetch(
          'async-key',
          () async {
            callCount++;
            return 'second data';
          },
          forceRefetch: true,
        );
        
        expect(data, equals('second data'));
        expect(callCount, equals(2));
      });
      
      test('should handle fetch errors', () async {
        const testError = 'Fetch failed';
        
        expect(
          () => dartQuery.fetch(
            'error-key',
            () async => throw testError,
          ),
          throwsA(equals(testError)),
        );
        
        // Query should have error state
        final errorData = dartQuery.get<String>('error-key');
        expect(errorData, isNull);
      });
      
      test('should respect stale and cache times', () async {
        var callCount = 0;
        
        await dartQuery.fetch(
          'time-key',
          () async {
            callCount++;
            return 'data';
          },
          staleTime: const Duration(milliseconds: 50),
        );
        
        // Should be fresh initially
        await dartQuery.fetch(
          'time-key',
          () async {
            callCount++;
            return 'new data';
          },
        );
        
        expect(callCount, equals(1));
        
        // Wait for data to become stale
        await Future.delayed(const Duration(milliseconds: 100));
        
        await dartQuery.fetch(
          'time-key',
          () async {
            callCount++;
            return 'stale data';
          },
        );
        
        expect(callCount, equals(2));
      });
      
      test('should provide reactive updates during fetch', () async {
        final completer = Completer<String>();
        final events = <QueryStatus>[];
        
        final subscription = dartQuery.watch<String>('fetch-key').listen((query) {
          events.add(query.status);
        });
        addTearDown(() => subscription.cancel());
        
        // Start fetch
        final future = dartQuery.fetch(
          'fetch-key',
          () => completer.future,
        );
        
        // Should show loading state
        await Future.delayed(Duration.zero);
        expect(events, contains(QueryStatus.loading));
        
        // Complete fetch
        completer.complete('fetched data');
        await future;
        
        expect(events, contains(QueryStatus.success));
      });
    });
    
    group('invalidate', () {
      test('should invalidate cached data', () async {
        await dartQuery.fetch(
          'cache-key',
          () async => 'cached data',
        );
        
        expect(dartQuery.get<String>('cache-key'), equals('cached data'));
        
        dartQuery.invalidate('cache-key');
        
        // Data should still be there but query should be stale
        expect(dartQuery.get<String>('cache-key'), equals('cached data'));
        
        // Next fetch should call fetcher again
        var callCount = 0;
        await dartQuery.fetch(
          'cache-key',
          () async {
            callCount++;
            return 'new data';
          },
        );
        
        expect(callCount, equals(1));
        expect(dartQuery.get<String>('cache-key'), equals('new data'));
      });
      
      test('should handle non-existent keys gracefully', () {
        expect(() => dartQuery.invalidate('non-existent'), returnsNormally);
      });
      
      test('should trigger reactive updates', () async {
        await dartQuery.fetch('reactive-key', () async => 'data');
        
        final events = <QueryStatus>[];
        final subscription = dartQuery.watch<String>('reactive-key').listen((query) {
          events.add(query.status);
        });
        addTearDown(() => subscription.cancel());
        
        dartQuery.invalidate('reactive-key');
        
        await Future.delayed(Duration.zero);
        expect(events, contains(QueryStatus.idle));
      });
    });
    
    group('invalidateAll', () {
      test('should invalidate multiple queries', () async {
        await dartQuery.fetch('key1', () async => 'data1');
        await dartQuery.fetch('key2', () async => 'data2');
        await dartQuery.fetch('key3', () async => 'data3');
        
        dartQuery.invalidateAll(['key1', 'key2']);
        
        // key1 and key2 should be invalidated, key3 should not
        var callCount = 0;
        
        await dartQuery.fetch('key1', () async {
          callCount++;
          return 'new data1';
        });
        
        await dartQuery.fetch('key2', () async {
          callCount++;
          return 'new data2';
        });
        
        await dartQuery.fetch('key3', () async {
          callCount++;
          return 'new data3';
        });
        
        expect(callCount, equals(2)); // Only key1 and key2 should refetch
      });
      
      test('should handle empty list', () {
        expect(() => dartQuery.invalidateAll([]), returnsNormally);
      });
      
      test('should handle non-existent keys', () {
        expect(() => dartQuery.invalidateAll(['non-existent']), returnsNormally);
      });
    });
    
    group('remove', () {
      test('should remove cached data', () {
        dartQuery.put('remove-key', 'test data');
        expect(dartQuery.get<String>('remove-key'), equals('test data'));
        
        dartQuery.remove('remove-key');
        
        expect(dartQuery.get<String>('remove-key'), isNull);
      });
      
      test('should handle non-existent keys gracefully', () {
        expect(() => dartQuery.remove('non-existent'), returnsNormally);
      });
      
      test('should stop reactive streams', () async {
        dartQuery.put('stream-key', 'data');
        
        final events = <Query<String>>[];
        final subscription = dartQuery.watch<String>('stream-key').listen(events.add);
        
        dartQuery.remove('stream-key');
        
        // Stream should close or no longer emit
        await Future.delayed(const Duration(milliseconds: 10));
        
        subscription.cancel();
      });
    });
    
    group('clear', () {
      test('should clear all cached data', () {
        dartQuery.put('key1', 'data1');
        dartQuery.put('key2', 'data2');
        dartQuery.put('key3', 'data3');
        
        expect(dartQuery.get<String>('key1'), equals('data1'));
        expect(dartQuery.get<String>('key2'), equals('data2'));
        expect(dartQuery.get<String>('key3'), equals('data3'));
        
        dartQuery.clear();
        
        expect(dartQuery.get<String>('key1'), isNull);
        expect(dartQuery.get<String>('key2'), isNull);
        expect(dartQuery.get<String>('key3'), isNull);
      });
      
      test('should handle empty state gracefully', () {
        expect(() => dartQuery.clear(), returnsNormally);
      });
    });
    
    group('watch', () {
      test('should return broadcast stream', () {
        final stream = dartQuery.watch<String>('watch-key');
        
        expect(stream, isNotNull);
        expect(stream.isBroadcast, isTrue);
      });
      
      test('should emit current state immediately', () async {
        dartQuery.put('immediate-key', 'immediate data');
        
        final events = <Query<String>>[];
        final subscription = dartQuery.watch<String>('immediate-key').listen(events.add);
        addTearDown(() => subscription.cancel());
        
        await Future.delayed(Duration.zero);
        
        expect(events, hasLength(1));
        expect(events.first.data, equals('immediate data'));
      });
      
      test('should emit updates when data changes', () async {
        final events = <String?>[];
        final subscription = dartQuery.watch<String>('reactive-key').listen((query) {
          events.add(query.data);
        });
        addTearDown(() => subscription.cancel());
        
        await Future.delayed(Duration.zero);
        expect(events, hasLength(1));
        expect(events.first, isNull);
        
        dartQuery.put('reactive-key', 'first value');
        await Future.delayed(Duration.zero);
        expect(events, hasLength(2));
        expect(events.last, equals('first value'));
        
        dartQuery.put('reactive-key', 'second value');
        await Future.delayed(Duration.zero);
        expect(events, hasLength(3));
        expect(events.last, equals('second value'));
      });
      
      test('should support multiple listeners', () async {
        final events1 = <String?>[];
        final events2 = <String?>[];
        
        final sub1 = dartQuery.watch<String>('multi-key').listen((query) {
          events1.add(query.data);
        });
        
        final sub2 = dartQuery.watch<String>('multi-key').listen((query) {
          events2.add(query.data);
        });
        
        addTearDown(() => sub1.cancel());
        addTearDown(() => sub2.cancel());
        
        dartQuery.put('multi-key', 'shared data');
        
        await Future.delayed(Duration.zero);
        
        expect(events1.last, equals('shared data'));
        expect(events2.last, equals('shared data'));
      });
      
      test('should emit loading, success, and error states', () async {
        final completer = Completer<String>();
        final events = <QueryStatus>[];
        
        final subscription = dartQuery.watch<String>('state-key').listen((query) {
          events.add(query.status);
        });
        addTearDown(() => subscription.cancel());
        
        // Start with idle
        await Future.delayed(Duration.zero);
        expect(events, contains(QueryStatus.idle));
        
        // Start fetch (should show loading)
        final future = dartQuery.fetch('state-key', () => completer.future);
        await Future.delayed(Duration.zero);
        expect(events, contains(QueryStatus.loading));
        
        // Complete successfully
        completer.complete('success data');
        await future;
        await Future.delayed(Duration.zero);
        expect(events, contains(QueryStatus.success));
      });
    });
    
    group('integration', () {
      test('should work with complex workflow', () async {
        // Initial data
        dartQuery.put('user-id', '123');
        expect(dartQuery.get<String>('user-id'), equals('123'));
        
        // Fetch user profile
        final profile = await dartQuery.fetch(
          'user-profile',
          () async => {'id': '123', 'name': 'John Doe'},
        );
        
        expect(profile['name'], equals('John Doe'));
        
        // Watch for changes
        final profileUpdates = <Map<String, String>>[];
        final subscription = dartQuery.watch<Map<String, String>>('user-profile').listen((query) {
          if (query.data != null) profileUpdates.add(query.data!);
        });
        addTearDown(() => subscription.cancel());
        
        // Update profile data
        dartQuery.put('user-profile', {'id': '123', 'name': 'Jane Doe'});
        
        await Future.delayed(Duration.zero);
        
        expect(profileUpdates.last['name'], equals('Jane Doe'));
        
        // Invalidate and refetch
        dartQuery.invalidate('user-profile');
        
        final updatedProfile = await dartQuery.fetch(
          'user-profile',
          () async => {'id': '123', 'name': 'Updated Name'},
        );
        
        expect(updatedProfile['name'], equals('Updated Name'));
        
        // Clean up
        dartQuery.remove('user-id');
        dartQuery.remove('user-profile');
        
        expect(dartQuery.get<String>('user-id'), isNull);
        expect(dartQuery.get<Map<String, String>>('user-profile'), isNull);
      });
    });
  });
}