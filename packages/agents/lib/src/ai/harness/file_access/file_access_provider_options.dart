import 'file_access_provider.dart';

/// Options controlling the behavior of [FileAccessProvider].
class FileAccessProviderOptions {
  FileAccessProviderOptions();

  /// Custom instructions provided to the agent for using the file access
  /// tools.
  String? instructions;

  /// Whether the tools that modify the store (write, delete, replace, and
  /// replace_lines) are omitted, exposing only the read-only tools (read,
  /// ls, and grep).
  bool disableWriteTools = false;

  /// Whether approval is disabled for the read-only tools (read, ls, and
  /// grep).
  ///
  /// When `false` (the default), the read-only tools require approval before
  /// invocation. When approval is required, auto-approval rules (e.g.
  /// [FileAccessProvider.readOnlyToolsAutoApprovalRule] or
  /// [FileAccessProvider.allToolsAutoApprovalRule]) can be used to
  /// automatically approve calls.
  bool disableReadOnlyToolApproval = false;

  /// Whether approval is disabled for the tools that modify the store
  /// (write, delete, replace, and replace_lines).
  ///
  /// When `false` (the default), the write tools require approval before
  /// invocation.
  bool disableWriteToolApproval = false;
}
