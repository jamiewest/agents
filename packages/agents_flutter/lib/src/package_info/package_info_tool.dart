import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'app_info.dart';

/// Builds the `get_app_info` tool bound to [appInfo].
///
/// Reports this app's own metadata — name, package/bundle id, version, and
/// build number — from the value cached at startup by
/// [PackageInfoHostedService]. Returns a not-available message if startup
/// loading has not completed yet.
AIFunctionDeclaration createGetAppInfoTool(AppInfo appInfo) {
  return AIFunctionFactory.create(
    name: 'get_app_info',
    description:
        'Returns this app\'s own metadata: display name, package/bundle '
        'identifier, version, and build number.',
    callback: (arguments, {CancellationToken? cancellationToken}) async {
      final info = appInfo.info;
      if (info == null) {
        return 'App info is not available yet.';
      }
      return 'App name: ${info.appName}\n'
          'Package id: ${info.packageName}\n'
          'Version: ${info.version}\n'
          'Build number: ${info.buildNumber}';
    },
  );
}
