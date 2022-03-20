import express from "express";
import http from "http";

import cors from "cors";

import { Server, Socket } from "socket.io";

const TLSSigAPIv2 = require("tls-sig-api-v2");

import config from "./config";

var sig = new TLSSigAPIv2.Api(config.sdkappid, config.secret);

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const server = http.createServer(app);

const socketServer = new Server(server, {
  pingInterval: 10000,
  pingTimeout: 5000,
  cors: {
    origin: "*",
  },
});

socketServer.on("connection", async (socket: Socket) => {
  socket.on("join", async (data: any, ack: Function) => {
    const room = data.room;
    const user = data.user;

    socket.data.room = room;
    socket.data.user = user;

    const sockets = await socketServer.of("/").in(room).fetchSockets();
    let streams = [];

    for (const s of sockets) {
      if (s.data.published) {
        streams.push({
          user: s.data.user,
          stream: s.data.stream,
        });
      }
    }

    ack({
      code: 0,
      userSig: sig.genSig(user, 3600 * 24),
      sdkappid: config.sdkappid,
      streams: streams,
    });

    socket.join(room);

    socket.to(room).emit("user-joined", {
      user: user,
      room: room,
    });
  });

  socket.on("publish", async (data: any, ack: Function) => {
    const stream = data.stream;
    const user = data.user;
    const room = data.room;

    socket.data.published = true;
    socket.data.stream = stream;

    ack({
      code: 0,
    });

    socket.to(room).emit("stream-published", {
      user: user,
      stream: stream,
    });
  });

  socket.on("unpublish", async (data: any, ack: Function) => {
    const stream = data.stream;
    const user = data.user;
    const room = data.room;

    socket.data.published = false;
    socket.data.stream = stream;

    ack({
      code: 0,
    });

    socket.to(room).emit("stream-unpublished", {
      user: user,
      stream: stream,
    });
  });

  socket.on("disconnect", async () => {
    const room = socket.data.room;
    const user = socket.data.user;

    socket.data.published = false;

    socket.leave(room);

    socket.to(room).emit("user-left", {
      user: user,
      room: room,
    });
  });
});

const port = 8000;

server.listen(port, "0.0.0.0", () => {
  console.log(`Server started on ${port}`);
});
