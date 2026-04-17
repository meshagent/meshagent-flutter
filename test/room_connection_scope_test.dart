import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter/meshagent_flutter.dart';

class _IdleProtocolChannel extends ProtocolChannel {
  @override
  void start(void Function(Uint8List data) onDataReceived, {void Function()? onDone, void Function(Object? error)? onError}) {}

  @override
  void dispose() {}

  @override
  Future<void> sendData(Uint8List data) async {}
}

class _ControlledRoomClient extends RoomClient {
  _ControlledRoomClient({required Future<void> readyFuture, required Future<void> Function() onStart})
    : _readyFuture = readyFuture,
      _onStart = onStart,
      super(protocolFactory: () => Protocol(channel: _IdleProtocolChannel())) {
    unawaited(_readyFuture.catchError((Object _) {}));
  }

  final Future<void> _readyFuture;
  final Future<void> Function() _onStart;

  @override
  Future<void> get ready {
    return _readyFuture;
  }

  @override
  Future<void> start({void Function()? onDone, void Function(Object? error)? onError}) async {
    await _onStart();
  }

  @override
  void dispose() {}
}

void main() {
  testWidgets('retries when the room is temporarily unavailable', (tester) async {
    final retryableError = RoomServerException('temporary startup failure', retryable: true);
    var authorizationCount = 0;
    var clientCount = 0;

    RoomClient makeClient(RoomConnectionInfo connectionInfo) {
      clientCount++;

      if (clientCount == 1) {
        return _ControlledRoomClient(
          readyFuture: Future<void>.value(),
          onStart: () async {
            throw retryableError;
          },
        );
      }

      return _ControlledRoomClient(readyFuture: Future<void>.value(), onStart: () async {});
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
    final retryableError = RoomServerException('temporary startup failure', retryable: true);
    var clientCount = 0;

    RoomClient makeClient(RoomConnectionInfo connectionInfo) {
      clientCount++;

      if (clientCount == 1) {
        return _ControlledRoomClient(
          readyFuture: Future<void>.value(),
          onStart: () async {
            throw retryableError;
          },
        );
      }

      return _ControlledRoomClient(readyFuture: Future<void>.value(), onStart: () async {});
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

  testWidgets('does not show doneBuilder while a retryable startup failure is still transitioning into retry', (tester) async {
    final retryableError = RoomServerException('temporary startup failure', retryable: true);
    final firstReady = Completer<void>();
    final releaseFirstStart = Completer<void>();
    var clientCount = 0;

    RoomClient makeClient(RoomConnectionInfo connectionInfo) {
      clientCount++;
      if (clientCount == 1) {
        return _ControlledRoomClient(
          readyFuture: firstReady.future,
          onStart: () async {
            await releaseFirstStart.future;
            throw retryableError;
          },
        );
      }

      return _ControlledRoomClient(readyFuture: Future<void>.value(), onStart: () async {});
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
          connectingBuilder: (context, room) => const Text('connecting'),
          retryingBuilder: (context, error) => const Text('waiting to retry'),
          doneBuilder: (context, error) => const Text('done'),
          builder: (context, room) => const Text('connected'),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('connecting'), findsOneWidget);

    firstReady.completeError(retryableError);
    await tester.pump();

    expect(find.text('done'), findsNothing);
    expect(find.text('connecting'), findsOneWidget);

    releaseFirstStart.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('waiting to retry'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text('connected'), findsOneWidget);
  });
}
