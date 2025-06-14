import 'dart:math';
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
  int retryCount = 0;

  late final RoomClient client;
  MeshDocument? document;
  Object? error;

  /*
   * Waits for the schema file to be available in the storage. Schema file MUST be present
   */
  Future<void> waitForSchemaFile() async {
    final ext = widget.path.split(".").last.toLowerCase();

    final schemaFile = '/.schemas/$ext.json';

    bool schemaExists = await widget.room.storage.exists(schemaFile);

    while (!schemaExists) {
      await Future.delayed(const Duration(milliseconds: 500));

      debugPrint('Waiting for schema file: $schemaFile');

      schemaExists = await widget.room.storage.exists(schemaFile);
    }
  }

  Future<void> syncDocument() async {
    try {
      final doc = await widget.room.sync.open(widget.path);

      if (mounted) {
        setState(() {
          document = doc;
        });
      }
    } catch (e) {
      debugPrint('Retrying to open document: ${widget.path}');

      final delay = min(60000, pow(2, retryCount).toInt() * 500);
      retryCount++;

      await Future.delayed(Duration(milliseconds: delay));

      if (mounted) {
        syncDocument();
      }
    }
  }

  @override
  void initState() {
    super.initState();

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
