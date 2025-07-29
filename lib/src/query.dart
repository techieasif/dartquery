import 'dart:async';

/// Represents the current status of a query operation.
/// 
/// - [idle]: Query hasn't been executed yet
/// - [loading]: Query is currently fetching data
/// - [success]: Query completed successfully with data
/// - [error]: Query failed with an error
enum QueryStatus { idle, loading, success, error }

/// A reactive query that manages data fetching, caching, and state.
/// 
/// Each query is identified by a unique [key] and can hold data of type [T].
/// The query automatically manages caching with configurable [staleTime] and [cacheTime].
/// 
/// Example:
/// ```dart
/// final query = Query<String>(key: 'user-data');
/// query.setData('Hello World');
/// print(query.data); // 'Hello World'
/// ```
class Query<T> {
  final String key;
  T? _data;
  Object? _error;
  QueryStatus _status = QueryStatus.idle;
  DateTime? _lastUpdated;
  Duration? _staleTime;
  Duration? _cacheTime;
  
  final StreamController<Query<T>> _controller = StreamController<Query<T>>.broadcast();
  Timer? _staleTimer;
  Timer? _cacheTimer;
  bool _disposed = false;
  
  // Callback to notify parent client when query should be removed
  void Function(String key)? _onCacheExpire;

  /// Creates a new query with the specified [key].
  /// 
  /// - [key]: Unique identifier for this query
  /// - [staleTime]: Duration after which data is considered stale (default: 5 minutes)
  /// - [cacheTime]: Duration to keep data in cache after becoming unused (default: 10 minutes)
  /// - [onCacheExpire]: Optional callback when cache expires
  Query({
    required this.key,
    Duration? staleTime,
    Duration? cacheTime,
    void Function(String key)? onCacheExpire,
  }) : _staleTime = staleTime ?? const Duration(minutes: 5),
       _cacheTime = cacheTime ?? const Duration(minutes: 10),
       _onCacheExpire = onCacheExpire;

  /// The current data held by this query, or null if no data is available.
  T? get data => _data;
  
  /// The error that occurred during the last query execution, or null if no error.
  Object? get error => _error;
  
  /// The current status of this query.
  QueryStatus get status => _status;
  
  /// The timestamp when this query was last updated with data or error.
  DateTime? get lastUpdated => _lastUpdated;
  
  /// Returns true if the query is currently loading data.
  bool get isLoading => _status == QueryStatus.loading;
  
  /// Returns true if the query has successfully loaded data.
  bool get isSuccess => _status == QueryStatus.success;
  
  /// Returns true if the query failed with an error.
  bool get isError => _status == QueryStatus.error;
  
  /// Returns true if the query hasn't been executed yet.
  bool get isIdle => _status == QueryStatus.idle;
  
  /// Returns true if the query has been disposed.
  bool get isDisposed => _disposed;
  
  /// Returns true if the query has active listeners.
  bool get hasListeners => _controller.hasListener;
  
  /// Returns true if the data is considered stale and should be refetched.
  /// 
  /// Data is stale if:
  /// - It has never been loaded ([_lastUpdated] is null)
  /// - The time since last update exceeds [_staleTime]
  bool get isStale {
    if (_lastUpdated == null) return true;
    if (_staleTime == null) return false;
    return DateTime.now().difference(_lastUpdated!) > _staleTime!;
  }

  /// A stream that emits this query instance whenever its state changes.
  /// 
  /// Useful for reactive UI updates or listening to query state changes.
  Stream<Query<T>> get stream => _controller.stream;

  /// Atomically sets the query data and updates the state to success.
  /// 
  /// This operation:
  /// - Sets the [data] 
  /// - Clears any previous error
  /// - Updates status to [QueryStatus.success]
  /// - Records the current timestamp
  /// - Starts stale and cache timers
  /// - Notifies all listeners
  /// 
  /// The operation is atomic to ensure consistent state.
  void setData(T data) {
    if (_disposed) return;
    
    // Atomic update of all related state
    final now = DateTime.now();
    _data = data;
    _error = null;
    _status = QueryStatus.success;
    _lastUpdated = now;
    
    // Start timers after state is consistent
    _startStaleTimer();
    _startCacheTimer();
    
    // Notify listeners after all state is updated
    if (!_disposed) {
      _controller.add(this);
    }
  }

  /// Atomically sets the query error and updates the state to error.
  /// 
  /// This operation:
  /// - Clears any previous data (for consistency)
  /// - Sets the [error]
  /// - Updates status to [QueryStatus.error] 
  /// - Records the current timestamp
  /// - Starts cache timer
  /// - Notifies all listeners
  /// 
  /// The operation is atomic to ensure consistent state.
  void setError(Object error) {
    if (_disposed) return;
    
    // Atomic update of error state
    final now = DateTime.now();
    _data = null; // Clear stale data for consistency
    _error = error;
    _status = QueryStatus.error;
    _lastUpdated = now;
    
    // Start cache timer after state is consistent
    _startCacheTimer();
    
    // Notify listeners after all state is updated
    if (!_disposed) {
      _controller.add(this);
    }
  }

  /// Sets the query status to loading.
  /// 
  /// This should be called when starting an async operation.
  /// The operation is atomic and notifies all listeners.
  void setLoading() {
    if (_disposed) return;
    
    _status = QueryStatus.loading;
    if (!_disposed) {
      _controller.add(this);
    }
  }

  /// Atomically invalidates the query, marking it as idle.
  /// 
  /// This operation:
  /// - Resets status to [QueryStatus.idle]
  /// - Clears the last updated timestamp
  /// - Notifies all listeners
  /// 
  /// Use this to force a refetch on next access.
  void invalidate() {
    if (_disposed) return;
    
    // Atomic invalidation
    _status = QueryStatus.idle;
    _lastUpdated = null;
    
    // Notify listeners after state is updated
    if (!_disposed) {
      _controller.add(this);
    }
  }

  /// Starts or restarts the stale timer.
  /// 
  /// When the timer expires, listeners are notified so they can
  /// check if data should be refetched.
  void _startStaleTimer() {
    _staleTimer?.cancel();
    if (_staleTime != null && !_disposed) {
      _staleTimer = Timer(_staleTime!, () {
        if (!_disposed) {
          _controller.add(this);
        }
      });
    }
  }

  /// Starts or restarts the cache timer.
  /// 
  /// When the timer expires, notifies the parent client to consider
  /// removing this query if it has no active listeners.
  void _startCacheTimer() {
    _cacheTimer?.cancel();
    if (_cacheTime != null && !_disposed) {
      _cacheTimer = Timer(_cacheTime!, () {
        if (!_disposed && !_controller.hasListener && _onCacheExpire != null) {
          _onCacheExpire!(key);
        }
      });
    }
  }

  /// Disposes of the query, canceling all timers and closing the stream.
  /// 
  /// Call this when the query is no longer needed to free resources.
  /// After disposal, the query should not be used.
  void dispose() {
    if (_disposed) return;
    
    _disposed = true;
    _staleTimer?.cancel();
    _cacheTimer?.cancel();
    _staleTimer = null;
    _cacheTimer = null;
    _onCacheExpire = null;
    
    // Close the stream controller
    _controller.close();
  }
}