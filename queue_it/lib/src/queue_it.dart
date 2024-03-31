import 'dart:async';

import 'package:queue_it/extensions.dart';
import 'package:queue_it/src/callbacks/item_handler.dart';
import 'package:queue_it/src/models/queue_event.dart';
import 'package:queue_it/src/models/queue_item.dart';
import 'package:queue_it/src/models/queue_item_status.dart';
import 'package:queue_it/src/models/queue_snapshot.dart';
import 'package:queue_it/src/models/semaphore.dart';
import 'package:queue_it/src/utils/readable_uuid.dart';
import 'package:uuid/uuid.dart';

class QueueIt<T> {
  QueueIt({
    required this.itemHandler,
    this.retries = 3,
    this.parallel = 1,
    this.useFriendlyIds = false,
  }) {
    _currentBatchId = const Uuid().v4();
  }

  final _items = <QueueItem<T>>[];
  final _onUpdateStreamController =
      StreamController<QueueSnapshot<T>>.broadcast(sync: true);
  late String _currentBatchId;
  late final _semaphore = Semaphore(parallel);
  var _isStarted = false;
  var _isProcessing = false;

  /// An internal stream controller is being used for tracking item processing events
  /// to eliminate the chances of a user disposing the `onUpdate` [StreamController].
  final _itemController = StreamController<QueueItem<T>>.broadcast(sync: false);

  StreamSubscription<QueueItem<T>>? _itemSubscription;

  /// The number of tasks that can be processed at once.
  final int parallel;

  /// The number of times to retry processing an item before marking it as failed.
  final int retries;

  /// Whether to use readable phrases as ids instead of UUIDs.
  final bool useFriendlyIds;

  /// The function that will be called to process each item in the queue.
  ///
  /// By default the next item status will be set to [QueueItemStatus.completed] if the function
  /// completes successfully, and [QueueItemStatus.failed] if the function throws an error.
  /// You can override this behavior by setting `nextStatus` of the item manually.
  final ItemHandler<T> itemHandler;

  /// The current batch id
  String get currentBatchId => _currentBatchId;

  /// Whether the queue is currently processing items.
  bool get isProcessing => _isProcessing;

  /// Whether the queue is currently started.
  bool get isStarted => _isStarted;

  /// A future that completes when the queue stops running.
  Future<void> get running => _running?.future ?? Future.value();
  Completer<void>? _running;

  /// The items in the current queue.
  Iterable<QueueItem<T>> get currentBatchItems => items(_currentBatchId);

  /// All items in the queue.
  /// If [batchId] is provided, only items in that batch will be returned.
  Iterable<QueueItem<T>> items([String? batchId]) =>
      _items.where((e) => batchId == null || e.batchId == batchId);

  /// A snapshot of the current state of the queue.
  Stream<QueueSnapshot<T>> get onUpdate => _onUpdateStreamController.stream;

  /// The last time the queue was started.
  DateTime? _lastStartedAt;

  /// The last time the queue was started processing.
  DateTime? _lastStartedProcessingAt;

  /// The last time the queue was stopped processing.
  DateTime? _lastStoppedProcessingAt;

  /// The last time the queue was stopped.
  DateTime? _lastStoppedAt;

  /// Starts the queue.
  /// If the queue is already running, this will do nothing.
  ///
  /// [stopAutomatically] - Whether to stop the queue automatically after all items have been processed.
  void start({
    bool stopAutomatically = true,
  }) async {
    if (_isStarted) return;
    _isStarted = true;
    _running = Completer<void>();
    _lastStartedAt = DateTime.now();
    _sendOnUpdateEvent(QueueEvent.startedQueue, null);
    _processQueueItemsOnDemand(stopAutomatically: stopAutomatically);
  }

  /// Stops the queue from processing any more items.
  /// If the queue is currently processing an item, it will finish processing that item before stopping.
  void stop() {
    if (!_isStarted) return;
    _isStarted = false;
    _running?.complete();
    _lastStoppedAt = DateTime.now();
    _sendOnUpdateEvent(QueueEvent.stoppedQueue, null);
    _itemSubscription?.cancel();
    _semaphore.reset();
  }

  bool hasItem(QueueItem<T> item) => _items.contains(item);

  bool hasItemById(String id) => _items.any((e) => e.id == id);

  /// Adds an item to the queue and returns it's id
  String add(T data, {String? id}) {
    /// if the queue is empty, assign a new batch id
    if (_items.isEmpty) _currentBatchId = const Uuid().v4();

    /// use friendly ids if enabled

    if (id == null && useFriendlyIds) {
      id = ReadableUuid().generateReadableUuid();

      /// failsafe to prevent duplicates
      if (hasItemById(id)) {
        id = null;
      }
    }

    final item = QueueItem(
      data: data,
      status: QueueItemStatus.pending,
      batchId: _currentBatchId,
      id: id,
    );
    _items.add(item);
    _itemController.add(item);
    _sendOnUpdateEvent(QueueEvent.itemAdded, item);
    return item.id;
  }

  /// Removes a single item in the queue.
  bool remove(QueueItem<T> item) {
    final itemCopy = item.copyWith()..status = QueueItemStatus.removed;
    bool didRemove = _items.remove(item);
    if (didRemove) {
      _sendOnUpdateEvent(QueueEvent.itemRemoved, itemCopy);
    }
    return didRemove;
  }

  /// Removes a single item in the queue by it's id.
  bool removeById(String id) {
    try {
      final item = _items.firstWhere((e) => e.id == id);
      return remove(item);
    } catch (e) {
      return false;
    }
  }

  /// Removes all items in the queue.
  void removeAll() {
    _items.clear();
    _sendOnUpdateEvent(QueueEvent.removedAll, null);
  }

  /// Cancels a single item in the queue.
  bool cancel(QueueItem<T> item) {
    final didCancel = _cancel(item);
    if (didCancel) {
      _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
    }
    return didCancel;
  }

  /// Cancels a single item in the queue by it's id.
  bool cancelById(String id) {
    try {
      return cancel(_items.firstWhere((e) => e.id == id));
    } catch (e) {
      return false;
    }
  }

  /// Cancels all items in the queue.
  void cancelAll() {
    for (final item in _items) {
      _cancel(item);
    }
    _sendOnUpdateEvent(QueueEvent.cancelledAll, null);
  }

  bool _cancel(QueueItem<T> item) {
    if (item.status == QueueItemStatus.completed) return false;
    item.status = QueueItemStatus.canceled;
    return true;
  }

  /// Disposes of the [QueueIt] instance.
  void dispose() {
    stop();
    _onUpdateStreamController.close();
    _itemSubscription?.cancel();
    _itemController.close();
  }

  @override
  String toString() {
    final s = StringBuffer();
    s.writeln('Started: $_isStarted');
    s.writeln('Processing: $_isProcessing');
    s.writeln('Current Batch Id: $_currentBatchId');
    s.writeln('Items: ${_items.map((e) => e.data).toList()}');
    s.writeln('Started At: $_lastStartedAt');
    s.writeln('Started Processing At: $_lastStartedProcessingAt');
    s.writeln('Stopped Processing At: $_lastStoppedProcessingAt');
    s.writeln('Stopped At: $_lastStoppedAt');
    return s.toString();
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
        _lastStartedProcessingAt = DateTime.now();
        _sendOnUpdateEvent(QueueEvent.startedProcessing, null);
      }
      await _processQueueItem(event);

      // Check if there are any more items in the queue
      if (_items.pending.isEmpty &&
          _items.processing.isEmpty &&
          _items.failed.isEmpty) {
        _isProcessing = false;
        _lastStoppedProcessingAt = DateTime.now();
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

  /// Processes a single item in the queue based on it's current status.
  Future<void> _processQueueItem(QueueItem<T> item) async {
    /// handle the item based on it's status
    switch (item.status) {
      case QueueItemStatus.processing:
      case QueueItemStatus.completed:
      case QueueItemStatus.canceled:
      case QueueItemStatus.removed:
        break;
      case QueueItemStatus.pending:
        await _handlePendingItem(item);
      case QueueItemStatus.failed:
        await _handleFailedItem(item);
    }
  }

  /// Processes a single item in the queue based on it's next status.
  Future<void> _processQueueItemNextStatus(QueueItem<T> item) async {
    if (item.nextStatus == null) return;
    item
      ..status = item.nextStatus!
      ..nextStatus = null;
    _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
    switch (item.status) {
      case QueueItemStatus.processing:
      case QueueItemStatus.completed:
        break;
      case QueueItemStatus.pending:
        await _handlePendingItem(item);
      case QueueItemStatus.failed:
        await _handleFailedItem(item);
      case QueueItemStatus.canceled:
        cancel(item);
      case QueueItemStatus.removed:
        remove(item);
    }
  }

  /// Handles a queued item by calling the [itemHandler] function.
  Future<void> _handlePendingItem(QueueItem<T> item) async {
    try {
      item.status = QueueItemStatus.processing;
      _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
      await itemHandler.call(item);

      /// if the item's next status was not set, set it to completed
      item.nextStatus ??= QueueItemStatus.completed;
      await _processQueueItemNextStatus(item);
    } catch (e) {
      item.nextStatus = QueueItemStatus.failed;
      await _processQueueItemNextStatus(item);
    }
  }

  /// Handles a failed item by either retrying it or marking it as failed.
  Future<void> _handleFailedItem(QueueItem<T> item) async {
    if (item.retryCount < retries) {
      item.status = QueueItemStatus.pending;
      _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
      await _handlePendingItem(item);
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
          retries: retries,
          isStarted: _isStarted,
          isProcessing: _isProcessing,
          currentBatchId: _currentBatchId,
          eventItem: item?.copyWith(),
          items: currentBatchItems.map((e) => e.copyWith()).toList(),
          startedAt: _lastStartedAt,
          startedProcessingAt: _lastStartedProcessingAt,
          stoppedProcessingAt: _lastStoppedProcessingAt,
          stoppedAt: _lastStoppedAt,
        ),
      );
    }
  }
}
