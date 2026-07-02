// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:extensions_flutter/extensions_flutter.dart';

import 'record_store.dart';
import 'sembast_record_store.dart';

/// Registers the durable [RecordStore] into a [ServiceCollection].
extension StorageServiceCollectionExtensions on ServiceCollection {
  /// Registers a singleton [RecordStore].
  ///
  /// Uses `tryAddSingleton`, so any instance registered earlier — including
  /// an [InMemoryRecordStore] test fake — is preserved. By default the store
  /// is a [SembastRecordStore] over the platform database (file-backed on
  /// native, IndexedDB on the web). Supply [recordStore] to override.
  ServiceCollection addRecordStore({
    RecordStore Function(ServiceProvider sp)? recordStore,
  }) {
    tryAddSingleton<RecordStore>(
      (sp) => recordStore?.call(sp) ?? SembastRecordStore.open(),
    );
    return this;
  }
}
