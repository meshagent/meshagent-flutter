import 'package:meshagent/agents_client.dart';
import 'package:meshagent/room_server_client.dart';

class LivekitConnectionInfo {
  const LivekitConnectionInfo({required this.url, required this.token});

  final String url;
  final String token;
}

class LivekitClient {
  LivekitClient({required this.room});

  RoomClient room;

  Future<LivekitConnectionInfo> getConnectionInfo({String? breakoutRoom}) async {
    final output = await room.invoke(
      toolkit: "livekit",
      tool: "connect",
      input: ToolContentInput(JsonContent(json: {"breakout_room": breakoutRoom})),
    );
    if (output is! ToolContentOutput || output.content is! JsonContent) {
      throw RoomServerException("unexpected return type from livekit.connect");
    }
    final response = (output.content as JsonContent).json;
    final token = response["token"];
    final url = response["url"];
    if (token is! String || url is! String) {
      throw RoomServerException("unexpected return type from livekit.connect");
    }

    return LivekitConnectionInfo(token: token, url: url);
  }
}

extension RCLivekitClient on RoomClient {
  LivekitClient get livekit {
    return LivekitClient(room: this);
  }
}
