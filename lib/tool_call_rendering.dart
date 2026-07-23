import 'package:flutter/widgets.dart';
import 'package:meshagent/meshagent.dart';

enum ChatToolCallStatus { pending, running, succeeded, failed, cancelled }

@immutable
class ChatToolCallIdentity {
  const ChatToolCallIdentity({required this.threadId, required this.turnId, required this.itemId, this.callId});

  final String threadId;
  final String turnId;
  final String itemId;
  final String? callId;

  String get stableKey {
    final normalizedCallId = callId?.trim();
    final localId = normalizedCallId == null || normalizedCallId.isEmpty ? itemId : normalizedCallId;
    return '$threadId:$localId';
  }
}

@immutable
class ChatToolCallLogEntry {
  const ChatToolCallLogEntry({required this.source, required this.text});

  final String source;
  final String text;
}

@immutable
class ChatToolCallSnapshot {
  ChatToolCallSnapshot({
    required this.identity,
    required this.namespace,
    required this.toolkit,
    required this.tool,
    required this.status,
    Map<String, Object?>? arguments,
    List<ChatToolCallLogEntry> logs = const <ChatToolCallLogEntry>[],
    this.argumentDeltaBytes = 0,
    this.result,
    this.errorMessage,
    this.authorName,
    required this.startedAt,
    required this.updatedAt,
  }) : arguments = arguments == null ? null : Map<String, Object?>.unmodifiable(arguments),
       logs = List<ChatToolCallLogEntry>.unmodifiable(logs);

  final ChatToolCallIdentity identity;
  final String namespace;
  final String toolkit;
  final String tool;
  final ChatToolCallStatus status;
  final Map<String, Object?>? arguments;
  final List<ChatToolCallLogEntry> logs;
  final int argumentDeltaBytes;
  final Content? result;
  final String? errorMessage;
  final String? authorName;
  final DateTime startedAt;
  final DateTime updatedAt;

  bool get isTerminal => switch (status) {
    ChatToolCallStatus.pending || ChatToolCallStatus.running => false,
    ChatToolCallStatus.succeeded || ChatToolCallStatus.failed || ChatToolCallStatus.cancelled => true,
  };
}

@immutable
class ChatToolCallRendererKey {
  const ChatToolCallRendererKey({required this.tool, this.toolkit, this.namespace});

  final String tool;
  final String? toolkit;
  final String? namespace;

  @override
  bool operator ==(Object other) =>
      other is ChatToolCallRendererKey && other.tool == tool && other.toolkit == toolkit && other.namespace == namespace;

  @override
  int get hashCode => Object.hash(tool, toolkit, namespace);
}

abstract interface class ChatToolCallRenderer {
  Widget build(BuildContext context, ChatToolCallRenderContext renderContext);
}

class ChatToolCallRenderContext {
  const ChatToolCallRenderContext({required this.snapshot, required Widget Function() defaultBuilder}) : _defaultBuilder = defaultBuilder;

  final ChatToolCallSnapshot snapshot;
  final Widget Function() _defaultBuilder;

  Widget buildDefault() => _defaultBuilder();
}

typedef WidgetToolRender = Widget Function(BuildContext context, ChatToolCallRenderContext renderContext);
typedef ChatToolCallVisibilityPredicate = bool Function(ChatToolCallSnapshot snapshot);

abstract interface class WidgetTool {
  WidgetToolRender get render;
}

abstract class WidgetFunctionTool extends FunctionTool implements WidgetTool {
  WidgetFunctionTool({
    required super.name,
    super.description,
    super.title,
    required super.inputSchema,
    super.outputSpec,
    super.outputSchema,
    super.defs,
    required this.render,
  });

  @override
  final WidgetToolRender render;
}

abstract class WidgetContentTool extends ContentTool implements WidgetTool {
  WidgetContentTool({
    required super.name,
    super.description,
    super.title,
    required super.inputSchema,
    super.inputSpec,
    super.outputSpec,
    super.outputSchema,
    super.defs,
    required this.render,
  });

  @override
  final WidgetToolRender render;
}

@immutable
class ChatToolCallRendererRegistry {
  ChatToolCallRendererRegistry({
    Map<ChatToolCallRendererKey, ChatToolCallRenderer> renderers = const <ChatToolCallRendererKey, ChatToolCallRenderer>{},
  }) : _renderers = Map<ChatToolCallRendererKey, ChatToolCallRenderer>.unmodifiable(renderers);

  factory ChatToolCallRendererRegistry.fromToolkits(
    Iterable<Toolkit> toolkits, {
    String? namespace,
    Map<ChatToolCallRendererKey, ChatToolCallRenderer> renderers = const <ChatToolCallRendererKey, ChatToolCallRenderer>{},
  }) {
    final normalizedNamespace = namespace?.trim();
    final registrations = <ChatToolCallRendererKey, ChatToolCallRenderer>{};
    for (final toolkit in toolkits) {
      for (final tool in toolkit.tools) {
        if (tool is! WidgetTool) {
          continue;
        }
        final widgetTool = tool as WidgetTool;
        registrations[ChatToolCallRendererKey(
          namespace: normalizedNamespace == null || normalizedNamespace.isEmpty ? null : normalizedNamespace,
          toolkit: toolkit.name,
          tool: tool.name,
        )] = _WidgetToolCallRenderer(
          widgetTool.render,
        );
      }
    }
    registrations.addAll(renderers);
    return ChatToolCallRendererRegistry(renderers: registrations);
  }

  static final ChatToolCallRendererRegistry empty = ChatToolCallRendererRegistry();

  final Map<ChatToolCallRendererKey, ChatToolCallRenderer> _renderers;

  bool get isEmpty => _renderers.isEmpty;

  ChatToolCallRenderer? resolve(ChatToolCallSnapshot snapshot) {
    final namespace = snapshot.namespace.trim();
    final toolkit = snapshot.toolkit.trim();
    final tool = snapshot.tool.trim();
    return _renderers[ChatToolCallRendererKey(namespace: namespace, toolkit: toolkit, tool: tool)] ??
        _renderers[ChatToolCallRendererKey(toolkit: toolkit, tool: tool)] ??
        _renderers[ChatToolCallRendererKey(tool: tool)];
  }
}

class _WidgetToolCallRenderer implements ChatToolCallRenderer {
  const _WidgetToolCallRenderer(this.render);

  final WidgetToolRender render;

  @override
  Widget build(BuildContext context, ChatToolCallRenderContext renderContext) => render(context, renderContext);
}
