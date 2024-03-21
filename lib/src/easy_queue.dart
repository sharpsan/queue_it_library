import 'dart:async';

import 'package:easy_queue/src/callbacks/item_handler.dart';
import 'package:easy_queue/src/extensions/queue_items_extension.dart';
import 'package:easy_queue/src/models/queue_item.dart';
import 'package:easy_queue/src/models/queue_item_status.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

class EasyQueue<T> {
  EasyQueue({
    this.itemHandler,
    this.retryCount = 3,
  }) {
    _currentBatchId = const Uuid().v4();
  }

  /// The number of times to retry processing an item before marking it as failed.
  final int retryCount;

  /// Called when an item is being processed.
  ItemHandler<T>? itemHandler;

  /// state
  final List<QueueItem<T>> _items = [];
  final _isProcessingNotifier = ValueNotifier(false);
  late String _currentBatchId;

  ValueNotifier<bool> get isProcessingNotifier => _isProcessingNotifier;

  bool get isProcessing => _isProcessingNotifier.value;

  Iterable<QueueItem<T>> get currentBatchItems => items(_currentBatchId);

  Iterable<QueueItem<T>> items([String? batchId]) =>
      _items.where((e) => batchId == null || e.batchId == batchId);

  /// listeners

  Stream<String> get onStart => _onStartStreamController.stream;

  Stream<QueueItem<T>> get onUpdate => _onUpdateStreamController.stream;

  Stream<Iterable<QueueItem<T>>> get onDone => _onDoneStreamController.stream;

  /// Returns batch id
  final _onStartStreamController = StreamController<String>();

  /// Returns snapshot of the updated item
  final _onUpdateStreamController = StreamController<QueueItem<T>>();

  /// Returns processed items
  final _onDoneStreamController = StreamController<Iterable<QueueItem<T>>>();

  Future<void> start() async {
    if (_isProcessingNotifier.value) return;
    if (_items.isEmpty) return;
    if (_items.pending.isEmpty) return;
    _isProcessingNotifier.value = true;
    _onStartStreamController.add(_currentBatchId);
    try {
      await _processQueueItems();
    } finally {
      _onDoneStreamController.add(currentBatchItems);
      _currentBatchId = const Uuid().v4();
      _isProcessingNotifier.value = false;
    }
  }

  void stop() {
    _isProcessingNotifier.value = false;
  }

  void clear(QueueItem<T> item) {
    if (isProcessing) throw StateError('Cannot clear queue while processing');
    _items.remove(item);
  }

  void clearAll() {
    if (isProcessing) throw StateError('Cannot clear queue while processing');
    _items.clear();
  }

  void cancelAll() {
    for (final item in _items) {
      cancel(item);
    }
  }

  void add(T data) {
    _items.add(
      QueueItem(
        data: data,
        queuedAt: DateTime.now(),
        status: QueueItemStatus.pending,
        batchId: _currentBatchId,
      ),
    );
  }

  void cancel(QueueItem<T> item) {
    if (item.status == QueueItemStatus.completed) return;
    _items[_items.indexOf(item)]
      ..status = QueueItemStatus.canceled
      ..canceledAt = DateTime.now();
  }

  void dispose() {
    _onStartStreamController.close();
    _onUpdateStreamController.close();
    _onDoneStreamController.close();
  }

  //////// INTERNALS ////////

  Future<void> _processQueueItems() async {
    for (final item in _items) {
      if (!isProcessing) return;
      //TODO: figure out a way to stop the currently-running future
      await _processQueueItem(item);
    }
  }

  Future<void> _processQueueItem(QueueItem<T> item) async {
    /// handle the item based on it's status
    switch (item.status) {
      case QueueItemStatus.processing:
      case QueueItemStatus.completed:
      case QueueItemStatus.canceled:
        break;
      case QueueItemStatus.pending:
        await _handleQueuedItem(item);
      case QueueItemStatus.failed:
        _handleFailedItem(item);
    }
  }

  Future<void> _handleQueuedItem(QueueItem<T> item) async {
    try {
      item
        ..status = QueueItemStatus.processing
        ..startedProcessingAt = DateTime.now();
      _onUpdateStreamController.add(item);
      await itemHandler?.call(item.copyWith());
      item
        ..status = QueueItemStatus.completed
        ..completedAt = DateTime.now();
      _onUpdateStreamController.add(item.copyWith());
    } catch (e) {
      item
        ..status = QueueItemStatus.failed
        ..failedAt = DateTime.now();
      _onUpdateStreamController.add(item.copyWith());
    }
  }

  void _handleFailedItem(QueueItem<T> item) {
    if (item.retryCount < retryCount) {
      item.status = QueueItemStatus.pending;
      item.retryCount++;
      _onUpdateStreamController.add(item.copyWith());
    } else {
      item
        ..status = QueueItemStatus.canceled
        ..canceledAt = DateTime.now();
      _onUpdateStreamController.add(item.copyWith());
    }
  }
}
