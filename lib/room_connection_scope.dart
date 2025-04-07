import 'package:meshagent/participant_token.dart';
import 'package:meshagent/protocol.dart';

import 'package:meshagent/room_server_client.dart';
import 'package:flutter/widgets.dart';

class RoomConnectionInfo {
  RoomConnectionInfo({required this.url, required this.jwt});

  Uri url;
  String jwt;
}

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

    return RoomConnectionInfo(url: url, jwt: token.toJwt(token: secret));
  };
}

Future<RoomConnectionInfo> Function() staticAuthorization({required Uri url, required String jwt}) {
  return () async {
    return RoomConnectionInfo(url: url, jwt: jwt);
  };
}

class RoomConnectionScope extends StatefulWidget {
  const RoomConnectionScope({super.key, required this.authorization, required this.builder, this.doneBuilder, this.authorizingBuilder});

  final Future<RoomConnectionInfo> Function() authorization;

  final Widget Function(BuildContext context)? authorizingBuilder;
  final Widget Function(BuildContext context, RoomClient client) builder;
  final Widget Function(BuildContext context, Object? error)? doneBuilder;

  @override
  State createState() => _RoomConnectionScopeState();
}

class _RoomConnectionScopeState extends State<RoomConnectionScope> {
  RoomClient? client;

  @override
  void initState() {
    super.initState();
    connect();
  }

  RoomConnectionInfo? connection;

  void connect() async {
    connection = await widget.authorization();

    if (mounted) {
      setState(() {
        client = RoomClient(protocol: Protocol(channel: WebSocketProtocolChannel(url: connection!.url, jwt: connection!.jwt)));
        client!.start(onDone: onDone, onError: onError);
      });
    }
  }

  bool done = false;
  Object? error;

  void onDone() {
    if (!mounted) return;
    setState(() {
      done = true;
    });
  }

  void onError(Object? error) {
    if (!mounted) return;
    setState(() {
      done = true;
      error = error;
    });
  }

  @override
  void dispose() {
    super.dispose();
    client?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!done) {
      if (client == null) {
        if (widget.authorizingBuilder != null) {
          return widget.authorizingBuilder!(context);
        } else {
          return Container();
        }
      }
      return widget.builder(context, client!);
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
