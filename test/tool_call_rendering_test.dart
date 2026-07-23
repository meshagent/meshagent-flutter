import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter/tool_call_rendering.dart';

void main() {
  testWidgets('widget function and content tools register their render callbacks', (tester) async {
    final functionTool = _TestWidgetFunctionTool(
      render: (context, renderContext) => Text('function:${renderContext.snapshot.status.name}'),
    );
    final contentTool = _TestWidgetContentTool(render: (context, renderContext) => Text('content:${renderContext.snapshot.status.name}'));
    final registry = ChatToolCallRendererRegistry.fromToolkits(<Toolkit>[
      _TestToolkit(name: 'ui', tools: <BaseTool>[functionTool, contentTool]),
    ], namespace: 'client');

    final functionSnapshot = _snapshot(tool: 'function');
    final contentSnapshot = _snapshot(tool: 'content');
    final functionRenderer = registry.resolve(functionSnapshot);
    final contentRenderer = registry.resolve(contentSnapshot);

    expect(functionRenderer, isNotNull);
    expect(contentRenderer, isNotNull);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) => Column(
            children: <Widget>[
              functionRenderer!.build(
                context,
                ChatToolCallRenderContext(snapshot: functionSnapshot, defaultBuilder: () => const Text('default')),
              ),
              contentRenderer!.build(
                context,
                ChatToolCallRenderContext(snapshot: contentSnapshot, defaultBuilder: () => const Text('default')),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('function:running'), findsOneWidget);
    expect(find.text('content:running'), findsOneWidget);
  });

  test('explicit renderers override widget tool defaults', () {
    final override = _TestRenderer();
    final registry = ChatToolCallRendererRegistry.fromToolkits(
      <Toolkit>[
        _TestToolkit(
          name: 'ui',
          tools: <BaseTool>[_TestWidgetFunctionTool(render: (context, renderContext) => const Text('tool'))],
        ),
      ],
      namespace: 'client',
      renderers: <ChatToolCallRendererKey, ChatToolCallRenderer>{
        const ChatToolCallRendererKey(namespace: 'client', toolkit: 'ui', tool: 'function'): override,
      },
    );

    expect(registry.resolve(_snapshot(tool: 'function')), same(override));
  });
}

ChatToolCallSnapshot _snapshot({required String tool}) {
  final now = DateTime.utc(2026, 7, 21);
  return ChatToolCallSnapshot(
    identity: ChatToolCallIdentity(threadId: 'thread-1', turnId: 'turn-1', itemId: 'item-$tool'),
    namespace: 'client',
    toolkit: 'ui',
    tool: tool,
    status: ChatToolCallStatus.running,
    startedAt: now,
    updatedAt: now,
  );
}

class _TestWidgetFunctionTool extends WidgetFunctionTool {
  _TestWidgetFunctionTool({required super.render}) : super(name: 'function', inputSchema: const <String, dynamic>{'type': 'object'});

  @override
  Future<Content> execute(ToolContext context, Map<String, dynamic> arguments) async => EmptyContent();
}

class _TestWidgetContentTool extends WidgetContentTool {
  _TestWidgetContentTool({required super.render}) : super(name: 'content', inputSchema: const <String, dynamic>{'type': 'object'});

  @override
  Future<ToolCallOutput> execute(ToolContext context, ToolInput input) async {
    return ToolContentOutput(EmptyContent());
  }
}

class _TestToolkit extends Toolkit {
  _TestToolkit({required super.name, required super.tools});
}

class _TestRenderer implements ChatToolCallRenderer {
  @override
  Widget build(BuildContext context, ChatToolCallRenderContext renderContext) => const Text('override');
}
