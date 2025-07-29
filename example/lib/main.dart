import 'package:flutter/material.dart';
import 'package:dartquery/dartquery.dart';
import 'dart:async';
import 'dart:math';

// Simulated API service
class ApiService {
  static final Random _random = Random();
  
  static Future<Map<String, dynamic>> fetchUser(int id) async {
    await Future.delayed(Duration(seconds: 1));
    if (_random.nextInt(10) < 2) {
      throw 'Network error: Failed to fetch user';
    }
    return {
      'id': id,
      'name': 'User $id',
      'email': 'user$id@example.com',
      'avatar': 'https://i.pravatar.cc/150?u=$id',
      'bio': 'This is the bio for user $id. ' * 10, // Large data
    };
  }
  
  static Future<List<Map<String, dynamic>>> fetchPosts(int page) async {
    await Future.delayed(Duration(milliseconds: 800));
    return List.generate(20, (i) => {
      'id': page * 20 + i,
      'title': 'Post ${page * 20 + i}',
      'content': 'Content for post ${page * 20 + i}. ' * 50, // Large content
      'author': 'User ${_random.nextInt(100)}',
      'likes': _random.nextInt(1000),
      'comments': _random.nextInt(100),
    });
  }
  
  static Future<Map<String, dynamic>> fetchStats() async {
    await Future.delayed(Duration(milliseconds: 500));
    return {
      'totalUsers': _random.nextInt(10000),
      'totalPosts': _random.nextInt(50000),
      'activeUsers': _random.nextInt(1000),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}

void main() {
  // Configure cache for the example app
  final cacheConfig = CacheConfig(
    maxQueries: 50,                    // Limit to 50 queries
    maxMemoryBytes: 10 * 1024 * 1024,  // 10MB memory limit
    evictionPolicy: EvictionPolicy.lru, // Use LRU eviction
    enableMemoryPressureHandling: true,
    cleanupInterval: Duration(minutes: 1),
  );
  
  runApp(MyApp(cacheConfig: cacheConfig));
}

class MyApp extends StatelessWidget {
  final CacheConfig cacheConfig;
  
  const MyApp({Key? key, required this.cacheConfig}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DartQuery Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: QueryProvider(
        client: QueryClient.withConfig(cacheConfig),
        child: HomePage(),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  
  final List<Widget> _pages = [
    CacheManagementDemo(),
    UserProfilesDemo(),
    InfinitePostsDemo(),
    LiveStatsDemo(),
  ];
  
  final List<String> _titles = [
    'Cache Management',
    'User Profiles',
    'Infinite Posts',
    'Live Stats',
  ];
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('DartQuery: ${_titles[_selectedIndex]}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.storage),
            label: 'Cache',
          ),
          NavigationDestination(
            icon: Icon(Icons.person),
            label: 'Users',
          ),
          NavigationDestination(
            icon: Icon(Icons.list),
            label: 'Posts',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics),
            label: 'Stats',
          ),
        ],
      ),
    );
  }
}

// Cache Management Demo
class CacheManagementDemo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final client = QueryProvider.of(context);
    
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cache Statistics',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          SizedBox(height: 16),
          StreamBuilder(
            stream: Stream.periodic(Duration(seconds: 1)),
            builder: (context, snapshot) {
              final stats = client.getCacheStats();
              final isNearLimit = client.isCacheNearLimit();
              
              return Card(
                color: isNearLimit ? Colors.orange.shade50 : null,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _StatRow('Queries in Cache', '${stats.queryCount}'),
                      _StatRow('Memory Usage', '${(stats.memoryBytes / 1024 / 1024).toStringAsFixed(2)} MB'),
                      _StatRow('Cache Hit Ratio', '${(stats.hitRatio * 100).toStringAsFixed(1)}%'),
                      _StatRow('Total Hits', '${stats.hits}'),
                      _StatRow('Total Misses', '${stats.misses}'),
                      _StatRow('Evictions', '${stats.evictions}'),
                      _StatRow('Expirations', '${stats.expirations}'),
                      if (isNearLimit)
                        Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            '⚠️ Cache is approaching size limits',
                            style: TextStyle(color: Colors.orange.shade700),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          SizedBox(height: 16),
          Text(
            'Cache Actions',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  client.cleanup();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Cache cleanup completed')),
                  );
                },
                icon: Icon(Icons.cleaning_services),
                label: Text('Force Cleanup'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  // Simulate memory pressure
                  MemoryPressureHandler.instance.triggerMemoryPressure();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Memory pressure triggered')),
                  );
                },
                icon: Icon(Icons.memory),
                label: Text('Simulate Memory Pressure'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  client.clear();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Cache cleared')),
                  );
                },
                icon: Icon(Icons.clear),
                label: Text('Clear All'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            'Memory Pressure Info',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: 8),
          StreamBuilder(
            stream: Stream.periodic(Duration(seconds: 2)),
            builder: (context, snapshot) {
              final info = MemoryPressureHandler.instance.getMemoryPressureInfo();
              
              return Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _StatRow('Total Memory', '${info.memoryMB.toStringAsFixed(2)} MB'),
                      _StatRow('Cache Managers', '${info.totalCacheManagers}'),
                      _StatRow('Total Queries', '${info.totalQueries}'),
                      _StatRow('Under Pressure', info.isUnderPressure ? 'Yes' : 'No'),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// User Profiles Demo
class UserProfilesDemo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.all(8),
      itemCount: 20,
      itemBuilder: (context, index) {
        final userId = index + 1;
        
        return Card(
          margin: EdgeInsets.symmetric(vertical: 4),
          child: QueryBuilder<Map<String, dynamic>>(
            queryKey: 'user-$userId',
            fetcher: () => ApiService.fetchUser(userId),
            staleTime: Duration(minutes: 5),
            builder: (context, query) {
              if (query.isLoading) {
                return ListTile(
                  leading: CircleAvatar(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text('Loading...'),
                );
              }
              
              if (query.isError) {
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.red,
                    child: Icon(Icons.error, color: Colors.white),
                  ),
                  title: Text('Error loading user'),
                  subtitle: Text(query.error.toString()),
                  trailing: IconButton(
                    icon: Icon(Icons.refresh),
                    onPressed: () {
                      DartQuery.instance.invalidate('user-$userId');
                    },
                  ),
                );
              }
              
              final user = query.data!;
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: NetworkImage(user['avatar']),
                ),
                title: Text(user['name']),
                subtitle: Text(user['email']),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      query.isStale ? Icons.access_time : Icons.check_circle,
                      color: query.isStale ? Colors.orange : Colors.green,
                      size: 16,
                    ),
                    Text(
                      query.isStale ? 'Stale' : 'Fresh',
                      style: TextStyle(fontSize: 10),
                    ),
                  ],
                ),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(user['name']),
                      content: SingleChildScrollView(
                        child: Text(user['bio']),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

// Infinite Posts Demo
class InfinitePostsDemo extends StatefulWidget {
  @override
  _InfinitePostsDemoState createState() => _InfinitePostsDemoState();
}

class _InfinitePostsDemoState extends State<InfinitePostsDemo> {
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  List<Map<String, dynamic>> _allPosts = [];
  bool _isLoadingMore = false;
  
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  
  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }
  
  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    
    setState(() {
      _isLoadingMore = true;
    });
    
    try {
      final newPosts = await DartQuery.instance.fetch(
        'posts-page-$_currentPage',
        () => ApiService.fetchPosts(_currentPage),
        staleTime: Duration(minutes: 10),
      );
      
      setState(() {
        _allPosts.addAll(newPosts);
        _currentPage++;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return QueryBuilder<List<Map<String, dynamic>>>(
      queryKey: 'posts-page-1',
      fetcher: () => ApiService.fetchPosts(1),
      builder: (context, query) {
        if (query.isLoading && _allPosts.isEmpty) {
          return Center(child: CircularProgressIndicator());
        }
        
        if (query.isError && _allPosts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red),
                SizedBox(height: 16),
                Text('Failed to load posts'),
                SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    DartQuery.instance.invalidate('posts-page-1');
                  },
                  child: Text('Retry'),
                ),
              ],
            ),
          );
        }
        
        if (query.data != null && _allPosts.isEmpty) {
          _allPosts = List.from(query.data!);
        }
        
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _currentPage = 1;
              _allPosts.clear();
            });
            DartQuery.instance.invalidate('posts-page-1');
          },
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.all(8),
            itemCount: _allPosts.length + (_isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _allPosts.length) {
                return Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              
              final post = _allPosts[index];
              return Card(
                margin: EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(
                    post['title'],
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 4),
                      Text(
                        post['content'],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.person, size: 16),
                          SizedBox(width: 4),
                          Text(post['author']),
                          SizedBox(width: 16),
                          Icon(Icons.favorite, size: 16, color: Colors.red),
                          SizedBox(width: 4),
                          Text('${post['likes']}'),
                          SizedBox(width: 16),
                          Icon(Icons.comment, size: 16, color: Colors.blue),
                          SizedBox(width: 4),
                          Text('${post['comments']}'),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// Live Stats Demo
class LiveStatsDemo extends StatefulWidget {
  @override
  _LiveStatsDemoState createState() => _LiveStatsDemoState();
}

class _LiveStatsDemoState extends State<LiveStatsDemo> {
  Timer? _timer;
  
  @override
  void initState() {
    super.initState();
    // Auto-refresh stats every 5 seconds
    _timer = Timer.periodic(Duration(seconds: 5), (_) {
      DartQuery.instance.invalidate('live-stats');
    });
  }
  
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: QueryBuilder<Map<String, dynamic>>(
          queryKey: 'live-stats',
          fetcher: () => ApiService.fetchStats(),
          staleTime: Duration(seconds: 5),
          builder: (context, query) {
            if (query.isLoading && query.data == null) {
              return CircularProgressIndicator();
            }
            
            final stats = query.data ?? {};
            final isRefreshing = query.isLoading && query.data != null;
            
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Live Statistics',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                SizedBox(height: 8),
                if (isRefreshing)
                  LinearProgressIndicator(),
                SizedBox(height: 24),
                _StatCard(
                  icon: Icons.people,
                  label: 'Total Users',
                  value: '${stats['totalUsers'] ?? 0}',
                  color: Colors.blue,
                ),
                SizedBox(height: 16),
                _StatCard(
                  icon: Icons.article,
                  label: 'Total Posts',
                  value: '${stats['totalPosts'] ?? 0}',
                  color: Colors.green,
                ),
                SizedBox(height: 16),
                _StatCard(
                  icon: Icons.online_prediction,
                  label: 'Active Users',
                  value: '${stats['activeUsers'] ?? 0}',
                  color: Colors.orange,
                ),
                SizedBox(height: 24),
                Text(
                  'Last updated: ${_formatTimestamp(stats['timestamp'])}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      query.isStale ? Icons.access_time : Icons.check_circle,
                      color: query.isStale ? Colors.orange : Colors.green,
                    ),
                    SizedBox(width: 8),
                    Text(
                      query.isStale ? 'Data is stale' : 'Data is fresh',
                      style: TextStyle(
                        color: query.isStale ? Colors.orange : Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
  
  String _formatTimestamp(String? timestamp) {
    if (timestamp == null) return 'Never';
    try {
      final dt = DateTime.parse(timestamp);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inSeconds < 60) {
        return '${diff.inSeconds}s ago';
      } else if (diff.inMinutes < 60) {
        return '${diff.inMinutes}m ago';
      } else {
        return '${diff.inHours}h ago';
      }
    } catch (e) {
      return 'Invalid';
    }
  }
}

// Utility Widgets
class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  
  const _StatRow(this.label, this.value);
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}