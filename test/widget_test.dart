import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartquery/src/query_client.dart';
import 'package:dartquery/src/widgets/query_provider.dart';
import 'package:dartquery/src/widgets/query_builder.dart';

void main() {
  group('QueryProvider', () {
    testWidgets('should provide QueryClient to widget tree', (tester) async {
      final client = QueryClient.forTesting();
      addTearDown(() => client.dispose());
      
      QueryClient? receivedClient;
      
      await tester.pumpWidget(
        QueryProvider(
          client: client,
          child: Builder(
            builder: (context) {
              receivedClient = QueryProvider.of(context);
              return Container();
            },
          ),
        ),
      );
      
      expect(receivedClient, same(client));
    });
    
    testWidgets('should fall back to global instance when no provider', (tester) async {
      QueryClient? receivedClient;
      
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            receivedClient = QueryProvider.of(context);
            return Container();
          },
        ),
      );
      
      expect(receivedClient, same(QueryClient.instance));
    });
    
    testWidgets('should notify dependents when client changes', (tester) async {
      final client1 = QueryClient.forTesting();
      final client2 = QueryClient.forTesting();
      addTearDown(() => client1.dispose());
      addTearDown(() => client2.dispose());
      
      var buildCount = 0;
      QueryClient? currentClient;
      
      await tester.pumpWidget(
        QueryProvider(
          client: client1,
          child: Builder(
            builder: (context) {
              buildCount++;
              currentClient = QueryProvider.of(context);
              return Container();
            },
          ),
        ),
      );
      
      expect(buildCount, equals(1));
      expect(currentClient, same(client1));
      
      // Change client
      await tester.pumpWidget(
        QueryProvider(
          client: client2,
          child: Builder(
            builder: (context) {
              buildCount++;
              currentClient = QueryProvider.of(context);
              return Container();
            },
          ),
        ),
      );
      
      expect(buildCount, equals(2));
      expect(currentClient, same(client2));
    });
  });
  
  group('QueryBuilder', () {
    late QueryClient client;
    
    setUp(() {
      client = QueryClient.forTesting();
    });
    
    tearDown(() {
      client.dispose();
    });
    
    testWidgets('should display loading state initially', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QueryProvider(
            client: client,
            child: QueryBuilder<String>(
              queryKey: 'test-key',
              fetcher: () async {
                await Future.delayed(const Duration(milliseconds: 100));
                return 'test data';
              },
              builder: (context, query) {
                if (query.isLoading) {
                  return const Text('Loading...');
                }
                return Text(query.data ?? 'No data');
              },
            ),
          ),
        ),
      );
      
      expect(find.text('Loading...'), findsOneWidget);
    });
    
    testWidgets('should display data after successful fetch', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QueryProvider(
            client: client,
            child: QueryBuilder<String>(
              queryKey: 'test-key',
              fetcher: () async => 'test data',
              builder: (context, query) {
                if (query.isLoading) {
                  return const Text('Loading...');
                }
                if (query.isError) {
                  return Text('Error: ${query.error}');
                }
                return Text(query.data ?? 'No data');
              },
            ),
          ),
        ),
      );
      
      // Initially loading
      expect(find.text('Loading...'), findsOneWidget);
      
      // Wait for fetch to complete
      await tester.pumpAndSettle();
      
      expect(find.text('test data'), findsOneWidget);
    });
    
    testWidgets('should display error state on fetch failure', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QueryProvider(
            client: client,
            child: QueryBuilder<String>(
              queryKey: 'error-key',
              fetcher: () async => throw 'Fetch failed',
              builder: (context, query) {
                if (query.isLoading) {
                  return const Text('Loading...');
                }
                if (query.isError) {
                  return Text('Error: ${query.error}');
                }
                return Text(query.data ?? 'No data');
              },
            ),
          ),
        ),
      );
      
      // Initially loading
      expect(find.text('Loading...'), findsOneWidget);
      
      // Wait for fetch to fail
      await tester.pumpAndSettle();
      
      expect(find.text('Error: Fetch failed'), findsOneWidget);
    });
    
    testWidgets('should not fetch when disabled', (tester) async {
      var fetchCalled = false;
      
      await tester.pumpWidget(
        MaterialApp(
          home: QueryProvider(
            client: client,
            child: QueryBuilder<String>(
              queryKey: 'disabled-key',
              enabled: false,
              fetcher: () async {
                fetchCalled = true;
                return 'test data';
              },
              builder: (context, query) {
                return Text(query.data ?? 'No data');
              },
            ),
          ),
        ),
      );
      
      await tester.pumpAndSettle();
      
      expect(fetchCalled, isFalse);
      expect(find.text('No data'), findsOneWidget);
    });
    
    testWidgets('should display cached data immediately', (tester) async {
      // Pre-populate cache
      client.setQueryData('cached-key', 'cached data');
      
      await tester.pumpWidget(
        MaterialApp(
          home: QueryProvider(
            client: client,
            child: QueryBuilder<String>(
              queryKey: 'cached-key',
              fetcher: () async => 'fresh data',
              builder: (context, query) {
                return Text(query.data ?? 'No data');
              },
            ),
          ),
        ),
      );
      
      // Should show cached data immediately
      expect(find.text('cached data'), findsOneWidget);
    });
    
    testWidgets('should update UI when query data changes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QueryProvider(
            client: client,
            child: QueryBuilder<String>(
              queryKey: 'reactive-key',
              builder: (context, query) {
                return Text(query.data ?? 'No data');
              },
            ),
          ),
        ),
      );
      
      expect(find.text('No data'), findsOneWidget);
      
      // Update data externally
      client.setQueryData('reactive-key', 'updated data');
      await tester.pump();
      
      expect(find.text('updated data'), findsOneWidget);
    });
    
    testWidgets('should handle stale and cache times', (tester) async {
      var fetchCount = 0;
      
      await tester.pumpWidget(
        MaterialApp(
          home: QueryProvider(
            client: client,
            child: QueryBuilder<String>(
              queryKey: 'time-key',
              staleTime: const Duration(milliseconds: 50),
              cacheTime: const Duration(milliseconds: 100),
              fetcher: () async {
                fetchCount++;
                return 'data $fetchCount';
              },
              builder: (context, query) {
                if (query.isLoading) {
                  return const Text('Loading...');
                }
                return Text(query.data ?? 'No data');
              },
            ),
          ),
        ),
      );
      
      // Wait for initial fetch
      await tester.pumpAndSettle();
      expect(find.text('data 1'), findsOneWidget);
      expect(fetchCount, equals(1));
      
      // Rebuild widget - should not refetch (data is fresh)
      await tester.pumpWidget(
        MaterialApp(
          home: QueryProvider(
            client: client,
            child: QueryBuilder<String>(
              queryKey: 'time-key',
              staleTime: const Duration(milliseconds: 50),
              fetcher: () async {
                fetchCount++;
                return 'data $fetchCount';
              },
              builder: (context, query) {
                return Text(query.data ?? 'No data');
              },
            ),
          ),
        ),
      );
      
      await tester.pump();
      expect(fetchCount, equals(1)); // Should not increase
    });
    
    testWidgets('should clean up resources when disposed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QueryProvider(
            client: client,
            child: QueryBuilder<String>(
              queryKey: 'cleanup-key',
              fetcher: () async => 'test data',
              builder: (context, query) {
                return Text(query.data ?? 'No data');
              },
            ),
          ),
        ),
      );
      
      await tester.pumpAndSettle();
      expect(client.queries, hasLength(1));
      
      // Remove the widget
      await tester.pumpWidget(
        MaterialApp(
          home: QueryProvider(
            client: client,
            child: const Text('Different widget'),
          ),
        ),
      );
      
      // Allow cleanup timer to run
      await tester.pump(const Duration(milliseconds: 200));
      
      // Query should be removed or marked for cleanup
      expect(
        client.queries.isEmpty || 
        client.queries['cleanup-key']?.isDisposed == true,
        isTrue,
      );
    });
  });
  
  group('QueryConsumer', () {
    late QueryClient client;
    
    setUp(() {
      client = QueryClient.forTesting();
    });
    
    tearDown(() {
      client.dispose();
    });
    
    testWidgets('should display cached data', (tester) async {
      client.setQueryData('consumer-key', 'consumer data');
      
      await tester.pumpWidget(
        MaterialApp(
          home: QueryProvider(
            client: client,
            child: QueryConsumer<String>(
              queryKey: 'consumer-key',
              builder: (context, query) {
                return Text(query.data ?? 'No data');
              },
            ),
          ),
        ),
      );
      
      expect(find.text('consumer data'), findsOneWidget);
    });
    
    testWidgets('should react to data changes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QueryProvider(
            client: client,
            child: QueryConsumer<String>(
              queryKey: 'reactive-consumer-key',
              builder: (context, query) {
                return Text(query.data ?? 'No data');
              },
            ),
          ),
        ),
      );
      
      expect(find.text('No data'), findsOneWidget);
      
      // Update data
      client.setQueryData('reactive-consumer-key', 'new data');
      await tester.pump();
      
      expect(find.text('new data'), findsOneWidget);
      
      // Update again
      client.setQueryData('reactive-consumer-key', 'updated data');
      await tester.pump();
      
      expect(find.text('updated data'), findsOneWidget);
    });
    
    testWidgets('should handle query states', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QueryProvider(
            client: client,
            child: QueryConsumer<String>(
              queryKey: 'state-key',
              builder: (context, query) {
                if (query.isLoading) {
                  return const Text('Loading...');
                }
                if (query.isError) {
                  return Text('Error: ${query.error}');
                }
                return Text(query.data ?? 'No data');
              },
            ),
          ),
        ),
      );
      
      expect(find.text('No data'), findsOneWidget);
      
      // Set loading state
      final query = client.getQuery<String>('state-key');
      query.setLoading();
      await tester.pump();
      
      expect(find.text('Loading...'), findsOneWidget);
      
      // Set error state
      query.setError('Test error');
      await tester.pump();
      
      expect(find.text('Error: Test error'), findsOneWidget);
      
      // Set success state
      query.setData('Success data');
      await tester.pump();
      
      expect(find.text('Success data'), findsOneWidget);
    });
  });
  
  group('Integration Tests', () {
    testWidgets('should work with multiple QueryBuilders and QueryConsumers', (tester) async {
      final client = QueryClient.forTesting();
      addTearDown(() => client.dispose());
      
      var fetchCount = 0;
      
      await tester.pumpWidget(
        MaterialApp(
          home: QueryProvider(
            client: client,
            child: Column(
              children: [
                QueryBuilder<String>(
                  queryKey: 'shared-key',
                  fetcher: () async {
                    fetchCount++;
                    return 'shared data';
                  },
                  builder: (context, query) {
                    if (query.isLoading) return const Text('Builder Loading...');
                    return Text('Builder: ${query.data ?? "No data"}');
                  },
                ),
                QueryConsumer<String>(
                  queryKey: 'shared-key',
                  builder: (context, query) {
                    return Text('Consumer: ${query.data ?? "No data"}');
                  },
                ),
              ],
            ),
          ),
        ),
      );
      
      // Initially builder shows loading, consumer shows no data
      expect(find.text('Builder Loading...'), findsOneWidget);
      expect(find.text('Consumer: No data'), findsOneWidget);
      
      // Wait for fetch to complete
      await tester.pumpAndSettle();
      
      // Both should show the same data
      expect(find.text('Builder: shared data'), findsOneWidget);
      expect(find.text('Consumer: shared data'), findsOneWidget);
      expect(fetchCount, equals(1)); // Only fetched once
      
      // Update data externally
      client.setQueryData('shared-key', 'updated data');
      await tester.pump();
      
      // Both should show updated data
      expect(find.text('Builder: updated data'), findsOneWidget);
      expect(find.text('Consumer: updated data'), findsOneWidget);
    });
    
    testWidgets('should handle complex query lifecycle', (tester) async {
      final client = QueryClient.forTesting();
      addTearDown(() => client.dispose());
      
      var fetchCount = 0;
      String? lastFetchedData;
      
      await tester.pumpWidget(
        MaterialApp(
          home: QueryProvider(
            client: client,
            child: QueryBuilder<String>(
              queryKey: 'lifecycle-key',
              fetcher: () async {
                fetchCount++;
                lastFetchedData = 'fetch $fetchCount';
                return lastFetchedData!;
              },
              builder: (context, query) {
                return Column(
                  children: [
                    Text('Status: ${query.status.name}'),
                    Text('Data: ${query.data ?? "null"}'),
                    Text('Error: ${query.error ?? "null"}'),
                    Text('Stale: ${query.isStale}'),
                  ],
                );
              },
            ),
          ),
        ),
      );
      
      // Initial loading state
      expect(find.text('Status: loading'), findsOneWidget);
      expect(find.text('Data: null'), findsOneWidget);
      
      // Wait for fetch
      await tester.pumpAndSettle();
      
      expect(find.text('Status: success'), findsOneWidget);
      expect(find.text('Data: fetch 1'), findsOneWidget);
      expect(find.text('Stale: false'), findsOneWidget);
      
      // Invalidate query
      client.invalidateQuery('lifecycle-key');
      await tester.pump();
      
      expect(find.text('Status: idle'), findsOneWidget);
      expect(find.text('Stale: true'), findsOneWidget);
    });
  });
}