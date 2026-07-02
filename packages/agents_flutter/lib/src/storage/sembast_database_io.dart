// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

/// Opens a file-backed sembast database under application support.
Future<Database> openPlatformDatabase(String name) async {
  final directory = await getApplicationSupportDirectory();
  return databaseFactoryIo.openDatabase('${directory.path}/$name');
}
