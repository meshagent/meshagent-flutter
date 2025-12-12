import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter/meshagent_flutter.dart';

// Replace these placeholders with values from your Meshagent project.
const projectId = 'insert-project-id';
const roomName = 'insert-room-name';
const roomUrl = 'wss://api.meshagent.com/rooms/$roomName';
const apiKey = '';

void main() {
  runApp(const MeshagentExampleApp());
}

class MeshagentExampleApp extends StatelessWidget {
  const MeshagentExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final token = ParticipantToken(name: 'mega-man');
    token.addRoomGrant(roomName);
    token.addRoleGrant("agent");
    token.addApiGrant(ApiScope.agentDefault());

    return MaterialApp(
      title: 'Meshagent Flutter Example',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: RoomConnectionScope(
        authorization: staticAuthorization(
          projectId: projectId,
          roomName: roomName,
          url: Uri.parse(roomUrl),
          jwt: token.toJwt(apiKey: apiKey),
        ),
        builder: (context, room) => MeshagentRoomView(room: room),
      ),
    );
  }
}

class MeshagentRoomView extends StatefulWidget {
  const MeshagentRoomView({super.key, required this.room});

  final RoomClient room;

  @override
  State<MeshagentRoomView> createState() => _MeshagentRoomViewState();
}

class _MeshagentRoomViewState extends State<MeshagentRoomView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meshagent Room')),
      body: Center(
        child: FutureBuilder(
          future: widget.room.ready,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _StatusCard(title: 'Connecting...', details: 'Waiting for the WebSocket connection to be ready.', spinner: true);
            }

            final connectedRoomName = widget.room.roomName ?? roomName;
            final connectedRoomUrl = widget.room.roomUrl ?? roomUrl;
            return _StatusCard(title: 'Connected', details: 'Connected to room "$connectedRoomName" at "$connectedRoomUrl".');
          },
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.title, required this.details, this.spinner = false});

  final String title;
  final String details;
  final bool spinner;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(details, textAlign: TextAlign.center),
            if (spinner) ...[const SizedBox(height: 24), const CircularProgressIndicator()],
          ],
        ),
      ),
    );
  }
}
