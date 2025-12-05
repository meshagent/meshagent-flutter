import 'package:flutter/material.dart';
import 'package:meshagent_flutter/meshagent_flutter.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent/runtime.dart';

Future<RoomConnectionInfo> Function() developmentAuthorization({
  required Uri url,
  required String projectId,
  required String apiKeyId,
  required String participantName,
  required String identity,
  required String roomName,
  required String secret,
}) {
  return () async {
    final token = ParticipantToken(name: participantName, projectId: projectId, apiKeyId: apiKeyId);
    token.addRoomGrant(roomName);
    token.addRoleGrant("user");

    return RoomConnectionInfo(
      projectId: projectId,
      roomName: roomName,
      roomUrl: url,
      jwt: token.toJwt(token: secret),
    );
  };
}

Future<RoomConnectionInfo> Function() staticAuthorization({
  required String projectId,
  required String roomName,
  required Uri url,
  required String jwt,
}) {
  return () async {
    return RoomConnectionInfo(projectId: projectId, roomName: roomName, roomUrl: url, jwt: jwt);
  };
}

class RoomConnectionScope extends StatefulWidget {
  const RoomConnectionScope({
    super.key,
    required this.authorization,
    required this.builder,
    this.doneBuilder,
    this.authorizingBuilder,
    this.notFoundBuilder,
    this.connectingBuilder,
    this.onReady,
    this.enableMessaging = true,
    this.oauthTokenRequestHandler,
    this.client,
  });

  final String? client;

  final bool enableMessaging;
  final Function(RoomClient, OAuthTokenRequest)? oauthTokenRequestHandler;

  final Future<RoomConnectionInfo> Function() authorization;
  final void Function(RoomClient room)? onReady;

  final Widget Function(BuildContext context)? authorizingBuilder;
  final Widget Function(BuildContext context)? notFoundBuilder;
  final Widget Function(BuildContext context, RoomClient room)? connectingBuilder;
  final Widget Function(BuildContext context, RoomClient room) builder;
  final Widget Function(BuildContext context, Object? error)? doneBuilder;

  @override
  State createState() => _RoomConnectionScopeState();
}

class _RoomConnectionScopeState extends State<RoomConnectionScope> {
  RoomClient? client;
  RoomConnectionInfo? connection;

  bool done = false;
  bool notFound = false;
  Object? error;

  @override
  void initState() {
    if (DocumentRuntime.instance == null) {
      initializeFlutterDocumenRuntime();
    }
    super.initState();
    connect();
  }

  Future<void> connect() async {
    try {
      connection = await widget.authorization();
    } catch (e) {
      if (mounted) {
        if (e is NotFoundException) {
          setState(() {
            notFound = true;
            error = e;
          });
        } else {
          setState(() {
            done = true;
            error = e;
          });
        }
      }

      return;
    }

    final cli = RoomClient(
      protocol: Protocol(
        channel: WebSocketProtocolChannel(url: connection!.roomUrl, jwt: connection!.jwt),
      ),
      oauthTokenRequestHandler: widget.oauthTokenRequestHandler == null
          ? null
          : (request) => widget.oauthTokenRequestHandler!(client!, request),
    );

    if (mounted) {
      setState(() {
        client = cli;
      });
    }

    await cli.start(onDone: onDone, onError: onError);

    if (widget.enableMessaging) {
      await cli.messaging.enable();
    }

    widget.onReady?.call(cli);
  }

  void onDone() {
    if (mounted && !done) {
      setState(() {
        done = true;
      });
    }
  }

  void onError(Object? error) {
    if (mounted && !done) {
      setState(() {
        done = true;
        error = error;
      });
    }
  }

  @override
  void dispose() {
    super.dispose();

    done = true;
    client?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (notFound) {
      if (widget.notFoundBuilder != null) {
        return widget.notFoundBuilder!(context);
      } else {
        return Text("Room Not Found");
      }
    }

    if (!done) {
      if (client == null) {
        if (widget.authorizingBuilder != null) {
          return widget.authorizingBuilder!(context);
        } else {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [CircularProgressIndicator(), SizedBox(height: 20), Text("Initializing...")],
          );
        }
      } else {
        return FutureBuilder(
          future: client!.ready,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return widget.builder(context, client!);
            } else {
              if (widget.connectingBuilder == null) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [CircularProgressIndicator(), SizedBox(height: 20), Text("Connecting to room...")],
                );
              } else {
                return widget.connectingBuilder!(context, client!);
              }
            }
          },
        );
      }
    } else {
      if (widget.doneBuilder == null) {
        if (error != null) {
          return Text("Room Disconnected: $error");
        } else {
          return Text("Room Closed");
        }
      }

      return widget.doneBuilder!(context, error);
    }
  }
}
