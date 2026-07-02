import 'package:agents/agents.dart';
import 'package:agents/src/abstractions/invoked_context.dart';
import 'package:extensions_flutter/extensions_flutter.dart';

class FlutterChatHistoryProvider implements ChatHistoryProvider {
  @override
  Object? getService(Type serviceType, {Object? serviceKey}) {
    // TODO: implement getService
    throw UnimplementedError();
  }

  @override
  Future<void> invoked(
    InvokedContext context, {
    CancellationToken? cancellationToken,
  }) {
    // TODO: implement invoked
    throw UnimplementedError();
  }

  @override
  Future<void> invokedCore(
    InvokedContext context, {
    CancellationToken? cancellationToken,
  }) {
    // TODO: implement invokedCore
    throw UnimplementedError();
  }

  @override
  Future<Iterable<ChatMessage>> invoking(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) {
    // TODO: implement invoking
    throw UnimplementedError();
  }

  @override
  Future<Iterable<ChatMessage>> invokingCore(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) {
    // TODO: implement invokingCore
    throw UnimplementedError();
  }

  @override
  Future<Iterable<ChatMessage>> provideChatHistory(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) {
    // TODO: implement provideChatHistory
    throw UnimplementedError();
  }

  @override
  // TODO: implement stateKeys
  List<String> get stateKeys => throw UnimplementedError();

  @override
  Future<void> storeChatHistory(
    InvokedContext context, {
    CancellationToken? cancellationToken,
  }) {
    // TODO: implement storeChatHistory
    throw UnimplementedError();
  }
}
