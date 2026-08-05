import 'package:extensions_flutter/extensions_flutter.dart';

import '../storage/record_store.dart';
import 'skill_store.dart';

/// Registers the user-authored skills subsystem into a [ServiceCollection].
extension SkillsServiceCollectionExtensions on ServiceCollection {
  /// Registers the [SkillStore] over the registered `RecordStore`.
  ///
  /// With the store registered, `ConversationScopeWiring.apply` connects it
  /// to each conversation: stored skills back the agent's skills provider,
  /// and durable conversations gain the `create_skill` tool. Registration is
  /// `tryAddSingleton`, so an earlier registration wins.
  ServiceCollection addSkillStore() {
    tryAddSingleton<SkillStore>(
      (sp) => SkillStore(sp.getRequiredService<RecordStore>()),
    );
    return this;
  }
}
