import 'package:flutter/material.dart';
import 'package:dartquery/dartquery.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: QueryProvider(
        client: QueryClient.instance,
        child: HomePage(),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('DartQuery Example')),
      body: Column(
        children: [
          // Basic usage example
          QueryBuilder<String>(
            queryKey: 'user-data',
            fetcher: () => Future.delayed(
              Duration(seconds: 2),
              () => 'Hello from DartQuery!',
            ),
            builder: (context, query) {
              if (query.isLoading) {
                return Center(child: CircularProgressIndicator());
              }
              if (query.isError) {
                return Center(child: Text('Error: ${query.error}'));
              }
              return Center(child: Text(query.data ?? 'No data'));
            },
          ),
          
          // Manual data manipulation
          ElevatedButton(
            onPressed: () {
              DartQuery.instance.put('manual-data', 'Manually set data');
            },
            child: Text('Set Manual Data'),
          ),
          
          QueryConsumer<String>(
            queryKey: 'manual-data',
            builder: (context, query) {
              return Text('Manual: ${query.data ?? 'No data'}');
            },
          ),
        ],
      ),
    );
  }
}