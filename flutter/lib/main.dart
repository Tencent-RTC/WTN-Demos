import 'dart:core';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:random_string/random_string.dart';

import 'wtnclient.dart';

void main() {
  if (!WebRTC.platformIsWeb) {
    WidgetsFlutterBinding.ensureInitialized();
  }
  runApp(WTNSample());
}

class WTNSample extends StatefulWidget {
  static String tag = 'whip_publish_sample';

  @override
  _WTNSampleState createState() => _WTNSampleState();
}

class _WTNSampleState extends State<WTNSample> {
  LocalStream? _localStream;
  RTCVideoRenderer? _localRenderer;
  final Map<String, RTCVideoRenderer> _remoteRenderers =
      <String, RTCVideoRenderer>{};
  bool _connecting = false;
  late WTNClient _wtnClient;
  final user = randomAlpha(5).toLowerCase();
  final streamId = randomAlpha(5).toLowerCase();
  final _serverController = TextEditingController();
  final _roomController = TextEditingController();
  late SharedPreferences _preferences;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() async {
    _preferences = await SharedPreferences.getInstance();
    this.setState(() {
      _serverController.text =
          _preferences.getString('server') ?? 'http://localhost:8000/';
      _roomController.text = _preferences.getString('room') ?? '123456';
    });
  }

  @override
  void deactivate() {
    super.deactivate();
    _saveSettings();
  }

  void _saveSettings() {
    _preferences.setString('server', _serverController.text);
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  void _connect() async {
    final url = _serverController.text;
    final room = _roomController.text;

    if (url.isEmpty || room.isEmpty) {
      return;
    }

    _wtnClient = WTNClient(url);

    _wtnClient.onStreamPublished.stream.listen((remoteStream) async {
      remoteStream.onPlay.stream.listen((mediastream) async {
        final renderer = RTCVideoRenderer();
        await renderer.initialize();
        setState(() {
          _remoteRenderers[remoteStream.streamId] = renderer;
          renderer.srcObject = mediastream;
        });
      });
      await _wtnClient.subscribe(remoteStream);
    });

    _wtnClient.onStreamUnPublished.stream.listen((remoteStream) async {
      setState(() {
        final renderer = _remoteRenderers.remove(remoteStream.streamId);
        if (renderer != null) {
          renderer.srcObject = null;
          renderer.dispose();
        }
      });
      await _wtnClient.unsubscribe(remoteStream);
    });

    _wtnClient.onConnected.stream.listen((event) async {
      await _wtnClient.join(room, user);

      try {
        _localStream = LocalStream(streamId);
        await _localStream!.init(audio: true, video: true);
        _localRenderer = RTCVideoRenderer();
        await _localRenderer?.initialize();
        setState(() {
          _localRenderer?.srcObject = _localStream!.mediaStream;
        });

        await _wtnClient.publish(_localStream!);
      } catch (e) {
        print('connect: error => ' + e.toString());
        _localRenderer?.srcObject = null;
        _localStream?.stop();
        return;
      }
    });

    if (!mounted) return;

    setState(() {
      _connecting = true;
    });
  }

  void _disconnect() async {
    try {
      setState(() {
        _connecting = false;

        _localRenderer?.srcObject = null;
        _localRenderer?.dispose();
        _localRenderer = null;

        _remoteRenderers.forEach((streamId, renderer) {
          renderer.srcObject = null;
          renderer.dispose();
        });
        _remoteRenderers.clear();
      });
      _localStream?.stop();
      await _wtnClient.unpublish(_localStream!);
      await _localStream!.stop();

      _wtnClient.remoteStreams.forEach((streamId, remoteStream) async {
        await _wtnClient.unsubscribe(remoteStream);
      });
    } catch (e) {
      print(e.toString());
    }
  }

  void _toggleCamera() async {
    if (_localStream == null) throw Exception('Stream is not initialized');
    final videoTrack = _localStream!.mediaStream!
        .getVideoTracks()
        .firstWhere((track) => track.kind == 'video');
    await Helper.switchCamera(videoTrack);
  }

  @override
  Widget build(BuildContext context) {
    final room = _roomController.text;
    final stateStr = 'room: $room, user: $user, stream: $streamId';
    return MaterialApp(
        home: Scaffold(
      appBar: AppBar(title: Text('WTN Sample'), actions: <Widget>[
        if (_connecting)
          IconButton(
            icon: Icon(Icons.switch_video),
            onPressed: _toggleCamera,
          ),
      ]),
      body: OrientationBuilder(
        builder: (context, orientation) {
          return Column(children: <Widget>[
            Column(children: <Widget>[
              FittedBox(
                child: Text(
                  '${stateStr}',
                  textAlign: TextAlign.left,
                ),
              ),
              if (!_connecting)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10.0, 18.0, 10.0, 0),
                  child: Align(
                    child: Text('Room Server URI:'),
                    alignment: Alignment.centerLeft,
                  ),
                ),
              if (!_connecting)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10.0, 0.0, 10.0, 0),
                  child: TextFormField(
                    controller: _serverController,
                    keyboardType: TextInputType.text,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      contentPadding: EdgeInsets.all(10.0),
                      border: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.black12)),
                    ),
                  ),
                ),
              if (!_connecting)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10.0, 18.0, 10.0, 0),
                  child: Align(
                    child: Text('Room ID:'),
                    alignment: Alignment.centerLeft,
                  ),
                ),
              if (!_connecting)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10.0, 0.0, 10.0, 0),
                  child: TextFormField(
                    controller: _roomController,
                    keyboardType: TextInputType.text,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      contentPadding: EdgeInsets.all(10.0),
                      border: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.black12)),
                    ),
                  ),
                )
            ]),
            if (_connecting && _localRenderer != null)
              Center(
                child: Container(
                  margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height - 110,
                  child: Column(
                    children: [
                      Row(
                        children: [Text('Local Video')],
                      ),
                      Row(
                        children: [
                          SizedBox(
                              width: 160,
                              height: 120,
                              child:
                                  RTCVideoView(_localRenderer!, mirror: true))
                        ],
                      ),
                      Row(
                        children: [Text('Remote Video')],
                      ),
                      Row(
                        children: [
                          ..._remoteRenderers.entries.map((entrie) {
                            return (Container(
                                width: 160,
                                height: 140,
                                decoration:
                                    BoxDecoration(color: Colors.black12),
                                child: Column(children: [
                                  Row(
                                    children: [Text('${entrie.key}')],
                                  ),
                                  Row(children: [
                                    SizedBox(
                                        width: 160,
                                        height: 120,
                                        child: RTCVideoView(entrie.value))
                                  ])
                                ])));
                          }).toList(),
                        ],
                      ),
                    ],
                  ),
                ),
              )
          ]);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _connecting ? _disconnect : _connect,
        tooltip: _connecting ? 'Hangup' : 'Call',
        child: Icon(_connecting ? Icons.call_end : Icons.phone),
      ),
    ));
  }
}
