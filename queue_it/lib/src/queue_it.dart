import 'dart:async';
import 'dart:collection';

import 'package:queue_it/src/callbacks/item_handler.dart';
import 'package:queue_it/src/models/queue_event.dart';
import 'package:queue_it/src/models/queue_item.dart';
import 'package:queue_it/src/models/queue_item_status.dart';
import 'package:queue_it/src/models/queue_snapshot.dart';
import 'package:queue_it/src/utils/readable_uuid.dart';
import 'package:uuid/uuid.dart';

/// A queue that processes its items with [itemHandler], up to [parallel] at a
/// time, in the order they were added.
///
/// ```dart
/// final queue = QueueIt<String>(
///   parallel: 2,
///   retries: 3,
///   itemHandler: (item) => upload(item.data),
/// );
/// queue.add('photo.jpg');
/// queue.start();
/// await queue.running;
/// ```
///
/// ## Processing
///
/// Items wait as [QueueItemStatus.pending] until the queue is started with
/// [start]. A started queue keeps taking items, including ones added later,
/// until it's stopped with [stop] or, by default, until it runs out of items.
///
/// An item is [QueueItemStatus.completed] when its handler returns. When the
/// handler throws, the item is retried up to [retries] times, after
/// [retryDelay] and if [retryIf] allows it, and then it has
/// [QueueItemStatus.failed], with the error in [QueueItem.error].
///
/// ## Listening
///
/// [onUpdate] sends a [QueueSnapshot] for every change. Listeners can call
/// the queue, for example to cancel the remaining items when one fails.
///
/// ## Disposing
///
/// Call [dispose] when you're done with the queue.
class QueueIt<T> {
  /// Creates a queue that processes items with [itemHandler].
  QueueIt({
    required this.itemHandler,
    this.retries = 0,
    this.retryDelay,
    this.retryIf,
    this.parallel = 1,
    this.useFriendlyIds = false,
    this.deepCopyItemsInSnapshot = false,
  })  : assert(parallel > 0, 'Parallel must be greater than 0'),
        assert(retries >= 0, 'Retries must not be negative');

  /// Every item in the queue, in the order they were added.
  final _items = <QueueItem<T>>[];
  final _itemsById = <String, QueueItem<T>>{};

  /// The items waiting to be processed, in order. Items canceled or removed
  /// while they wait stay here until they reach the front.
  final _waiting = Queue<QueueItem<T>>();

  /// The timers of the items waiting out [retryDelay], by item id.
  final _retryTimers = <String, Timer>{};

  /// The futures handed out by [waitFor], by item id.
  final _waiters = <String, List<Completer<QueueItem<T>>>>{};

  final _onUpdateStreamController =
      StreamController<QueueSnapshot<T>>.broadcast(sync: true);

  /// Snapshots waiting for the one being sent to reach every listener.
  final _unsentSnapshots = Queue<QueueSnapshot<T>>();
  var _isSendingSnapshots = false;

  var _currentBatchId = const Uuid().v4();
  var _isStarted = false;
  var _isProcessing = false;
  var _isDisposed = false;
  var _stopAutomatically = true;
  var _isPumpScheduled = false;

  /// The number of items whose handler is running.
  var _runningHandlers = 0;

  /// The number of items processed at once.
  final int parallel;

  /// The number of times to retry an item whose handler fails, before marking
  /// it as failed.
  final int retries;

  /// How long to wait before each retry. It's called with the number of the
  /// retry, 1 for the first. Without it, failed items are retried right away.
  ///
  /// The item waits as [QueueItemStatus.pending] without using one of the
  /// [parallel] slots. For example, to double the wait each time:
  ///
  /// ```dart
  /// retryDelay: (retry) => Duration(seconds: 1 << (retry - 1)),
  /// ```
  final Duration Function(int retry)? retryDelay;

  /// Decides whether to retry an item whose handler threw `error`. Without
  /// it, every failure is retried while [retries] last.
  ///
  /// It isn't called once the retries are used up, or for attempts failed
  /// through [QueueItem.nextStatus]. If it throws, the item isn't retried.
  final bool Function(Object error)? retryIf;

  /// Whether to use readable phrases as ids instead of UUIDs.
  ///
  /// The phrases, such as "big wizard cat", are unique within the queue. When
  /// no unused phrase turns up after a few tries, the item gets a UUID.
  final bool useFriendlyIds;

  /// Whether snapshots hold copies of the items instead of the queue's live
  /// items. Copying costs time for every event, in proportion to the size of
  /// the current batch.
  final bool deepCopyItemsInSnapshot;

  /// The function that processes each item.
  ///
  /// The item is [QueueItemStatus.completed] when the function returns, and
  /// fails when it throws. The function can set [QueueItem.nextStatus] to
  /// choose another outcome.
  final ItemHandler<T> itemHandler;

  /// The id of the current batch. See [QueueItem.batchId].
  String get currentBatchId => _currentBatchId;

  /// Whether the queue is processing items.
  ///
  /// It becomes true when the queue starts an item after having none to
  /// process, and false when it has none left, waiting retries included, or
  /// when it was stopped and the items it was processing have finished.
  bool get isProcessing => _isProcessing;

  /// Whether the queue has been started and not stopped since.
  bool get isStarted => _isStarted;

  /// A future that completes when the queue has stopped and the items it was
  /// processing have finished. It's already complete if the queue was never
  /// started.
  Future<void> get running => _running?.future ?? Future.value();
  Completer<void>? _running;

  /// The items in the current batch.
  Iterable<QueueItem<T>> get currentBatchItems => items(_currentBatchId);

  /// All items in the queue, in the order they were added. If [batchId] is
  /// provided, only items in that batch are returned.
  ///
  /// These are the queue's live items, in a lazy view of its list: copy it
  /// with `toList()` before changing the queue while iterating it.
  Iterable<QueueItem<T>> items([String? batchId]) =>
      _items.where((e) => batchId == null || e.batchId == batchId);

  /// A snapshot of the queue for every change, sent synchronously.
  ///
  /// Listeners can call the queue. Events that causes are sent once the
  /// current event has reached every listener, so every listener gets the
  /// events in order. A queue with no listeners builds no snapshots.
  Stream<QueueSnapshot<T>> get onUpdate => _onUpdateStreamController.stream;

  /// The last time the queue was started.
  DateTime? _lastStartedAt;

  /// The last time the queue was started processing.
  DateTime? _lastStartedProcessingAt;

  /// The last time the queue was stopped processing.
  DateTime? _lastStoppedProcessingAt;

  /// The last time the queue was stopped.
  DateTime? _lastStoppedAt;

  /// Starts processing items.
  ///
  /// If the queue is already started, this does nothing. Pending items,
  /// including ones left by an earlier [stop], are processed in order.
  ///
  /// With [stopAutomatically], the queue stops once it has processed every
  /// item, and items added after that wait for the next [start]. A queue
  /// started with no items waits for one. Without it, the queue keeps waiting
  /// for items until [stop] is called.
  ///
  /// Throws a [StateError] if the queue was disposed.
  void start({
    bool stopAutomatically = true,
  }) {
    _checkNotDisposed();
    if (_isStarted) return;
    _isStarted = true;
    _stopAutomatically = stopAutomatically;
    final running = _running;
    if (running == null || running.isCompleted) _running = Completer<void>();
    _lastStartedAt = DateTime.now();
    _sendOnUpdateEvent(QueueEvent.startedQueue, null);
    _schedulePump();
  }

  /// Stops the queue from starting any more items.
  ///
  /// Items being processed finish, and then the queue stops processing and
  /// [running] completes. Pending items stay pending until the next [start].
  void stop() {
    if (!_isStarted) return;
    _isStarted = false;
    _lastStoppedAt = DateTime.now();
    _sendOnUpdateEvent(QueueEvent.stoppedQueue, null);
    _checkIdle();
  }

  /// Whether the queue has an item with the same id as [item].
  bool hasItem(QueueItem<T> item) => hasItemById(item.id);

  /// Whether the queue has an item with [id].
  bool hasItemById(String id) => _itemsById.containsKey(id);

  /// Adds an item with [data] to the end of the queue and returns its id.
  ///
  /// Without an [id], the item gets a UUID, or a readable phrase if
  /// [useFriendlyIds] is set. A started queue processes the item when its
  /// turn comes.
  ///
  /// Throws an [ArgumentError] if the queue already has an item with [id],
  /// and a [StateError] if the queue was disposed.
  String add(T data, {String? id}) {
    _checkNotDisposed();
    if (id != null && hasItemById(id)) {
      throw ArgumentError.value(
          id, 'id', 'The queue already has an item with this id');
    }
    if (!_hasUnfinishedItems()) _currentBatchId = const Uuid().v4();

    final item = QueueItem(
      data: data,
      status: QueueItemStatus.pending,
      batchId: _currentBatchId,
      id: id ?? _newId(),
    );
    _items.add(item);
    _itemsById[item.id] = item;
    _waiting.add(item);
    _sendOnUpdateEvent(QueueEvent.itemAdded, item);
    _schedulePump();
    return item.id;
  }

  /// Removes the queue's item with the same id as [item]. Returns whether
  /// there was one.
  ///
  /// The item's status becomes [QueueItemStatus.removed]. If it's being
  /// processed, its handler keeps running, but the queue ignores the outcome.
  bool remove(QueueItem<T> item) => removeById(item.id);

  /// Removes the item with [id]. Returns whether there was one. See [remove].
  bool removeById(String id) {
    final item = _itemsById[id];
    if (item == null) return false;
    _remove(item);
    _schedulePump();
    return true;
  }

  /// Removes all items, as [remove] does, and sends one
  /// [QueueEvent.removedAll] event.
  void removeAll() {
    final removed = List.of(_items);
    _items.clear();
    _itemsById.clear();
    _waiting.clear();
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    for (final item in removed) {
      item.status = QueueItemStatus.removed;
    }
    _sendOnUpdateEvent(QueueEvent.removedAll, null);
    removed.forEach(_notifyWaiters);
    _schedulePump();
  }

  /// Cancels the queue's item with the same id as [item], if it's pending or
  /// processing. Returns whether it was canceled.
  ///
  /// A canceled item isn't processed or retried. If it's being processed,
  /// its handler keeps running, but the queue ignores the outcome. The
  /// handler can check the item's status to stop early.
  bool cancel(QueueItem<T> item) => cancelById(item.id);

  /// Cancels the item with [id]. Returns whether it was canceled. See
  /// [cancel].
  bool cancelById(String id) {
    final item = _itemsById[id];
    if (item == null || !_cancel(item)) return false;
    _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
    _notifyWaiters(item);
    _schedulePump();
    return true;
  }

  /// Cancels every pending and processing item, as [cancel] does, and sends
  /// one [QueueEvent.cancelledAll] event.
  void cancelAll() {
    final canceled = <QueueItem<T>>[];
    for (final item in _items) {
      if (_cancel(item)) canceled.add(item);
    }
    _sendOnUpdateEvent(QueueEvent.cancelledAll, null);
    canceled.forEach(_notifyWaiters);
    _schedulePump();
  }

  /// Waits for the item with [id] to finish, and completes with a copy of it.
  ///
  /// An item finishes when it's completed, canceled or removed, or when it
  /// has failed with no retries left. For an item that already has, the
  /// future completes right away.
  ///
  /// The future completes with an [ArgumentError] if the queue has no item
  /// with [id], and with a [StateError] if the queue is disposed first.
  Future<QueueItem<T>> waitFor(String id) {
    final item = _itemsById[id];
    if (item == null) {
      return Future.error(
          ArgumentError.value(id, 'id', 'The queue has no item with this id'));
    }
    if (_isFinished(item)) return Future.value(item.copyWith());
    final completer = Completer<QueueItem<T>>();
    (_waiters[id] ??= []).add(completer);
    return completer.future;
  }

  /// Stops the queue and closes [onUpdate].
  ///
  /// Handlers that are running keep running, but the queue ignores their
  /// outcome. [running] completes, and futures from [waitFor] complete with a
  /// [StateError]. The queue can't be started or added to afterwards.
  void dispose() {
    if (_isDisposed) return;
    stop();
    _isDisposed = true;
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    final error = StateError('The queue was disposed before the item finished');
    for (final waiters in _waiters.values) {
      for (final waiter in waiters) {
        waiter.completeError(error);
      }
    }
    _waiters.clear();
    final running = _running;
    if (running != null && !running.isCompleted) running.complete();
    // A listener that disposes the queue is closed once the event reaches every listener.
    if (!_isSendingSnapshots) _onUpdateStreamController.close();
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

  void _checkNotDisposed() {
    if (_isDisposed) throw StateError('The queue was disposed');
  }

  String _newId() {
    if (useFriendlyIds) {
      for (var i = 0; i < 10; i++) {
        final id = ReadableUuid().generateReadableUuid();
        if (!hasItemById(id)) return id;
      }
    }
    return const Uuid().v4();
  }

  bool _isFinished(QueueItem<T> item) => switch (item.status) {
        QueueItemStatus.pending || QueueItemStatus.processing => false,
        QueueItemStatus.completed ||
        QueueItemStatus.failed ||
        QueueItemStatus.canceled ||
        QueueItemStatus.removed =>
          true,
      };

  bool _hasUnfinishedItems() =>
      _runningHandlers > 0 || _retryTimers.isNotEmpty || _hasWaitingItem();

  /// Whether an item is waiting to be processed. Drops the items at the front
  /// of [_waiting] that were canceled or removed while they waited.
  bool _hasWaitingItem() {
    while (_waiting.isNotEmpty) {
      final item = _waiting.first;
      if (item.status == QueueItemStatus.pending &&
          identical(_itemsById[item.id], item)) {
        return true;
      }
      _waiting.removeFirst();
    }
    return false;
  }

  bool _cancel(QueueItem<T> item) {
    if (item.status != QueueItemStatus.pending &&
        item.status != QueueItemStatus.processing) {
      return false;
    }
    _retryTimers.remove(item.id)?.cancel();
    item.status = QueueItemStatus.canceled;
    return true;
  }

  void _remove(QueueItem<T> item) {
    _itemsById.remove(item.id);
    _items.remove(item);
    _retryTimers.remove(item.id)?.cancel();
    item.status = QueueItemStatus.removed;
    _sendOnUpdateEvent(QueueEvent.itemRemoved, item);
    _notifyWaiters(item);
  }

  void _notifyWaiters(QueueItem<T> item) {
    final waiters = _waiters.remove(item.id);
    if (waiters == null) return;
    final copy = item.copyWith();
    for (final waiter in waiters) {
      waiter.complete(copy);
    }
  }

  /// Starts processing waiting items soon, once the current code is done
  /// changing the queue.
  void _schedulePump() {
    if (_isPumpScheduled) return;
    _isPumpScheduled = true;
    scheduleMicrotask(() {
      _isPumpScheduled = false;
      _pump();
    });
  }

  /// Starts waiting items while there are free slots, then checks whether the
  /// queue ran out of work.
  void _pump() {
    if (_isDisposed) return;
    while (_isStarted && _runningHandlers < parallel && _hasWaitingItem()) {
      unawaited(_process(_waiting.removeFirst()));
    }
    _checkIdle();
  }

  /// Sends [QueueEvent.stoppedProcessing] once the queue has no work left,
  /// stops it if it stops automatically, and completes [running] once a
  /// stopped queue's last handler has returned.
  void _checkIdle() {
    if (_runningHandlers > 0) return;
    if (_isStarted && (_retryTimers.isNotEmpty || _hasWaitingItem())) return;
    if (_isProcessing) {
      _isProcessing = false;
      _lastStoppedProcessingAt = DateTime.now();
      _sendOnUpdateEvent(QueueEvent.stoppedProcessing, null);
      if (_isStarted && _stopAutomatically) stop();
    }
    final running = _running;
    if (!_isStarted && running != null && !running.isCompleted) {
      running.complete();
    }
  }

  /// Runs the handler for [item] and applies the outcome.
  Future<void> _process(QueueItem<T> item) async {
    _runningHandlers++;
    if (!_isProcessing) {
      _isProcessing = true;
      _lastStartedProcessingAt = DateTime.now();
      _sendOnUpdateEvent(QueueEvent.startedProcessing, null);
    }
    item.status = QueueItemStatus.processing;
    _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);

    Object? error;
    StackTrace? stackTrace;
    try {
      await itemHandler(item);
    } catch (e, s) {
      error = e;
      stackTrace = s;
    }
    _runningHandlers--;
    if (_isDisposed) return;
    try {
      _settle(item, error, stackTrace);
    } finally {
      _pump();
    }
  }

  /// Moves [item] on from processing, according to its handler's outcome.
  void _settle(QueueItem<T> item, Object? error, StackTrace? stackTrace) {
    final nextStatus = item.nextStatus;
    item.nextStatus = null;
    // Canceled or removed while the handler ran.
    if (item.status != QueueItemStatus.processing) return;

    if (error != null) {
      _fail(item, error, stackTrace);
      return;
    }
    switch (nextStatus) {
      case null || QueueItemStatus.completed:
        item.status = QueueItemStatus.completed;
        _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
        _notifyWaiters(item);
      case QueueItemStatus.failed:
        _fail(item, null, null);
      case QueueItemStatus.canceled:
        item.status = QueueItemStatus.canceled;
        _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
        _notifyWaiters(item);
      case QueueItemStatus.removed:
        _remove(item);
      case QueueItemStatus.pending:
        item.status = QueueItemStatus.pending;
        _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
        _waiting.add(item);
      case QueueItemStatus.processing:
        _fail(
          item,
          StateError("An item's nextStatus can't be processing"),
          StackTrace.current,
        );
    }
  }

  /// Marks [item] as failed, then queues a retry if it has any left.
  void _fail(QueueItem<T> item, Object? error, StackTrace? stackTrace) {
    item
      ..error = error
      ..stackTrace = stackTrace
      ..status = QueueItemStatus.failed;
    _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
    // A listener removed it.
    if (item.status != QueueItemStatus.failed) return;

    Duration? delay;
    try {
      if (item.retryCount < retries &&
          (error == null || (retryIf?.call(error) ?? true))) {
        delay = retryDelay?.call(item.retryCount + 1) ?? Duration.zero;
      }
    } finally {
      if (delay == null) _notifyWaiters(item);
    }
    if (delay == null) return;

    item.status = QueueItemStatus.pending;
    _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
    if (delay <= Duration.zero) {
      _waiting.addFirst(item);
    } else {
      _retryTimers[item.id] = Timer(delay, () {
        _retryTimers.remove(item.id);
        _waiting.addFirst(item);
        _pump();
      });
    }
  }

  /// Sends an [QueueSnapshot] event to the [onUpdate] stream.
  void _sendOnUpdateEvent(
    QueueEvent event,
    QueueItem<T>? item,
  ) {
    if (!_onUpdateStreamController.hasListener) return;
    _unsentSnapshots.add(
      QueueSnapshot(
        event: event,
        retries: retries,
        isStarted: _isStarted,
        isProcessing: _isProcessing,
        currentBatchId: _currentBatchId,
        eventItem: item?.copyWith(),
        items: deepCopyItemsInSnapshot
            ? currentBatchItems.map((e) => e.copyWith()).toList()
            : currentBatchItems,
        startedAt: _lastStartedAt,
        startedProcessingAt: _lastStartedProcessingAt,
        stoppedProcessingAt: _lastStoppedProcessingAt,
        stoppedAt: _lastStoppedAt,
      ),
    );
    // A synchronous stream can't send an event while it's sending one, so an
    // event caused by a listener waits for the current one to reach every
    // listener.
    if (_isSendingSnapshots) return;
    _isSendingSnapshots = true;
    try {
      while (_unsentSnapshots.isNotEmpty) {
        _onUpdateStreamController.add(_unsentSnapshots.removeFirst());
      }
    } finally {
      _isSendingSnapshots = false;
    }
    if (_isDisposed) _onUpdateStreamController.close();
  }
}
