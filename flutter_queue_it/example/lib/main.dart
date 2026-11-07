import 'package:flutter_queue_it/flutter_queue_it.dart';
import 'package:material_ui/material_ui.dart';

import 'photos.dart';

void main() {
  runApp(
    MaterialApp(
      title: 'Upload photos',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
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

  /// Uploads a photo, reporting how much has been sent, from 0 to 1.
  final Stream<double> Function(Photo photo) upload;

  @override
  State<UploadsPage> createState() => _UploadsPageState();
}

class _UploadsPageState extends State<UploadsPage> {
  late final _queue = QueueIt<Photo>(
    parallel: 3,
    retries: 2,
    retryDelay: (retry) => Duration(seconds: retry),
    itemHandler: _upload,
  );

  /// How much of each photo's current attempt has been sent, by item id. The
  /// queue only knows the item's status.
  final _progress = <String, ValueNotifier<double>>{};

  /// The photos already shown, so only new ones animate in.
  final _shown = <String>{};

  @override
  void initState() {
    super.initState();
    // Keep the queue running, so photos added later upload right away.
    _queue.start(stopAutomatically: false);
  }

  @override
  void dispose() {
    _queue.dispose();
    super.dispose();
  }

  ValueNotifier<double> _progressOf(QueueItem<Photo> item) =>
      _progress.putIfAbsent(item.id, () => ValueNotifier(0));

  Future<void> _upload(QueueItem<Photo> item) async {
    final progress = _progressOf(item)..value = 0;
    await for (final sent in widget.upload(item.data)) {
      // The queue doesn't stop a handler when its photo is canceled or
      // removed, so stop the upload here.
      if (item.status != QueueItemStatus.processing) return;
      progress.value = sent;
    }
  }

  Future<void> _addPhotos() async {
    final photos = await widget.pickPhotos();
    if (!mounted) return;
    for (final photo in photos) {
      _queue.add(photo);
    }
  }

  void _remove(QueueItem<Photo> item) {
    _queue.remove(item);
    _progress.remove(item.id);
  }

  /// Adds the photo again, at the end of the list.
  void _retry(QueueItem<Photo> item) {
    // Already retried or removed, for example from its SnackBar.
    if (!_queue.remove(item)) return;
    _progress.remove(item.id);
    _queue.add(item.data);
  }

  void _clearFinished() {
    for (final item in _queue.items().toList()) {
      if (item.status
          case QueueItemStatus.completed ||
              QueueItemStatus.failed ||
              QueueItemStatus.canceled) {
        _remove(item);
      }
    }
  }

  /// Tells the user when a photo has run out of retries.
  void _showFailure(BuildContext context, QueueSnapshot<Photo> snapshot) {
    final item = snapshot.eventItem;
    // Every failed attempt sends a failed status. Only the last one stays.
    if (item == null ||
        item.status != QueueItemStatus.failed ||
        item.retryCount < _queue.retries) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("${item.data.name} couldn't be uploaded"),
        action: SnackBarAction(label: 'Retry', onPressed: () => _retry(item)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          IconButton(
            onPressed: _clearFinished,
            tooltip: 'Clear finished',
            icon: const Icon(Icons.clear_all),
          ),
        ],
      ),
      body: QueueItListener<Photo>(
        queue: _queue,
        listener: _showFailure,
        child: QueueItWidget<Photo>(
          queue: _queue,
          builder: (context, snapshot) {
            final items = _queue.items().toList();
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: items.isEmpty
                  ? const _EmptyState()
                  : Column(
                      key: const ValueKey('uploads'),
                      children: [
                        _Summary(
                          items: items,
                          isStarted: _queue.isStarted,
                          progressOf: _progressOf,
                        ),
                        Expanded(child: _buildList(items)),
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
    );
  }

  Widget _buildList(List<QueueItem<Photo>> items) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _PhotoTile(
          key: ValueKey(item.id),
          item: item,
          progress: _progressOf(item),
          animateIn: _shown.add(item.id),
          onCancel: () => _queue.cancel(item),
          onRetry: () => _retry(item),
          onRemove: () => _remove(item),
        );
      },
      // Match the tiles to their photos, so the ones below a removed photo
      // keep their state, like a swipe in progress.
      findChildIndexCallback: (key) {
        final index = items.indexWhere((item) => ValueKey(item.id) == key);
        return index < 0 ? null : index;
      },
    );
  }
}

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
  final ValueNotifier<double> Function(QueueItem<Photo> item) progressOf;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final uploading = items.processing.toList();
    final active = uploading.length + items.pending.length;
    final uploaded = items.completed.length;
    final failed = items.failed.length;

    final (icon, color, title) = switch ((active, isStarted, failed)) {
      (> 0, true, _) => (
        Icons.cloud_upload_outlined,
        colors.primary,
        'Uploading photos',
      ),
      (> 0, false, _) => (
        Icons.pause_circle_outline,
        colors.onSurfaceVariant,
        'Paused',
      ),
      (_, _, 0) => (
        Icons.cloud_done_outlined,
        colors.primary,
        'Uploads finished',
      ),
      _ => (Icons.error_outline, colors.error, 'Some photos failed'),
    };
    final detail = [
      '$uploaded of ${items.length} uploaded',
      if (failed > 0) '$failed failed',
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
                        style: text.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: active == 0
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      // Count the photos being uploaded by how much of them
                      // has been sent, so the bar moves smoothly.
                      child: ListenableBuilder(
                        listenable: Listenable.merge([
                          for (final item in uploading) progressOf(item),
                        ]),
                        builder: (context, _) {
                          final finished = items.length - active;
                          final sending = uploading.fold(
                            0.0,
                            (sum, item) => sum + progressOf(item).value,
                          );
                          return _Bar(
                            value: (finished + sending) / items.length,
                          );
                        },
                      ),
                    ),
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
    super.key,
    required this.item,
    required this.progress,
    required this.animateIn,
    required this.onCancel,
    required this.onRetry,
    required this.onRemove,
  });

  final QueueItem<Photo> item;
  final ValueNotifier<double> progress;
  final bool animateIn;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tile = ListTile(
      leading: _Thumbnail(image: item.data.image),
      title: Text(item.data.name),
      subtitle: _buildStatus(context),
      trailing: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: _buildAction(colors),
      ),
    );
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) => onRemove(),
      background: ColoredBox(
        color: colors.errorContainer,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Icon(Icons.delete_outline, color: colors.onErrorContainer),
          ),
        ),
      ),
      child: animateIn ? _AnimateIn(child: tile) : tile,
    );
  }

  Widget _buildStatus(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyMedium;
    final size = _megabytes(item.data.size);
    final retry = item.retryCount;
    final Widget status = switch (item.status) {
      QueueItemStatus.pending when retry > 0 => Text(
        'Upload failed, retrying',
        style: style?.copyWith(color: colors.tertiary),
      ),
      QueueItemStatus.pending => Text('Waiting · $size MB'),
      QueueItemStatus.processing => ValueListenableBuilder(
        valueListenable: progress,
        builder: (context, sent, _) => Text(
          '${retry > 0 ? 'Retry $retry · ' : ''}'
          '${_megabytes(item.data.size * sent)} of $size MB',
        ),
      ),
      QueueItemStatus.completed => Text('Uploaded · $size MB'),
      QueueItemStatus.failed => Text(
        "Couldn't upload: ${item.error}",
        style: style?.copyWith(color: colors.error),
      ),
      QueueItemStatus.canceled => const Text('Canceled'),
      QueueItemStatus.removed => const Text('Removed'),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(key: ValueKey((item.status, retry)), child: status),
    );
  }

  Widget _buildAction(ColorScheme colors) {
    switch (item.status) {
      case QueueItemStatus.pending:
        return IconButton(
          key: const ValueKey('waiting'),
          onPressed: onCancel,
          tooltip: 'Cancel',
          icon: const Icon(Icons.close),
        );
      case QueueItemStatus.processing:
        // The cross, with a ring around it for how much has been sent.
        return Stack(
          key: const ValueKey('uploading'),
          alignment: Alignment.center,
          children: [
            ValueListenableBuilder(
              valueListenable: progress,
              builder: (context, sent, _) => _Ring(value: sent),
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
        return const SizedBox.shrink();
    }
  }
}

String _megabytes(num bytes) => (bytes / 1000000).toStringAsFixed(1);

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

/// Slides and fades a new photo in.
class _AnimateIn extends StatefulWidget {
  const _AnimateIn({required this.child});

  final Widget child;

  @override
  State<_AnimateIn> createState() => _AnimateInState();
}

class _AnimateInState extends State<_AnimateIn>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  )..forward();
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

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
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).animate(_curve),
        child: widget.child,
      ),
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
      key: const ValueKey('empty'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_outlined, size: 64, color: colors.outline),
          const SizedBox(height: 16),
          Text('No uploads yet', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Add photos to upload them, three at a time.',
            style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
