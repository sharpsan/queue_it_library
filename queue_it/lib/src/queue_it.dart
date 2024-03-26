import 'dart:async';

import 'package:queue_it/extensions.dart';
import 'package:queue_it/src/callbacks/item_handler.dart';
import 'package:queue_it/src/models/queue_event.dart';
import 'package:queue_it/src/models/queue_item.dart';
import 'package:queue_it/src/models/queue_item_status.dart';
import 'package:queue_it/src/models/queue_snapshot.dart';
import 'package:queue_it/src/models/semaphore.dart';
import 'package:uuid/uuid.dart';

class QueueIt<T> {
  QueueIt({
    required this.itemHandler,
    this.retryLimit = 3,
    this.concurrentOperations = 1,
  }) {
    _currentBatchId = const Uuid().v4();
  }

  final _items = <QueueItem<T>>[];
  final _onUpdateStreamController =
      StreamController<QueueSnapshot<T>>.broadcast(sync: true);
  late String _currentBatchId;
  late final _semaphore = Semaphore(concurrentOperations);
  var _isStarted = false;
  var _isProcessing = false;

  /// An internal stream controller is being used for tracking item processing events
  /// to eliminate the chances of a user disposing the `onUpdate` [StreamController].
  final _itemController = StreamController<QueueItem<T>>.broadcast(sync: false);

  StreamSubscription<QueueItem<T>>? _itemSubscription;

  /// The number of tasks that can be processed at once.
  final int concurrentOperations;

  /// The number of times to retry processing an item before marking it as failed.
  final int retryLimit;

  /// The function that will be called to process each item in the queue.
  ///
  /// By default the next item status will be set to [QueueItemStatus.completed] if the function
  /// completes successfully, and [QueueItemStatus.failed] if the function throws an error.
  /// You can override this behavior by setting the status of the item manually.
  final ItemHandler<T> itemHandler;

  /// The current batch id
  String get currentBatchId => _currentBatchId;

  /// Whether the queue is currently processing items.
  bool get isProcessing => _isProcessing;

  /// Whether the queue is currently started.
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
  ///
  /// [stopAutomatically] - Whether to stop the queue automatically after all items have been processed.
  void start({
    bool stopAutomatically = false,
  }) async {
    if (_isStarted) return;
    _isStarted = true;
    _sendOnUpdateEvent(QueueEvent.startedQueue, null);
    _processQueueItemsOnDemand(stopAutomatically: stopAutomatically);
  }

  /// Stops the queue from processing any more items.
  /// If the queue is currently processing an item, it will finish processing that item before stopping.
  void stop() {
    if (!_isStarted) return;
    _isStarted = false;
    _sendOnUpdateEvent(QueueEvent.stoppedQueue, null);
    _itemSubscription?.cancel();
    _semaphore.reset();
  }

  /// Adds an item to the queue.
  void add(T data) {
    /// if the queue is empty, assign a new batch id
    if (_items.isEmpty) _currentBatchId = const Uuid().v4();

    final item = QueueItem(
      data: data,
      status: QueueItemStatus.pending,
      batchId: _currentBatchId,
    );
    _items.add(item);
    _itemController.add(item);
    _sendOnUpdateEvent(QueueEvent.itemAdded, item);
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
    _items[_items.indexOf(item)].status = QueueItemStatus.canceled;
  }

  /// Disposes of the [QueueIt] instance.
  void dispose() {
    stop();
    _onUpdateStreamController.close();
    _itemSubscription?.cancel();
    _itemController.close();
  }

  //////// INTERNALS ////////

  /// Processes the queue items as they become available.
  ///
  /// [stopAutomatically] - Whether to stop the queue automatically after all items have been processed.
  void _processQueueItemsOnDemand({
    bool stopAutomatically = false,
  }) async {
    _itemSubscription = _itemController.stream.listen((event) async {
      await _semaphore.acquire();

      if (!_isStarted) return;

      if (!_isProcessing) {
        _isProcessing = true;
        _sendOnUpdateEvent(QueueEvent.startedProcessing, null);
      }
      await _processQueueItem(event);

      // Check if there are any more items in the queue
      if (_items.pending.isEmpty) {
        _isProcessing = false;
        _sendOnUpdateEvent(QueueEvent.stoppedProcessing, null);
        if (stopAutomatically) stop();
      }

      _semaphore.release();
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
      item.status = QueueItemStatus.processing;
      _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
      await itemHandler.call(item);

      /// if the item was not manually updated, set it to completed
      if (item.status == QueueItemStatus.processing) {
        item.status = QueueItemStatus.completed;
      } else {
        item.status = item.status;
      }

      _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
    } catch (e) {
      item.status = QueueItemStatus.failed;
      _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
    }
  }

  /// Handles a failed item by either retrying it or marking it as failed.
  void _handleFailedItem(QueueItem<T> item) {
    if (item.retryCount < retryLimit) {
      item.status = QueueItemStatus.pending;
      _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
    } else {
      item.status = QueueItemStatus.canceled;
      _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
    }
  }

  /// Sends an [QueueSnapshot] event to the [onUpdate] stream.
  void _sendOnUpdateEvent(
    QueueEvent event,
    QueueItem<T>? item,
  ) {
    if (_onUpdateStreamController.hasListener) {
      _onUpdateStreamController.add(
        QueueSnapshot(
          event: event,
          isStarted: _isStarted,
          isProcessing: _isProcessing,
          currentBatchId: _currentBatchId,
          eventItem: item?.copyWith(),
          items: currentBatchItems.map((e) => e.copyWith()).toList(),
        ),
      );
    }
  }
}
