# DartQuery Example App

A comprehensive example demonstrating all features of DartQuery including cache management, reactive data fetching, and memory optimization.

## Features Demonstrated

### 🔧 Cache Management Demo
- **Real-time cache statistics** - Monitor queries, memory usage, and hit ratios
- **Cache actions** - Force cleanup, simulate memory pressure, clear cache
- **Memory pressure info** - View system-wide memory statistics
- **Visual warnings** - Orange highlighting when approaching cache limits

### 👥 User Profiles Demo
- **Efficient data fetching** - Each user profile is fetched independently
- **Visual state indicators** - Shows loading, error, fresh, and stale states
- **Error handling** - Retry failed requests with refresh button
- **Large data simulation** - Each user has a bio field with substantial content
- **Stale/fresh indicators** - Visual feedback on data freshness

### 📜 Infinite Posts Demo
- **Pagination support** - Loads 20 posts per page
- **Scroll-based loading** - Automatically loads more when near bottom
- **Pull-to-refresh** - Swipe down to refresh all posts
- **Memory efficient** - Old pages can be evicted when memory is needed
- **Large content** - Each post contains substantial text to test memory limits

### 📊 Live Stats Demo
- **Auto-refresh** - Stats update every 5 seconds automatically
- **Loading states** - Shows progress bar during background refresh
- **Relative timestamps** - Shows "Xs ago" format for last update
- **Fresh/stale indicators** - Visual feedback on data status
- **Beautiful cards** - Stats displayed in material design cards

## Cache Configuration

The example app uses a balanced cache configuration:

```dart
CacheConfig(
  maxQueries: 50,                    // Maximum 50 queries
  maxMemoryBytes: 10 * 1024 * 1024,  // 10MB memory limit
  evictionPolicy: EvictionPolicy.lru, // Least Recently Used
  enableMemoryPressureHandling: true, // React to system memory warnings
  cleanupInterval: Duration(minutes: 1), // Cleanup every minute
)
```

## Running the Example

1. Navigate to the example directory:
   ```bash
   cd example
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   flutter run
   ```

## Testing Cache Behavior

### 1. Fill the Cache
- Navigate to "Users" tab and scroll through all 20 users
- Switch to "Posts" and scroll to load multiple pages
- Go to "Stats" to add live data queries

### 2. Monitor Cache Stats
- Return to "Cache" tab to see:
  - Number of queries in cache
  - Memory usage in MB
  - Cache hit ratio
  - Eviction count

### 3. Test Eviction
- Continue loading more data until you see the orange warning
- Watch as older queries are automatically evicted
- Notice queries with active UI listeners are protected

### 4. Test Memory Pressure
- Tap "Simulate Memory Pressure" button
- Observe aggressive cache cleanup
- Check reduced memory usage

### 5. Test Error Handling
- The API randomly fails ~20% of requests
- See error states in User Profiles
- Use refresh buttons to retry

## Code Structure

### API Service
Simulates a real API with:
- Network delays (0.5-2 seconds)
- Random failures (~20% error rate)
- Large response payloads
- Realistic data structures

### State Management
- Uses `QueryBuilder` for reactive UI updates
- `QueryConsumer` for lightweight data display
- Manual invalidation for refresh actions
- Stream-based monitoring for real-time stats

### Memory Testing
- Large bio fields in user profiles
- Long content in posts
- Configurable cache limits
- Visual feedback when approaching limits

## Key Patterns Demonstrated

1. **Dependent Queries** - Posts depend on successful initial load
2. **Optimistic Updates** - Stats show loading state while keeping old data
3. **Error Recovery** - All screens handle and recover from errors
4. **Memory Efficiency** - Automatic cleanup of unused queries
5. **Real-time Monitoring** - Live cache statistics updates

## Customization

Modify the cache configuration in `main.dart` to test different scenarios:

- **Memory Constrained**: Use `CacheConfig.compact()`
- **Large Application**: Use `CacheConfig.large()`
- **No Limits**: Use `CacheConfig.unlimited()`
- **Custom Settings**: Create your own configuration

## Screenshots

The app includes four main screens accessible via bottom navigation:

1. **Cache Management** - Monitor and control cache behavior
2. **User Profiles** - List of users with individual query states
3. **Infinite Posts** - Paginated content with scroll loading
4. **Live Stats** - Auto-refreshing dashboard with real-time data