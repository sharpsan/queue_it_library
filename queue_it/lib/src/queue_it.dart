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
/// [QueueItemStatus.failed], with the error in [QueueItem.error]. Retries go
/// ahead of the other pending items, in the order they're due.
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
  ///
  /// Throws an [ArgumentError] if [parallel] is less than 1 or [retries] is
  /// negative.
  QueueIt({
    required this.itemHandler,
    this.retries = 0,
    this.retryDelay,
    this.retryIf,
    this.parallel = 1,
    this.useFriendlyIds = false,
    this.deepCopyItemsInSnapshot = false,
  }) {
    if (parallel < 1) {
      throw ArgumentError.value(parallel, 'parallel', 'Must be at least 1');
    }
    if (retries < 0) {
      throw ArgumentError.value(retries, 'retries', 'Must not be negative');
    }
  }

  /// Every item in the queue, in the order they were added, and each one's
  /// place in it by id. Removing an item takes it out at once.
  final _items = LinkedList<_ItemEntry<T>>();
  final _itemsById = <String, _ItemEntry<T>>{};

  /// The items waiting to be processed, and each one's place among them.
  /// Retries go first, in the order they're due, then the other items in
  /// order. Items leave as soon as they're canceled or removed.
  final _waitingRetries = LinkedList<_WaitingItem<T>>();
  final _waiting = LinkedList<_WaitingItem<T>>();
  final _waitingEntries = <QueueItem<T>, _WaitingItem<T>>{};

  /// The items whose handler is running or about to start, or whose outcome
  /// is being applied, including items canceled or removed since then.
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

  /// The first item of the current batch in [_items], or null if it has
  /// none left. Items are only added at the end, and a batch only starts once
  /// every item has finished, so the current batch is the end of the list.
  _ItemEntry<T>? _batchStart;

  /// Counts the changes to [_items], so that iterating the current batch
  /// notices the queue changing, as iterating a list does.
  var _itemChanges = 0;
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
  /// Handlers of items canceled or removed while they run count until they
  /// return.
  bool get isProcessing => _isProcessing;

  /// Whether the queue has been started and not stopped since.
  bool get isStarted => _isStarted;

  /// A future that completes when the queue has stopped and the items it was
  /// processing have finished, including the handlers of items canceled or
  /// removed meanwhile. It's already complete if the queue was never
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
      ? _items.map((entry) => entry.item)
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
    // Started again before the handlers of a stop returned, the queue carries
    // on with the same run. Once they've returned, that run is over, even if
    // a listener of the stop starts the queue before running completes.
    final running = _running;
    if (running != null && !running.isCompleted && _runningItems.isEmpty) {
      running.complete();
    }
    if (_running?.isCompleted ?? true) _running = Completer<void>();
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

  QueueItem<T>? _itemById(String id) => _itemsById[id]?.item;

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
      _batchStart = null;
    }

    final item = QueueItem(
      data: data,
      status: QueueItemStatus.pending,
      batchId: _currentBatchId,
      id: id ?? _newId(),
    );
    final entry = _ItemEntry(item);
    _items.add(entry);
    _itemChanges++;
    _itemsById[item.id] = entry;
    _batchStart ??= entry;
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
    final item = _itemById(id);
    if (item == null) return false;
    _remove(item);
    _schedulePump();
    return true;
  }

  /// Removes all items, as [remove] does, and sends one
  /// [QueueEvent.removedAll] event.
  void removeAll() {
    final removed = items().toList();
    _items.clear();
    _itemChanges++;
    _batchStart = null;
    _itemsById.clear();
    _waitingRetries.clear();
    _waiting.clear();
    _waitingEntries.clear();
    _retrying.clear();
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    for (final item in removed) {
      item.updateStatus(QueueItemStatus.removed);
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
    final item = _itemById(id);
    if (item == null || !_cancel(item)) return false;
    _notifyWaiters(item);
    _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
    _schedulePump();
    return true;
  }

  /// Cancels every pending and processing item, as [cancel] does, and sends
  /// one [QueueEvent.canceledAll] event.
  void cancelAll() {
    final canceled = <QueueItem<T>>[];
    for (final entry in _items) {
      if (_cancel(entry.item)) canceled.add(entry.item);
    }
    canceled.forEach(_notifyWaiters);
    _sendOnUpdateEvent(QueueEvent.canceledAll, null);
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
    final item = _itemById(id);
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
    // When a listener disposes the queue, the stream closes once the events
    // queued until then have reached every listener.
    if (!_isSendingSnapshots) _onUpdateStreamController.close();
  }

  @override
  String toString() {
    final s = StringBuffer();
    s.writeln('Started: $_isStarted');
    s.writeln('Processing: $_isProcessing');
    s.writeln('Current Batch Id: $_currentBatchId');
    s.writeln('Items: ${items().map((e) => e.data).toList()}');
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
      _waitingEntries.isNotEmpty ||
      _retryTimers.isNotEmpty ||
      _retrying.isNotEmpty ||
      _runningItems.any((item) =>
          item.status == QueueItemStatus.pending ||
          item.status == QueueItemStatus.processing);

  /// Whether the queue has anything left to do: items waiting or waiting to
  /// be retried, or handlers running.
  bool _hasWork() =>
      _waitingEntries.isNotEmpty ||
      _retryTimers.isNotEmpty ||
      _runningItems.isNotEmpty;

  /// Adds [item] to the end of the waiting items, or of the waiting retries,
  /// or with [first], puts it back at the front of them.
  void _enqueue(QueueItem<T> item, {bool retry = false, bool first = false}) {
    final entry = _WaitingItem(item, isRetry: retry);
    _waitingEntries[item] = entry;
    final waiting = retry ? _waitingRetries : _waiting;
    first ? waiting.addFirst(entry) : waiting.add(entry);
  }

  _WaitingItem<T> _dequeue() {
    final waiting = _waitingRetries.isNotEmpty ? _waitingRetries : _waiting;
    final entry = waiting.first..unlink();
    _waitingEntries.remove(entry.item);
    return entry;
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
    item.updateStatus(QueueItemStatus.canceled);
    return true;
  }

  void _remove(QueueItem<T> item) {
    final entry = _itemsById.remove(item.id)!;
    if (identical(entry, _batchStart)) _batchStart = entry.next;
    entry.unlink();
    _itemChanges++;
    _retrying.remove(item);
    _unqueue(item);
    _retryTimers.remove(item.id)?.cancel();
    item.updateStatus(QueueItemStatus.removed);
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
    while (_isStarted &&
        _runningItems.length < parallel &&
        _waitingEntries.isNotEmpty) {
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

  /// Runs the handler for the [waiting] item and applies the outcome.
  Future<void> _process(_WaitingItem<T> waiting) async {
    final item = waiting.item;
    _runningItems.add(item);
    if (!_isProcessing) {
      _isProcessing = true;
      _lastStartedProcessingAt = DateTime.now();
      _sendOnUpdateEvent(QueueEvent.startedProcessing, null);
    }
    // Listeners can stop or dispose the queue, or cancel or remove the item,
    // before its handler starts.
    if (_isStarted && item.status == QueueItemStatus.pending) {
      item.updateStatus(QueueItemStatus.processing);
      _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
    } else if (item.status == QueueItemStatus.pending) {
      _enqueue(item, retry: waiting.isRetry, first: true);
    }
    if (_isDisposing || item.status != QueueItemStatus.processing) {
      _runningItems.remove(item);
      return;
    }

    // Only the handler chooses the attempt's outcome, so a nextStatus set
    // before it starts doesn't count.
    item.nextStatus = null;
    Object? error;
    StackTrace? stackTrace;
    try {
      // A handler that throws right away still settles a microtask later, as
      // one that returns does. Otherwise a run of such failures would start
      // each next item deeper on the stack.
      await Future<void>.sync(() => itemHandler(item));
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
        item.updateStatus(QueueItemStatus.completed);
        _notifyWaiters(item);
        _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
      case QueueItemStatus.failed:
        _fail(item, null, null);
      case QueueItemStatus.canceled:
        item.updateStatus(QueueItemStatus.canceled);
        _notifyWaiters(item);
        _sendOnUpdateEvent(QueueEvent.itemStatusUpdated, item);
      case QueueItemStatus.removed:
        _remove(item);
      case QueueItemStatus.pending:
        item.updateStatus(QueueItemStatus.pending);
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
      ..recordError(error, stackTrace)
      ..updateStatus(QueueItemStatus.failed);
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

    item.updateStatus(QueueItemStatus.pending);
    // A listener disposed the queue. The item stays pending, like the other
    // items that were waiting.
    if (_isDisposing) return;
    if (delay <= Duration.zero) {
      _enqueue(item, retry: true);
    } else {
      _retryTimers[item.id] = Timer(delay, () {
        _retryTimers.remove(item.id);
        _enqueue(item, retry: true);
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
      // retryIf canceled or removed the item, or disposed the queue.
      if (_isDisposing || item.status != QueueItemStatus.processing) {
        return null;
      }
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
    // A disposed queue sends no more events, even while the ones queued
    // before are still being delivered. A paused subscription keeps
    // hasListener true after the stream closes.
    if (_isDisposed ||
        _onUpdateStreamController.isClosed ||
        !_onUpdateStreamController.hasListener) {
      return;
    }
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

/// An item's place among the queue's items.
final class _ItemEntry<T> extends LinkedListEntry<_ItemEntry<T>> {
  _ItemEntry(this.item);

  final QueueItem<T> item;
}

/// An item's place among the waiting items or retries.
final class _WaitingItem<T> extends LinkedListEntry<_WaitingItem<T>> {
  _WaitingItem(this.item, {required this.isRetry});

  final QueueItem<T> item;
  final bool isRetry;
}

/// The items of a batch: a lazy view of the queue's items. The current batch
/// is the end of the list, so finding it doesn't go through the earlier
/// batches.
class _BatchItems<T> extends Iterable<QueueItem<T>> {
  _BatchItems(this._queue, this._batchId);

  final QueueIt<T> _queue;
  final String _batchId;

  @override
  Iterator<QueueItem<T>> get iterator => _batchId == _queue._currentBatchId
      ? _CurrentBatchIterator(_queue)
      : _queue.items().where((item) => item.batchId == _batchId).iterator;
}

/// Goes through the current batch from its first item. Like a list's
/// iterator, it throws a [ConcurrentModificationError] if items are added or
/// removed meanwhile.
class _CurrentBatchIterator<T> implements Iterator<QueueItem<T>> {
  _CurrentBatchIterator(this._queue)
      : _changes = _queue._itemChanges,
        _next = _queue._batchStart;

  final QueueIt<T> _queue;
  final int _changes;
  _ItemEntry<T>? _next;
  QueueItem<T>? _current;

  @override
  QueueItem<T> get current => _current as QueueItem<T>;

  @override
  bool moveNext() {
    if (_queue._itemChanges != _changes) {
      throw ConcurrentModificationError(_queue);
    }
    final entry = _next;
    if (entry == null) {
      _current = null;
      return false;
    }
    _current = entry.item;
    _next = entry.next;
    return true;
  }
}
