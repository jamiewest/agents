// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Microsoft.Agents.AI.Hosting.OpenAI/InMemoryStorageOptions.cs.

import 'package:extensions/caching.dart';

/// Configuration options for in-memory storage implementations.
class InMemoryStorageOptions {
  /// Creates [InMemoryStorageOptions].
  InMemoryStorageOptions({
    this.sizeLimit = 1000,
    this.absoluteExpirationRelativeToNow,
    this.slidingExpiration = const Duration(hours: 1),
  });

  /// The maximum number of items to store in the cache.
  ///
  /// Default is 1000. Set to null for no size limit.
  int? sizeLimit;

  /// The absolute expiration, relative to now, for items in storage.
  ///
  /// When set, items expire after this duration regardless of access. Default
  /// is null (no absolute expiration).
  Duration? absoluteExpirationRelativeToNow;

  /// The sliding expiration for items in storage.
  ///
  /// Items expire if not accessed within this duration. Default is one hour.
  Duration? slidingExpiration;

  /// Creates [MemoryCacheOptions] from these options.
  MemoryCacheOptions toMemoryCacheOptions() =>
      MemoryCacheOptions(sizeLimit: sizeLimit);

  /// Creates [MemoryCacheEntryOptions] from these options.
  MemoryCacheEntryOptions toMemoryCacheEntryOptions() =>
      MemoryCacheEntryOptions(
        absoluteExpirationRelativeToNow: absoluteExpirationRelativeToNow,
        slidingExpiration: slidingExpiration,
        size: 1,
      );
}
