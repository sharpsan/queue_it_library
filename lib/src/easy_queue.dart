import 'dart:async';

import 'package:easy_queue/src/callbacks/on_start_callback.dart';
import 'package:easy_queue/src/extensions/queue_items_extension.dart';
import 'package:easy_queue/src/models/queue_callback.dart';
import 'package:easy_queue/src/models/queue_item.dart';
import 'package:easy_queue/src/models/queue_item_status.dart';
import 'package:easy_queue/src/callbacks/item_handler.dart';
import 'package:easy_queue/src/callbacks/on_done_callback.dart';
import 'package:easy_queue/src/callbacks/on_update_callback.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

class EasyQueue<T> {
  EasyQueue({
    this.retryCount = 3,
  }) {
    _currentBatchId = const Uuid().v4();
  }
  final int retryCount;

  /// Called when an item is being processed.
  ItemHandler<T>? itemHandler;

  /// state
  final List<QueueItem<T>> _items = [];
  List<QueueItem<T>> get queuedImages => _items;
  final _isProcessingNotifier = ValueNotifier(false);
  late String _currentBatchId;

  ValueNotifier<bool> get isProcessingNotifier => _isProcessingNotifier;
  bool get isProcessing => _isProcessingNotifier.value;
  Iterable<QueueItem<T>> get currentBatchItems => items(_currentBatchId);
  Iterable<QueueItem<T>> items([String? batchId]) =>
      _items.where((e) => batchId == null || e.batchId == batchId);

  /// listener callbacks

  final _statusChangeCallbacks = <QueueCallback, dynamic>{
    QueueCallback.onStart: {},
    QueueCallback.onItemUpdated: {},
    QueueCallback.onDone: {},
  };

  void addOnStartListener(OnStartCallback callback) {
    _addListener(QueueCallback.onStart, callback);
  }

  void removeOnStartListener(OnStartCallback callback) {
    _removeListener(QueueCallback.onStart, callback);
  }

  void addOnUpdateListener(OnUpdateCallback<T> callback) {
    _addListener(QueueCallback.onItemUpdated, callback);
  }

  void removeOnUpdateListener(OnUpdateCallback<T> callback) {
    _removeListener(QueueCallback.onItemUpdated, callback);
  }

  void addOnDoneListener(OnDoneCallback<T> callback) {
    _addListener(QueueCallback.onDone, callback);
  }

  void removeOnDoneListener(OnDoneCallback<T> callback) {
    _removeListener(QueueCallback.onDone, callback);
  }

  Future<void> processQueue() async {
    if (_isProcessingNotifier.value) return;
    if (_items.isEmpty) return;
    if (_items.pending.isEmpty) return;
    _isProcessingNotifier.value = true;
    _notifyListeners(
      QueueCallback.onStart,
      positionalArguments: [_currentBatchId],
    );
    try {
      await _processQueueItems();
    } finally {
      _notifyListeners(
        QueueCallback.onDone,
        positionalArguments: [currentBatchItems],
      );
      _currentBatchId = const Uuid().v4();
      _isProcessingNotifier.value = false;
    }
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
    _statusChangeCallbacks.forEach((key, value) {
      value.clear();
    });
  }

  //////// INTERNALS ////////

  Future<void> _processQueueItems() async {
    for (final item in _items) {
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
    item
      ..status = QueueItemStatus.processing
      ..startedProcessingAt = DateTime.now();
    _notifyListeners(
      QueueCallback.onItemUpdated,
      positionalArguments: [item.status, item],
    );
    try {
      await itemHandler?.call(item);
      item
        ..status = QueueItemStatus.completed
        ..completedAt = DateTime.now();
      _notifyListeners(
        QueueCallback.onItemUpdated,
        positionalArguments: [item.status, item],
      );
    } catch (e) {
      item
        ..status = QueueItemStatus.failed
        ..failedAt = DateTime.now();
      _notifyListeners(
        QueueCallback.onItemUpdated,
        positionalArguments: [item.status, item],
      );
    }
  }

  void _handleFailedItem(QueueItem<T> item) {
    if (item.retryCount < retryCount) {
      item.status = QueueItemStatus.pending;
      item.retryCount++;
      _notifyListeners(
        QueueCallback.onItemUpdated,
        positionalArguments: [item.status, item],
      );
    } else {
      item
        ..status = QueueItemStatus.canceled
        ..canceledAt = DateTime.now();
      _notifyListeners(
        QueueCallback.onItemUpdated,
        positionalArguments: [item.status, item],
      );
    }
  }

  String _addListener(QueueCallback callbackType, dynamic callback) {
    final key = const Uuid().v4();
    _statusChangeCallbacks[callbackType]![key] = callback;
    return key;
  }

  void _removeListener(QueueCallback callbackType, dynamic callback) {
    _statusChangeCallbacks[callbackType]!.remove(callback);
  }

  void _notifyListeners(
    QueueCallback callbackType, {
    List<dynamic>? positionalArguments = const [],
    Map<Symbol, dynamic>? namedArguments = const {},
  }) {
    for (final callback in _statusChangeCallbacks[callbackType]!.values) {
      Function.apply(callback, positionalArguments, namedArguments);
    }
  }
}
