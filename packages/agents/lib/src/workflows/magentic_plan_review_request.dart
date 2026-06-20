import 'package:extensions/ai.dart';

import 'magentic_plan_review_response.dart';
import 'magentic_progress_ledger.dart';

/// Request for human review of a proposed Magentic plan.
class MagenticPlanReviewRequest {
  /// Creates a plan review request.
  ///
  /// [plan] is the proposed plan. [currentProgress] is the latest progress
  /// ledger when replanning after a stall, or `null` during the initial
  /// review. [isStalled] indicates whether the workflow is currently stalled.
  const MagenticPlanReviewRequest(
    this.plan,
    this.currentProgress,
    this.isStalled,
  );

  /// The proposed plan.
  final ChatMessage plan;

  /// The current progress ledger, if available.
  final MagenticProgressLedger? currentProgress;

  /// Whether the workflow is currently stalled.
  final bool isStalled;

  /// Creates an approving [MagenticPlanReviewResponse].
  MagenticPlanReviewResponse approve() => MagenticPlanReviewResponse(const []);

  /// Creates a revision response from a text [message].
  MagenticPlanReviewResponse reviseText(String message) =>
      MagenticPlanReviewResponse([
        ChatMessage.fromText(ChatRole.user, message),
      ]);

  /// Creates a revision response from one or more [messages].
  MagenticPlanReviewResponse revise(Iterable<ChatMessage> messages) =>
      MagenticPlanReviewResponse(messages.toList());
}
