import 'package:meshagent/protocol.dart';

import 'package:meshagent/room_server_client.dart';
import 'package:flutter/widgets.dart';

class RoomConnectionScope extends StatefulWidget {
  const RoomConnectionScope(
      {super.key, required this.uri, required this.builder, required this.jwt, this.doneBuilder });

  final Uri uri;
  final String jwt;

  final Widget Function(BuildContext context, RoomClient client) builder;
  final Widget Function(BuildContext context, Object? error)? doneBuilder;

  @override
  State createState() => _RoomConnectionScopeState();
}

class _RoomConnectionScopeState extends State<RoomConnectionScope> {
  
  late final RoomClient client;

  @override
  void initState() {
    super.initState();

    client = RoomClient(
      protocol: Protocol(
          channel: WebSocketProtocolChannel(url: widget.uri, jwt: widget.jwt)),
    );
    client.start(onDone: onDone, onError: onError);
  }

  bool done = false;
  Object? error;

  void onDone() {
    if(!mounted) return;
    setState(() {
      done = true;
    });
  }

  void onError(Object? error) {

    if(!mounted) return;
    setState(() {
        done = true;
        error = error;      
    });

  }

  @override
  void dispose() {
    super.dispose();
    client.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if(!done) {
      return widget.builder(context, client);
    } else {
      if(widget.doneBuilder == null) {
        if(error != null) {
          return Text("Room Disconnected: $error");
        } else {
          return Text("Room Closed");
        }
      }
      return widget.doneBuilder!(context, error);
    }
  }
}
