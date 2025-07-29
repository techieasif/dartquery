import 'dart:async';
import 'package:test/test.dart';
import 'package:dartquery/src/cache_config.dart';
import 'package:dartquery/src/cache_manager.dart';
import 'package:dartquery/src/query_client.dart';
import 'package:dartquery/src/query.dart';
import 'package:dartquery/src/memory_pressure_handler.dart';

void main() {
  group('CacheConfig', () {
    test('should have sensible defaults', () {
      const config = CacheConfig();
      
      expect(config.maxQueries, equals(100));
      expect(config.maxMemoryBytes, equals(50 * 1024 * 1024));
      expect(config.evictionPolicy, equals(EvictionPolicy.lru));
      expect(config.enableMemoryPressureHandling, isTrue);
      expect(config.hasLimits, isTrue);
    });
    
    test('should support large application configuration', () {
      const config = CacheConfig.large();
      
      expect(config.maxQueries, equals(500));
      expect(config.maxMemoryBytes, equals(200 * 1024 * 1024));
      expect(config.hasLimits, isTrue);
    });
    
    test('should support compact configuration', () {
      const config = CacheConfig.compact();
      
      expect(config.maxQueries, equals(50));
      expect(config.maxMemoryBytes, equals(10 * 1024 * 1024));
      expect(config.hasLimits, isTrue);
    });
    
    test('should support unlimited configuration', () {
      const config = CacheConfig.unlimited();
      
      expect(config.maxQueries, equals(-1));
      expect(config.maxMemoryBytes, equals(-1));
      expect(config.hasLimits, isFalse);
    });
  });
  
  group('CacheStats', () {
    test('should calculate hit ratio correctly', () {
      const stats = CacheStats(
        queryCount: 10,
        memoryBytes: 1024,
        hits: 75,
        misses: 25,
        evictions: 5,
        expirations: 2,
      );
      
      expect(stats.hitRatio, equals(0.75));
      expect(stats.totalOperations, equals(100));
    });
    
    test('should handle zero operations gracefully', () {
      const stats = CacheStats(
        queryCount: 0,
        memoryBytes: 0,
        hits: 0,
        misses: 0,
        evictions: 0,
        expirations: 0,
      );
      
      expect(stats.hitRatio, equals(0.0));
      expect(stats.totalOperations, equals(0));
    });
    
    test('should calculate usage ratios correctly', () {
      const stats = CacheStats(
        queryCount: 80,
        memoryBytes: 40 * 1024 * 1024,
        hits: 100,
        misses: 20,
        evictions: 5,
        expirations: 2,
      );
      
      expect(stats.queryCountRatio(100), equals(0.8));
      expect(stats.memoryUsageRatio(50 * 1024 * 1024), equals(0.8));
    });
  });
  
  group('CacheManager', () {
    late CacheManager cacheManager;
    
    setUp(() {
      cacheManager = CacheManager(const CacheConfig.compact());
    });
    
    tearDown(() {
      cacheManager.dispose();
    });
    
    test('should track queries and statistics', () {
      final query1 = Query<String>(key: 'test1');
      final query2 = Query<String>(key: 'test2');
      
      cacheManager.addQuery('test1', query1);
      cacheManager.addQuery('test2', query2);
      
      final stats = cacheManager.getStats();
      expect(stats.queryCount, equals(2));
      expect(stats.memoryBytes, greaterThan(0));
      
      // Test cache hit
      final retrieved = cacheManager.getQuery('test1');
      expect(retrieved, same(query1));
      
      // Test cache miss
      final missing = cacheManager.getQuery('nonexistent');
      expect(missing, isNull);
      
      final updatedStats = cacheManager.getStats();
      expect(updatedStats.hits, equals(1));
      expect(updatedStats.misses, equals(1));
      
      query1.dispose();
      query2.dispose();
    });
    
    test('should enforce query count limits with LRU eviction', () async {
      final config = CacheConfig(
        maxQueries: 3,
        maxMemoryBytes: -1, // No memory limit
        evictionPolicy: EvictionPolicy.lru,
        cleanupInterval: Duration(milliseconds: 100),
      );
      
      final manager = CacheManager(config);
      addTearDown(() => manager.dispose());
      
      // Add queries up to limit
      for (int i = 1; i <= 5; i++) {
        final query = Query<String>(key: 'test$i');
        query.setData('data$i');
        manager.addQuery('test$i', query);
        
        // Access queries to establish LRU order
        if (i <= 3) {
          await Future.delayed(Duration(milliseconds: 10));
          manager.getQuery('test$i');
        }
      }
      
      // Should have evicted to stay within limit
      final stats = manager.getStats();
      expect(stats.queryCount, lessThanOrEqualTo(3));
      expect(stats.evictions, greaterThan(0));
    });
    
    test('should handle memory-based eviction', () {
      final config = CacheConfig(
        maxQueries: -1, // No query limit
        maxMemoryBytes: 1024, // Very small memory limit
        evictionPolicy: EvictionPolicy.lru,
      );
      
      final manager = CacheManager(config);
      addTearDown(() => manager.dispose());
      
      // Add queries with data that will exceed memory limit
      for (int i = 1; i <= 10; i++) {
        final query = Query<String>(key: 'large$i');
        query.setData('x' * 200); // Large string data
        manager.addQuery('large$i', query);
      }
      
      final stats = manager.getStats();
      expect(stats.memoryBytes, lessThanOrEqualTo(config.maxMemoryBytes * 2)); // Allow some overhead
      expect(stats.evictions, greaterThan(0));
    });
    
    test('should respect different eviction policies', () {
      // Test LRU vs LRC eviction
      final lruConfig = CacheConfig(
        maxQueries: 2,
        evictionPolicy: EvictionPolicy.lru,
      );
      
      final lruManager = CacheManager(lruConfig);
      addTearDown(() => lruManager.dispose());
      
      // Add queries and access them in specific order
      final query1 = Query<String>(key: 'lru1');
      final query2 = Query<String>(key: 'lru2');
      final query3 = Query<String>(key: 'lru3');
      
      lruManager.addQuery('lru1', query1);
      lruManager.addQuery('lru2', query2);
      
      // Access query1 to make it more recently used
      lruManager.getQuery('lru1');
      
      // Add query3, should evict query2 (least recently used)
      lruManager.addQuery('lru3', query3);
      
      expect(lruManager.getQuery('lru1'), isNotNull); // Should still exist
      expect(lruManager.getQuery('lru2'), isNull);    // Should be evicted
      expect(lruManager.getQuery('lru3'), isNotNull); // Should exist
    });
    
    test('should handle cleanup of expired queries', () async {
      final query1 = Query<String>(key: 'expired1');
      final query2 = Query<String>(key: 'active2');
      
      cacheManager.addQuery('expired1', query1);
      cacheManager.addQuery('active2', query2);
      
      // Dispose one query to simulate expiration
      query1.dispose();
      
      // Keep a listener on the other
      final subscription = query2.stream.listen((_) {});
      addTearDown(() => subscription.cancel());
      
      cacheManager.cleanup();
      
      final stats = cacheManager.getStats();
      expect(cacheManager.getQuery('expired1'), isNull);
      expect(cacheManager.getQuery('active2'), isNotNull);
      expect(stats.expirations, greaterThan(0));
      
      query2.dispose();
    });
    
    test('should detect when near limits', () {
      final config = CacheConfig(
        maxQueries: 10,
        warnThreshold: 0.8, // 80%
      );
      
      final manager = CacheManager(config);
      addTearDown(() => manager.dispose());
      
      expect(manager.isNearLimit(), isFalse);
      
      // Add queries to approach limit
      for (int i = 1; i <= 8; i++) {
        final query = Query<String>(key: 'near$i');
        manager.addQuery('near$i', query);
      }
      
      expect(manager.isNearLimit(), isTrue);
    });
    
    test('should clear all queries and reset stats', () {
      final query1 = Query<String>(key: 'clear1');
      final query2 = Query<String>(key: 'clear2');
      
      cacheManager.addQuery('clear1', query1);
      cacheManager.addQuery('clear2', query2);
      cacheManager.getQuery('clear1'); // Generate some stats
      
      var stats = cacheManager.getStats();
      expect(stats.queryCount, equals(2));
      expect(stats.hits, equals(1));
      
      cacheManager.clear();
      
      stats = cacheManager.getStats();
      expect(stats.queryCount, equals(0));
      expect(stats.hits, equals(0));
      expect(query1.isDisposed, isTrue);
      expect(query2.isDisposed, isTrue);
    });
  });
  
  group('QueryClientCacheIntegration', () {
    test('should integrate cache management with QueryClient', () async {
      final config = CacheConfig(
        maxQueries: 3,
        evictionPolicy: EvictionPolicy.lru,
      );
      
      final client = QueryClient.withConfig(config);
      addTearDown(() => client.dispose());
      
      // Add queries that exceed cache limit
      for (int i = 1; i <= 5; i++) {
        await client.fetchQuery('integration$i', () async => 'data$i');
      }
      
      final stats = client.getCacheStats();
      expect(stats.queryCount, lessThanOrEqualTo(3));
      expect(stats.evictions, greaterThan(0));
      
      // Check cache limit detection
      expect(client.isCacheNearLimit(), isTrue);
    });
    
    test('should handle large application scenario', () async {
      final client = QueryClient.withConfig(const CacheConfig.large());
      addTearDown(() => client.dispose());
      
      // Simulate large application with many queries
      final futures = <Future>[];
      for (int i = 1; i <= 100; i++) {
        futures.add(client.fetchQuery('large$i', () async => 'data$i'));
      }
      
      await Future.wait(futures);
      
      final stats = client.getCacheStats();
      expect(stats.queryCount, lessThanOrEqualTo(500)); // Within large config limit
      expect(stats.hitRatio, greaterThanOrEqualTo(0.0));
      
      // Manual cleanup
      client.cleanup();
      
      final afterStats = client.getCacheStats();
      expect(afterStats.queryCount, lessThanOrEqualTo(stats.queryCount));
    });
    
    test('should work with unlimited cache', () async {
      final client = QueryClient.withConfig(const CacheConfig.unlimited());
      addTearDown(() => client.dispose());
      
      // Add many queries without limit
      for (int i = 1; i <= 200; i++) {
        await client.fetchQuery('unlimited$i', () async => 'data$i');
      }
      
      final stats = client.getCacheStats();
      expect(stats.queryCount, equals(200)); // No eviction
      expect(stats.evictions, equals(0));
      expect(client.isCacheNearLimit(), isFalse);
    });
  });
  
  group('MemoryPressureHandler', () {
    test('should handle memory pressure notifications', () {
      final handler = MemoryPressureHandler.instance;
      final manager = CacheManager(const CacheConfig());
      
      // Add some queries
      for (int i = 1; i <= 5; i++) {
        final query = Query<String>(key: 'pressure$i');
        query.setData('data$i');
        manager.addQuery('pressure$i', query);
      }
      
      final statsBefore = manager.getStats();
      
      // Trigger memory pressure
      handler.triggerMemoryPressure();
      
      final statsAfter = manager.getStats();
      
      // Should have cleaned up some queries or at least attempted to
      expect(statsAfter.queryCount, lessThanOrEqualTo(statsBefore.queryCount));
      
      manager.dispose();
    });
    
    test('should provide memory pressure information', () {
      final handler = MemoryPressureHandler.instance;
      final manager1 = CacheManager(const CacheConfig.compact());
      final manager2 = CacheManager(const CacheConfig.compact());
      
      addTearDown(() => manager1.dispose());
      addTearDown(() => manager2.dispose());
      
      // Add queries to approach limits
      for (int i = 1; i <= 40; i++) {
        final query1 = Query<String>(key: 'info1_$i');
        final query2 = Query<String>(key: 'info2_$i');
        query1.setData('data$i');
        query2.setData('data$i');
        manager1.addQuery('info1_$i', query1);
        manager2.addQuery('info2_$i', query2);
      }
      
      final info = handler.getMemoryPressureInfo();
      
      expect(info.totalCacheManagers, greaterThan(0));
      expect(info.totalQueries, greaterThan(0));
      expect(info.totalMemoryBytes, greaterThan(0));
      expect(info.memoryMB, greaterThan(0));
    });
  });
  
  group('CacheEvictionScenarios', () {
    test('should handle mixed query types and sizes', () async {
      final config = CacheConfig(
        maxMemoryBytes: 5 * 1024, // 5KB limit
        evictionPolicy: EvictionPolicy.lru,
      );
      
      final manager = CacheManager(config);
      addTearDown(() => manager.dispose());
      
      // Add queries with different data sizes
      final smallQuery = Query<String>(key: 'small');
      smallQuery.setData('small');
      manager.addQuery('small', smallQuery);
      
      final mediumQuery = Query<List<String>>(key: 'medium');
      mediumQuery.setData(List.generate(100, (i) => 'item$i'));
      manager.addQuery('medium', mediumQuery);
      
      final largeQuery = Query<Map<String, String>>(key: 'large');
      largeQuery.setData(Map.fromEntries(
        List.generate(1000, (i) => MapEntry('key$i', 'value$i'))
      ));
      manager.addQuery('large', largeQuery);
      
      final stats = manager.getStats();
      
      // Should have evicted some queries to stay within memory limit
      expect(stats.memoryBytes, lessThan(config.maxMemoryBytes * 2));
      
      // Large query should likely be evicted first due to size
      expect(manager.getQuery('large'), isNull);
    });
    
    test('should preserve queries with active listeners during eviction', () {
      final config = CacheConfig(
        maxQueries: 2,
        evictionPolicy: EvictionPolicy.lru,
      );
      
      final manager = CacheManager(config);
      addTearDown(() => manager.dispose());
      
      final query1 = Query<String>(key: 'listener1');
      final query2 = Query<String>(key: 'nolistener2');
      final query3 = Query<String>(key: 'listener3');
      
      // Add queries
      manager.addQuery('listener1', query1);
      manager.addQuery('nolistener2', query2);
      
      // Add listener to query1
      final subscription = query1.stream.listen((_) {});
      addTearDown(() => subscription.cancel());
      
      // Add third query, should evict query2 (no listeners)
      manager.addQuery('listener3', query3);
      
      expect(manager.getQuery('listener1'), isNotNull); // Has listener
      expect(manager.getQuery('nolistener2'), isNull);  // Evicted
      expect(manager.getQuery('listener3'), isNotNull); // Newly added
      
      query1.dispose();
      query3.dispose();
    });
  });
}