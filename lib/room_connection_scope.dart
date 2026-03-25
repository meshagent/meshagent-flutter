import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:meshagent_flutter/meshagent_flutter.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent/runtime.dart';

Future<RoomConnectionInfo> Function() developmentAuthorization({
  required Uri url,
  required String projectId,
  required String apiKeyId,
  required String participantName,
  required String identity,
  required String roomName,
  required String secret,
}) {
  return () async {
    final token = ParticipantToken(name: participantName, projectId: projectId, apiKeyId: apiKeyId);
    token.addRoomGrant(roomName);
    token.addRoleGrant("user");

    return RoomConnectionInfo(
      projectId: projectId,
      roomName: roomName,
      roomUrl: url,
      jwt: token.toJwt(token: secret),
    );
  };
}

Future<RoomConnectionInfo> Function() staticAuthorization({
  required String projectId,
  required String roomName,
  required Uri url,
  required String jwt,
}) {
  return () async {
    return RoomConnectionInfo(projectId: projectId, roomName: roomName, roomUrl: url, jwt: jwt);
  };
}

class RoomConnectionScope extends StatefulWidget {
  const RoomConnectionScope({
    super.key,
    required this.authorization,
    required this.builder,
    this.doneBuilder,
    this.authorizingBuilder,
    this.retryingBuilder,
    this.notFoundBuilder,
    this.connectingBuilder,
    this.onReady,
    this.enableMessaging = true,
    this.oauthTokenRequestHandler,
    this.secretRequestHandler,
    this.client,
    this.roomClientFactory,
  });

  final String? client;

  final bool enableMessaging;
  final Function(RoomClient, OAuthTokenRequest)? oauthTokenRequestHandler;
  final Function(RoomClient, SecretRequest)? secretRequestHandler;
  final RoomClient Function(RoomConnectionInfo connectionInfo)? roomClientFactory;

  final Future<RoomConnectionInfo> Function() authorization;
  final void Function(RoomClient room)? onReady;

  final Widget Function(BuildContext context)? authorizingBuilder;
  final Widget Function(BuildContext context, Object? error)? retryingBuilder;
  final Widget Function(BuildContext context)? notFoundBuilder;
  final Widget Function(BuildContext context, RoomClient room)? connectingBuilder;
  final Widget Function(BuildContext context, RoomClient room) builder;
  final Widget Function(BuildContext context, Object? error)? doneBuilder;

  @override
  State createState() => _RoomConnectionScopeState();
}

class _RoomConnectionScopeState extends State<RoomConnectionScope> {
  static const int _retryBaseDelayMs = 500;
  static const int _retryMaxDelayMs = 30000;

  RoomClient? client;
  RoomConnectionInfo? connection;

  bool done = false;
  bool notFound = false;
  Object? error;
  bool _waitingToRetry = false;
  int _connectGeneration = 0;

  @override
  void initState() {
    if (DocumentRuntime.instance == null) {
      initializeFlutterDocumenRuntime();
    }
    super.initState();
    unawaited(connect());
  }

  Future<void> connect() async {
    final generation = ++_connectGeneration;
    var retryCount = 0;

    while (mounted && !done && generation == _connectGeneration) {
      try {
        final nextConnection = await widget.authorization();
        if (!mounted || generation != _connectGeneration) {
          return;
        }

        connection = nextConnection;
      } catch (e) {
        if (!mounted || generation != _connectGeneration) {
          return;
        }

        if (e is NotFoundException) {
          setState(() {
            notFound = true;
            error = e;
            _waitingToRetry = false;
          });
        } else {
          setState(() {
            done = true;
            error = e;
            _waitingToRetry = false;
          });
        }

        return;
      }

      final cli =
          widget.roomClientFactory?.call(connection!) ??
          RoomClient(
            protocol: Protocol(
              channel: WebSocketProtocolChannel(url: connection!.roomUrl, jwt: connection!.jwt),
            ),
            oauthTokenRequestHandler: widget.oauthTokenRequestHandler == null
                ? null
                : (request) => widget.oauthTokenRequestHandler!(client!, request),
            secretRequestHandler: widget.secretRequestHandler == null ? null : (request) => widget.secretRequestHandler!(client!, request),
          );

      var connectionEstablished = false;

      if (mounted && generation == _connectGeneration) {
        setState(() {
          client = cli;
          notFound = false;
          error = null;
          _waitingToRetry = false;
        });
      }

      try {
        await cli.start(
          onDone: () {
            if (!connectionEstablished) {
              return;
            }
            onDone();
          },
          onError: (err) {
            if (!connectionEstablished) {
              return;
            }
            onError(err);
          },
        );

        if (widget.enableMessaging) {
          await cli.messaging.enable();
        }

        if (!mounted || generation != _connectGeneration) {
          cli.dispose();
          return;
        }

        connectionEstablished = true;
        widget.onReady?.call(cli);
        return;
      } catch (e) {
        cli.dispose();

        if (!mounted || generation != _connectGeneration) {
          return;
        }

        if (!_isRetryableConnectionError(e)) {
          setState(() {
            done = true;
            error = e;
            _waitingToRetry = false;
          });
          return;
        }

        final delay = _getRetryDelay(retryCount);
        retryCount++;

        setState(() {
          client = null;
          error = e;
          _waitingToRetry = true;
        });

        await Future.delayed(delay);

        if (mounted && !done && generation == _connectGeneration) {
          setState(() {
            _waitingToRetry = false;
          });
        }
      }
    }
  }

  Duration _getRetryDelay(int retryCount) {
    final multiplier = math.pow(2, retryCount).toInt();
    return Duration(milliseconds: math.min(_retryMaxDelayMs, _retryBaseDelayMs * multiplier));
  }

  bool _isRetryableConnectionError(Object error) {
    return error is RoomServerException && error.retryable;
  }

  void onDone() {
    if (mounted && !done) {
      setState(() {
        done = true;
      });
    }
  }

  void onError(Object? err) {
    if (mounted && !done) {
      setState(() {
        done = true;
        error = err;
      });
    }
  }

  @override
  void dispose() {
    _connectGeneration++;
    done = true;
    client?.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (notFound) {
      if (widget.notFoundBuilder != null) {
        return widget.notFoundBuilder!(context);
      } else {
        return Text("Room Not Found");
      }
    }

    if (!done) {
      if (client == null) {
        if (_waitingToRetry) {
          if (widget.retryingBuilder != null) {
            return widget.retryingBuilder!(context, error);
          } else {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [CircularProgressIndicator(), SizedBox(height: 20), Text("Waiting to retry...")],
            );
          }
        }

        if (widget.authorizingBuilder != null) {
          return widget.authorizingBuilder!(context);
        } else {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [CircularProgressIndicator(), SizedBox(height: 20), Text("Initializing...")],
          );
        }
      } else {
        return FutureBuilder(
          future: client!.ready,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              if (widget.doneBuilder != null) {
                return widget.doneBuilder!(context, snapshot.error);
              }

              return Text("Room Disconnected: ${snapshot.error}");
            }

            if (snapshot.connectionState != ConnectionState.done) {
              if (widget.connectingBuilder == null) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [CircularProgressIndicator(), SizedBox(height: 20), Text("Connecting to room...")],
                );
              }

              return widget.connectingBuilder!(context, client!);
            }

            return widget.builder(context, client!);
          },
        );
      }
    } else {
      if (widget.doneBuilder == null) {
        if (error != null) {
          return Text("Room Disconnected: $error");
        } else {
          return Text("Room Closed");
        }
      }

      return widget.doneBuilder!(context, error);
    }
  }
}
