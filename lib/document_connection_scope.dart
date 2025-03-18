import 'package:meshagent/room_server_client.dart';
import 'package:flutter/widgets.dart';

class DocumentConnectionScope extends StatefulWidget {
  const DocumentConnectionScope({super.key, required this.room, required this.path, required this.builder});

  final RoomClient room;
  final String path;

  final Widget Function(BuildContext context, MeshDocument? document, Object? error) builder;

  @override
  State createState() => _DocumentConnectionScope();
}

class _DocumentConnectionScope extends State<DocumentConnectionScope> {
  bool connected = false;

  late final RoomClient client;
  MeshDocument? document;

  Object? error;

  @override
  void initState() {
    super.initState();

    widget.room.sync
        .open(widget.path)
        .then((doc) {
          if (mounted) {
            setState(() {
              document = doc;
            });
          }
        })
        .catchError((err) {
          if (mounted) {
            setState(() {
              error = err;
            });
          }
        });
  }

  @override
  void dispose() {
    super.dispose();
    widget.room.sync.close(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, document, error);
  }
}
