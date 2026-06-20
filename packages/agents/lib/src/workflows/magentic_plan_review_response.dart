import 'package:extensions/ai.dart';

/// Review feedback for a proposed Magentic plan.
///
/// An empty [review] list indicates the plan is approved as-is; a non-empty
/// list provides revision feedback to the manager.
class MagenticPlanReviewResponse {
  /// Creates a plan review response carrying [review] feedback messages.
  MagenticPlanReviewResponse(List<ChatMessage> review)
    : review = List<ChatMessage>.unmodifiable(review);

  /// Review feedback for the proposed plan. Empty when approved as-is.
  final List<ChatMessage> review;

  /// Whether the plan is approved without revisions.
  bool get isApproved => review.isEmpty;
}
