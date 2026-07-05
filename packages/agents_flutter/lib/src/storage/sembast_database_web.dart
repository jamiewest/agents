// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:sembast_web/sembast_web.dart';

/// Opens an IndexedDB-backed sembast database.
Future<Database> openPlatformDatabase(String name) =>
    databaseFactoryWeb.openDatabase(name);

/// Deletes the IndexedDB-backed sembast database named [name].
///
/// The database must be closed first.
Future<void> deletePlatformDatabase(String name) =>
    databaseFactoryWeb.deleteDatabase(name);
