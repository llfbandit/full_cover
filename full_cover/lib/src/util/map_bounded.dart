/// Applies [task] to each of [items] with at most [maxConcurrent] running at
/// once, preserving input order in the returned results.
Future<List<T>> mapBounded<S, T>(
  List<S> items,
  int maxConcurrent,
  Future<T> Function(S item) task,
) async {
  final results = List<T?>.filled(items.length, null);
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final index = next++;
      if (index >= items.length) return;
      results[index] = await task(items[index]);
    }
  }

  final workerCount = maxConcurrent < items.length
      ? maxConcurrent
      : items.length;
  await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
  return results.cast<T>();
}
