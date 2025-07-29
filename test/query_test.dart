import 'dart:async';
import 'package:test/test.dart';
import 'package:dartquery/src/query.dart';

void main() {
  group('Query', () {
    late Query<String> query;
    
    setUp(() {
      query = Query<String>(
        key: 'test-key',
        staleTime: const Duration(minutes: 5),
        cacheTime: const Duration(minutes: 10),
      );
    });
    
    tearDown(() {
      query.dispose();
    });
    
    group('initialization', () {
      test('should initialize with correct key and default values', () {
        expect(query.key, equals('test-key'));
        expect(query.data, isNull);
        expect(query.error, isNull);
        expect(query.status, equals(QueryStatus.idle));
        expect(query.lastUpdated, isNull);
        expect(query.isIdle, isTrue);
        expect(query.isLoading, isFalse);
        expect(query.isSuccess, isFalse);
        expect(query.isError, isFalse);
        expect(query.isStale, isTrue); // No data = stale
        expect(query.isDisposed, isFalse);
      });
      
      test('should initialize with custom stale and cache times', () {
        final customQuery = Query<int>(
          key: 'custom',
          staleTime: const Duration(minutes: 1),
          cacheTime: const Duration(minutes: 2),
        );
        
        expect(customQuery.key, equals('custom'));
        addTearDown(() => customQuery.dispose());
      });
    });
    
    group('setData', () {
      test('should set data and update state atomically', () async {
        final streamEvents = <Query<String>>[];
        final subscription = query.stream.listen(streamEvents.add);
        addTearDown(() => subscription.cancel());
        
        query.setData('test data');
        
        expect(query.data, equals('test data'));
        expect(query.error, isNull);
        expect(query.status, equals(QueryStatus.success));
        expect(query.lastUpdated, isNotNull);
        expect(query.isSuccess, isTrue);
        expect(query.isStale, isFalse);
        
        // Should emit stream event
        await Future.delayed(Duration.zero);
        expect(streamEvents, hasLength(1));
        expect(streamEvents.first.data, equals('test data'));
      });
      
      test('should clear previous error when setting data', () {
        query.setError('previous error');
        query.setData('new data');
        
        expect(query.data, equals('new data'));
        expect(query.error, isNull);
        expect(query.status, equals(QueryStatus.success));
      });
      
      test('should not update if disposed', () {
        query.dispose();
        query.setData('test data');
        
        expect(query.data, isNull);
        expect(query.status, equals(QueryStatus.idle));
      });
    });
    
    group('setError', () {
      test('should set error and update state atomically', () async {
        final streamEvents = <Query<String>>[];
        final subscription = query.stream.listen(streamEvents.add);
        addTearDown(() => subscription.cancel());
        
        const testError = 'test error';
        query.setError(testError);
        
        expect(query.data, isNull);
        expect(query.error, equals(testError));
        expect(query.status, equals(QueryStatus.error));
        expect(query.lastUpdated, isNotNull);
        expect(query.isError, isTrue);
        
        // Should emit stream event
        await Future.delayed(Duration.zero);
        expect(streamEvents, hasLength(1));
        expect(streamEvents.first.error, equals(testError));
      });
      
      test('should clear previous data when setting error', () {
        query.setData('previous data');
        query.setError('new error');
        
        expect(query.data, isNull);
        expect(query.error, equals('new error'));
        expect(query.status, equals(QueryStatus.error));
      });
      
      test('should not update if disposed', () {
        query.dispose();
        query.setError('test error');
        
        expect(query.error, isNull);
        expect(query.status, equals(QueryStatus.idle));
      });
    });
    
    group('setLoading', () {
      test('should set loading state', () async {
        final streamEvents = <Query<String>>[];
        final subscription = query.stream.listen(streamEvents.add);
        addTearDown(() => subscription.cancel());
        
        query.setLoading();
        
        expect(query.status, equals(QueryStatus.loading));
        expect(query.isLoading, isTrue);
        
        // Should emit stream event
        await Future.delayed(Duration.zero);
        expect(streamEvents, hasLength(1));
        expect(streamEvents.first.isLoading, isTrue);
      });
      
      test('should not update if disposed', () {
        query.dispose();
        query.setLoading();
        
        expect(query.status, equals(QueryStatus.idle));
      });
    });
    
    group('invalidate', () {
      test('should reset query to idle state', () async {
        final streamEvents = <Query<String>>[];
        final subscription = query.stream.listen(streamEvents.add);
        addTearDown(() => subscription.cancel());
        
        // Set some data first
        query.setData('test data');
        expect(query.isSuccess, isTrue);
        
        // Clear events
        streamEvents.clear();
        
        query.invalidate();
        
        expect(query.status, equals(QueryStatus.idle));
        expect(query.lastUpdated, isNull);
        expect(query.isIdle, isTrue);
        expect(query.isStale, isTrue);
        
        // Should emit stream event
        await Future.delayed(Duration.zero);
        expect(streamEvents, hasLength(1));
        expect(streamEvents.first.isIdle, isTrue);
      });
      
      test('should not update if disposed', () {
        query.setData('test data');
        query.dispose();
        query.invalidate();
        
        expect(query.status, equals(QueryStatus.success));
        expect(query.lastUpdated, isNotNull);
      });
    });
    
    group('staleness', () {
      test('should be stale initially', () {
        expect(query.isStale, isTrue);
      });
      
      test('should not be stale immediately after setting data', () {
        query.setData('test data');
        expect(query.isStale, isFalse);
      });
      
      test('should become stale after stale time', () async {
        final shortStaleQuery = Query<String>(
          key: 'short-stale',
          staleTime: const Duration(milliseconds: 50),
        );
        addTearDown(() => shortStaleQuery.dispose());
        
        shortStaleQuery.setData('test data');
        expect(shortStaleQuery.isStale, isFalse);
        
        await Future.delayed(const Duration(milliseconds: 100));
        expect(shortStaleQuery.isStale, isTrue);
      });
      
      test('should emit stream event when becoming stale', () async {
        final shortStaleQuery = Query<String>(
          key: 'short-stale',
          staleTime: const Duration(milliseconds: 50),
        );
        addTearDown(() => shortStaleQuery.dispose());
        
        final streamEvents = <Query<String>>[];
        final subscription = shortStaleQuery.stream.listen(streamEvents.add);
        addTearDown(() => subscription.cancel());
        
        shortStaleQuery.setData('test data');
        streamEvents.clear();
        
        await Future.delayed(const Duration(milliseconds: 100));
        
        expect(streamEvents, hasLength(1));
        expect(streamEvents.first.isStale, isTrue);
      });
    });
    
    group('cache expiration', () {
      test('should call onCacheExpire callback when cache expires', () async {
        String? expiredKey;
        
        final shortCacheQuery = Query<String>(
          key: 'short-cache',
          cacheTime: const Duration(milliseconds: 50),
          onCacheExpire: (key) => expiredKey = key,
        );
        addTearDown(() => shortCacheQuery.dispose());
        
        shortCacheQuery.setData('test data');
        
        await Future.delayed(const Duration(milliseconds: 100));
        
        expect(expiredKey, equals('short-cache'));
      });
      
      test('should not call onCacheExpire if has listeners', () async {
        String? expiredKey;
        
        final shortCacheQuery = Query<String>(
          key: 'short-cache',
          cacheTime: const Duration(milliseconds: 50),
          onCacheExpire: (key) => expiredKey = key,
        );
        addTearDown(() => shortCacheQuery.dispose());
        
        // Add a listener
        final subscription = shortCacheQuery.stream.listen((_) {});
        addTearDown(() => subscription.cancel());
        
        shortCacheQuery.setData('test data');
        
        await Future.delayed(const Duration(milliseconds: 100));
        
        expect(expiredKey, isNull);
      });
    });
    
    group('stream', () {
      test('should be a broadcast stream', () {
        expect(query.stream.isBroadcast, isTrue);
      });
      
      test('should support multiple listeners', () async {
        final events1 = <Query<String>>[];
        final events2 = <Query<String>>[];
        
        final sub1 = query.stream.listen(events1.add);
        final sub2 = query.stream.listen(events2.add);
        
        addTearDown(() => sub1.cancel());
        addTearDown(() => sub2.cancel());
        
        query.setData('test data');
        
        await Future.delayed(Duration.zero);
        
        expect(events1, hasLength(1));
        expect(events2, hasLength(1));
        expect(events1.first.data, equals('test data'));
        expect(events2.first.data, equals('test data'));
      });
    });
    
    group('hasListeners', () {
      test('should return false initially', () {
        expect(query.hasListeners, isFalse);
      });
      
      test('should return true when has listeners', () {
        final subscription = query.stream.listen((_) {});
        addTearDown(() => subscription.cancel());
        
        expect(query.hasListeners, isTrue);
      });
      
      test('should return false after listeners are cancelled', () {
        final subscription = query.stream.listen((_) {});
        expect(query.hasListeners, isTrue);
        
        subscription.cancel();
        expect(query.hasListeners, isFalse);
      });
    });
    
    group('dispose', () {
      test('should cancel timers and close stream', () {
        final subscription = query.stream.listen((_) {});
        
        query.setData('test data'); // This starts timers
        expect(query.isDisposed, isFalse);
        
        query.dispose();
        
        expect(query.isDisposed, isTrue);
        expect(() => subscription.cancel(), returnsNormally);
      });
      
      test('should be idempotent', () {
        query.dispose();
        expect(query.isDisposed, isTrue);
        
        // Should not throw
        expect(() => query.dispose(), returnsNormally);
        expect(query.isDisposed, isTrue);
      });
      
      test('should prevent further updates after disposal', () {
        query.dispose();
        
        query.setData('test data');
        query.setError('test error');
        query.setLoading();
        query.invalidate();
        
        expect(query.data, isNull);
        expect(query.error, isNull);
        expect(query.status, equals(QueryStatus.idle));
      });
    });
    
    group('memory leaks', () {
      test('should not leak when stream is not listened to', () {
        // Create query and set data to start timers
        final testQuery = Query<String>(key: 'leak-test');
        testQuery.setData('test data');
        
        // Query should be eligible for GC when no references exist
        expect(testQuery.hasListeners, isFalse);
        
        testQuery.dispose();
      });
      
      test('should not leak when listeners are cancelled', () {
        final testQuery = Query<String>(key: 'leak-test');
        final subscription = testQuery.stream.listen((_) {});
        
        testQuery.setData('test data');
        expect(testQuery.hasListeners, isTrue);
        
        subscription.cancel();
        expect(testQuery.hasListeners, isFalse);
        
        testQuery.dispose();
      });
    });
  });
}