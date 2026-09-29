/// Hybrid Logical Clock (HLC) for CRDT conflict resolution.
///
/// Combines a physical wall-clock timestamp with a logical counter and a
/// unique node ID so that distributed writes can be totally ordered even
/// when clocks drift between machines.
class HLC implements Comparable<HLC> {
  /// Milliseconds since epoch (physical component).
  final int timestamp;

  /// Logical counter — breaks ties when timestamps are equal.
  final int counter;

  /// Unique identifier of the node that generated this clock value.
  final String nodeId;

  const HLC({
    required this.timestamp,
    required this.counter,
    required this.nodeId,
  });

  /// Creates an HLC seeded from the current wall-clock time.
  factory HLC.now(String nodeId) {
    return HLC(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      counter: 0,
      nodeId: nodeId,
    );
  }

  /// Zero-value HLC (compares less than any real clock).
  factory HLC.zero(String nodeId) {
    return HLC(timestamp: 0, counter: 0, nodeId: nodeId);
  }

  // ---------------------------------------------------------------------------
  // Core HLC operations
  // ---------------------------------------------------------------------------

  /// Increment this clock for a **local write**.
  ///
  /// Returns a new HLC whose timestamp is `max(wall-clock, this.timestamp)`
  /// with an appropriate counter bump.
  HLC send() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now > timestamp) {
      return HLC(timestamp: now, counter: 0, nodeId: nodeId);
    }
    return HLC(timestamp: timestamp, counter: counter + 1, nodeId: nodeId);
  }

  /// Merge this clock with a **remote** clock received during sync.
  ///
  /// Returns a new HLC that is strictly greater than both `this` and [remote].
  HLC receive(HLC remote) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now > timestamp && now > remote.timestamp) {
      return HLC(timestamp: now, counter: 0, nodeId: nodeId);
    }
    if (timestamp == remote.timestamp) {
      final maxCounter = counter > remote.counter ? counter : remote.counter;
      return HLC(timestamp: timestamp, counter: maxCounter + 1, nodeId: nodeId);
    }
    if (timestamp > remote.timestamp) {
      return HLC(timestamp: timestamp, counter: counter + 1, nodeId: nodeId);
    }
    return HLC(
      timestamp: remote.timestamp,
      counter: remote.counter + 1,
      nodeId: nodeId,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialisation  (timestamp:counter:nodeId)
  // ---------------------------------------------------------------------------

  /// Pack to a string that can be stored in SQLite and compared lexically.
  ///
  /// Format: `<timestamp_hex_13>:<counter_hex_4>:<nodeId>`
  String pack() {
    final ts = timestamp.toRadixString(16).padLeft(13, '0');
    final ct = counter.toRadixString(16).padLeft(4, '0');
    return '$ts:$ct:$nodeId';
  }

  /// Unpack from a previously packed string.
  factory HLC.unpack(String packed) {
    if (packed.isEmpty) {
      return const HLC(timestamp: 0, counter: 0, nodeId: '');
    }
    final parts = packed.split(':');
    if (parts.length < 3) {
      return const HLC(timestamp: 0, counter: 0, nodeId: '');
    }
    return HLC(
      timestamp: int.parse(parts[0], radix: 16),
      counter: int.parse(parts[1], radix: 16),
      nodeId: parts.sublist(2).join(':'), // nodeId may contain colons
    );
  }

  // ---------------------------------------------------------------------------
  // Comparison
  // ---------------------------------------------------------------------------

  @override
  int compareTo(HLC other) {
    if (timestamp != other.timestamp) {
      return timestamp.compareTo(other.timestamp);
    }
    if (counter != other.counter) {
      return counter.compareTo(other.counter);
    }
    return nodeId.compareTo(other.nodeId);
  }

  bool operator >(HLC other) => compareTo(other) > 0;
  bool operator <(HLC other) => compareTo(other) < 0;
  bool operator >=(HLC other) => compareTo(other) >= 0;
  bool operator <=(HLC other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HLC &&
          timestamp == other.timestamp &&
          counter == other.counter &&
          nodeId == other.nodeId;

  @override
  int get hashCode => Object.hash(timestamp, counter, nodeId);

  @override
  String toString() => 'HLC($timestamp:$counter@$nodeId)';
}
