# DartQuery

A production-ready Dart library for reactive in-memory data management with intelligent caching, similar to React Query. Works seamlessly with both Dart and Flutter applications.

## ✨ Features

- **🔄 Reactive Updates** - Automatic UI updates when data changes
- **⚡ Smart Caching** - Intelligent caching with configurable stale and cache times
- **📏 Cache Size Management** - Configurable limits with intelligent eviction policies
- **🔄 Request Deduplication** - Prevents duplicate API calls for the same data
- **💾 In-Memory Storage** - Fast key-value storage accessible across your app
- **🎯 Query Invalidation** - Manual cache invalidation and cleanup
- **🧠 Memory Management** - Automatic cleanup and memory pressure handling
- **📊 Cache Monitoring** - Real-time statistics and performance metrics
- **🔧 Flutter Integration** - Purpose-built widgets for reactive UI
- **🛡️ Type Safety** - Full TypeScript-like type safety in Dart
- **⚡ Performance Optimized** - Atomic operations and efficient state management

## 📦 Installation

Add DartQuery to your `pubspec.yaml`:

```yaml
dependencies:
  dartquery: ^1.0.0
```

Then run:

```bash
flutter pub get
```

## 🚀 Quick Start

### Basic Usage

```dart
import 'package:dartquery/dartquery.dart';

// Simple key-value storage
DartQuery.instance.put('user-id', 'john_123');
String? userId = DartQuery.instance.get<String>('user-id');

// Async data fetching with caching
final userData = await DartQuery.instance.fetch(
  'user-profile',
  () async => await apiClient.getUserProfile(),
  staleTime: Duration(minutes: 5),
);

// Reactive data watching
DartQuery.instance.watch<User>('user-profile').listen((query) {
  if (query.isSuccess) {
    print('User data: ${query.data?.name}');
  }
});
```

### Flutter Integration

```dart
import 'package:flutter/material.dart';
import 'package:dartquery/dartquery.dart';

void main() {
  runApp(
    QueryProvider(
      client: QueryClient.instance,
      child: MyApp(),
    ),
  );
}

class UserProfile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return QueryBuilder<User>(
      queryKey: 'user-profile',
      fetcher: () => userService.getProfile(),
      builder: (context, query) {
        if (query.isLoading) {
          return CircularProgressIndicator();
        }
        
        if (query.isError) {
          return Text('Error: ${query.error}');
        }
        
        return Text('Hello, ${query.data?.name}!');
      },
    );
  }
}
```

## 📖 Core Concepts

### Query States

Every query can be in one of four states:

- **`idle`** - Query hasn't been executed yet
- **`loading`** - Query is currently fetching data  
- **`success`** - Query completed successfully with data
- **`error`** - Query failed with an error

### Caching Strategy

DartQuery uses intelligent caching with two key concepts:

- **Stale Time** - How long data is considered "fresh" (default: 5 minutes)
- **Cache Time** - How long data stays in memory after becoming unused (default: 10 minutes)

```dart
await DartQuery.instance.fetch(
  'user-data',
  fetcher,
  staleTime: Duration(minutes: 10),  // Data fresh for 10 minutes
  cacheTime: Duration(hours: 1),     // Keep in cache for 1 hour
);
```

## 🔧 API Reference

### DartQuery Class

The main entry point for the library.

#### Methods

##### `put<T>(String key, T data)`
Store data immediately with the specified key.

```dart
DartQuery.instance.put('settings', {'theme': 'dark'});
```

##### `get<T>(String key) → T?`
Retrieve cached data synchronously.

```dart
final settings = DartQuery.instance.get<Map>('settings');
```

##### `fetch<T>(String key, Future<T> Function() fetcher, {...}) → Future<T>`
Fetch data asynchronously with intelligent caching.

```dart
final posts = await DartQuery.instance.fetch(
  'posts',
  () => apiClient.getPosts(),
  staleTime: Duration(minutes: 5),
  forceRefetch: false,
);
```

**Parameters:**
- `key` - Unique identifier for the data
- `fetcher` - Function that returns the data
- `staleTime` - Duration data is considered fresh
- `cacheTime` - Duration to keep data in cache
- `forceRefetch` - Ignore cache and always fetch

##### `invalidate(String key)`
Mark a query as stale, forcing refetch on next access.

```dart
// After updating user data
await updateUserProfile(newData);
DartQuery.instance.invalidate('user-profile');
```

##### `invalidateAll(List<String> keys)`
Invalidate multiple queries atomically.

```dart
DartQuery.instance.invalidateAll([
  'user-profile',
  'user-settings', 
  'user-preferences'
]);
```

##### `remove(String key)`
Remove data from cache completely.

```dart
DartQuery.instance.remove('sensitive-data');
```

##### `clear()`
Clear all cached data.

```dart
// On user logout
DartQuery.instance.clear();
```

##### `watch<T>(String key) → Stream<Query<T>>`
Get a reactive stream of query state changes.

```dart
DartQuery.instance.watch<User>('user').listen((query) {
  print('Status: ${query.status}');
  print('Data: ${query.data}');
  print('Is loading: ${query.isLoading}');
});
```

### Flutter Widgets

#### QueryProvider

Provides QueryClient to the widget tree.

```dart
QueryProvider(
  client: QueryClient.instance, // or custom client
  child: MyApp(),
)
```

#### QueryBuilder

Automatically manages data fetching and provides reactive UI updates.

```dart
QueryBuilder<List<Post>>(
  queryKey: 'posts',
  fetcher: () => postService.getAllPosts(),
  staleTime: Duration(minutes: 10),
  enabled: true, // Set to false to disable auto-fetch
  builder: (context, query) {
    if (query.isLoading) return LoadingSpinner();
    if (query.isError) return ErrorWidget(query.error);
    
    return PostList(posts: query.data ?? []);
  },
)
```

#### QueryConsumer

Lightweight widget for consuming cached data reactively.

```dart
QueryConsumer<String>(
  queryKey: 'user-status',
  builder: (context, query) {
    return StatusBadge(status: query.data ?? 'Unknown');
  },
)
```

### Query Object

The `Query<T>` object represents the state of a cached query.

#### Properties

```dart
T? data              // The cached data
Object? error        // Error from last failed fetch
QueryStatus status   // Current status (idle/loading/success/error)
DateTime? lastUpdated // When data was last updated
bool isLoading       // true if currently fetching
bool isSuccess       // true if has successful data
bool isError         // true if last operation failed
bool isIdle          // true if never executed
bool isStale         // true if data should be refetched
```

#### Methods

```dart
Stream<Query<T>> stream  // Reactive stream of state changes
```

## 🏗️ Advanced Usage

### Custom QueryClient

For complex applications, you can create multiple QueryClient instances:

```dart
final userClient = QueryClient();
final postClient = QueryClient();

// Use different clients for different data domains
QueryProvider(
  client: userClient,
  child: UserSection(),
)
```

### Mutations with Cache Updates

```dart
// Perform mutation and invalidate related queries
await QueryClient.instance.mutate(
  'update-user',
  (userData) => userService.updateUser(userData),
  newUserData,
  invalidateQueries: ['user-profile', 'user-list'],
);
```

### Optimistic Updates

```dart
// Update cache immediately, then sync with server
DartQuery.instance.put('user-name', 'New Name');

try {
  await userService.updateName('New Name');
} catch (error) {
  // Revert on error
  DartQuery.instance.invalidate('user-name');
  rethrow;
}
```

### Background Refetching

```dart
// Set up periodic data refresh
Timer.periodic(Duration(minutes: 5), (_) {
  DartQuery.instance.fetch(
    'notifications',
    () => notificationService.getUnread(),
    forceRefetch: true,
  );
});
```

## 🔍 Query Patterns

### Dependent Queries

```dart
class UserPostsWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return QueryBuilder<User>(
      queryKey: 'current-user',
      fetcher: () => userService.getCurrentUser(),
      builder: (context, userQuery) {
        if (userQuery.isLoading) return LoadingSpinner();
        if (userQuery.data == null) return LoginPrompt();
        
        // Dependent query - only fetch posts if user is loaded
        return QueryBuilder<List<Post>>(
          queryKey: 'user-posts-${userQuery.data!.id}',
          fetcher: () => postService.getUserPosts(userQuery.data!.id),
          builder: (context, postsQuery) {
            if (postsQuery.isLoading) return LoadingSpinner();
            return PostsList(posts: postsQuery.data ?? []);
          },
        );
      },
    );
  }
}
```

### Paginated Queries

```dart
class InfinitePostsList extends StatefulWidget {
  @override
  _InfinitePostsListState createState() => _InfinitePostsListState();
}

class _InfinitePostsListState extends State<InfinitePostsList> {
  int currentPage = 1;
  List<Post> allPosts = [];
  
  Future<void> loadNextPage() async {
    final newPosts = await DartQuery.instance.fetch(
      'posts-page-$currentPage',
      () => postService.getPosts(page: currentPage),
    );
    
    setState(() {
      allPosts.addAll(newPosts);
      currentPage++;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: allPosts.length + 1,
      itemBuilder: (context, index) {
        if (index == allPosts.length) {
          return LoadMoreButton(onTap: loadNextPage);
        }
        return PostTile(post: allPosts[index]);
      },
    );
  }
}
```

### Search Queries

```dart
class SearchScreen extends StatefulWidget {
  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String searchTerm = '';
  Timer? _debounceTimer;
  
  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: 500), () {
      setState(() {
        searchTerm = value;
      });
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          onChanged: _onSearchChanged,
          decoration: InputDecoration(hintText: 'Search...'),
        ),
        if (searchTerm.isNotEmpty)
          QueryBuilder<List<SearchResult>>(
            queryKey: 'search-$searchTerm',
            fetcher: () => searchService.search(searchTerm),
            builder: (context, query) {
              if (query.isLoading) return LoadingSpinner();
              return SearchResults(results: query.data ?? []);
            },
          ),
      ],
    );
  }
}
```

## 🧪 Testing

DartQuery is built with testing in mind. All components are fully testable.

### Testing Queries

```dart
testWidgets('should display user data', (tester) async {
  final client = QueryClient.forTesting();
  
  // Pre-populate test data
  client.setQueryData('user', User(name: 'Test User'));
  
  await tester.pumpWidget(
    QueryProvider(
      client: client,
      child: UserProfile(),
    ),
  );
  
  expect(find.text('Test User'), findsOneWidget);
  
  client.dispose();
});
```

### Mocking Network Calls

```dart
test('should handle fetch errors', () async {
  final mockFetcher = () async => throw 'Network error';
  
  expect(
    () => DartQuery.instance.fetch('test', mockFetcher),
    throwsA(equals('Network error')),
  );
});
```

## 🚀 Performance Tips

### 1. Appropriate Cache Times

```dart
// Frequently changing data
DartQuery.instance.fetch(
  'live-prices',
  fetcher,
  staleTime: Duration(seconds: 30),
);

// Rarely changing data
DartQuery.instance.fetch(
  'app-config',
  fetcher, 
  staleTime: Duration(hours: 24),
);
```

### 2. Query Key Strategies

```dart
// ✅ Good - Specific and cacheable
'user-${userId}'
'posts-${category}-page-${page}'

// ❌ Bad - Too generic or includes timestamps
'user-data'
'posts-${DateTime.now().millisecond}'
```

### 3. Selective Invalidation

```dart
// ✅ Good - Invalidate specific related queries
DartQuery.instance.invalidateAll([
  'user-profile',
  'user-preferences'
]);

// ❌ Bad - Clearing all cache unnecessarily
DartQuery.instance.clear();
```

### 4. Widget Optimization

```dart
// ✅ Good - Use QueryConsumer for display-only widgets
QueryConsumer<String>(
  queryKey: 'user-status',
  builder: (context, query) => StatusWidget(query.data),
)

// ✅ Good - Use QueryBuilder only when you need to fetch
QueryBuilder<User>(
  queryKey: 'user-profile',
  fetcher: () => userService.getProfile(),
  builder: (context, query) => ProfileWidget(query),
)
```

## 🛡️ Cache Management & Memory Control

DartQuery provides intelligent cache management to handle large applications and prevent memory issues.

### Cache Size Management

```dart
// Default configuration (suitable for most apps)
final client = QueryClient.withConfig(CacheConfig());

// Large application configuration
final client = QueryClient.withConfig(CacheConfig.large());

// Memory-constrained configuration  
final client = QueryClient.withConfig(CacheConfig.compact());

// Custom configuration
final client = QueryClient.withConfig(CacheConfig(
  maxQueries: 200,                    // Max 200 queries in cache
  maxMemoryBytes: 100 * 1024 * 1024,  // Max 100MB memory usage
  evictionPolicy: EvictionPolicy.lru, // Use LRU eviction
  enableMemoryPressureHandling: true, // React to system memory pressure
));
```

### Eviction Policies

Choose the best eviction strategy for your use case:

```dart
CacheConfig(
  evictionPolicy: EvictionPolicy.lru,  // Least Recently Used (default)
  evictionPolicy: EvictionPolicy.lrc,  // Least Recently Created  
  evictionPolicy: EvictionPolicy.lfu,  // Least Frequently Used
  evictionPolicy: EvictionPolicy.ttl,  // Time-based (staleness priority)
)
```

### Cache Monitoring

Monitor cache performance and memory usage:

```dart
// Get current cache statistics
final stats = client.getCacheStats();
print('Queries: ${stats.queryCount}');
print('Memory: ${(stats.memoryBytes / 1024 / 1024).toStringAsFixed(1)}MB');
print('Hit ratio: ${(stats.hitRatio * 100).toStringAsFixed(1)}%');
print('Evictions: ${stats.evictions}');

// Check if approaching limits
if (client.isCacheNearLimit()) {
  print('Cache is approaching configured limits');
}

// Force cleanup
client.cleanup();
```

### Memory Pressure Handling

DartQuery automatically responds to system memory pressure:

```dart
// Enable automatic memory pressure handling (default: true)
CacheConfig(enableMemoryPressureHandling: true)

// Manual memory pressure trigger (for testing)
MemoryPressureHandler.instance.triggerMemoryPressure();

// Get memory pressure information
final info = MemoryPressureHandler.instance.getMemoryPressureInfo();
print('Total memory: ${info.memoryMB.toStringAsFixed(1)}MB');
print('Under pressure: ${info.isUnderPressure}');
```

### Automatic Memory Management

DartQuery automatically manages memory to prevent leaks:

- **Smart Eviction** - Removes least important queries when limits are reached
- **Memory Pressure Response** - Automatically cleans up on system memory warnings
- **Timer Management** - All timers are properly cancelled on disposal
- **Stream Disposal** - Broadcast streams are closed when no longer needed
- **Widget Lifecycle** - QueryBuilder properly cleans up when disposed
- **Listener Tracking** - Queries with active listeners are protected from eviction

### Manual Cleanup

```dart
// Clear specific data when no longer needed
DartQuery.instance.remove('temporary-data');

// Clear all data (e.g., on logout)
DartQuery.instance.clear();

// Force cache cleanup
client.cleanup();

// Dispose custom clients
customClient.dispose();
```

### Cache Configuration Examples

**Mobile App (Memory Conscious):**
```dart
final client = QueryClient.withConfig(CacheConfig(
  maxQueries: 50,
  maxMemoryBytes: 20 * 1024 * 1024, // 20MB
  evictionPolicy: EvictionPolicy.lru,
  cleanupInterval: Duration(minutes: 2),
));
```

**Desktop App (Large Dataset):**
```dart
final client = QueryClient.withConfig(CacheConfig(
  maxQueries: 1000,
  maxMemoryBytes: 500 * 1024 * 1024, // 500MB
  evictionPolicy: EvictionPolicy.lfu,
  cleanupInterval: Duration(minutes: 10),
));
```

**Development/Testing (Unlimited):**
```dart
final client = QueryClient.withConfig(CacheConfig.unlimited());
```

## 🐛 Troubleshooting

### Common Issues

**Q: QueryBuilder not updating when data changes**
```dart
// ✅ Ensure you're using the same query key
QueryBuilder<User>(queryKey: 'user-123', ...)  // ✅
DartQuery.instance.put('user-123', newUser);   // ✅

// ❌ Different keys won't sync
QueryBuilder<User>(queryKey: 'user', ...)      // ❌
DartQuery.instance.put('user-123', newUser);   // ❌
```

**Q: Memory leaks in long-running apps**
```dart
// ✅ Configure appropriate cache limits
final client = QueryClient.withConfig(CacheConfig(
  maxQueries: 100,
  maxMemoryBytes: 50 * 1024 * 1024,
  evictionPolicy: EvictionPolicy.lru,
));

// ✅ Monitor cache usage
final stats = client.getCacheStats();
if (stats.memoryBytes > 100 * 1024 * 1024) {
  client.cleanup();
}

// ✅ Use appropriate cache times
DartQuery.instance.fetch(
  'temporary-data',
  fetcher,
  cacheTime: Duration(minutes: 1),
);
```

**Q: Cache growing too large**
```dart
// ✅ Enable automatic eviction
final client = QueryClient.withConfig(CacheConfig(
  maxQueries: 200,              // Limit number of queries
  maxMemoryBytes: 100 * 1024 * 1024, // Limit memory usage
  evictionPolicy: EvictionPolicy.lru,  // Remove least recently used
));

// ✅ Monitor and alert on cache size
Timer.periodic(Duration(minutes: 5), (_) {
  if (client.isCacheNearLimit()) {
    print('Warning: Cache approaching limits');
    client.cleanup();
  }
});
```

**Q: Tests failing due to shared state**
```dart
// ✅ Use separate clients for tests
testWidgets('test name', (tester) async {
  final client = QueryClient.forTesting();
  // ... test code
  client.dispose(); // Always dispose
});
```

### Debugging

Enable debug logging to see what DartQuery is doing:

```dart
// In your main() function
if (kDebugMode) {
  // Query state changes will be logged
  DartQuery.instance.watch<dynamic>('*').listen((query) {
    print('Query ${query.key}: ${query.status}');
  });
}
```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup

```bash
git clone https://github.com/your-repo/dartquery.git
cd dartquery
flutter pub get
flutter test
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by [TanStack Query](https://tanstack.com/query) (formerly React Query)
- Built with ❤️ for the Dart and Flutter community

---

**Made with ❤️ by the DartQuery team**

For more examples and advanced usage, check out our [documentation](https://dartquery.dev) and [examples repository](https://github.com/your-repo/dartquery-examples).