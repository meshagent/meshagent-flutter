import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent/runtime.dart';
import 'package:meshagent_flutter/meshagent_flutter.dart';

class _ProtocolPair {
  _ProtocolPair() {
    serverProtocol = Protocol(
      channel: StreamProtocolChannel(input: _clientToServer.stream, output: _serverToClient.sink),
    );
  }

  final _clientToServer = StreamController<Uint8List>();
  final _serverToClient = StreamController<Uint8List>();
  Protocol? _clientProtocol;
  late final Protocol serverProtocol;

  Protocol get clientProtocol {
    final protocol = _clientProtocol;
    if (protocol == null) {
      throw StateError('client protocol has not been created');
    }
    return protocol;
  }

  Protocol clientProtocolFactory() {
    if (_clientProtocol != null) {
      throw ProtocolReconnectUnsupportedException('protocolFactory was not configured for reconnecting this protocol');
    }
    final protocol = Protocol(
      channel: StreamProtocolChannel(input: _serverToClient.stream, output: _clientToServer.sink),
    );
    _clientProtocol = protocol;
    return protocol;
  }

  Future<void> dispose() async {
    final clientProtocol = _clientProtocol;
    if (clientProtocol != null) {
      try {
        clientProtocol.dispose();
      } catch (_) {}
    }
    try {
      serverProtocol.dispose();
    } catch (_) {}
    unawaited(_clientToServer.close());
    if (!_serverToClient.isClosed) {
      unawaited(_serverToClient.close());
    }
  }
}

class _FakeDocumentRuntime extends DocumentRuntime {
  _FakeDocumentRuntime() : super.base();

  @override
  void applyBackendChanges({required String documentId, required String base64}) {
    final current = DocumentRuntime.instance;
    if (current is _FakeDocumentRuntime) {
      current.appliedChanges.add((documentId: documentId, base64: base64));
    }
  }

  @override
  void registerDocument(RuntimeDocument document) {}

  @override
  String getState({required String documentId, String? vectorBase64}) {
    return '';
  }

  @override
  String getStateVector({required String documentId}) {
    return '';
  }

  @override
  void sendChanges(Map<String, dynamic> message) {}

  @override
  void unregisterDocument(RuntimeDocument document) {}

  final appliedChanges = <({String documentId, String base64})>[];
}

Future<void> _sendRoomReady(Protocol protocol) async {
  await protocol.send(
    'room_ready',
    packMessage({'room_name': 'test-room', 'room_url': 'ws://example/rooms/test-room', 'session_id': 'session-1'}),
  );
  await protocol.send(
    'connected',
    packMessage({
      'type': 'init',
      'participantId': 'self',
      'attributes': {'name': 'self'},
    }),
  );
}

Future<void> _sendToolCallResponseChunk({required Protocol protocol, required String toolCallId, required Content chunk}) async {
  final packed = unpackMessage(chunk.pack());
  await protocol.send(
    'room.tool_call_response_chunk',
    packMessage({'tool_call_id': toolCallId, 'chunk': packed.header}, packed.payload.isEmpty ? null : packed.payload),
  );
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition, {Duration timeout = const Duration(seconds: 1)}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      fail('condition was not met before timeout');
    }
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  testWidgets('closes a document if sync.open resolves after the scope is disposed', (tester) async {
    final pair = _ProtocolPair();
    final schema = MeshSchema(
      rootTagName: 'thread',
      elements: [ElementType(tagName: 'thread', description: '', properties: [])],
    );

    String? toolCallId;
    Map<String, dynamic>? invokeRequest;
    final requestChunks = <Content>[];
    final releaseState = Completer<void>();
    final closeReceived = Completer<void>();
    final closeResponseSent = Completer<void>();

    pair.serverProtocol.start(
      onMessage: (protocol, messageId, type, data) async {
        if (type == 'room.invoke_tool') {
          invokeRequest = Map<String, dynamic>.from(unpackMessage(data).header);
          toolCallId = invokeRequest!['tool_call_id'] as String;
          await protocol.send('__response__', ControlContent(method: 'open').pack(), id: messageId);
          return;
        }

        if (type != 'room.tool_call_request_chunk') {
          return;
        }

        final message = unpackMessage(data);
        final header = message.header;
        final chunkHeader = Map<String, dynamic>.from(header['chunk'] as Map);
        final packedChunk = packMessage(chunkHeader, message.payload.isEmpty ? null : message.payload);
        final chunk = unpackContent(packedChunk);
        requestChunks.add(chunk);

        await protocol.send('__response__', EmptyContent().pack(), id: messageId);

        final activeToolCallId = toolCallId;
        if (activeToolCallId == null) {
          return;
        }

        if (chunk is BinaryContent && chunk.headers['kind'] == 'start') {
          await releaseState.future;
          await _sendToolCallResponseChunk(
            protocol: protocol,
            toolCallId: activeToolCallId,
            chunk: BinaryContent(data: Uint8List(0), headers: {'kind': 'state', 'path': 'thread.thread', 'schema': schema.toJson()}),
          );
          return;
        }

        if (chunk is ControlContent && chunk.method == 'close') {
          if (!closeReceived.isCompleted) {
            closeReceived.complete();
          }
          await _sendToolCallResponseChunk(
            protocol: protocol,
            toolCallId: activeToolCallId,
            chunk: ControlContent(method: 'close'),
          );
          if (!closeResponseSent.isCompleted) {
            closeResponseSent.complete();
          }
        }
      },
    );

    final room = RoomClient(protocolFactory: pair.clientProtocolFactory);
    final startFuture = room.start();
    await _sendRoomReady(pair.serverProtocol);
    await startFuture;

    final previousRuntime = DocumentRuntime.instance;
    DocumentRuntime.instance = _FakeDocumentRuntime();

    try {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: DocumentConnectionScope(
            room: room,
            path: '/thread.thread',
            builder: (context, document, error) {
              return const SizedBox();
            },
          ),
        ),
      );

      await _pumpUntil(tester, () => requestChunks.any((chunk) => chunk is BinaryContent && chunk.headers['kind'] == 'start'));

      expect(invokeRequest?['toolkit'], 'sync');
      expect(invokeRequest?['tool'], 'open');

      await tester.pumpWidget(const SizedBox());
      releaseState.complete();

      await closeReceived.future.timeout(const Duration(seconds: 1));
      await closeResponseSent.future.timeout(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 10));

      expect(requestChunks.whereType<ControlContent>().map((chunk) => chunk.method), contains('close'));
    } finally {
      DocumentRuntime.instance = previousRuntime ?? _FakeDocumentRuntime();
      room.dispose();
      await pair.dispose();
    }
  });
}
