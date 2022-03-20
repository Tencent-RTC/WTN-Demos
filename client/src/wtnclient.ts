import events from "events";
import { connect, Socket } from "socket.io-client";

const WTNBaseURL = "https://signaling.rtc.qcloud.com";

class LocalStream extends events.EventEmitter {
  public options: any;
  public mediaStream: MediaStream = null;

  public room: string;
  public user: string;
  public stream: string;
  public peerconnection: RTCPeerConnection;
  public pushUrl: string;
  public stopUrl: string;

  public audioTransceiver: RTCRtpTransceiver;
  public videoTransceiver: RTCRtpTransceiver;

  constructor(options: any) {
    super();
    this.options = options;
    this.room = options.room;
    this.user = options.user;
    this.stream = options.stream;
  }
  public async init(audio: boolean, video: boolean) {
    this.mediaStream = await navigator.mediaDevices.getUserMedia({
      audio: audio,
      video: video
        ? {
            width: { min: 640, ideal: 640, max: 1080 },
            height: { min: 480, ideal: 480, max: 720 },
          }
        : false,
    });
  }
  async play(videoElement: HTMLVideoElement) {
    videoElement.srcObject = this.mediaStream;
    videoElement.play();
  }
  async stop() {
    this.mediaStream.getTracks().forEach((track) => {
      track.stop();
    });
  }
}

class RemoteStream extends events.EventEmitter {
  private options: any;

  public user: string;
  public room: string;
  public stream: string;

  public peerconnection: RTCPeerConnection;
  public playUrl: string;
  public stopUrl: string;

  public audioTransceiver: RTCRtpTransceiver;
  public videoTransceiver: RTCRtpTransceiver;
  public mediaStream: MediaStream;

  constructor(options: any) {
    super();
    this.options = options;

    this.user = options.user;
    this.room = options.room;
    this.stream = options.stream;
    this.mediaStream = new MediaStream();
  }

  async play(videoElement: HTMLVideoElement) {
    videoElement.srcObject = this.mediaStream;
    videoElement.play();
  }
  async stop() {
    this.mediaStream.getTracks().forEach((track) => {
      track.stop();
    });
  }
}

class WTNClient extends events.EventEmitter {
  private socket: Socket;
  private options: any;
  private localUserSig: string;
  private sdkappid: number;
  private room: string;
  private user: string;
  private remoteStreams: Map<string, RemoteStream>;
  private localStream: LocalStream;

  constructor(options: any) {
    super();

    this.options = options;

    this.localStream = null;
    this.remoteStreams = new Map();

    this.socket = connect(this.options.url, {
      reconnection: true,
      reconnectionDelay: 1000,
      reconnectionDelayMax: 5000,
    });

    this.socket.on("connect", () => {
      this.emit("connect");
    });

    this.socket.on("disconnect", (reason: string) => {
      console.log("disconnect reason ", reason);
      this.emit("disconnect");
    });

    this.socket.on("stream-published", (data: any) => {
      console.log("stream-published  ===== ", data);

      const remoteStream = new RemoteStream(data);
      this.remoteStreams.set(data.user, remoteStream);
      this.emit("stream-published", remoteStream);
    });

    this.socket.on("stream-unpublished", (data: any) => {
      const remoteStream = this.remoteStreams.get(data.user);
      this.remoteStreams.delete(data.user);
      this.emit("stream-unpublished", remoteStream);
    });

    this.socket.on("user-left", (data: any) => {
      const remoteStream = this.remoteStreams.get(data.user);
      remoteStream.stop();
      this.remoteStreams.delete(data.user);
      this.emit("user-left", data);
    });

    this.socket.on("user-joined", (data: any) => {
      this.emit("user-joined", data);
    });
  }

  public async join(room: string, user: string) {
    this.room = room;
    this.user = user;

    return new Promise((resolve, reject) => {
      this.socket.emit(
        "join",
        {
          room: room,
          user: user,
        },
        (data: any) => {
          if (data.code === 0) {
            this.localUserSig = data.userSig;
            this.sdkappid = data.sdkappid;
            console.log("joined, streams", data.streams);
            resolve(data);

            for (const stream of data.streams) {
              const remoteStream = new RemoteStream(stream);
              this.remoteStreams.set(stream.user, remoteStream);
              this.emit("stream-published", remoteStream);
            }
          } else {
            reject(data);
          }
        }
      );
    });
  }

  public createLocalSteam(stream: string) {
    const localStream = new LocalStream({
      stream,
    });
    return localStream;
  }

  public async publish(stream: LocalStream) {
    stream.user = this.user;
    stream.room = this.room;

    const pushUrl = `${WTNBaseURL}/v1/push/${stream.stream}?sdkappid=${this.sdkappid}&userid=${this.user}&usersig=${this.localUserSig}`;
    console.log("pushUrl", pushUrl);

    let options = {
      iceServers: [],
      iceTransportPolicy: "all", // relay or all
      bundlePolicy: "max-bundle",
      rtcpMuxPolicy: "require",
      sdpSemantics: "unified-plan",
    };

    const peerconnection = new RTCPeerConnection(options as RTCConfiguration);

    const transceiverInit: RTCRtpTransceiverInit = {
      direction: "sendonly",
      streams: [stream.mediaStream],
    };

    if (stream.mediaStream.getVideoTracks().length > 0) {
      peerconnection.addTransceiver(
        stream.mediaStream.getVideoTracks()[0],
        transceiverInit
      );
    }

    if (stream.mediaStream.getAudioTracks().length > 0) {
      peerconnection.addTransceiver(
        stream.mediaStream.getAudioTracks()[0],
        transceiverInit
      );
    }

    const offer = await peerconnection.createOffer();
    await peerconnection.setLocalDescription(offer);

    let res = await fetch(pushUrl, {
      method: "POST",
      headers: { "Content-Type": "application/sdp" },
      body: offer.sdp,
    });

    if (!res.ok) {
      throw new Error(`WTN error:${res.status} ${res.statusText}`);
    }

    const stopUrl = res.headers.get("Location");
    const answer = await res.text();

    const answerDesc = {
      type: "answer",
      sdp: answer,
    };
    await peerconnection.setRemoteDescription(
      answerDesc as RTCSessionDescription
    );

    this.localStream = stream;
    this.localStream.peerconnection = peerconnection;
    this.localStream.pushUrl = pushUrl;
    this.localStream.stopUrl = stopUrl;

    this.localStream = stream;

    return new Promise((resolve, reject) => {
      this.socket.emit(
        "publish",
        {
          room: this.room,
          user: this.user,
          stream: stream.stream,
        },
        (data: any) => {
          if (data.code === 0) {
            console.log("published", data);
            resolve(data);
          } else {
            reject(data);
          }
        }
      );
    });
  }

  public async unpublish(stream: LocalStream) {
    if (!stream.stopUrl) {
      throw new Error("stream not published");
    }
    console.log("stopUrl", stream.stopUrl);

    this.remoteStreams.delete(stream.user);
    // send bye rtcp
    stream.peerconnection.getTransceivers().forEach((transceiver) => {
      transceiver.stop();
    });

    stream.peerconnection.close();

    let res = await fetch(stream.stopUrl, {
      method: "DELETE",
      headers: { "Content-Type": "application/sdp" },
    });

    if (!res.ok) {
      throw new Error(`WTN stop error:${res.status} ${res.statusText}`);
    }

    return new Promise((resolve, reject) => {
      this.socket.emit(
        "unpublish",
        {
          room: this.room,
          user: this.user,
          stream: stream.stream,
        },
        (data: any) => {
          if (data.code === 0) {
            console.log("unpublished", data);
            resolve(data);
          } else {
            reject(data.message);
          }
        }
      );
    });
  }

  public async subscribe(stream: RemoteStream) {
    const playUrl = `${WTNBaseURL}/v1/play/${stream.stream}?sdkappid=${this.sdkappid}&userid=${this.user}&usersig=${this.localUserSig}`;
    console.log("playUrl", playUrl);

    let options = {
      iceServers: [],
      iceTransportPolicy: "all", // relay or all
      bundlePolicy: "max-bundle",
      rtcpMuxPolicy: "require",
      sdpSemantics: "unified-plan",
    };

    const peerconnection = new RTCPeerConnection(options as RTCConfiguration);

    const transceiverInit: RTCRtpTransceiverInit = {
      direction: "recvonly",
    };

    const videoTransceiver = peerconnection.addTransceiver(
      "video",
      transceiverInit
    );
    const audioTransceiver = peerconnection.addTransceiver(
      "audio",
      transceiverInit
    );

    const offer = await peerconnection.createOffer();
    await peerconnection.setLocalDescription(offer);

    let res = await fetch(playUrl, {
      method: "POST",
      headers: { "Content-Type": "application/sdp" },
      body: offer.sdp,
    });

    if (!res.ok) {
      throw new Error(`WTN play error:${res.status} ${res.statusText}`);
    }

    const stopUrl = res.headers.get("Location");
    const answer = await res.text();

    const answerDesc = {
      type: "answer",
      sdp: answer,
    };
    await peerconnection.setRemoteDescription(
      answerDesc as RTCSessionDescription
    );

    stream.peerconnection = peerconnection;
    stream.playUrl = playUrl;
    stream.stopUrl = stopUrl;
    stream.audioTransceiver = audioTransceiver;
    stream.videoTransceiver = videoTransceiver;

    stream.mediaStream.addTrack(audioTransceiver.receiver.track);
    stream.mediaStream.addTrack(videoTransceiver.receiver.track);

    return;
  }

  public async unsubscribe(stream: RemoteStream) {
    if (!stream.stopUrl) {
      throw new Error("stream not played");
    }
    console.log("stopUrl", stream.stopUrl);

    // send bye rtcp
    stream.peerconnection.getTransceivers().forEach((transceiver) => {
      transceiver.stop();
    });

    stream.peerconnection.close();

    let res = await fetch(stream.stopUrl, {
      method: "DELETE",
      headers: { "Content-Type": "application/sdp" },
    });

    if (!res.ok) {
      throw new Error(`WTN stop error:${res.status} ${res.statusText}`);
    }
  }

  public async leave(room: string, user: string) {
    if (this.socket.connected) {
      this.socket.disconnect();
    }
  }
}

export { WTNClient, LocalStream, RemoteStream };
