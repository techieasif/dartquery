import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'cache_manager.dart';

/// Handles memory pressure events from the system and triggers cache cleanup
class MemoryPressureHandler {
  static MemoryPressureHandler? _instance;
  static MemoryPressureHandler get instance => _instance ??= MemoryPressureHandler._();
  
  MemoryPressureHandler._();
  
  final List<CacheManager> _registeredManagers = [];
  bool _initialized = false;
  
  /// Registers a cache manager to receive memory pressure notifications
  void register(CacheManager manager) {
    if (!_registeredManagers.contains(manager)) {
      _registeredManagers.add(manager);
      _ensureInitialized();
    }
  }
  
  /// Unregisters a cache manager from memory pressure notifications
  void unregister(CacheManager manager) {
    _registeredManagers.remove(manager);
  }
  
  /// Manually triggers memory pressure handling (for testing or manual control)
  void triggerMemoryPressure() {
    _handleMemoryPressure();
  }
  
  void _ensureInitialized() {
    if (_initialized || !kIsWeb && !defaultTargetPlatform.toString().contains('android') && !defaultTargetPlatform.toString().contains('ios')) {
      return;
    }
    
    _initialized = true;
    
    // Listen for system memory pressure events
    try {
      SystemChannels.system.setMessageHandler(_handleSystemMessage);
    } catch (e) {
      debugPrint('DartQuery: Failed to set up memory pressure handling: $e');
    }
  }
  
  Future<dynamic> _handleSystemMessage(dynamic message) async {
    if (message == null) return;
    
    final Map<String, dynamic> messageMap = message as Map<String, dynamic>;
    
    // Handle memory pressure warnings
    if (messageMap['type'] == 'memoryPressure') {
      _handleMemoryPressure();
    }
    
    return null;
  }
  
  void _handleMemoryPressure() {
    debugPrint('DartQuery: Handling memory pressure - cleaning up caches');
    
    // Trigger aggressive cleanup on all registered cache managers
    for (final manager in _registeredManagers) {
      try {
        manager.cleanup();
        
        // Log cache stats after cleanup
        final stats = manager.getStats();
        debugPrint('DartQuery: Cache cleanup completed. ${stats.toString()}');
      } catch (e) {
        debugPrint('DartQuery: Error during cache cleanup: $e');
      }
    }
  }
  
  /// Gets memory pressure status and recommendations
  MemoryPressureInfo getMemoryPressureInfo() {
    int totalQueries = 0;
    int totalMemory = 0;
    int managersNearLimit = 0;
    
    for (final manager in _registeredManagers) {
      final stats = manager.getStats();
      totalQueries += stats.queryCount;
      totalMemory += stats.memoryBytes;
      
      if (manager.isNearLimit()) {
        managersNearLimit++;
      }
    }
    
    return MemoryPressureInfo(
      totalCacheManagers: _registeredManagers.length,
      totalQueries: totalQueries,
      totalMemoryBytes: totalMemory,
      managersNearLimit: managersNearLimit,
      isUnderPressure: managersNearLimit > 0,
    );
  }
}

/// Information about current memory pressure and cache usage
class MemoryPressureInfo {
  final int totalCacheManagers;
  final int totalQueries;
  final int totalMemoryBytes;
  final int managersNearLimit;
  final bool isUnderPressure;
  
  const MemoryPressureInfo({
    required this.totalCacheManagers,
    required this.totalQueries,
    required this.totalMemoryBytes,
    required this.managersNearLimit,
    required this.isUnderPressure,
  });
  
  /// Memory usage in megabytes
  double get memoryMB => totalMemoryBytes / (1024 * 1024);
  
  /// Average queries per cache manager
  double get avgQueriesPerManager => 
      totalCacheManagers > 0 ? totalQueries / totalCacheManagers : 0;
  
  @override
  String toString() {
    return 'MemoryPressureInfo('
           'managers: $totalCacheManagers, '
           'queries: $totalQueries, '
           'memory: ${memoryMB.toStringAsFixed(1)}MB, '
           'nearLimit: $managersNearLimit, '
           'underPressure: $isUnderPressure)';
  }
}