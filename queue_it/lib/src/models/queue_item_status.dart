/// Where a queue item is in its life.
enum QueueItemStatus {
  /// Waiting to be processed, for the first time or for a retry.
  pending,

  /// Being processed: the queue's handler is running for the item.
  processing,

  /// Processed successfully. Final.
  completed,

  /// The last attempt failed and no retries are left. Final.
  ///
  /// Each failed attempt also passes through this status before the item goes
  /// back to [pending] for a retry.
  failed,

  /// Canceled before it finished. Final.
  canceled,

  /// Removed from the queue. Final.
  removed,
}
