import 'package:meshagent/protocol.dart';

import 'package:meshagent/room_server_client.dart';
import 'package:flutter/widgets.dart';

class RoomConnectionScope extends StatefulWidget {
  const RoomConnectionScope(
      {super.key, required this.uri, required this.builder, required this.jwt});

  final Uri uri;
  final String jwt;

  final Widget Function(BuildContext context, RoomClient client) builder;

  @override
  State createState() => _RoomConnectionScopeState();
}

class _RoomConnectionScopeState extends State<RoomConnectionScope> {
  bool connected = false;

  late final RoomClient client;

  @override
  void initState() {
    super.initState();

    client = RoomClient(
      protocol: Protocol(
          channel: WebSocketProtocolChannel(url: widget.uri, jwt: widget.jwt)),
    );
    client.start();
  }

  @override
  void dispose() {
    super.dispose();
    client.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, client);
  }
}
