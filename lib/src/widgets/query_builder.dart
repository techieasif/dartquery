import 'dart:async';
import 'package:flutter/widgets.dart';
import '../query.dart';
import '../query_client.dart';
import 'query_provider.dart';

/// Builder function for creating widgets based on query state.
/// 
/// - [context]: The build context
/// - [query]: The current query state with data, loading, and error information
typedef QueryBuilderFunction<T> = Widget Function(BuildContext context, Query<T> query);

/// Function type for fetching data asynchronously.
typedef QueryFetcher<T> = Future<T> Function();

/// A Flutter widget that automatically manages data fetching and provides reactive UI updates.
/// 
/// [QueryBuilder] handles the complete lifecycle of data fetching:
/// - Automatically fetches data when the widget mounts (if enabled)
/// - Re-fetches when data becomes stale
/// - Provides loading, success, and error states to the builder
/// - Automatically updates the UI when data changes
/// 
/// Example usage:
/// ```dart
/// QueryBuilder<User>(
///   queryKey: 'user-123',
///   fetcher: () => userService.getUser(123),
///   builder: (context, query) {
///     if (query.isLoading) {
///       return CircularProgressIndicator();
///     }
///     if (query.isError) {
///       return Text('Error: ${query.error}');
///     }
///     return Text('Hello, ${query.data?.name}!');
///   },
/// )
/// ```
class QueryBuilder<T> extends StatefulWidget {
  /// Unique key identifying this query.
  final String queryKey;
  
  /// Optional function to fetch data. If null, only displays cached data.
  final QueryFetcher<T>? fetcher;
  
  /// Function that builds the UI based on the current query state.
  final QueryBuilderFunction<T> builder;
  
  /// Duration after which data is considered stale and should be refetched.
  final Duration? staleTime;
  
  /// Duration to keep data in cache after it becomes unused.
  final Duration? cacheTime;
  
  /// Whether the query should automatically fetch data. Default is true.
  final bool enabled;

  /// Creates a QueryBuilder widget.
  /// 
  /// - [queryKey]: Unique identifier for this query
  /// - [fetcher]: Optional function to fetch data
  /// - [builder]: Function to build UI based on query state
  /// - [staleTime]: How long data is considered fresh
  /// - [cacheTime]: How long to keep data in cache
  /// - [enabled]: Whether to automatically fetch data
  const QueryBuilder({
    Key? key,
    required this.queryKey,
    this.fetcher,
    required this.builder,
    this.staleTime,
    this.cacheTime,
    this.enabled = true,
  }) : super(key: key);

  @override
  State<QueryBuilder<T>> createState() => _QueryBuilderState<T>();
}

class _QueryBuilderState<T> extends State<QueryBuilder<T>> {
  late QueryClient _client;
  late Query<T> _query;
  late Stream<Query<T>> _stream;
  StreamSubscription<Query<T>>? _subscription;

  @override
  void initState() {
    super.initState();
    _initializeQuery();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _client = QueryProvider.of(context);
    _initializeQuery();
  }

  /// Initializes the query and sets up the reactive stream.
  /// 
  /// This method:
  /// 1. Gets or creates the query from the client
  /// 2. Sets up the reactive stream for UI updates
  /// 3. Triggers data fetching if conditions are met
  void _initializeQuery() {
    // Get or create the query atomically
    _query = _client.getQuery<T>(
      widget.queryKey,
      staleTime: widget.staleTime,
      cacheTime: widget.cacheTime,
    );
    _stream = _query.stream;

    // Fetch data if enabled and needed
    if (widget.enabled && widget.fetcher != null && (_query.isIdle || _query.isStale)) {
      _fetchData();
    }
  }

  /// Fetches data using the provided fetcher function.
  /// 
  /// Errors are automatically handled by the query object and will be
  /// reflected in the query state for the UI to handle.
  Future<void> _fetchData() async {
    if (widget.fetcher == null) return;
    
    try {
      await _client.fetchQuery(
        widget.queryKey,
        widget.fetcher!,
        staleTime: widget.staleTime,
        cacheTime: widget.cacheTime,
      );
    } catch (e) {
      // Error is handled in the query object and will trigger UI update
    }
  }

  /// Builds the widget using the current query state.
  /// 
  /// Uses StreamBuilder to automatically rebuild when query state changes.
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Query<T>>(
      stream: _stream,
      initialData: _query,
      builder: (context, snapshot) {
        final query = snapshot.data ?? _query;
        return widget.builder(context, query);
      },
    );
  }
  
  /// Disposes of the widget and cleans up resources.
  /// 
  /// Cancels any active subscriptions and removes the query if no other
  /// widgets are using it.
  @override
  void dispose() {
    _subscription?.cancel();
    
    // Schedule query cleanup if no other listeners
    if (!_query.isDisposed && !_query.hasListeners) {
      // Use a timer to allow for brief gaps between widget disposals
      Timer(const Duration(milliseconds: 100), () {
        if (!_query.hasListeners && !_query.isDisposed) {
          _client.removeQuery(widget.queryKey);
        }
      });
    }
    
    super.dispose();
  }
}

/// A lightweight widget for consuming cached query data reactively.
/// 
/// Unlike [QueryBuilder], [QueryConsumer] doesn't fetch data automatically.
/// It only displays data that's already in the cache and updates reactively
/// when that data changes.
/// 
/// This is useful for:
/// - Displaying cached data in multiple locations
/// - Creating reactive UI that responds to data changes
/// - Avoiding unnecessary refetches when data is already available
/// 
/// Example usage:
/// ```dart
/// QueryConsumer<String>(
///   queryKey: 'user-status',
///   builder: (context, query) {
///     return Text('Status: ${query.data ?? "Unknown"}');
///   },
/// )
/// ```
class QueryConsumer<T> extends StatelessWidget {
  /// Unique key identifying the query to consume.
  final String queryKey;
  
  /// Function that builds the UI based on the current query state.
  final QueryBuilderFunction<T> builder;

  /// Creates a QueryConsumer widget.
  /// 
  /// - [queryKey]: Unique identifier for the query to consume
  /// - [builder]: Function to build UI based on query state
  const QueryConsumer({
    Key? key,
    required this.queryKey,
    required this.builder,
  }) : super(key: key);

  /// Builds the widget using the current cached query state.
  /// 
  /// Gets the query from the client and uses StreamBuilder to automatically
  /// rebuild when the query state changes.
  @override
  Widget build(BuildContext context) {
    final client = QueryProvider.of(context);
    final query = client.getQuery<T>(queryKey);

    return StreamBuilder<Query<T>>(
      stream: query.stream,
      initialData: query,
      builder: (context, snapshot) {
        final currentQuery = snapshot.data ?? query;
        return builder(context, currentQuery);
      },
    );
  }
}