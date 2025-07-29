import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'cache_config.dart';
import 'query.dart';
import 'memory_pressure_handler.dart';

/// Internal cache entry with metadata for eviction policies
class _CacheEntry {
  final Query query;
  final DateTime createdAt;
  DateTime lastAccessedAt;
  int accessCount;
  int estimatedSize;
  
  _CacheEntry({
    required this.query,
    required this.createdAt,
    required this.estimatedSize,
  }) : lastAccessedAt = createdAt,
       accessCount = 1;
       
  /// Update access tracking
  void markAccessed() {
    lastAccessedAt = DateTime.now();
    accessCount++;
  }
  
  /// Calculate priority for eviction (lower = more likely to evict)
  double getEvictionPriority(EvictionPolicy policy) {
    final now = DateTime.now();
    
    switch (policy) {
      case EvictionPolicy.none:
        return double.infinity;
        
      case EvictionPolicy.lru:
        // Prioritize by last access time (older = lower priority)
        return lastAccessedAt.millisecondsSinceEpoch.toDouble();
        
      case EvictionPolicy.lrc:
        // Prioritize by creation time (older = lower priority)
        return createdAt.millisecondsSinceEpoch.toDouble();
        
      case EvictionPolicy.lfu:
        // Prioritize by access frequency (less frequent = lower priority)
        return accessCount.toDouble();
        
      case EvictionPolicy.ttl:
        // Prioritize by staleness and expiration
        if (query.isStale) return 0.0; // Stale queries have lowest priority
        if (query.lastUpdated != null) {
          final age = now.difference(query.lastUpdated!).inMilliseconds;
          return -age.toDouble(); // Older = lower priority
        }
        return createdAt.millisecondsSinceEpoch.toDouble();
    }
  }
}

/// Manages cache size, eviction, and memory pressure
class CacheManager {
  final CacheConfig config;
  final Map<String, _CacheEntry> _entries = {};
  
  // Statistics tracking
  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;
  int _expirations = 0;
  DateTime? _lastCleanup;
  
  // Memory pressure handling
  Timer? _cleanupTimer;
  bool _disposed = false;
  
  CacheManager(this.config) {
    if (config.hasLimits) {
      _startPeriodicCleanup();
    }
    
    // Register for memory pressure notifications if enabled
    if (config.enableMemoryPressureHandling) {
      MemoryPressureHandler.instance.register(this);
    }
  }
  
  /// Adds a query to the cache
  void addQuery(String key, Query query) {
    if (_disposed) return;
    
    final estimatedSize = _estimateQuerySize(query);
    final entry = _CacheEntry(
      query: query,
      createdAt: DateTime.now(),
      estimatedSize: estimatedSize,
    );
    
    _entries[key] = entry;
    
    // Check if eviction is needed
    if (config.hasLimits) {
      _enforceCache();
    }
  }
  
  /// Retrieves a query from cache and updates access tracking
  Query? getQuery(String key) {
    if (_disposed) return null;
    
    final entry = _entries[key];
    if (entry != null) {
      entry.markAccessed();
      _hits++;
      return entry.query;
    }
    
    _misses++;
    return null;
  }
  
  /// Removes a query from cache
  void removeQuery(String key) {
    if (_disposed) return;
    
    final entry = _entries.remove(key);
    entry?.query.dispose();
  }
  
  /// Clears all queries from cache
  void clear() {
    if (_disposed) return;
    
    for (final entry in _entries.values) {
      entry.query.dispose();
    }
    _entries.clear();
    
    // Reset statistics
    _hits = 0;
    _misses = 0;
    _evictions = 0;
    _expirations = 0;
  }
  
  /// Forces cache cleanup and eviction
  void cleanup() {
    if (_disposed) return;
    
    _cleanupExpiredQueries();
    _enforceCache();
    _lastCleanup = DateTime.now();
  }
  
  /// Gets current cache statistics
  CacheStats getStats() {
    return CacheStats(
      queryCount: _entries.length,
      memoryBytes: _calculateTotalMemoryUsage(),
      hits: _hits,
      misses: _misses,
      evictions: _evictions,
      expirations: _expirations,
      lastCleanup: _lastCleanup,
    );
  }
  
  /// Checks if cache is near limits
  bool isNearLimit() {
    if (!config.hasLimits) return false;
    
    final stats = getStats();
    
    if (config.hasQueryLimit) {
      final ratio = stats.queryCountRatio(config.maxQueries);
      if (ratio >= config.warnThreshold) return true;
    }
    
    if (config.hasMemoryLimit) {
      final ratio = stats.memoryUsageRatio(config.maxMemoryBytes);
      if (ratio >= config.warnThreshold) return true;
    }
    
    return false;
  }
  
  /// Disposes the cache manager
  void dispose() {
    if (_disposed) return;
    
    _disposed = true;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    
    // Unregister from memory pressure notifications
    if (config.enableMemoryPressureHandling) {
      MemoryPressureHandler.instance.unregister(this);
    }
    
    clear();
  }
  
  /// Starts periodic cleanup timer
  void _startPeriodicCleanup() {
    _cleanupTimer = Timer.periodic(config.cleanupInterval, (_) {
      cleanup();
    });
  }
  
  /// Enforces cache size limits through eviction
  void _enforceCache() {
    if (!config.hasLimits || config.evictionPolicy == EvictionPolicy.none) {
      return;
    }
    
    // Check memory limit
    if (config.hasMemoryLimit) {
      final memoryUsage = _calculateTotalMemoryUsage();
      if (memoryUsage > config.maxMemoryBytes) {
        _evictByPolicy(memoryUsage - config.maxMemoryBytes, _evictByMemory);
      }
    }
    
    // Check query count limit
    if (config.hasQueryLimit && _entries.length > config.maxQueries) {
      final excess = _entries.length - config.maxQueries;
      _evictByPolicy(excess, _evictByCount);
    }
  }
  
  /// Evicts queries based on configured policy
  void _evictByPolicy(int target, void Function(int) evictFunction) {
    if (target <= 0) return;
    
    // Sort entries by eviction priority
    final sortedEntries = _entries.entries.toList();
    sortedEntries.sort((a, b) {
      final priorityA = a.value.getEvictionPriority(config.evictionPolicy);
      final priorityB = b.value.getEvictionPriority(config.evictionPolicy);
      return priorityA.compareTo(priorityB);
    });
    
    // Evict lowest priority entries
    int evicted = 0;
    for (final entry in sortedEntries) {
      if (evicted >= target) break;
      
      // Don't evict queries with active listeners
      if (entry.value.query.hasListeners) continue;
      
      removeQuery(entry.key);
      _evictions++;
      evicted++;
    }
  }
  
  /// Evicts queries by memory target
  void _evictByMemory(int targetBytes) {
    final sortedEntries = _entries.entries.toList();
    sortedEntries.sort((a, b) {
      final priorityA = a.value.getEvictionPriority(config.evictionPolicy);
      final priorityB = b.value.getEvictionPriority(config.evictionPolicy);
      return priorityA.compareTo(priorityB);
    });
    
    int freedBytes = 0;
    for (final entry in sortedEntries) {
      if (freedBytes >= targetBytes) break;
      
      if (entry.value.query.hasListeners) continue;
      
      freedBytes += entry.value.estimatedSize;
      removeQuery(entry.key);
      _evictions++;
    }
  }
  
  /// Evicts queries by count target
  void _evictByCount(int targetCount) {
    final sortedEntries = _entries.entries.toList();
    sortedEntries.sort((a, b) {
      final priorityA = a.value.getEvictionPriority(config.evictionPolicy);
      final priorityB = b.value.getEvictionPriority(config.evictionPolicy);
      return priorityA.compareTo(priorityB);
    });
    
    int evicted = 0;
    for (final entry in sortedEntries) {
      if (evicted >= targetCount) break;
      
      if (entry.value.query.hasListeners) continue;
      
      removeQuery(entry.key);
      _evictions++;
      evicted++;
    }
  }
  
  /// Cleans up expired and stale queries
  void _cleanupExpiredQueries() {
    final keysToRemove = <String>[];
    
    for (final entry in _entries.entries) {
      final query = entry.value.query;
      
      // Remove disposed queries
      if (query.isDisposed) {
        keysToRemove.add(entry.key);
        continue;
      }
      
      // Remove queries without listeners that are stale
      if (!query.hasListeners && query.isStale) {
        keysToRemove.add(entry.key);
        continue;
      }
    }
    
    for (final key in keysToRemove) {
      removeQuery(key);
      _expirations++;
    }
  }
  
  /// Estimates memory usage of a query
  int _estimateQuerySize(Query query) {
    int size = 1024; // Base size for query object
    
    // Estimate data size
    if (query.data != null) {
      size += _estimateDataSize(query.data);
    }
    
    // Add error size if present
    if (query.error != null) {
      size += query.error.toString().length * 2; // UTF-16 encoding
    }
    
    // Add key size
    size += query.key.length * 2;
    
    return size;
  }
  
  /// Estimates size of arbitrary data
  int _estimateDataSize(dynamic data) {
    if (data == null) return 0;
    
    try {
      // Try to serialize to JSON for size estimation
      final jsonString = jsonEncode(data);
      return jsonString.length * 2; // UTF-16 encoding
    } catch (e) {
      // Fallback estimation
      if (data is String) {
        return data.length * 2;
      } else if (data is List) {
        return data.length * 100; // Rough estimate
      } else if (data is Map) {
        return data.length * 200; // Rough estimate
      } else {
        return 500; // Default estimate for complex objects
      }
    }
  }
  
  /// Calculates total memory usage of all cached queries
  int _calculateTotalMemoryUsage() {
    return _entries.values.fold(0, (sum, entry) => sum + entry.estimatedSize);
  }
  
  // Debug and testing helpers
  @visibleForTesting
  Map<String, _CacheEntry> get entries => Map.unmodifiable(_entries);
  
  @visibleForTesting
  void resetStats() {
    _hits = 0;
    _misses = 0;
    _evictions = 0;
    _expirations = 0;
  }
}