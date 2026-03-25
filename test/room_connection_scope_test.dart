import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter/meshagent_flutter.dart';

class _ProtocolPair {
  _ProtocolPair() {
    clientProtocol = Protocol(
      channel: StreamProtocolChannel(input: _serverToClient.stream, output: _clientToServer.sink),
    );
    serverProtocol = Protocol(
      channel: StreamProtocolChannel(input: _clientToServer.stream, output: _serverToClient.sink),
    );
  }

  final _clientToServer = StreamController<Uint8List>();
  final _serverToClient = StreamController<Uint8List>();
  late final Protocol clientProtocol;
  late final Protocol serverProtocol;

  Future<void> closeServerToClient() async {
    await _serverToClient.close();
  }

  Future<void> dispose() async {
    try {
      clientProtocol.dispose();
    } catch (_) {}
    try {
      serverProtocol.dispose();
    } catch (_) {}
    await _clientToServer.close();
    if (!_serverToClient.isClosed) {
      await _serverToClient.close();
    }
  }
}

Future<void> _sendRoomReady(Protocol protocol) async {
  await protocol.send(
    'room_ready',
    packMessage({'room_name': 'test-room', 'room_url': 'ws://example/rooms/test-room', 'session_id': 'session-1'}),
  );
}

void main() {
  testWidgets('retries when the room is temporarily unavailable', (tester) async {
    final pairs = <_ProtocolPair>[];
    var authorizationCount = 0;
    var clientCount = 0;

    addTearDown(() {
      for (final pair in pairs) {
        unawaited(pair.dispose());
      }
    });

    RoomClient makeClient(RoomConnectionInfo connectionInfo) {
      final pair = _ProtocolPair();
      pairs.add(pair);
      clientCount++;

      if (clientCount == 1) {
        unawaited(pair.closeServerToClient());
      } else {
        pair.serverProtocol.start(onMessage: (protocol, messageId, type, data) async {});
        unawaited(_sendRoomReady(pair.serverProtocol));
      }

      return RoomClient(protocol: pair.clientProtocol);
    }

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RoomConnectionScope(
          enableMessaging: false,
          authorization: () async {
            authorizationCount++;
            return RoomConnectionInfo(
              projectId: 'project-1',
              roomName: 'test-room',
              roomUrl: Uri.parse('ws://example.test/rooms/test-room'),
              jwt: 'token',
            );
          },
          roomClientFactory: makeClient,
          builder: (context, room) {
            return const Text('connected');
          },
        ),
      ),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (find.text('connected').evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail(
          'RoomConnectionScope did not reconnect before timeout '
          '(authorizations: $authorizationCount, clients: $clientCount)',
        );
      }
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(authorizationCount, 2);
    expect(clientCount, 2);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows retryingBuilder between retryable attempts', (tester) async {
    final pairs = <_ProtocolPair>[];
    var clientCount = 0;

    addTearDown(() {
      for (final pair in pairs) {
        unawaited(pair.dispose());
      }
    });

    RoomClient makeClient(RoomConnectionInfo connectionInfo) {
      final pair = _ProtocolPair();
      pairs.add(pair);
      clientCount++;

      if (clientCount == 1) {
        unawaited(pair.closeServerToClient());
      } else {
        pair.serverProtocol.start(onMessage: (protocol, messageId, type, data) async {});
        unawaited(_sendRoomReady(pair.serverProtocol));
      }

      return RoomClient(protocol: pair.clientProtocol);
    }

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RoomConnectionScope(
          enableMessaging: false,
          authorization: () async => RoomConnectionInfo(
            projectId: 'project-1',
            roomName: 'test-room',
            roomUrl: Uri.parse('ws://example.test/rooms/test-room'),
            jwt: 'token',
          ),
          roomClientFactory: makeClient,
          retryingBuilder: (context, error) => const Text('waiting to retry'),
          builder: (context, room) {
            return const Text('connected');
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('waiting to retry'), findsOneWidget);

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (find.text('connected').evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('RoomConnectionScope did not reconnect before timeout');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.pumpWidget(const SizedBox());
  });
}
