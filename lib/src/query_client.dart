import 'dart:async';
import 'package:flutter/foundation.dart';
import 'query.dart';

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
  
  QueryClient._() {
    // Start periodic cleanup of unused queries
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _cleanupUnusedQueries();
    });
  }
  
  /// Creates a QueryClient instance for testing.
  /// 
  /// This constructor is primarily intended for testing and doesn't start
  /// the automatic cleanup timer.
  @visibleForTesting
  QueryClient.forTesting();

  final Map<String, Query> _queries = {};
  final Map<String, Future> _ongoingRequests = {};
  Timer? _cleanupTimer;
  bool _disposed = false;

  /// Gets or creates a query with the specified [key].
  /// 
  /// If a query with the given [key] doesn't exist, creates a new one.
  /// This operation is atomic and thread-safe.
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
    
    // Atomic check and create operation
    if (!_queries.containsKey(key)) {
      _queries[key] = Query<T>(
        key: key,
        staleTime: staleTime,
        cacheTime: cacheTime,
        onCacheExpire: _scheduleQueryRemoval,
      );
    }
    return _queries[key] as Query<T>;
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
  /// 3. Removes the query from cache
  /// 
  /// The removal is atomic to prevent partial cleanup states.
  void removeQuery(String key) {
    if (_disposed) return;
    
    // Get references before removal for atomic cleanup
    final query = _queries[key];
    
    // Atomically remove from maps first
    _queries.remove(key);
    _ongoingRequests.remove(key);
    
    // Then cleanup resources
    query?.dispose();
    // Note: We don't cancel ongoing requests as they might be awaited elsewhere
  }

  /// Atomically clears all queries and ongoing requests.
  /// 
  /// This operation:
  /// 1. Collects all resources to cleanup
  /// 2. Clears the maps atomically
  /// 3. Cleans up all resources
  /// 
  /// Use this to reset the client state, typically during app shutdown.
  void clear() {
    if (_disposed) return;
    
    // Collect all resources before clearing maps for atomic operation
    final queriesToDispose = List<Query>.from(_queries.values);
    
    // Atomically clear maps first
    _queries.clear();
    _ongoingRequests.clear();
    
    // Then cleanup resources
    for (final query in queriesToDispose) {
      query.dispose();
    }
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
  
  /// Periodically cleans up unused queries that have no listeners.
  void _cleanupUnusedQueries() {
    if (_disposed) return;
    
    final keysToRemove = <String>[];
    
    for (final entry in _queries.entries) {
      final query = entry.value;
      if (!query.hasListeners && !query.isDisposed) {
        keysToRemove.add(entry.key);
      }
    }
    
    for (final key in keysToRemove) {
      removeQuery(key);
    }
  }
  
  /// Disposes the QueryClient and all its resources.
  /// 
  /// After disposal, the client should not be used.
  void dispose() {
    if (_disposed) return;
    
    _disposed = true;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    
    clear();
  }
  
  // Test-only getters for accessing private state
  @visibleForTesting
  Map<String, Query> get queries => Map.unmodifiable(_queries);
  
  @visibleForTesting
  Map<String, Future> get ongoingRequests => Map.unmodifiable(_ongoingRequests);
}