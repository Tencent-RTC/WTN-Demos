import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_whip/flutter_whip.dart';

const wtnBaseURL = "https://signaling.rtc.qcloud.com";

class LocalStream {
  String streamId;
  MediaStream? mediaStream;
  String? pushUrl;
  WHIP? whip;
  LocalStream(this.streamId);

  Future<void> init({bool? audio, bool? video}) async {
    mediaStream = await navigator.mediaDevices.getUserMedia({
      'audio': audio ?? true,
      'video': video ??
          {
            'mandatory': {
              'minWidth': '1280',
              'minHeight': '720',
              'minFrameRate': '30',
            },
            'facingMode': 'user',
            'optional': [],
          },
    });
  }

  Future<void> publish(String url) async {
    pushUrl = url;

    if (mediaStream == null) {
      print('mediaStream is null');
      return;
    }
    whip ??= WHIP(url: pushUrl!);

    await whip!.initlize(mode: WhipMode.kSend, stream: mediaStream!);
    await whip!.connect();
  }

  Future<void> unpublish() async {
    whip?.close();
  }

  Future<void> stop() async {
    mediaStream?.getTracks().forEach((track) async {
      await track.stop();
    });
  }
}

class RemoteStream {
  MediaStream? mediaStream;
  final StreamController<MediaStream?> onPlay = StreamController.broadcast();
  Map<String, dynamic> options;
  String? playUrl;
  late String streamId;
  late String user;
  WHIP? whip;
  RemoteStream(this.options) {
    streamId = options['stream'] as String;
    user = options['user'] as String;
  }

  Future<void> init() async {}

  Future<void> subscribe(String playUrl) async {
    this.playUrl = playUrl;
    whip ??= WHIP(url: playUrl);
    whip?.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'video') {
        mediaStream = event.streams.first;
        onPlay.add(mediaStream);
      }
    };
    await whip!.initlize(mode: WhipMode.kReceive);
    await whip!.connect();
  }

  Future<void> unsubscribe() async {
    whip?.close();
    await stop();
  }

  Future<void> stop() async {
    mediaStream?.getTracks().forEach((track) async {
      await track.stop();
    });
    mediaStream = null;
  }
}

class WTNClient {
  String url;
  bool connected = false;
  late socket_io.Socket socket;
  String? localUserSig;
  String? room;
  String? user;
  int? sdkappid;
  LocalStream? localStream;
  Map<String, RemoteStream> remoteStreams = {};
  bool joined = false;

  final StreamController<bool> onConnected = StreamController.broadcast();
  final StreamController<bool> onDisconnected = StreamController.broadcast();
  final StreamController<dynamic> onUserJoin = StreamController.broadcast();
  final StreamController<dynamic> onUserLeft = StreamController.broadcast();
  final StreamController<RemoteStream> onStreamPublished =
      StreamController.broadcast();
  final StreamController<RemoteStream> onStreamUnPublished =
      StreamController.broadcast();

  WTNClient(this.url) {
    socket = socket_io.io(
        url,
        socket_io.OptionBuilder()
            .setTransports(['websocket']) // for Flutter or Dart VM
            .enableAutoConnect() // disable auto-connection
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(5000)
            .build());

    socket.onConnect((_) {
      print('connect');
      connected = true;
      onConnected.add(connected);
    });

    socket.onDisconnect((_) {
      print('disconnect');
      connected = false;
      onDisconnected.add(connected);
    });

    socket.on('user-joined', (data) {
      print('user-joined: $data');
      onUserJoin.add(data);
    });

    socket.on('user-left', (data) {
      print('user-left: $data');
      final remoteStream = remoteStreams.remove(data['user']);
      if (remoteStream != null) {
        remoteStream.stop();
        onStreamUnPublished.add(remoteStream);
      }
      onUserLeft.add(data);
    });

    socket.on('stream-published', (data) {
      print('stream-published: $data');
      final remoteStream = RemoteStream(data);
      remoteStreams[data['user']] = remoteStream;
      onStreamPublished.add(remoteStream);
    });

    socket.on('stream-unpublished', (data) {
      final remoteStream = remoteStreams.remove(data['user']);
      if (remoteStream != null) {
        remoteStream.stop();
        onStreamUnPublished.add(remoteStream);
      }
    });

    socket.connect();
  }

  Future<dynamic> join(String room, String user) async {
    this.room = room;
    this.user = user;
    final Completer<dynamic> completer = Completer<dynamic>();
    socket.emitWithAck("join", {
      'room': room,
      'user': user,
    }, ack: (Map<String, dynamic> data) {
      if (data['code'] == 0) {
        localUserSig = data['userSig'] as String;
        sdkappid = data['sdkappid'] as int;
        print("joined, streams ${data['streams']}");
        data['streams'].forEach((stream) {
          final remoteStream = RemoteStream(stream);
          remoteStreams[stream['user']] = remoteStream;
          onStreamPublished.add(remoteStream);
        });
        completer.complete(data);
      } else {
        completer.completeError(data);
      }
    });
    return completer.future;
  }

  Future<dynamic> publish(LocalStream localStream) async {
    final pushUrl =
        '$wtnBaseURL/v1/push/${localStream.streamId}?sdkappid=$sdkappid&userid=$user&usersig=$localUserSig';
    print('pushUrl $pushUrl');
    await localStream.publish(pushUrl);

    final Completer<dynamic> completer = Completer<dynamic>();
    socket.emitWithAck("publish", {
      'room': room,
      'user': user,
      'stream': localStream.streamId,
    }, ack: (Map<String, dynamic> data) {
      if (data['code'] == 0) {
        print("published $data");
        completer.complete(data);
      } else {
        completer.completeError(data);
      }
    });
    return completer.future;
  }

  Future<void> unpublish(LocalStream localStream) async {
    await localStream.unpublish();
    final Completer<dynamic> completer = Completer<dynamic>();
    socket.emitWithAck("unpublish", {
      'room': room,
      'user': user,
      'stream': localStream.streamId,
    }, ack: (Map<String, dynamic> data) {
      if (data['code'] == 0) {
        print("unpublished $data");
        completer.complete(data);
      } else {
        completer.completeError(data);
      }
    });
    return completer.future;
  }

  Future<void> subscribe(RemoteStream remoteStream) async {
    final playUrl =
        '$wtnBaseURL/v1/play/${remoteStream.streamId}?sdkappid=$sdkappid&userid=$user&usersig=$localUserSig';
    print('playUrl $playUrl');
    print("subscribe ${remoteStream.streamId}");
    await remoteStream.subscribe(playUrl);
  }

  Future<void> unsubscribe(RemoteStream remoteStream) async {
    print("unsubscribe ${remoteStream.streamId}");
    await remoteStream.unsubscribe();
  }
}
