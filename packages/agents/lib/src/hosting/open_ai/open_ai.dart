// Copyright (c) Microsoft. All rights reserved.
//
// Public surface for the OpenAI-compatible hosting module
// (port of Microsoft.Agents.AI.Hosting.OpenAI).
//
// Currently exposes the Chat Completions surface and shared foundation. The
// Conversations and Responses surfaces are exported here as they are ported.

export 'chat_completions/ai_agent_chat_completions_processor.dart';
export 'chat_completions/agent_response_extensions.dart';
export 'chat_completions/chat_completions_router.dart';
export 'chat_completions/converters/chat_client_agent_run_options_converter.dart';
export 'chat_completions/converters/message_content_part_converter.dart';
export 'chat_completions/models/chat_completion.dart';
export 'chat_completions/models/chat_completion_choice.dart';
export 'chat_completions/models/chat_completion_chunk.dart';
export 'chat_completions/models/chat_completion_request_message.dart';
export 'chat_completions/models/completion_usage.dart';
export 'chat_completions/models/create_chat_completion.dart';
export 'chat_completions/models/message_content.dart';
export 'chat_completions/models/response_format.dart';
export 'chat_completions/models/stop_sequences.dart';
export 'chat_completions/models/tool.dart';
export 'chat_completions/models/tool_choice.dart';
export 'api_result.dart';
export 'conversations/agent_conversation_index.dart';
export 'conversations/conversation_storage.dart';
export 'conversations/conversations_handler.dart';
export 'conversations/conversations_router.dart';
export 'conversations/in_memory_agent_conversation_index.dart';
export 'conversations/in_memory_conversation_storage.dart';
export 'conversations/models/conversation.dart';
export 'conversations/models/create_conversation_request.dart';
export 'conversations/models/create_items_request.dart';
export 'conversations/models/update_conversation_request.dart';
export 'conversations/sort_order_extensions.dart';
export 'id_generator.dart';
export 'in_memory_storage_options.dart';
export 'models/delete_response.dart';
export 'models/error_response.dart';
export 'models/list_response.dart';
export 'models/sort_order.dart';
export 'open_ai_hosting_service_collection_extensions.dart';
export 'responses/agent_invocation_context.dart';
export 'responses/ai_agent_response_executor.dart';
export 'responses/in_memory_responses_service.dart';
export 'responses/models/conversation_reference.dart';
export 'responses/models/create_response.dart';
export 'responses/models/item_param.dart';
export 'responses/models/item_resource.dart';
export 'responses/models/response.dart';
export 'responses/models/response_input.dart';
export 'responses/models/streaming_response_event.dart';
export 'responses/response_executor.dart';
export 'responses/responses_handler.dart';
export 'responses/responses_router.dart';
export 'responses/responses_service.dart';
export 'sse_json_result.dart';
