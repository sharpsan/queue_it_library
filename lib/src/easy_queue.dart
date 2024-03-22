import 'dart:async';

import 'package:easy_queue/src/callbacks/item_handler.dart';
import 'package:easy_queue/src/extensions/queue_items_extension.dart';
import 'package:easy_queue/src/models/queue_event.dart';
import 'package:easy_queue/src/models/queue_item.dart';
import 'package:easy_queue/src/models/queue_item_status.dart';
import 'package:easy_queue/src/models/queue_snapshot.dart';
import 'package:uuid/uuid.dart';

class EasyQueue<T> {
  EasyQueue({
    this.itemHandler,
    this.retryCount = 3,
  }) {
    _currentBatchId = const Uuid().v4();
  }

  final List<QueueItem<T>> _items = [];
  final _onUpdateStreamController =
      StreamController<QueueSnapshot<T>>.broadcast();
  late String _currentBatchId;
  var _isProcessing = false;

  /// The number of times to retry processing an item before marking it as failed.
  final int retryCount;

  /// The function that will be called to process each item in the queue.
  ItemHandler<T>? itemHandler;

  /// The current batch id
  String get currentBatchId => _currentBatchId;

  /// Whether the queue is currently processing items.
  bool get isProcessing => _isProcessing;

  /// The items in the current queue.
  Iterable<QueueItem<T>> get currentBatchItems => items(_currentBatchId);

  /// All items in the queue.
  /// If [batchId] is provided, only items in that batch will be returned.
  Iterable<QueueItem<T>> items([String? batchId]) =>
      _items.where((e) => batchId == null || e.batchId == batchId);

  /// A snapshot of the current state of the queue.
  Stream<QueueSnapshot<T>> get onUpdate => _onUpdateStreamController.stream;

  /// Starts the queue.
  /// If the queue is already running, this will do nothing.
  Future<void> start() async {
    //TODO: when started, we need to detect when new items are added to the queue and process them immediately
    //TODO: we should not stop the queue processing until the user explicitly stops it

    if (_isProcessing) return;
    if (_items.isEmpty) return;
    if (_items.pending.isEmpty) return;
    _isProcessing = true;
    _sendOnUpdateEvent(QueueEvent.started, null);
    try {
      await _processQueueItems();
    } finally {
      _sendOnUpdateEvent(QueueEvent.stopped, null);
      _currentBatchId = const Uuid().v4();
      _isProcessing = false;
    }
  }

  /// Stops the queue from processing any more items.
  /// If the queue is currently processing an item, it will finish processing that item before stopping.
  void stop() {
    if (!_isProcessing) return;
    _isProcessing = false;
    _sendOnUpdateEvent(QueueEvent.stopped, null);
  }

  /// Adds an item to the queue.
  void add(T data) {
    _items.add(
      QueueItem(
        data: data,
        queuedAt: DateTime.now(),
        status: QueueItemStatus.pending,
        batchId: _currentBatchId,
      ),
    );
    _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, null);
  }

  /// Clears a single item in the queue.
  /// If the item is currently being processed, this will throw a [StateError].
  void clear(QueueItem<T> item) {
    if (isProcessing) throw StateError('Cannot clear queue while processing');
    final itemCopy = item.copyWith()..status = QueueItemStatus.cleared;
    _items.remove(item);
    _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, itemCopy);
  }

  /// Clears all items in the queue.
  /// If any items are currently being processed, this will throw a [StateError].
  void clearAll() {
    if (isProcessing) throw StateError('Cannot clear queue while processing');
    _items.clear();
    _sendOnUpdateEvent(QueueEvent.clearAll, null);
  }

  /// Cancels a single item in the queue.
  void cancel(QueueItem<T> item) {
    _cancel(item);
    _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
  }

  /// Cancels all items in the queue.
  void cancelAll() {
    for (final item in _items) {
      _cancel(item);
    }
    _sendOnUpdateEvent(QueueEvent.cancelAll, null);
  }

  void _cancel(QueueItem<T> item) {
    if (item.status == QueueItemStatus.completed) return;
    _items[_items.indexOf(item)]
      ..status = QueueItemStatus.canceled
      ..canceledAt = DateTime.now();
  }

  /// Disposes of the [EasyQueue] instance.
  void dispose() {
    stop();
    _onUpdateStreamController.close();
  }

  //////// INTERNALS ////////

  /// Processes all items in the queue.
  Future<void> _processQueueItems() async {
    int i = 0;
    while (i < _items.length) {
      if (!isProcessing) return;
      await _processQueueItem(_items[i]);
      i++;
    }
  }

  /// Processes a single item in the queue.
  Future<void> _processQueueItem(QueueItem<T> item) async {
    /// handle the item based on it's status
    switch (item.status) {
      case QueueItemStatus.processing:
      case QueueItemStatus.completed:
      case QueueItemStatus.canceled:
      case QueueItemStatus.cleared:
        break;
      case QueueItemStatus.pending:
        await _handleQueuedItem(item);
      case QueueItemStatus.failed:
        _handleFailedItem(item);
    }
  }

  /// Handles a queued item by calling the [itemHandler] function.
  Future<void> _handleQueuedItem(QueueItem<T> item) async {
    try {
      item
        ..status = QueueItemStatus.processing
        ..startedProcessingAt = DateTime.now();
      _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
      await itemHandler?.call(item);
      item
        ..status = QueueItemStatus.completed
        ..completedAt = DateTime.now();
      _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
    } catch (e) {
      item
        ..status = QueueItemStatus.failed
        ..failedAt = DateTime.now();
      _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
    }
  }

  /// Handles a failed item by either retrying it or marking it as failed.
  void _handleFailedItem(QueueItem<T> item) {
    if (item.retryCount < retryCount) {
      item.status = QueueItemStatus.pending;
      item.retryCount++;
      _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
    } else {
      item
        ..status = QueueItemStatus.canceled
        ..canceledAt = DateTime.now();
      _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
    }
  }

  /// Sends an [QueueSnapshot] event to the [onUpdate] stream.
  void _sendOnUpdateEvent(
    QueueEvent event,
    QueueItem<T>? item,
  ) {
    _onUpdateStreamController.add(
      QueueSnapshot(
        event: event,
        isRunning: _isProcessing,
        currentBatchId: _currentBatchId,
        updatedItem: item?.copyWith(),
        items: currentBatchItems.map((e) => e.copyWith()).toList(),
      ),
    );
  }
}
