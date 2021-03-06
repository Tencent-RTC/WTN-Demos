# WTN-Demos
WTN(WebRTC Transmission Network) Demos






## HOW TO USE



1, Create your own TRTC app in Tencent Cloud.

2, Change your own `sdkappid` and `secret` in `server/config.ts`.

***Note that WTN is not for public for now, you should contact me to add your sdkappid to white list***

3, Run the server.

```bash
cd server/ && npm install 
npx ts-node server.ts
```

4, Run the client.

```bash
cd client/ && npm install
npm run dev
```


## WTN(WebRTC Transmission Network)


WTN(WebRTC Transmission Network) is based on Tencent's RTC(TRTC), providing a high-quality WebRTC service.

It provides a simple http signaling api based on `WHIP`,  and extend `WHIP` to support WebRTC playback.


[WHIP ietf](https://datatracker.ietf.org/doc/html/draft-ietf-wish-whip-02)


### Push stream 

Push URL

`https://signaling.rtc.qcloud.com/v1/push/streamid?sdkappid=xxx&userid=xxx&usersig=xxxx`


|  Params           |     Description      |    Required       |
| ----------------- | -------------------- |  --------------   |
| sdkappid          |   current sdkappid   |    YES            |
| userid            |   current userid     |    YES            |
| usersig           |   current usersig    |    YES            |
| streamid          |   streamid           |    YES            |
| prefervcodec      |   'h264' or 'vp8', h264 default  |    NO   |


Method: `POST`

Body: `SDP`

Content-Type: `application/sdp`

Resonse Code:

```
200/201: OK
400: Bad Request
403: Unauthorized
404: Not Found
409: Conflict, the steam exist
```

Response Header:

`Location: https://signaling.rtc.qcloud.com/v1/push/streamid?sdkappid=xxx&userid=xxxx&usersig=xxxxx&relay=xxxxx`  

***Location is the url used to stop the stream***

Response Body: `SDP`




### Stop push stream 

Stop URL

`https://signaling.rtc.qcloud.com/v1/push/streamid?sdkappid=xxx&userid=xxx&usersig=xxxx?relay=xxxx`


|  Params           |     Description      |    Required       |
| ----------------- | -------------------- |  --------------   |
| sdkappid          |   current sdkappid   |    YES            |
| userid            |   current userid     |    YES            |
| usersig           |   current usersig    |    YES            |
| streamid          |   streamid           |    YES            |
| relay             |   relay id           |    YES            |


Method: `DELETE`

Resonse Code:

```
200/201: OK
400: Bad Request
403: Unauthorized
404: Not Found
```



### Play stream 

Push URL

`https://signaling.rtc.qcloud.com/v1/play/streamid?sdkappid=xxx&userid=xxx&usersig=xxxx`


|  Params           |     Description      |    Required       |
| ----------------- | -------------------- |  --------------   |
| sdkappid          |   current sdkappid   |    YES            |
| userid            |   current userid     |    YES            |
| usersig           |   current usersig    |    YES            |
| streamid          |   streamid           |    YES            |

Method: `POST`

Body: `SDP`

Content-Type: `application/sdp`

Resonse Code:

```
200/201: OK
400: Bad Request
403: Unauthorized
404: Not Found
```

Response Header:

`Location: https://signaling.rtc.qcloud.com/v1/play/streamid?sdkappid=xxx&userid=xxxx&usersig=xxxxx&relay=xxxxx`  

***Location is the url used to stop the stream***

Response Body: `SDP`


### Stop Play stream 

Stop URL

`https://signaling.rtc.qcloud.com/v1/play/streamid?sdkappid=xxx&userid=xxx&usersig=xxxx?relay=xxxx`


|  Params           |     Description      |    Required       |
| ----------------- | -------------------- |  --------------   |
| sdkappid          |   current sdkappid   |    YES            |
| userid            |   current userid     |    YES            |
| usersig           |   current usersig    |    YES            |
| streamid          |   streamid           |    YES            |
| relay             |   relay id           |    YES            |


Method: `DELETE`

Resonse Code:

```
200/201: OK
400: Bad Request
403: Unauthorized
404: Not Found
```

