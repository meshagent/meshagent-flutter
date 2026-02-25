import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:meshagent/meshagent.dart';

class RoomParticipantsBuilder extends StatefulWidget {
  const RoomParticipantsBuilder({super.key, required this.room, required this.builder});

  final RoomClient room;
  final Widget Function(BuildContext context, List<RemoteParticipant> participants) builder;

  @override
  State createState() => _RoomParticipantsBuilderState();
}

class _RoomParticipantsBuilderState extends State<RoomParticipantsBuilder> {
  List<RemoteParticipant> participants = [];
  Set<String> participantIds = {};

  void _onEvent() {
    final newParticipantIds = widget.room.messaging.remoteParticipants.map((p) => p.id).toSet();

    if (!setEquals(participantIds, newParticipantIds)) {
      setState(() {
        participants = widget.room.messaging.remoteParticipants.toList();
        participantIds = newParticipantIds;
      });
    }
  }

  @override
  void initState() {
    super.initState();

    widget.room.messaging.addListener(_onEvent);
  }

  @override
  void dispose() {
    widget.room.messaging.removeListener(_onEvent);

    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RoomParticipantsBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.room != widget.room) {
      oldWidget.room.messaging.removeListener(_onEvent);
      widget.room.messaging.addListener(_onEvent);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        _onEvent();
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, participants);
}
