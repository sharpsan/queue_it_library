import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_queue_it/flutter_queue_it.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MaterialApp(home: ImageQueuePage()));
}

/// Downloads images three at a time. Some attempts fail on purpose, so you
/// can watch the retries, and the images that run out of retries.
class ImageQueuePage extends StatefulWidget {
  const ImageQueuePage({super.key});

  @override
  State<ImageQueuePage> createState() => _ImageQueuePageState();
}

class _ImageQueuePageState extends State<ImageQueuePage> {
  final _random = math.Random();

  /// The downloaded images, by item id.
  final _images = <String, Uint8List>{};

  late final _queue = QueueIt<String>(
    parallel: 3,
    retries: 2,
    retryDelay: (retry) => Duration(seconds: retry),
    useFriendlyIds: true,
    itemHandler: _download,
  );

  Future<void> _download(QueueItem<String> item) async {
    // Slow the downloads down and make some of them fail, so the queue's
    // work is easy to follow.
    await Future<void>.delayed(
      Duration(milliseconds: 500 + _random.nextInt(1500)),
    );
    // The queue doesn't stop a handler when its image is canceled or removed,
    // so check before going on.
    if (item.status != QueueItemStatus.processing) return;
    if (_random.nextDouble() < 0.3) {
      throw Exception('Simulated network error');
    }
    final response = await http.get(Uri.parse(item.data));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    if (item.status != QueueItemStatus.processing) return;
    _images[item.id] = response.bodyBytes;
  }

  @override
  void dispose() {
    _queue.dispose();
    super.dispose();
  }

  void _addImages() {
    for (var i = 0; i < 5; i++) {
      _queue.add('https://picsum.photos/seed/${_random.nextInt(100000)}/200');
    }
  }

  void _remove(QueueItem<String> item) {
    _queue.remove(item);
    _images.remove(item.id);
  }

  void _removeFinished() {
    for (final item in _queue.items().toList()) {
      if (item.status
          case QueueItemStatus.completed ||
              QueueItemStatus.failed ||
              QueueItemStatus.canceled) {
        _remove(item);
      }
    }
  }

  /// Tells the user when an image has run out of retries.
  void _showFailure(BuildContext context, QueueSnapshot<String> snapshot) {
    final item = snapshot.eventItem;
    // Every failed attempt sends a failed status. Only the last one stays.
    if (item == null ||
        item.status != QueueItemStatus.failed ||
        item.retryCount < _queue.retries) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.id} failed: ${item.error}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('queue_it'),
        actions: [
          IconButton(
            onPressed: _removeFinished,
            tooltip: 'Remove finished images',
            icon: const Icon(Icons.clear_all),
          ),
        ],
      ),
      body: QueueItListener<String>(
        queue: _queue,
        listener: _showFailure,
        child: QueueItWidget<String>(
          queue: _queue,
          builder: (context, snapshot) {
            final items = _queue.items().toList();
            return Column(
              children: [
                if (_queue.isProcessing)
                  LinearProgressIndicator(
                    value: _queue.currentBatchItems.progress,
                  ),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('Add images to download'))
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 100),
                          itemCount: items.length,
                          itemBuilder: (context, index) =>
                              _buildItem(items[index]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
      // Only the start and stop events change the buttons.
      floatingActionButton: QueueItWidget<String>(
        queue: _queue,
        buildWhen: (snapshot) =>
            snapshot.event == QueueEvent.startedQueue ||
            snapshot.event == QueueEvent.stoppedQueue,
        builder: (context, snapshot) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_queue.isStarted)
              FloatingActionButton(
                heroTag: 'stop',
                onPressed: _queue.stop,
                tooltip: 'Stop the queue',
                backgroundColor: Colors.red,
                child: const Icon(Icons.stop),
              )
            else
              FloatingActionButton(
                heroTag: 'start',
                // Keep the queue running, so images added later download
                // right away.
                onPressed: () => _queue.start(stopAutomatically: false),
                tooltip: 'Start the queue',
                backgroundColor: Colors.green,
                child: const Icon(Icons.play_arrow),
              ),
            const SizedBox(width: 16),
            FloatingActionButton(
              heroTag: 'add',
              onPressed: _addImages,
              tooltip: 'Add five images',
              child: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(QueueItem<String> item) {
    final image = _images[item.id];
    final active = item.status == QueueItemStatus.pending ||
        item.status == QueueItemStatus.processing;
    return Dismissible(
      key: ValueKey(item.id),
      onDismissed: (direction) => _remove(item),
      child: ListTile(
        leading: SizedBox.square(
          dimension: 48,
          child: image != null
              ? Image.memory(image, fit: BoxFit.cover)
              : Icon(_iconFromStatus(item.status)),
        ),
        title: Text(item.id),
        subtitle: Text(_describe(item)),
        trailing: active
            ? IconButton(
                onPressed: () => _queue.cancel(item),
                tooltip: 'Cancel',
                icon: const Icon(Icons.close),
              )
            : null,
      ),
    );
  }

  String _describe(QueueItem<String> item) {
    final retry = item.retryCount;
    switch (item.status) {
      case QueueItemStatus.pending:
        return retry == 0
            ? 'Waiting'
            : 'Waiting for retry $retry of ${_queue.retries}: ${item.error}';
      case QueueItemStatus.processing:
        return retry == 0 ? 'Downloading' : 'Downloading, retry $retry';
      case QueueItemStatus.completed:
        final time = item.completedAt!.difference(item.startedProcessingAt!);
        return 'Downloaded in ${time.inMilliseconds} ms';
      case QueueItemStatus.failed:
        return 'Failed: ${item.error}';
      case QueueItemStatus.canceled:
        return 'Canceled';
      case QueueItemStatus.removed:
        return 'Removed';
    }
  }

  /// Returns an icon based on the status of the item
  IconData _iconFromStatus(QueueItemStatus status) {
    switch (status) {
      case QueueItemStatus.pending:
        return Icons.timer;
      case QueueItemStatus.processing:
        return Icons.hourglass_top;
      case QueueItemStatus.completed:
        return Icons.check;
      case QueueItemStatus.failed:
        return Icons.error;
      case QueueItemStatus.canceled:
        return Icons.cancel;

      /// unused
      case QueueItemStatus.removed:
        return Icons.delete;
    }
  }
}
