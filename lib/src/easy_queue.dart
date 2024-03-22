import 'dart:async';

import 'package:easy_queue/extensions.dart';
import 'package:easy_queue/src/callbacks/item_handler.dart';
import 'package:easy_queue/src/models/queue_event.dart';
import 'package:easy_queue/src/models/queue_item.dart';
import 'package:easy_queue/src/models/queue_item_status.dart';
import 'package:easy_queue/src/models/queue_snapshot.dart';
import 'package:easy_queue/src/models/semaphore.dart';
import 'package:uuid/uuid.dart';

class EasyQueue<T> {
  EasyQueue({
    this.itemHandler,
    this.retryCount = 3,
    this.concurrentOperations = 1,
  }) {
    _currentBatchId = const Uuid().v4();
  }

  final _items = <QueueItem<T>>[];
  final _onUpdateStreamController =
      StreamController<QueueSnapshot<T>>.broadcast();
  late String _currentBatchId;
  late final _semaphore = Semaphore(concurrentOperations);
  var _isStarted = false;
  var _isProcessing = false;

  /// An internal stream controller is being used for tracking item processing events
  /// to eliminate the chances of a user disposing the `onUpdate` [StreamController].
  final _itemController = StreamController<QueueItem<T>>.broadcast(
    sync: true, //TODO: do I need sync?
  );

  StreamSubscription<QueueItem<T>>? _itemSubscription;

  /// The number of concurrent operations that can be processed at once.
  final int concurrentOperations;

  /// The number of times to retry processing an item before marking it as failed.
  final int retryCount;

  /// The function that will be called to process each item in the queue.
  ItemHandler<T>? itemHandler;

  /// The current batch id
  String get currentBatchId => _currentBatchId;

  /// Whether the queue is currently processing items.
  bool get isProcessing => _isProcessing;

  bool get isStarted => _isStarted;

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
  void start() async {
    if (_isStarted) return;
    _isStarted = true;
    _sendOnUpdateEvent(QueueEvent.startedQueue, null);
    _processQueueItemsOnDemand();
  }

  /// Stops the queue from processing any more items.
  /// If the queue is currently processing an item, it will finish processing that item before stopping.
  void stop() {
    if (!_isStarted) return;
    _isStarted = false;
    _sendOnUpdateEvent(QueueEvent.stoppedQueue, null);
    _itemSubscription?.cancel();
  }

  /// Adds an item to the queue.
  void add(T data) {
    /// if the queue is empty, assign a new batch id
    if (_items.isEmpty) _currentBatchId = const Uuid().v4();

    final item = QueueItem(
      data: data,
      queuedAt: DateTime.now(),
      status: QueueItemStatus.pending,
      batchId: _currentBatchId,
    );
    _items.add(item);
    _sendOnUpdateEvent(QueueEvent.itemAdded, item.copyWith());
    _itemController.add(item);
  }

  /// Removes a single item in the queue.
  void remove(QueueItem<T> item) {
    final itemCopy = item.copyWith()..status = QueueItemStatus.removed;
    _items.remove(item);
    _sendOnUpdateEvent(QueueEvent.itemRemoved, itemCopy);
  }

  /// Removes all items in the queue.
  void removeAll() {
    _items.clear();
    _sendOnUpdateEvent(QueueEvent.removedAll, null);
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
    _sendOnUpdateEvent(QueueEvent.cancelledAll, null);
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
    _itemController.close();
  }

  //////// INTERNALS ////////

  /// Processes the queue items as they become available.
  void _processQueueItemsOnDemand() async {
    _itemSubscription = _itemController.stream.listen((event) async {
      if (!_isProcessing) {
        _isProcessing = true;
        _sendOnUpdateEvent(QueueEvent.startedProcessing, null);
      }
      await _semaphore.acquire();
      await _processQueueItem(event);
      _semaphore.release();

      // Check if there are any more items in the queue
      if (_items.pending.isEmpty) {
        _isProcessing = false;
        _sendOnUpdateEvent(QueueEvent.stoppedProcessing, null);
      }
    });

    /// add all existing items to the stream controller so they get processed
    for (final item in _items.pending) {
      _itemController.add(item);
    }
  }

  /// Processes a single item in the queue.
  Future<void> _processQueueItem(QueueItem<T> item) async {
    /// handle the item based on it's status
    switch (item.status) {
      case QueueItemStatus.processing:
      case QueueItemStatus.completed:
      case QueueItemStatus.canceled:
      case QueueItemStatus.removed:
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
        isStarted: _isStarted,
        isProcessing: _isProcessing,
        currentBatchId: _currentBatchId,
        updatedItem: item?.copyWith(),
        items: currentBatchItems.map((e) => e.copyWith()).toList(),
      ),
    );
  }
}
