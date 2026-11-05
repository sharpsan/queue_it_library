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

  /// The items waiting to be processed, in order, and each one's place in it.
  /// Items leave it as soon as they're canceled or removed.
  final _waiting = LinkedList<_WaitingItem<T>>();
  final _waitingEntries = <QueueItem<T>, _WaitingItem<T>>{};

  /// The items whose handler is running, or whose outcome is being applied,
  /// including items canceled or removed since the handler started.
  final _runningItems = <QueueItem<T>>{};

  /// The items in the `failed` event of an attempt that will be retried.
  final _retrying = <QueueItem<T>>{};

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

  /// Where the current batch starts in [_items]. Items are only added at the
  /// end, and a batch only starts once every item has finished, so the
  /// current batch is the end of the list.
  var _batchStart = 0;
  var _isStarted = false;
  var _isProcessing = false;
  var _stopAutomatically = true;
  var _isPumpScheduled = false;

  /// Whether the queue has had items to process since it was started.
  var _hasHadItems = false;

  /// How many times the queue has been started, to tell whether a listener
  /// started it again.
  var _starts = 0;

  /// Whether [dispose] has been called, and whether it has finished stopping
  /// the queue.
  var _isDisposing = false;
  var _isDisposed = false;

  /// The number of items processed at once.
  final int parallel;

  /// The number of times to retry an item whose handler fails, before marking
  /// it as failed.
  final int retries;

  /// How long to wait before each retry. It's called with the
  /// [QueueItem.retryCount] the item will have: 1 for the first retry, plus
  /// one for each time its handler sent it back with [QueueItem.nextStatus].
  /// Without it, failed items are retried right away.
  ///
  /// The item waits as [QueueItemStatus.pending] without using one of the
  /// [parallel] slots. For example, to double the wait each time:
  ///
  /// ```dart
  /// retryDelay: (retry) => Duration(seconds: 1 << (retry - 1)),
  /// ```
  ///
  /// If it throws, the item isn't retried, and the error is reported to the
  /// current [Zone] as an uncaught error, like an error in a listener.
  final Duration Function(int retry)? retryDelay;

  /// Decides whether to retry an item whose handler threw `error`. Without
  /// it, every failure is retried while [retries] last.
  ///
  /// It isn't called once the retries are used up, or for attempts the
  /// handler failed with `nextStatus = failed`. If it throws, the item isn't
  /// retried, and the error is reported to the current [Zone] as an uncaught
  /// error, like an error in a listener.
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
  Iterable<QueueItem<T>> items([String? batchId]) => batchId == null
      ? _items.where((item) => true)
      : _BatchItems(this, batchId);

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
  /// With [stopAutomatically], the queue stops once it runs out of items:
  /// they've all been processed, canceled or removed. Items added after that
  /// wait for the next [start]. A queue started with no items waits for one.
  /// Without it, the queue keeps waiting for items until [stop] is called.
  ///
  /// Throws a [StateError] if the queue was disposed.
  void start({
    bool stopAutomatically = true,
  }) {
    _checkNotDisposed();
    if (_isStarted) return;
    _isStarted = true;
    _starts++;
    _stopAutomatically = stopAutomatically;
    _hasHadItems = _hasUnfinishedItems();
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
    if (!_hasUnfinishedItems()) {
      _currentBatchId = const Uuid().v4();
      _batchStart = _items.length;
    }

    final item = QueueItem(
      data: data,
      status: QueueItemStatus.pending,
      batchId: _currentBatchId,
      id: id ?? _newId(),
    );
    _items.add(item);
    _itemsById[item.id] = item;
    _enqueue(item);
    if (_isStarted) _hasHadItems = true;
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
    _batchStart = 0;
    _itemsById.clear();
    _waiting.clear();
    _waitingEntries.clear();
    _retrying.clear();
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    for (final item in removed) {
      item.status = QueueItemStatus.removed;
    }
    removed.forEach(_notifyWaiters);
    _sendOnUpdateEvent(QueueEvent.removedAll, null);
    _schedulePump();
  }

  /// Cancels the queue's item with the same id as [item], if it's pending or
  /// processing. Returns whether it was canceled.
  ///
  /// A canceled item isn't processed or retried. If it's being processed,
  /// its handler keeps running, but the queue ignores the outcome. The
  /// handler can check the item's status to stop early.
  ///
  /// A listener can also cancel an item in the `failed` event of an attempt
  /// that would be retried, to stop the retry.
  bool cancel(QueueItem<T> item) => cancelById(item.id);

  /// Cancels the item with [id]. Returns whether it was canceled. See
  /// [cancel].
  bool cancelById(String id) {
    final item = _itemsById[id];
    if (item == null || !_cancel(item)) return false;
    _notifyWaiters(item);
    _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
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
    canceled.forEach(_notifyWaiters);
    _sendOnUpdateEvent(QueueEvent.cancelledAll, null);
    _schedulePump();
  }

  /// Waits for the item with [id] to finish, and completes with a copy of it,
  /// as it was when it finished.
  ///
  /// An item finishes when it's completed, canceled or removed, or when it
  /// has failed with no retries left. For an item that already has, the
  /// future completes right away.
  ///
  /// The future completes with an [ArgumentError] if the queue has no item
  /// with [id], and with a [StateError] if the queue is disposed before the
  /// item finishes.
  Future<QueueItem<T>> waitFor(String id) {
    final item = _itemsById[id];
    if (item == null) {
      return Future.error(
          ArgumentError.value(id, 'id', 'The queue has no item with this id'));
    }
    if (_isFinished(item)) return Future.value(item.copyWith());
    if (_isDisposing) return Future.error(_disposedError());
    final completer = Completer<QueueItem<T>>();
    (_waiters[id] ??= []).add(completer);
    return completer.future;
  }

  /// Stops the queue and closes [onUpdate].
  ///
  /// Handlers that are running keep running, but the queue ignores their
  /// outcome, so their items stay [QueueItemStatus.processing]. [running]
  /// completes, and futures from [waitFor] complete with a
  /// [StateError]. The queue can't be started or added to afterwards.
  void dispose() {
    if (_isDisposing) return;
    // From here on, listeners of the events below can't start the queue again.
    _isDisposing = true;
    stop();
    _isDisposed = true;
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    final error = _disposedError();
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
    if (_isDisposing) throw StateError('The queue was disposed');
  }

  StateError _disposedError() =>
      StateError('The queue was disposed before the item finished');

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
        QueueItemStatus.failed => !_retrying.contains(item),
        QueueItemStatus.completed ||
        QueueItemStatus.canceled ||
        QueueItemStatus.removed =>
          true,
      };

  /// Whether an item is still to be finished: waiting, being processed (or
  /// about to be) or about to be retried. A handler that's still running for
  /// an item that was canceled or removed doesn't count.
  bool _hasUnfinishedItems() =>
      _waiting.isNotEmpty ||
      _retryTimers.isNotEmpty ||
      _retrying.isNotEmpty ||
      _runningItems.any((item) =>
          item.status == QueueItemStatus.pending ||
          item.status == QueueItemStatus.processing);

  /// Whether the queue has anything left to do: items waiting or waiting to
  /// be retried, or handlers running.
  bool _hasWork() =>
      _waiting.isNotEmpty ||
      _retryTimers.isNotEmpty ||
      _runningItems.isNotEmpty;

  void _enqueue(QueueItem<T> item, {bool first = false}) {
    final entry = _WaitingItem(item);
    _waitingEntries[item] = entry;
    first ? _waiting.addFirst(entry) : _waiting.add(entry);
  }

  QueueItem<T> _dequeue() {
    final entry = _waiting.first..unlink();
    _waitingEntries.remove(entry.item);
    return entry.item;
  }

  /// Takes [item] out of the waiting items, if it's there.
  void _unqueue(QueueItem<T> item) => _waitingEntries.remove(item)?.unlink();

  bool _cancel(QueueItem<T> item) {
    if (item.status != QueueItemStatus.pending &&
        item.status != QueueItemStatus.processing &&
        !_retrying.contains(item)) {
      return false;
    }
    _retrying.remove(item);
    _unqueue(item);
    _retryTimers.remove(item.id)?.cancel();
    item.status = QueueItemStatus.canceled;
    return true;
  }

  void _remove(QueueItem<T> item) {
    _itemsById.remove(item.id);
    final index = _items.indexOf(item);
    _items.removeAt(index);
    if (index < _batchStart) _batchStart--;
    _retrying.remove(item);
    _unqueue(item);
    _retryTimers.remove(item.id)?.cancel();
    item.status = QueueItemStatus.removed;
    _notifyWaiters(item);
    _sendOnUpdateEvent(QueueEvent.itemRemoved, item);
  }

  /// Completes the [waitFor] futures for [item], which has finished. It's
  /// called before the event is sent, so what listeners do about the event
  /// doesn't change the result.
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
    while (
        _isStarted && _runningItems.length < parallel && _waiting.isNotEmpty) {
      unawaited(_process(_dequeue()));
    }
    _checkIdle();
  }

  /// Sends [QueueEvent.stoppedProcessing] once the queue has no work left,
  /// stops it if it stops automatically, and completes [running] once a
  /// stopped queue's last handler has returned.
  void _checkIdle() {
    if (_runningItems.isNotEmpty) return;
    if (_isDisposed) {
      // A disposed queue sends no more events.
      if (_isProcessing) {
        _isProcessing = false;
        _lastStoppedProcessingAt = DateTime.now();
      }
      return;
    }
    if (_isStarted && _hasWork()) return;
    final starts = _starts;
    if (_isProcessing) {
      _isProcessing = false;
      _lastStoppedProcessingAt = DateTime.now();
      _sendOnUpdateEvent(QueueEvent.stoppedProcessing, null);
    }
    // A listener may have added an item, or stopped and started the queue
    // again, in the meantime.
    if (_isStarted &&
        _starts == starts &&
        _stopAutomatically &&
        _hasHadItems &&
        !_hasWork()) {
      stop();
    }
    final running = _running;
    if (!_isStarted && running != null && !running.isCompleted) {
      running.complete();
    }
  }

  /// Runs the handler for [item] and applies the outcome.
  Future<void> _process(QueueItem<T> item) async {
    _runningItems.add(item);
    if (!_isProcessing) {
      _isProcessing = true;
      _lastStartedProcessingAt = DateTime.now();
      _sendOnUpdateEvent(QueueEvent.startedProcessing, null);
    }
    // Listeners can stop or dispose the queue, or cancel or remove the item,
    // before its handler starts.
    if (_isStarted && item.status == QueueItemStatus.pending) {
      item.status = QueueItemStatus.processing;
      _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
    } else if (item.status == QueueItemStatus.pending) {
      _enqueue(item, first: true);
    }
    if (_isDisposing || item.status != QueueItemStatus.processing) {
      _runningItems.remove(item);
      return;
    }

    Object? error;
    StackTrace? stackTrace;
    try {
      await itemHandler(item);
    } catch (e, s) {
      error = e;
      stackTrace = s;
    }
    try {
      if (!_isDisposed) _settle(item, error, stackTrace);
    } finally {
      _runningItems.remove(item);
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
        _notifyWaiters(item);
        _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
      case QueueItemStatus.failed:
        _fail(item, null, null);
      case QueueItemStatus.canceled:
        item.status = QueueItemStatus.canceled;
        _notifyWaiters(item);
        _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
      case QueueItemStatus.removed:
        _remove(item);
      case QueueItemStatus.pending:
        item.status = QueueItemStatus.pending;
        _enqueue(item);
        _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
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
    final delay = _retryDelay(item, error);
    // retryIf or retryDelay canceled or removed the item, or disposed the
    // queue.
    if (_isDisposing || item.status != QueueItemStatus.processing) return;
    item
      ..error = error
      ..stackTrace = stackTrace
      ..status = QueueItemStatus.failed;
    if (delay == null) {
      _notifyWaiters(item);
      _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
      return;
    }

    // The item will be retried, so it hasn't finished, and listeners can
    // still cancel it.
    _retrying.add(item);
    try {
      _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
    } finally {
      _retrying.remove(item);
    }
    // A listener canceled or removed it.
    if (item.status != QueueItemStatus.failed) return;

    item.status = QueueItemStatus.pending;
    // A listener disposed the queue. The item stays pending, like the other
    // items that were waiting.
    if (_isDisposing) return;
    if (delay <= Duration.zero) {
      _enqueue(item, first: true);
    } else {
      _retryTimers[item.id] = Timer(delay, () {
        _retryTimers.remove(item.id);
        _enqueue(item, first: true);
        _pump();
      });
    }
    _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
  }

  /// How long to wait before retrying [item], which failed with [error], or
  /// null if it isn't retried.
  Duration? _retryDelay(QueueItem<T> item, Object? error) {
    if (item.retryCount >= retries) return null;
    try {
      if (error != null && !(retryIf?.call(error) ?? true)) return null;
      return retryDelay?.call(item.retryCount + 1) ?? Duration.zero;
    } catch (e, s) {
      Zone.current.handleUncaughtError(e, s);
      return null;
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

/// An item's place among the waiting items.
final class _WaitingItem<T> extends LinkedListEntry<_WaitingItem<T>> {
  _WaitingItem(this.item);

  final QueueItem<T> item;
}

/// The items of a batch: a lazy view of the queue's items. The current batch
/// is the end of the list, so finding it doesn't go through the earlier
/// batches.
class _BatchItems<T> extends Iterable<QueueItem<T>> {
  _BatchItems(this._queue, this._batchId);

  final QueueIt<T> _queue;
  final String _batchId;

  @override
  Iterator<QueueItem<T>> get iterator {
    final start = _batchId == _queue._currentBatchId ? _queue._batchStart : 0;
    return _queue._items
        .skip(start)
        .where((item) => item.batchId == _batchId)
        .iterator;
  }
}
