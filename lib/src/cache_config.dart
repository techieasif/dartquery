/// Configuration for cache management and eviction policies.
class CacheConfig {
  /// Maximum number of queries to keep in cache (default: 100)
  final int maxQueries;
  
  /// Maximum memory size in bytes for cache data (default: 50MB)
  final int maxMemoryBytes;
  
  /// Eviction policy to use when cache limits are exceeded
  final EvictionPolicy evictionPolicy;
  
  /// Enable automatic cache cleanup on memory pressure
  final bool enableMemoryPressureHandling;
  
  /// Interval for periodic cache cleanup (default: 5 minutes)
  final Duration cleanupInterval;
  
  /// Threshold for cache size warning (0.8 = 80% of max)
  final double warnThreshold;
  
  const CacheConfig({
    this.maxQueries = 100,
    this.maxMemoryBytes = 50 * 1024 * 1024, // 50MB
    this.evictionPolicy = EvictionPolicy.lru,
    this.enableMemoryPressureHandling = true,
    this.cleanupInterval = const Duration(minutes: 5),
    this.warnThreshold = 0.8,
  });
  
  /// Creates a configuration optimized for large applications
  const CacheConfig.large({
    this.maxQueries = 500,
    this.maxMemoryBytes = 200 * 1024 * 1024, // 200MB
    this.evictionPolicy = EvictionPolicy.lru,
    this.enableMemoryPressureHandling = true,
    this.cleanupInterval = const Duration(minutes: 3),
    this.warnThreshold = 0.8,
  });
  
  /// Creates a configuration optimized for memory-constrained environments
  const CacheConfig.compact({
    this.maxQueries = 50,
    this.maxMemoryBytes = 10 * 1024 * 1024, // 10MB
    this.evictionPolicy = EvictionPolicy.lru,
    this.enableMemoryPressureHandling = true,
    this.cleanupInterval = const Duration(minutes: 2),
    this.warnThreshold = 0.7,
  });
  
  /// Creates a configuration with no limits (use with caution)
  const CacheConfig.unlimited({
    this.maxQueries = -1,
    this.maxMemoryBytes = -1,
    this.evictionPolicy = EvictionPolicy.none,
    this.enableMemoryPressureHandling = false,
    this.cleanupInterval = const Duration(minutes: 10),
    this.warnThreshold = 1.0,
  });
  
  /// Whether query count limit is enabled
  bool get hasQueryLimit => maxQueries > 0;
  
  /// Whether memory limit is enabled
  bool get hasMemoryLimit => maxMemoryBytes > 0;
  
  /// Whether any limits are enabled
  bool get hasLimits => hasQueryLimit || hasMemoryLimit;
}

/// Eviction policies for cache management
enum EvictionPolicy {
  /// No eviction - let cache grow unlimited
  none,
  
  /// Least Recently Used - evict queries that haven't been accessed recently
  lru,
  
  /// Least Recently Created - evict oldest queries first
  lrc,
  
  /// Least Frequently Used - evict queries with lowest access count
  lfu,
  
  /// Time-based - evict based on staleness and cache time
  ttl,
}

/// Cache statistics for monitoring and debugging
class CacheStats {
  /// Current number of queries in cache
  final int queryCount;
  
  /// Estimated memory usage in bytes
  final int memoryBytes;
  
  /// Number of cache hits
  final int hits;
  
  /// Number of cache misses
  final int misses;
  
  /// Number of evictions performed
  final int evictions;
  
  /// Number of expired queries cleaned up
  final int expirations;
  
  /// Last cleanup timestamp
  final DateTime? lastCleanup;
  
  const CacheStats({
    required this.queryCount,
    required this.memoryBytes,
    required this.hits,
    required this.misses,
    required this.evictions,
    required this.expirations,
    this.lastCleanup,
  });
  
  /// Cache hit ratio (0.0 to 1.0)
  double get hitRatio {
    final total = hits + misses;
    return total > 0 ? hits / total : 0.0;
  }
  
  /// Total cache operations
  int get totalOperations => hits + misses;
  
  /// Memory usage as percentage of limit (if limit is set)
  double memoryUsageRatio(int maxMemoryBytes) {
    return maxMemoryBytes > 0 ? memoryBytes / maxMemoryBytes : 0.0;
  }
  
  /// Query count as percentage of limit (if limit is set)
  double queryCountRatio(int maxQueries) {
    return maxQueries > 0 ? queryCount / maxQueries : 0.0;
  }
  
  @override
  String toString() {
    return 'CacheStats(queries: $queryCount, memory: ${(memoryBytes / 1024 / 1024).toStringAsFixed(1)}MB, '
           'hitRatio: ${(hitRatio * 100).toStringAsFixed(1)}%, evictions: $evictions)';
  }
}