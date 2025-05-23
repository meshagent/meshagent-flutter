import 'package:meshagent/room_server_client.dart';
import 'package:flutter/widgets.dart';

const int maxRetries = 3;

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
  int tries = 0;

  late final RoomClient client;
  MeshDocument? document;

  Object? error;

  Future<void> syncDocument() async {
    try {
      final doc = await widget.room.sync.open(widget.path);

      if (mounted) {
        setState(() {
          document = doc;
        });
      }
    } catch (e) {
      if (mounted) {
        if (tries < maxRetries) {
          tries++;

          await Future.delayed(const Duration(milliseconds: 800));

          return syncDocument();

        } else {
          setState(() {
            error = e;
          });
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();

    tries = 0;
    syncDocument();
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
