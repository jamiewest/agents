// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:sembast/sembast.dart';

import 'sembast_database_io.dart'
    if (dart.library.js_interop) 'sembast_database_web.dart'
    as platform;

/// Opens the app's sembast database for the current platform.
///
/// On native platforms the database is a file named [name] under the
/// application support directory; on the web it is stored in IndexedDB.
Future<Database> openSembastDatabase({String name = 'agents_app.db'}) =>
    platform.openPlatformDatabase(name);

/// Deletes the app's sembast database for the current platform.
///
/// The database must be closed first. Deleting the whole database is the
/// only complete wipe: sembast does not expose the set of stores, so a
/// store-by-store clear cannot reach collections the caller does not know
/// about.
Future<void> deleteSembastDatabase({String name = 'agents_app.db'}) =>
    platform.deletePlatformDatabase(name);
