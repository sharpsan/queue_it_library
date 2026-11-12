import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter_queue_it/flutter_queue_it.dart';
import 'package:material_ui/material_ui.dart';

import 'photos.dart';

void main() {
  runApp(
    MaterialApp(
      title: 'Upload photos',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const UploadsPage(pickPhotos: pickSamplePhotos, upload: fakeUpload),
    ),
  );
}

/// Uploads photos three at a time and retries the ones that fail.
/// `QueueItWidget` keeps the screen up to date, and `QueueItListener` tells
/// the user when a photo couldn't be uploaded.
class UploadsPage extends StatefulWidget {
  const UploadsPage({
    super.key,
    required this.pickPhotos,
    required this.upload,
  });

  /// Picks the photos to upload.
  final Future<List<Photo>> Function() pickPhotos;

  /// Uploads a photo, reporting how much has been sent, from 0 to 1. Canceling
  /// the stream's subscription should stop the upload.
  final Stream<double> Function(Photo photo) upload;

  @override
  State<UploadsPage> createState() => _UploadsPageState();
}

/// A photo's row in the list. Retrying a photo adds it to the queue again as
/// a new item, so the row keeps the id of the latest one.
class _Row {
  _Row(this.photo, this.itemId);

  final Photo photo;
  String itemId;
}

typedef _Upload = ({
  StreamSubscription<double> subscription,
  Completer<void> done,
});

class _UploadsPageState extends State<UploadsPage> {
  late final _queue = QueueIt<Photo>(
    parallel: 3,
    retries: 2,
    retryDelay: (item, retry) => Duration(seconds: retry),
    itemHandler: _upload,
  );

  /// The page's own ScaffoldMessenger, so its SnackBars go when it does.
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  /// The item whose failure the SnackBar is showing.
  String? _failureShown;

  /// The rows, in the order they're shown.
  final _rows = <_Row>[];

  /// The rows added since the last frame, which slide in.
  final _newRows = <_Row>{};

  /// How much of each upload has been sent, by item id. The queue only knows
  /// the item's status.
  final _progress = <String, ValueNotifier<double>>{};

  /// The uploads in progress, by item id.
  final _uploads = <String, _Upload>{};

  @override
  void initState() {
    super.initState();
    // Keep the queue running, so photos added later upload right away.
    _queue.start(stopAutomatically: false);
  }

  @override
  void dispose() {
    for (final id in _uploads.keys.toList()) {
      _stopUpload(id);
    }
    _queue.dispose();
    for (final progress in _progress.values) {
      progress.dispose();
    }
    super.dispose();
  }

  ValueNotifier<double> _progressOf(String id) =>
      _progress.putIfAbsent(id, () => ValueNotifier(0));

  Future<void> _upload(QueueItem<Photo> item) async {
    final progress = _progressOf(item.id)..value = 0;
    final done = Completer<void>();
    _uploads[item.id] = (
      subscription: widget
          .upload(item.data)
          .listen(
            (sent) => progress.value = sent,
            onError: (Object error, StackTrace stackTrace) {
              if (!done.isCompleted) done.completeError(error, stackTrace);
            },
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            cancelOnError: true,
          ),
      done: done,
    );
    try {
      // Throwing here, when the upload fails, makes the queue retry it.
      await done.future;
    } finally {
      _uploads.remove(item.id);
    }
  }

  /// Stops an upload in progress. The queue doesn't stop a handler when its
  /// item is canceled or removed, so this stops the upload and lets the
  /// handler return, which frees its place for the next photo.
  void _stopUpload(String id) {
    final upload = _uploads.remove(id);
    if (upload == null) return;
    // How a stopped upload ends doesn't matter any more.
    upload.subscription.cancel().ignore();
    if (!upload.done.isCompleted) upload.done.complete();
  }

  _Row? _rowOf(String id) {
    for (final row in _rows) {
      if (row.itemId == id) return row;
    }
    return null;
  }

  QueueItemStatus? _statusOf(_Row row) {
    for (final item in _queue.items()) {
      if (item.id == row.itemId) return item.status;
    }
    return null;
  }

  Future<void> _addPhotos() async {
    final photos = await widget.pickPhotos();
    if (!mounted) return;
    for (final photo in photos) {
      final row = _Row(photo, _queue.add(photo));
      _rows.add(row);
      _newRows.add(row);
    }
    // Only the rows shown in the next frame slide in, not the ones scrolled to
    // later.
    WidgetsBinding.instance.addPostFrameCallback((_) => _newRows.clear());
  }

  // The actions take a row rather than an item, since a row's item changes
  // when it's retried.

  void _cancel(_Row row) {
    _queue.cancelById(row.itemId);
    _stopUpload(row.itemId);
  }

  void _remove(_Row row) {
    _queue.removeById(row.itemId);
    _stopUpload(row.itemId);
    _hideFailure(row.itemId);
    _rows.remove(row);
    _progress.remove(row.itemId)?.dispose();
  }

  /// Adds a failed or canceled photo to the queue again, in the same row.
  void _retry(_Row row) {
    // Not if it's already been retried or removed, for example from its
    // SnackBar.
    final status = _statusOf(row);
    if (!mounted ||
        (status != QueueItemStatus.failed &&
            status != QueueItemStatus.canceled)) {
      return;
    }
    _queue.removeById(row.itemId);
    _hideFailure(row.itemId);
    _progress.remove(row.itemId)?.dispose();
    row.itemId = _queue.add(row.photo);
  }

  void _clearFinished() {
    for (final item in _queue.items().where(_isFinished).toList()) {
      if (_rowOf(item.id) case final row?) _remove(row);
    }
  }

  /// Tells the user when a photo has run out of retries.
  void _showFailure(BuildContext context, QueueSnapshot<Photo> snapshot) {
    final item = snapshot.eventItem;
    // Every failed attempt sends a failed status, and this queue retries every
    // error, so only the attempt with no retries left stays. With a retryIf,
    // an item can fail for good sooner: waitFor tells you when.
    if (item == null ||
        item.status != QueueItemStatus.failed ||
        item.retryCount < _queue.retries) {
      return;
    }
    _failureShown = item.id;
    ScaffoldMessenger.of(context)
      // Show the latest failure right away. Each photo's row can retry it too.
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text("${item.data.name} couldn't be uploaded"),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () {
              // The SnackBar hides itself.
              if (_failureShown == item.id) _failureShown = null;
              if (_rowOf(item.id) case final row?) _retry(row);
            },
          ),
          // Go after a few seconds, even though there's an action.
          persist: false,
        ),
      );
  }

  /// Hides the SnackBar if it's about [itemId], which was retried or removed.
  void _hideFailure(String itemId) {
    if (_failureShown != itemId) return;
    _failureShown = null;
    _messenger.currentState?.clearSnackBars();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messenger,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Upload photos'),
          actions: [
            // Only starting and stopping the queue changes this button.
            QueueItWidget<Photo>(
              queue: _queue,
              buildWhen: (snapshot) =>
                  snapshot.event == QueueEvent.startedQueue ||
                  snapshot.event == QueueEvent.stoppedQueue,
              builder: (context, snapshot) => _queue.isStarted
                  ? IconButton(
                      onPressed: _queue.stop,
                      tooltip: 'Pause uploads',
                      icon: const Icon(Icons.pause),
                    )
                  : IconButton(
                      onPressed: () => _queue.start(stopAutomatically: false),
                      tooltip: 'Resume uploads',
                      icon: const Icon(Icons.play_arrow),
                    ),
            ),
            QueueItWidget<Photo>(
              queue: _queue,
              builder: (context, snapshot) => IconButton(
                onPressed: _queue.items().any(_isFinished)
                    ? _clearFinished
                    : null,
                tooltip: 'Clear finished',
                icon: const Icon(Icons.clear_all),
              ),
            ),
          ],
        ),
        body: QueueItListener<Photo>(
          queue: _queue,
          listener: _showFailure,
          child: QueueItWidget<Photo>(
            queue: _queue,
            builder: (context, snapshot) {
              final items = {for (final item in _queue.items()) item.id: item};
              final rows = [
                for (final row in _rows)
                  if (items[row.itemId] case final item?)
                    (row: row, item: item),
              ];
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                // Fade the empty screen out before the list fades in.
                switchInCurve: _fadeIn,
                switchOutCurve: _fadeOut,
                child: rows.isEmpty
                    ? const _EmptyState()
                    : Column(
                        key: const ValueKey('uploads'),
                        children: [
                          _Summary(
                            items: [for (final (:item, row: _) in rows) item],
                            isStarted: _queue.isStarted,
                            progressOf: _progressOf,
                          ),
                          Expanded(child: _buildList(rows)),
                        ],
                      ),
              );
            },
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addPhotos,
          tooltip: 'Add photos',
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Add photos'),
        ),
      ),
    );
  }

  Widget _buildList(List<({_Row row, QueueItem<Photo> item})> rows) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final (:row, :item) = rows[index];
        return _PhotoTile(
          key: ObjectKey(row),
          item: item,
          progress: _progressOf(item.id),
          slideIn: _newRows.contains(row),
          onCancel: () => _cancel(row),
          onRetry: () => _retry(row),
          onRemove: () => _remove(row),
        );
      },
      // Match the tiles to their rows, so the ones below a removed photo keep
      // their state, like a swipe in progress.
      findChildIndexCallback: (key) {
        final index = rows.indexWhere((entry) => ObjectKey(entry.row) == key);
        return index < 0 ? null : index;
      },
    );
  }
}

// For AnimatedSwitcher: the old child fades out before the new one fades in,
// so they don't overlap.
const _fadeIn = Interval(0.5, 1, curve: Curves.easeOut);
const _fadeOut = Interval(0.5, 1, curve: Curves.easeIn);

bool _isFinished(QueueItem<Photo> item) => switch (item.status) {
  QueueItemStatus.completed ||
  QueueItemStatus.failed ||
  QueueItemStatus.canceled => true,
  _ => false,
};

/// How the uploads are going: what's happening, how many are done, and a
/// progress bar that moves with each photo.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.items,
    required this.isStarted,
    required this.progressOf,
  });

  final List<QueueItem<Photo>> items;
  final bool isStarted;
  final ValueNotifier<double> Function(String id) progressOf;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final uploading = items.processing.toList();
    final active = uploading.length + items.pending.length;
    final uploaded = items.completed.length;
    final failed = items.failed.length;
    final canceled = items.canceled.length;

    final (icon, color, title) = switch (active) {
      > 0 when isStarted => (
        Icons.cloud_upload_outlined,
        colors.primary,
        'Uploading photos',
      ),
      > 0 when uploading.isNotEmpty => (
        Icons.pause_circle_outline,
        colors.onSurfaceVariant,
        'Pausing…',
      ),
      > 0 => (Icons.pause_circle_outline, colors.onSurfaceVariant, 'Paused'),
      _ when uploaded == items.length => (
        Icons.cloud_done_outlined,
        colors.primary,
        'All photos uploaded',
      ),
      _ when failed > 0 => (
        Icons.error_outline,
        colors.error,
        'Some photos failed',
      ),
      _ => (Icons.cloud_outlined, colors.onSurfaceVariant, 'Uploads finished'),
    };
    final detail = [
      '$uploaded of ${items.length} uploaded',
      if (failed > 0) '$failed failed',
      if (canceled > 0) '$canceled canceled',
    ].join(' · ');

    return Card.filled(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: _fadeIn,
                  switchOutCurve: _fadeOut,
                  // The default one keys each child, and tapping Pause and Resume
                  // quickly would show the same icon twice.
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: Icon(icon, key: ValueKey(icon), color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.titleMedium),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Count the photos being uploaded by how much of them has been
            // sent, so the bar moves smoothly.
            ListenableBuilder(
              listenable: Listenable.merge([
                for (final item in uploading) progressOf(item.id),
              ]),
              builder: (context, _) {
                final sending = uploading.fold(
                  0.0,
                  (sum, item) => sum + progressOf(item.id).value,
                );
                return _Bar(
                  value: (items.length - active + sending) / items.length,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A photo in the list, with its status, progress and actions. Swipe it away
/// to remove it.
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required super.key,
    required this.item,
    required this.progress,
    required this.slideIn,
    required this.onCancel,
    required this.onRetry,
    required this.onRemove,
  });

  final QueueItem<Photo> item;
  final ValueNotifier<double> progress;
  final bool slideIn;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dismissible(
      key: key!,
      direction: DismissDirection.endToStart,
      // Stop the upload as soon as the photo is swiped away, rather than once
      // the row has gone.
      confirmDismiss: (direction) async {
        onCancel();
        return true;
      },
      onDismissed: (direction) => onRemove(),
      background: ColoredBox(
        color: colors.errorContainer,
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Icon(Icons.delete_outline, color: colors.onErrorContainer),
          ),
        ),
      ),
      child: _AnimateIn(
        animate: slideIn,
        // Lets screen readers remove a photo, since they can't swipe.
        child: Semantics(
          container: true,
          customSemanticsActions: {
            const CustomSemanticsAction(label: 'Remove'): onRemove,
          },
          child: ListTile(
            leading: _Thumbnail(image: item.data.image),
            title: Text(
              item.data.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: _buildStatus(context),
            trailing: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: _fadeIn,
              switchOutCurve: _fadeOut,
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(
                  opacity: animation,
                  child: _TappableWhenSettled(
                    animation: animation,
                    child: child,
                  ),
                ),
              ),
              child: _buildAction(colors),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatus(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = _megabytes(item.data.size);
    final retry = item.retryCount;
    final (String status, Color? color) = switch (item.status) {
      QueueItemStatus.pending when retry > 0 => (
        'Upload failed, retrying',
        colors.tertiary,
      ),
      QueueItemStatus.pending => ('Waiting · $size MB', null),
      QueueItemStatus.processing => ('', null),
      QueueItemStatus.completed => ('Uploaded · $size MB', null),
      QueueItemStatus.failed => (
        // Show the error only when it's one of ours, with a short message.
        item.error is UploadException
            ? "Couldn't upload: ${item.error}"
            : "Couldn't upload",
        colors.error,
      ),
      QueueItemStatus.canceled => ('Canceled', null),
      QueueItemStatus.removed => ('Removed', null),
    };
    Widget line(String text) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: color == null ? null : TextStyle(color: color),
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: _fadeIn,
      switchOutCurve: _fadeOut,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.topStart,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(
        key: ValueKey((item.id, item.status)),
        child: item.status == QueueItemStatus.processing
            ? ValueListenableBuilder(
                valueListenable: progress,
                builder: (context, sent, _) => line(
                  '${retry > 0 ? 'Retry $retry · ' : ''}'
                  '${_megabytes(item.data.size * sent)} of $size MB',
                ),
              )
            : line(status),
      ),
    );
  }

  Widget _buildAction(ColorScheme colors) {
    switch (item.status) {
      case QueueItemStatus.pending || QueueItemStatus.processing:
        // The same button while the photo waits and uploads, so it can always
        // be tapped, with a ring around it for how much has been sent.
        return Stack(
          key: const ValueKey('cancel'),
          alignment: Alignment.center,
          children: [
            AnimatedOpacity(
              opacity: item.status == QueueItemStatus.processing ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: ValueListenableBuilder(
                valueListenable: progress,
                builder: (context, sent, _) => _Ring(value: sent),
              ),
            ),
            IconButton(
              onPressed: onCancel,
              tooltip: 'Cancel',
              icon: const Icon(Icons.close, size: 20),
            ),
          ],
        );
      case QueueItemStatus.completed:
        return Padding(
          key: const ValueKey('done'),
          padding: const EdgeInsets.all(12),
          child: Icon(Icons.check_circle, color: colors.primary),
        );
      case QueueItemStatus.failed || QueueItemStatus.canceled:
        return IconButton(
          key: const ValueKey('retry'),
          onPressed: onRetry,
          tooltip: 'Retry',
          icon: const Icon(Icons.refresh),
        );
      case QueueItemStatus.removed:
        return const SizedBox.shrink(key: ValueKey('removed'));
    }
  }
}

String _megabytes(num bytes) => (bytes / 1000000).toStringAsFixed(1);

/// Lets [child] take taps only once [animation] has finished, so a quick
/// second tap doesn't land on the button that's replacing it.
class _TappableWhenSettled extends StatelessWidget {
  const _TappableWhenSettled({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) =>
          IgnorePointer(ignoring: !animation.isCompleted, child: child),
      child: child,
    );
  }
}

/// A rounded progress bar that moves smoothly between values.
class _Bar extends StatelessWidget {
  const _Bar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: const Duration(milliseconds: 200),
      builder: (context, value, _) => LinearProgressIndicator(
        value: value,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// A progress ring that moves smoothly between values.
class _Ring extends StatelessWidget {
  const _Ring({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: const Duration(milliseconds: 200),
      builder: (context, value, _) => SizedBox.square(
        dimension: 36,
        child: CircularProgressIndicator(
          value: value,
          strokeWidth: 3,
          backgroundColor: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest,
        ),
      ),
    );
  }
}

/// A photo's thumbnail, which fades in once it's loaded.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.image});

  final ImageProvider image;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: 48,
        child: ColoredBox(
          color: colors.surfaceContainerHighest,
          child: Image(
            image: image,
            fit: BoxFit.cover,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                wasSynchronouslyLoaded
                ? child
                : AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 300),
                    child: child,
                  ),
            errorBuilder: (context, error, stackTrace) =>
                Icon(Icons.image_outlined, color: colors.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// Slides and fades a new photo in. The rows are always wrapped in this, so
/// that rebuilding one keeps its state.
class _AnimateIn extends StatefulWidget {
  const _AnimateIn({required this.animate, required this.child});

  /// Whether to slide in, rather than appear in place. Only read once.
  final bool animate;
  final Widget child;

  @override
  State<_AnimateIn> createState() => _AnimateInState();
}

class _AnimateInState extends State<_AnimateIn>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
    value: widget.animate ? 0 : 1,
  )..forward();
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final _offset = Tween(
    begin: const Offset(0, 0.3),
    end: Offset.zero,
  ).animate(_curve);

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

/// Shown before any photos are added.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_outlined, size: 64, color: colors.outline),
          const SizedBox(height: 16),
          Text('No uploads yet', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Add photos to upload them, three at a time.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
