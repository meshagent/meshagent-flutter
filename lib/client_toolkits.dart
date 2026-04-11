import 'dart:async';

import 'package:meshagent/agent.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:flutter/widgets.dart';

class ClientToolkits extends StatefulWidget {
  const ClientToolkits({super.key, required this.room, required this.toolkits, this.public = false, required this.child});

  final RoomClient room;
  final bool public;
  final List<Toolkit> toolkits;

  final Widget child;

  @override
  State createState() => _ClientToolkitsState();
}

class _ClientToolkitsState extends State<ClientToolkits> {
  final List<HostedToolkit> _hostedToolkits = <HostedToolkit>[];
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_startToolkits());
  }

  Future<void> _startToolkits() async {
    try {
      for (final toolkit in widget.toolkits) {
        final hostedToolkit = await startHostedToolkit(room: widget.room, toolkit: toolkit, public: widget.public);
        if (_disposed) {
          await hostedToolkit.stop();
          continue;
        }
        _hostedToolkits.add(hostedToolkit);
      }
    } catch (error, stackTrace) {
      for (final toolkit in _hostedToolkits) {
        await toolkit.stop();
      }
      _hostedToolkits.clear();
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'meshagent_flutter',
          context: ErrorDescription('while starting hosted toolkits'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final toolkit in _hostedToolkits) {
      unawaited(toolkit.stop());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
