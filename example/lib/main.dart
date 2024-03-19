import 'package:easy_queue/easy_queue.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final _queue = EasyQueue<String>();

  @override
  void initState() {
    _queue
      ..addOnStartListener((batchId) {
        print('Queue started: $batchId');
      })
      ..addOnUpdateListener((status, item) {
        print('Queue updated: $status');
      })
      ..addOnDoneListener((processedItems) {
        print('Queue done: $processedItems');
      });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('easy_queue Example'),
      ),
      body: const Center(
        child: Text('Hello, World!'),
      ),
    );
  }
}
