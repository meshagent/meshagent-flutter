import 'dart:math';
import 'package:meshagent/meshagent.dart';
import 'package:flutter/widgets.dart';

class DocumentConnectionScope extends StatefulWidget {
  const DocumentConnectionScope({super.key, required this.room, required this.path, required this.builder, this.schema, this.initialJson});

  final RoomClient room;
  final String path;
  final MeshSchema? schema;
  final Map<String, dynamic>? initialJson;

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
  */

  Future<void> syncDocument() async {
    try {
      final doc = await widget.room.sync.open(widget.path, initialJson: widget.initialJson, schema: widget.schema);

      if (mounted) {
        setState(() {
          document = doc;
          error = null;
        });
      }
    } catch (e) {
      debugPrint('Retrying to open document: ${widget.path} ($retryCount)');

      if (!mounted) return;

      setState(() {
        document = null;
        error = e;
      });

      final delay = min(60000, pow(2, retryCount).toInt() * 500);
      retryCount++;

      await Future.delayed(Duration(milliseconds: delay));

      if (mounted) {
        await syncDocument();
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
    widget.room.sync.close(widget.path).catchError((_) {});

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, document, error);
  }
}
