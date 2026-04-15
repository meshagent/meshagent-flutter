import 'dart:async';
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
  int retryCount = 0;
  MeshDocument? document;
  Object? error;
  int _syncGeneration = 0;

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

  Future<void> _closeDocument({required RoomClient room, required String path}) async {
    try {
      await room.sync.close(path);
    } catch (_) {}
  }

  Future<void> _syncDocument({
    required int generation,
    required RoomClient room,
    required String path,
    required MeshSchema? schema,
    required Map<String, dynamic>? initialJson,
  }) async {
    var nextRetryCount = 0;

    while (generation == _syncGeneration) {
      try {
        final doc = await room.sync.open(path, initialJson: initialJson, schema: schema);

        if (!mounted || generation != _syncGeneration) {
          await _closeDocument(room: room, path: path);
          return;
        }

        if (!mounted) {
          return;
        }

        setState(() {
          document = doc;
          error = null;
          retryCount = 0;
        });
        return;
      } catch (e) {
        if (!mounted || generation != _syncGeneration) {
          return;
        }

        debugPrint('Retrying to open document: $path ($nextRetryCount)');

        setState(() {
          document = null;
          error = e;
          retryCount = nextRetryCount;
        });

        final delay = min(60000, pow(2, nextRetryCount).toInt() * 500);
        nextRetryCount++;

        await Future.delayed(Duration(milliseconds: delay));

        if (!mounted || generation != _syncGeneration) {
          return;
        }
      }
    }
  }

  void _startSync() {
    final generation = ++_syncGeneration;
    retryCount = 0;
    unawaited(
      _syncDocument(generation: generation, room: widget.room, path: widget.path, schema: widget.schema, initialJson: widget.initialJson),
    );
  }

  @override
  void initState() {
    super.initState();
    _startSync();
  }

  @override
  void didUpdateWidget(covariant DocumentConnectionScope oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.room == oldWidget.room && widget.path == oldWidget.path) {
      return;
    }

    final oldRoom = oldWidget.room;
    final oldPath = oldWidget.path;
    _syncGeneration++;

    setState(() {
      document = null;
      error = null;
      retryCount = 0;
    });

    unawaited(_closeDocument(room: oldRoom, path: oldPath));
    _startSync();
  }

  @override
  void dispose() {
    _syncGeneration++;
    unawaited(_closeDocument(room: widget.room, path: widget.path));

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, document, error);
  }
}
