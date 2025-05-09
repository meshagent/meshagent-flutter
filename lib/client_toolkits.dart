import 'package:meshagent/agent.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:flutter/widgets.dart';

class ClientToolkits extends StatefulWidget {
  const ClientToolkits({
    super.key,
    required this.room,
    required this.toolkits,
    this.public = false,
    required this.child,
  });

  final RoomClient room;
  final bool public;
  final List<RemoteToolkit> toolkits;

  final Widget child;

  @override
  State createState() => _ClientToolkitsState();
}

class _ClientToolkitsState extends State<ClientToolkits> {
  @override
  void initState() {
    super.initState();

    for (final toolkit in widget.toolkits) {
      toolkit.start(public: widget.public);
    }
  }

  @override
  void dispose() {
    for (final toolkit in widget.toolkits) {
      toolkit.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
