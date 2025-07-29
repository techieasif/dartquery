import 'query_client.dart';
import 'query.dart';

/// Main entry point for DartQuery - a simple, React Query-inspired data store.
/// 
/// DartQuery provides a high-level API for in-memory data storage with reactive
/// capabilities. It's designed to be familiar to developers coming from React Query
/// while being idiomatic to Dart/Flutter.
/// 
/// Key features:
/// - Simple key-value storage with `put()` and `get()`
/// - Async data fetching with intelligent caching via `fetch()`
/// - Reactive updates through `watch()` streams
/// - Cache invalidation and cleanup
/// 
/// Example usage:
/// ```dart
/// // Simple storage
/// DartQuery.instance.put('user-id', '123');
/// final userId = DartQuery.instance.get<String>('user-id');
/// 
/// // Async fetching with caching
/// final userData = await DartQuery.instance.fetch(
///   'user-profile',
///   () => userService.getProfile(),
/// );
/// 
/// // Reactive updates
/// DartQuery.instance.watch<User>('user-profile').listen((query) {
///   print('User data: ${query.data}');
/// });
/// ```
class DartQuery {
  static DartQuery? _instance;
  
  /// Global singleton instance of DartQuery.
  /// 
  /// This provides a convenient global access point for most use cases.
  /// For more advanced scenarios requiring multiple clients, use [QueryClient] directly.
  static DartQuery get instance => _instance ??= DartQuery._();
  
  DartQuery._();

  final QueryClient _client = QueryClient.instance;

  /// Access to the underlying [QueryClient] for advanced operations.
  /// 
  /// Use this when you need more control over query management,
  /// such as creating custom queries or accessing advanced features.
  QueryClient get client => _client;

  /// Atomically stores data with the specified key.
  /// 
  /// This is the simplest way to store data in DartQuery. The data is
  /// immediately available and will trigger updates to any watchers.
  /// 
  /// - [key]: Unique identifier for the data
  /// - [data]: The data to store
  /// 
  /// Example:
  /// ```dart
  /// DartQuery.instance.put('user-name', 'John Doe');
  /// DartQuery.instance.put('settings', {'theme': 'dark'});
  /// ```
  void put<T>(String key, T data) {
    _client.setQueryData(key, data);
  }

  /// Retrieves data for the specified key.
  /// 
  /// Returns the cached data if available, or null if the key doesn't exist
  /// or has no data. This is a synchronous operation that doesn't trigger fetching.
  /// 
  /// - [key]: The key to retrieve data for
  /// 
  /// Returns the data of type [T] or null if not found.
  /// 
  /// Example:
  /// ```dart
  /// final userName = DartQuery.instance.get<String>('user-name');
  /// final settings = DartQuery.instance.get<Map>('settings');
  /// ```
  T? get<T>(String key) {
    return _client.getQueryData<T>(key);
  }

  /// Fetches data asynchronously with intelligent caching.
  /// 
  /// This is the most powerful method in DartQuery. It:
  /// 1. Returns cached data immediately if fresh
  /// 2. Executes the fetcher function if data is stale or missing
  /// 3. Updates the cache with the result
  /// 4. Notifies all watchers of changes
  /// 
  /// - [key]: Unique identifier for this data
  /// - [fetcher]: Async function that fetches the data
  /// - [staleTime]: How long data is considered fresh (default: 5 minutes)
  /// - [cacheTime]: How long to keep data in cache (default: 10 minutes)
  /// - [forceRefetch]: If true, ignores cache and always fetches
  /// 
  /// Returns the fetched data or throws if the fetch fails.
  /// 
  /// Example:
  /// ```dart
  /// final user = await DartQuery.instance.fetch(
  ///   'user-123',
  ///   () => apiClient.getUser(123),
  ///   staleTime: Duration(minutes: 10),
  /// );
  /// ```
  Future<T> fetch<T>(
    String key,
    Future<T> Function() fetcher, {
    Duration? staleTime,
    Duration? cacheTime,
    bool forceRefetch = false,
  }) {
    return _client.fetchQuery(
      key,
      fetcher,
      staleTime: staleTime,
      cacheTime: cacheTime,
      forceRefetch: forceRefetch,
    );
  }

  /// Atomically invalidates a query, marking it for refetch.
  /// 
  /// This forces the query to be considered stale, so the next access
  /// will trigger a fresh fetch. Useful after data mutations.
  /// 
  /// - [key]: The key of the query to invalidate
  /// 
  /// Example:
  /// ```dart
  /// // After updating user data
  /// await updateUser(user);
  /// DartQuery.instance.invalidate('user-profile');
  /// ```
  void invalidate(String key) {
    _client.invalidateQuery(key);
  }

  /// Atomically invalidates multiple queries.
  /// 
  /// This is more efficient than calling [invalidate] multiple times
  /// as it ensures all invalidations happen atomically.
  /// 
  /// - [keys]: List of query keys to invalidate
  /// 
  /// Example:
  /// ```dart
  /// // After a user profile update, invalidate related queries
  /// DartQuery.instance.invalidateAll([
  ///   'user-profile',
  ///   'user-settings',
  ///   'user-preferences'
  /// ]);
  /// ```
  void invalidateAll(List<String> keys) {
    _client.invalidateQueries(keys);
  }

  /// Atomically removes a query from the cache.
  /// 
  /// This completely removes the query and its data from memory,
  /// freeing up resources. The next access will create a fresh query.
  /// 
  /// - [key]: The key of the query to remove
  /// 
  /// Example:
  /// ```dart
  /// // Remove sensitive data when user logs out
  /// DartQuery.instance.remove('user-tokens');
  /// ```
  void remove(String key) {
    _client.removeQuery(key);
  }

  /// Atomically clears all cached data and queries.
  /// 
  /// This removes everything from the cache and frees all resources.
  /// Use this during app shutdown or when switching user contexts.
  /// 
  /// Example:
  /// ```dart
  /// // Clear all data when user logs out
  /// await userService.logout();
  /// DartQuery.instance.clear();
  /// ```
  void clear() {
    _client.clear();
  }

  /// Creates a reactive stream that emits query state changes.
  /// 
  /// The stream emits the query instance whenever its state changes,
  /// including data updates, loading states, and errors. Perfect for
  /// reactive UI updates.
  /// 
  /// - [key]: The key of the query to watch
  /// 
  /// Returns a broadcast stream of [Query] instances.
  /// 
  /// Example:
  /// ```dart
  /// DartQuery.instance.watch<User>('user-profile').listen((query) {
  ///   if (query.isLoading) {
  ///     showLoadingIndicator();
  ///   } else if (query.isSuccess) {
  ///     displayUser(query.data!);
  ///   } else if (query.isError) {
  ///     showError(query.error.toString());
  ///   }
  /// });
  /// ```
  Stream<Query<T>> watch<T>(String key) {
    return _client.watchQuery<T>(key);
  }
}