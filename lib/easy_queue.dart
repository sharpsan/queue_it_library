library easy_queue;

import 'dart:async';

import 'package:uuid/uuid.dart';

typedef OnUpdateCallback<T> = FutureOr<void> Function(
  QueueItemStatus status,
  QueueItem<T> item,
);
typedef ItemHandler<T> = FutureOr<void> Function(
  QueueItem<T> item,
);

typedef OnDoneCallback = FutureOr<void> Function();

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
  final List<QueueItem<T>> _queuedImages = [];
  List<QueueItem<T>> get queuedImages => _queuedImages;
  bool _isProcessing = false;
  late String _currentBatchId;

  /// Queue information for the current batch.
  Iterable<QueueItem<T>> get pending =>
      _getItems(status: QueueItemStatus.pending, batchId: _currentBatchId);
  Iterable<QueueItem<T>> get processing =>
      _getItems(status: QueueItemStatus.processing, batchId: _currentBatchId);
  Iterable<QueueItem<T>> get completed =>
      _getItems(status: QueueItemStatus.completed, batchId: _currentBatchId);
  Iterable<QueueItem<T>> get failed =>
      _getItems(status: QueueItemStatus.failed, batchId: _currentBatchId);
  Iterable<QueueItem<T>> get cancelled =>
      _getItems(status: QueueItemStatus.canceled, batchId: _currentBatchId);
  Iterable<QueueItem<T>> get all => _getItems(batchId: _currentBatchId);
  bool get isProcessing => _isProcessing;

  /// Returns a double between 0 and 1 representing the progress of the queue.
  double get progress {
    if (all.isEmpty || pending.isEmpty) return 1;
    final percentage = pending.length / all.length;
    // round to 2 decimal places;
    return double.parse(percentage.toStringAsFixed(2));
  }

  /// listener callbacks

  final _statusChangeCallbacks = <QueueCallback, Map<String, dynamic>>{
    QueueCallback.onStart: {},
    QueueCallback.onItemUpdated: {},
    QueueCallback.onDone: {},
  };

  String addOnStartListener(FutureOr<void> Function() callback) {
    return _addListener(QueueCallback.onStart, callback);
  }

  void removeOnStartListener(String key) {
    _removeListener(QueueCallback.onStart, key);
  }

  String addOnUpdateListener(OnUpdateCallback<T> callback) {
    return _addListener(QueueCallback.onItemUpdated, callback);
  }

  void removeOnUpdateListener(String key) {
    _removeListener(QueueCallback.onItemUpdated, key);
  }

  String addOnDoneListener(OnDoneCallback callback) {
    return _addListener(QueueCallback.onDone, callback);
  }

  void removeOnDoneListener(String key) {
    _removeListener(QueueCallback.onDone, key);
  }

  Future<void> processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;
    _currentBatchId = const Uuid().v4();
    if (_queuedImages.isEmpty) return;
    _notifyListeners(QueueCallback.onStart);
    try {
      await _processQueueItems();
    } finally {
      _isProcessing = false;
      _currentBatchId = const Uuid().v4();
    }
    _notifyListeners(QueueCallback.onDone);
  }

  void cancelAll() {
    for (final item in _queuedImages) {
      cancel(item);
    }
  }

  void add(T data) {
    _queuedImages.add(
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
    _queuedImages[_queuedImages.indexOf(item)]
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
    for (final item in _queuedImages) {
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

  Iterable<QueueItem<T>> _getItems({
    QueueItemStatus? status,
    String? batchId,
  }) {
    return _queuedImages
        .where((item) => status == null || item.status == status)
        .where((item) => batchId == null || item.batchId == batchId);
  }

  String _addListener(QueueCallback callbackType, dynamic callback) {
    final key = const Uuid().v4();
    _statusChangeCallbacks[callbackType]![key] = callback;
    return key;
  }

  void _removeListener(QueueCallback callbackType, String key) {
    _statusChangeCallbacks[callbackType]!.remove(key);
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

enum QueueItemStatus {
  pending,
  processing,
  completed,
  failed,
  canceled,
}

class QueueItem<T> {
  QueueItem({
    required this.data,
    required this.status,
    required this.batchId,
    this.queuedAt,
    this.startedProcessingAt,
    this.completedAt,
    this.failedAt,
    this.canceledAt,
    this.retryCount = 0,
  });

  final T data;
  final String batchId;

  DateTime? queuedAt;
  DateTime? startedProcessingAt;
  DateTime? completedAt;
  DateTime? failedAt;
  DateTime? canceledAt;
  QueueItemStatus status;
  int retryCount;
}

enum QueueCallback {
  onStart,
  onItemUpdated,
  onDone,
}
