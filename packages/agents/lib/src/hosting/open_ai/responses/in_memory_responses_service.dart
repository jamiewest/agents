// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Responses/InMemoryResponsesService.cs.
//
// Orchestrates a [ResponseExecutor]: runs it, aggregates its streaming events
// into a stored [Response], and serves get/cancel/delete/list operations. Uses
// plain in-memory maps (dev/test only; see InMemoryConversationStorage).

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../conversations/conversation_storage.dart';
import '../id_generator.dart';
import '../models/list_response.dart';
import '../models/sort_order.dart';
import 'agent_invocation_context.dart';
import 'models/create_response.dart';
import 'models/item_resource.dart';
import 'models/response.dart';
import 'models/streaming_response_event.dart';
import 'response_executor.dart';
import 'responses_service.dart';

/// In-memory [ResponsesService] backed by a [ResponseExecutor].
class InMemoryResponsesService implements ResponsesService {
  /// Creates an [InMemoryResponsesService].
  InMemoryResponsesService(this._executor, [this._conversationStorage]);

  final ResponseExecutor _executor;
  final ConversationStorage? _conversationStorage;

  final Map<String, Response> _responses = {};
  final Map<String, List<StreamingResponseEvent>> _events = {};
  final Map<String, List<ItemResource>> _inputItems = {};

  @override
  Future<ResponseError?> validateRequest(
    CreateResponse request, {
    CancellationToken? cancellationToken,
  }) =>
      _executor.validateRequest(request, cancellationToken: cancellationToken);

  @override
  Future<Response> createResponse(
    CreateResponse request, {
    CancellationToken? cancellationToken,
  }) async {
    final context = _contextFor(request);
    final history = await _loadHistory(request, cancellationToken);

    final events = <StreamingResponseEvent>[];
    Response? terminal;
    await for (final event in _executor.execute(
      context,
      request,
      conversationHistory: history,
      cancellationToken: cancellationToken,
    )) {
      events.add(event);
      terminal = _terminalOf(event) ?? terminal;
    }

    final response =
        terminal ??
        Response(
          id: context.responseId,
          createdAt: _nowUnixSeconds(),
          status: ResponseStatus.completed,
        );
    await _store(request, context, response, events, cancellationToken);
    return response;
  }

  @override
  Stream<StreamingResponseEvent> createResponseStreaming(
    CreateResponse request, {
    CancellationToken? cancellationToken,
  }) async* {
    final context = _contextFor(request);
    final history = await _loadHistory(request, cancellationToken);

    final events = <StreamingResponseEvent>[];
    Response? terminal;
    await for (final event in _executor.execute(
      context,
      request,
      conversationHistory: history,
      cancellationToken: cancellationToken,
    )) {
      events.add(event);
      terminal = _terminalOf(event) ?? terminal;
      yield event;
    }

    if (terminal != null) {
      await _store(request, context, terminal, events, cancellationToken);
    }
  }

  @override
  Future<Response?> getResponse(
    String responseId, {
    CancellationToken? cancellationToken,
  }) async => _responses[responseId];

  @override
  Stream<StreamingResponseEvent> getResponseStreaming(
    String responseId, {
    int? startingAfter,
    CancellationToken? cancellationToken,
  }) async* {
    final events = _events[responseId] ?? const [];
    for (final event in events) {
      if (startingAfter == null || event.sequenceNumber > startingAfter) {
        yield event;
      }
    }
  }

  @override
  Future<Response> cancelResponse(
    String responseId, {
    CancellationToken? cancellationToken,
  }) async {
    final response = _responses[responseId];
    if (response == null) {
      throw StateError("Response '$responseId' not found.");
    }
    if (response.isTerminal) {
      throw StateError("Response '$responseId' is not in a cancellable state.");
    }
    response.status = ResponseStatus.cancelled;
    return response;
  }

  @override
  Future<bool> deleteResponse(
    String responseId, {
    CancellationToken? cancellationToken,
  }) async {
    _events.remove(responseId);
    _inputItems.remove(responseId);
    return _responses.remove(responseId) != null;
  }

  @override
  Future<ListResponse<ItemResource>> listResponseInputItems(
    String responseId, {
    int? limit,
    SortOrder? order,
    String? after,
    String? before,
    CancellationToken? cancellationToken,
  }) async {
    if (!_responses.containsKey(responseId)) {
      throw StateError("Response '$responseId' not found.");
    }

    final all = _inputItems[responseId] ?? const <ItemResource>[];
    final effectiveLimit = (limit ?? ResponsesService.defaultListLimit).clamp(
      1,
      100,
    );
    final ordered = (order ?? SortOrder.descending) == SortOrder.ascending
        ? all.toList()
        : all.reversed.toList();

    var startIndex = 0;
    if (after != null) {
      final idx = ordered.indexWhere((i) => i.id == after);
      if (idx >= 0) {
        startIndex = idx + 1;
      }
    }

    final page = ordered
        .skip(startIndex)
        .take(effectiveLimit)
        .toList(growable: false);
    return ListResponse<ItemResource>(
      data: page,
      firstId: page.isNotEmpty ? page.first.id : null,
      lastId: page.isNotEmpty ? page.last.id : null,
      hasMore: ordered.length > startIndex + effectiveLimit,
    );
  }

  AgentInvocationContext _contextFor(CreateResponse request) {
    final idGenerator = IdGenerator(
      responseId: request.metadata?['response_id'],
      conversationId: request.conversation?.id,
    );
    return AgentInvocationContext(
      idGenerator: idGenerator,
      responseId: idGenerator.responseId,
      conversationId: request.conversation?.id,
    );
  }

  Future<List<ChatMessage>?> _loadHistory(
    CreateResponse request,
    CancellationToken? cancellationToken,
  ) async {
    final conversation = request.conversation;
    final storage = _conversationStorage;
    if (conversation == null || storage == null) {
      return null;
    }
    final items = await storage.listItems(
      conversation.id,
      order: SortOrder.ascending,
      limit: 100,
      cancellationToken: cancellationToken,
    );
    return items.data.map(_itemToChatMessage).whereType<ChatMessage>().toList();
  }

  Future<void> _store(
    CreateResponse request,
    AgentInvocationContext context,
    Response response,
    List<StreamingResponseEvent> events,
    CancellationToken? cancellationToken,
  ) async {
    if (request.store == false) {
      return;
    }
    _responses[response.id] = response;
    _events[response.id] = events;
    _inputItems[response.id] = _buildInputItems(request, context);

    final conversation = request.conversation;
    if (conversation != null && _conversationStorage != null) {
      await _conversationStorage.addItems(
        conversation.id,
        response.output,
        cancellationToken: cancellationToken,
      );
    }
  }

  List<ItemResource> _buildInputItems(
    CreateResponse request,
    AgentInvocationContext context,
  ) {
    return request.input.getInputMessages().map((message) {
      final content = message.content;
      final parts = content is String
          ? [
              {'type': 'input_text', 'text': content},
            ]
          : (content is List ? content : const []);
      return ItemResource.fromJson({
        'id': context.idGenerator.generateMessageId(),
        'type': 'message',
        'role': message.role,
        'status': 'completed',
        'content': parts,
      });
    }).toList();
  }

  static ChatMessage? _itemToChatMessage(ItemResource item) {
    if (item.type != 'message') {
      return null;
    }
    final json = item.toJson();
    final role = json['role'] as String? ?? 'user';
    final content = json['content'];
    final contents = <AIContent>[];
    if (content is String) {
      contents.add(TextContent(content));
    } else if (content is List) {
      for (final part in content.whereType<Map<String, dynamic>>()) {
        final text = part['text'];
        if (text is String) {
          contents.add(TextContent(text));
        }
      }
    }
    return ChatMessage(role: ChatRole(role), contents: contents);
  }

  static Response? _terminalOf(StreamingResponseEvent event) {
    if (event is StreamingResponseCompleted) {
      return event.response;
    }
    if (event is StreamingResponseFailed) {
      return event.response;
    }
    return null;
  }

  static int _nowUnixSeconds() =>
      DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
}
