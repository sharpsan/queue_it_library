/// What happened to a queue, as told by each snapshot on its `onUpdate` stream.
///
/// New events may be added in minor versions, so give a `switch` over them a
/// default case.
enum QueueEvent {
  /// An item was added. The snapshot's `eventItem` is the new item.
  itemAdded,

  /// An item was removed. The snapshot's `eventItem` is the removed item.
  itemRemoved,

  /// The queue was started.
  startedQueue,

  /// The queue started processing items after having none to process.
  startedProcessing,

  /// An item's status changed. The snapshot's `eventItem` is the item, with
  /// its new status.
  itemStatusUpdated,

  /// Every item was removed.
  removedAll,

  /// Every pending and processing item was canceled.
  canceledAll,

  /// The queue has no items left to process, or it was stopped and the items
  /// it was processing have finished.
  stoppedProcessing,

  /// The queue was stopped.
  stoppedQueue,
}
