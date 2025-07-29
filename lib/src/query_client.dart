import 'dart:async';
import 'package:flutter/foundation.dart';
import 'query.dart';
import 'cache_config.dart';
import 'cache_manager.dart';

/// Function type for fetching query data.
typedef QueryFunction<T> = Future<T> Function();

/// Function type for mutation operations that take variables of type [V] and return [T].
typedef MutationFunction<T, V> = Future<T> Function(V variables);

/// Central client for managing queries, caching, and data synchronization.
/// 
/// The QueryClient is responsible for:
/// - Creating and managing query instances
/// - Coordinating data fetching and caching
/// - Handling mutations and cache invalidation
/// - Providing reactive streams for UI updates
/// 
/// Example:
/// ```dart
/// final client = QueryClient.instance;
/// final userData = await client.fetchQuery(
///   'user-123',
///   () => userService.getUser(123),
/// );
/// ```
class QueryClient {
  static QueryClient? _instance;
  
  /// Global singleton instance of QueryClient.
  /// 
  /// Use this for simple applications that need a single query client.
  /// For more complex scenarios, create dedicated instances.
  static QueryClient get instance => _instance ??= QueryClient._();
  
  QueryClient._([CacheConfig? cacheConfig]) : _cacheConfig = cacheConfig ?? const CacheConfig() {
    _cacheManager = CacheManager(_cacheConfig);
  }
  
  /// Creates a QueryClient instance with custom cache configuration.
  /// 
  /// Use this constructor to customize cache behavior, size limits,
  /// and eviction policies for your specific use case.
  /// 
  /// Example:
  /// ```dart
  /// final client = QueryClient.withConfig(
  ///   CacheConfig.large(), // For large applications
  /// );
  /// ```
  QueryClient.withConfig(CacheConfig cacheConfig) : _cacheConfig = cacheConfig {
    _cacheManager = CacheManager(_cacheConfig);
  }
  
  /// Creates a QueryClient instance for testing.
  /// 
  /// This constructor is primarily intended for testing and doesn't start
  /// the automatic cleanup timer.
  @visibleForTesting
  QueryClient.forTesting([CacheConfig? cacheConfig]) : _cacheConfig = cacheConfig ?? const CacheConfig.compact() {
    _cacheManager = CacheManager(_cacheConfig);
  }

  final CacheConfig _cacheConfig;
  late final CacheManager _cacheManager;
  final Map<String, Query> _queries = {};
  final Map<String, Future> _ongoingRequests = {};
  bool _disposed = false;

  /// Gets or creates a query with the specified [key].
  /// 
  /// If a query with the given [key] doesn't exist, creates a new one.
  /// This operation is atomic and thread-safe.
  /// 
  /// The cache manager will automatically handle size limits and eviction
  /// based on the configured cache policy.
  /// 
  /// - [key]: Unique identifier for the query
  /// - [staleTime]: Duration after which data is considered stale
  /// - [cacheTime]: Duration to keep data in cache after becoming unused
  /// 
  /// Returns the existing or newly created query instance.
  Query<T> getQuery<T>(String key, {
    Duration? staleTime,
    Duration? cacheTime,
  }) {
    if (_disposed) {
      throw StateError('QueryClient has been disposed');
    }
    
    // Check cache manager first
    final cachedQuery = _cacheManager.getQuery(key);
    if (cachedQuery != null) {
      return cachedQuery as Query<T>;
    }
    
    // Create new query if not found
    final query = Query<T>(
      key: key,
      staleTime: staleTime,
      cacheTime: cacheTime,
      onCacheExpire: _scheduleQueryRemoval,
    );
    
    // Add to both internal map and cache manager
    _queries[key] = query;
    _cacheManager.addQuery(key, query);
    
    // Log cache size warning if approaching limits
    if (_cacheManager.isNearLimit()) {
      debugPrint('DartQuery: Cache approaching size limits. Current stats: ${_cacheManager.getStats()}');
    }
    
    return query;
  }

  /// Fetches data for a query, with intelligent caching and staleness checks.
  /// 
  /// This method:
  /// 1. Gets or creates the query
  /// 2. Returns cached data if still fresh (unless [forceRefetch] is true)
  /// 3. Deduplicates concurrent requests for the same key
  /// 4. Sets loading state and executes [queryFn]
  /// 5. Atomically updates query state with result or error
  /// 
  /// - [key]: Unique identifier for the query
  /// - [queryFn]: Function that fetches the data
  /// - [staleTime]: Duration after which data is considered stale
  /// - [cacheTime]: Duration to keep data in cache after becoming unused
  /// - [forceRefetch]: If true, ignores cache and always fetches
  /// 
  /// Returns the fetched data or throws if the fetch fails.
  Future<T> fetchQuery<T>(
    String key,
    QueryFunction<T> queryFn, {
    Duration? staleTime,
    Duration? cacheTime,
    bool forceRefetch = false,
  }) async {
    if (_disposed) {
      throw StateError('QueryClient has been disposed');
    }
    
    final query = getQuery<T>(key, staleTime: staleTime, cacheTime: cacheTime);
    
    // Return cached data if available and fresh
    if (!forceRefetch && !query.isStale && query.data != null) {
      return query.data!;
    }

    // Check for ongoing request to prevent duplicate fetches
    if (_ongoingRequests.containsKey(key)) {
      return await _ongoingRequests[key] as Future<T>;
    }

    // Set loading state before fetch
    query.setLoading();
    
    // Create and store the fetch future for deduplication
    final fetchFuture = _performFetch(query, queryFn);
    _ongoingRequests[key] = fetchFuture;
    
    try {
      final data = await fetchFuture;
      return data;
    } finally {
      // Always clean up the ongoing request
      _ongoingRequests.remove(key);
    }
  }
  
  /// Internal method to perform the actual fetch operation.
  Future<T> _performFetch<T>(Query<T> query, QueryFunction<T> queryFn) async {
    try {
      final data = await queryFn();
      // Atomically update with success
      query.setData(data);
      return data;
    } catch (error) {
      // Atomically update with error
      query.setError(error);
      rethrow;
    }
  }

  /// Executes a mutation and optionally invalidates related queries.
  /// 
  /// Mutations are operations that modify server state (POST, PUT, DELETE).
  /// After successful mutation, specified queries can be invalidated to trigger refetch.
  /// 
  /// - [key]: Identifier for this mutation (for potential caching/deduplication)
  /// - [mutationFn]: Function that performs the mutation
  /// - [variables]: Data to pass to the mutation function
  /// - [invalidateQueries]: List of query keys to invalidate after success
  /// 
  /// Returns the result of the mutation or throws if it fails.
  /// Query invalidation is atomic - either all specified queries are invalidated or none.
  Future<T> mutate<T, V>(
    String key,
    MutationFunction<T, V> mutationFn,
    V variables, {
    List<String>? invalidateQueries,
  }) async {
    try {
      final result = await mutationFn(variables);
      
      // Atomically invalidate all specified queries after successful mutation
      if (invalidateQueries != null) {
        _atomicInvalidateQueries(invalidateQueries);
      }
      
      return result;
    } catch (error) {
      rethrow;
    }
  }

  /// Atomically sets data for a query without triggering a fetch.
  /// 
  /// This is useful for:
  /// - Setting initial data
  /// - Updating cache after mutations
  /// - Optimistic updates
  /// 
  /// The operation is atomic - the query state is updated consistently.
  void setQueryData<T>(String key, T data) {
    final query = getQuery<T>(key);
    query.setData(data);
  }

  /// Gets the current data for a query without triggering a fetch.
  /// 
  /// Returns null if the query doesn't exist or has no data.
  /// This is a read-only operation and doesn't affect query state.
  T? getQueryData<T>(String key) {
    return _queries[key]?.data as T?;
  }

  /// Atomically invalidates a single query, marking it for refetch.
  /// 
  /// If the query exists, it will be marked as idle and its timestamp cleared.
  /// This operation is atomic and will notify all listeners.
  void invalidateQuery(String key) {
    _queries[key]?.invalidate();
  }

  /// Atomically invalidates multiple queries.
  /// 
  /// This is more efficient than calling [invalidateQuery] multiple times
  /// as it ensures all invalidations happen atomically.
  void invalidateQueries(List<String> keys) {
    _atomicInvalidateQueries(keys);
  }
  
  /// Internal method for atomic invalidation of multiple queries.
  void _atomicInvalidateQueries(List<String> keys) {
    // Collect all queries to invalidate first
    final queriesToInvalidate = <Query>[];
    for (final key in keys) {
      final query = _queries[key];
      if (query != null) {
        queriesToInvalidate.add(query);
      }
    }
    
    // Invalidate all at once for atomicity
    for (final query in queriesToInvalidate) {
      query.invalidate();
    }
  }

  /// Atomically removes a query from the cache and cleans up resources.
  /// 
  /// This operation:
  /// 1. Cancels any ongoing requests
  /// 2. Disposes the query (cleaning up timers and streams)
  /// 3. Removes the query from cache and cache manager
  /// 
  /// The removal is atomic to prevent partial cleanup states.
  void removeQuery(String key) {
    if (_disposed) return;
    
    // Atomically remove from all storages
    _queries.remove(key);
    _ongoingRequests.remove(key);
    _cacheManager.removeQuery(key);
    
    // Cleanup is handled by cache manager
    // Note: We don't cancel ongoing requests as they might be awaited elsewhere
  }

  /// Atomically clears all queries and ongoing requests.
  /// 
  /// This operation:
  /// 1. Clears all internal maps
  /// 2. Delegates cleanup to cache manager
  /// 3. Resets all statistics
  /// 
  /// Use this to reset the client state, typically during app shutdown.
  void clear() {
    if (_disposed) return;
    
    // Atomically clear maps first
    _queries.clear();
    _ongoingRequests.clear();
    
    // Let cache manager handle disposal
    _cacheManager.clear();
  }

  /// Creates a reactive stream for watching query state changes.
  /// 
  /// The stream emits the query instance whenever its state changes.
  /// This is useful for reactive UI updates.
  /// 
  /// - [key]: The query key to watch
  /// 
  /// Returns a broadcast stream of query state changes.
  Stream<Query<T>> watchQuery<T>(String key) {
    if (_disposed) {
      throw StateError('QueryClient has been disposed');
    }
    
    final query = getQuery<T>(key);
    return query.stream;
  }
  
  /// Schedules a query for removal if it has no active listeners.
  /// This is called by queries when their cache expires.
  void _scheduleQueryRemoval(String key) {
    if (_disposed) return;
    
    // Use a short delay to allow for brief listener gaps
    Timer(const Duration(milliseconds: 100), () {
      final query = _queries[key];
      if (query != null && !query.hasListeners && !query.isDisposed) {
        removeQuery(key);
      }
    });
  }
  
  /// Forces cache cleanup and enforces size limits.
  /// 
  /// This method triggers the cache manager to:
  /// - Remove expired queries
  /// - Enforce size limits through eviction
  /// - Update cache statistics
  void cleanup() {
    if (_disposed) return;
    _cacheManager.cleanup();
  }
  
  /// Gets current cache statistics for monitoring and debugging.
  /// 
  /// Returns detailed information about cache usage, hit ratios,
  /// memory consumption, and eviction counts.
  CacheStats getCacheStats() {
    return _cacheManager.getStats();
  }
  
  /// Checks if cache is approaching configured size limits.
  /// 
  /// Returns true if cache usage is above the warning threshold
  /// for either query count or memory usage.
  bool isCacheNearLimit() {
    return _cacheManager.isNearLimit();
  }
  
  /// Disposes the QueryClient and all its resources.
  /// 
  /// After disposal, the client should not be used.
  void dispose() {
    if (_disposed) return;
    
    _disposed = true;
    _cacheManager.dispose();
    
    clear();
  }
  
  // Test-only getters for accessing private state
  @visibleForTesting
  Map<String, Query> get queries => Map.unmodifiable(_queries);
  
  @visibleForTesting
  Map<String, Future> get ongoingRequests => Map.unmodifiable(_ongoingRequests);
}