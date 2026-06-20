// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Conversations/SortOrderExtensions.cs.

import '../models/sort_order.dart';

/// Extension helpers for [SortOrder].
extension SortOrderExtensions on SortOrder {
  /// The string representation (`asc` or `desc`).
  String toOrderString() => this == SortOrder.ascending ? 'asc' : 'desc';

  /// Whether this order is ascending.
  bool get isAscending => this == SortOrder.ascending;
}
