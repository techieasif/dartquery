import 'package:flutter/widgets.dart';
import '../query_client.dart';

/// An InheritedWidget that provides a QueryClient to the widget tree.
/// 
/// This widget should be placed near the root of your app to make the
/// QueryClient available to all descendant widgets. Query widgets like
/// [QueryBuilder] and [QueryConsumer] use this to access the client.
/// 
/// Example usage:
/// ```dart
/// void main() {
///   runApp(
///     QueryProvider(
///       client: QueryClient.instance,
///       child: MyApp(),
///     ),
///   );
/// }
/// ```
/// 
/// For most apps, you can use the global [QueryClient.instance]. For more
/// complex scenarios requiring multiple clients, create dedicated instances.
class QueryProvider extends InheritedWidget {
  /// The QueryClient instance to provide to descendant widgets.
  final QueryClient client;

  /// Creates a QueryProvider that provides the [client] to descendant widgets.
  /// 
  /// - [client]: The QueryClient instance to provide
  /// - [child]: The widget subtree that can access the client
  const QueryProvider({
    Key? key,
    required this.client,
    required Widget child,
  }) : super(key: key, child: child);

  /// Retrieves the QueryClient from the widget tree.
  /// 
  /// This method looks up the widget tree for a [QueryProvider] and returns
  /// its client. If no provider is found, it falls back to the global
  /// [QueryClient.instance].
  /// 
  /// - [context]: The build context to search from
  /// 
  /// Returns the QueryClient instance for use in queries.
  /// 
  /// Example:
  /// ```dart
  /// Widget build(BuildContext context) {
  ///   final client = QueryProvider.of(context);
  ///   final query = client.getQuery('my-data');
  ///   // ...
  /// }
  /// ```
  static QueryClient of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<QueryProvider>();
    if (provider == null) {
      // Fallback to global instance if no provider found
      return QueryClient.instance;
    }
    return provider.client;
  }

  /// Determines if dependent widgets should be notified of changes.
  /// 
  /// Returns true if the client instance has changed, which would require
  /// dependent widgets to rebuild and use the new client.
  @override
  bool updateShouldNotify(QueryProvider oldWidget) {
    return client != oldWidget.client;
  }
}