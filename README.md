# zeroconnect

Uses NSD to automagically create data streams over the local network.

A translation of https://github.com/Erhannis/zeroconnect into Flutter.  Some statements/code may be slightly inaccurate or weird as a result.
Note that I've had some problems getting various NSD/MDNS/Zeroconf/etc. implementations to accept the same type structure or work together,
so this currently won't communicate with the python version, though it feels a sliver away from being able to do so.

Uses [NSD](https://github.com/sebastianhaberey/nsd), which means this has its requirements:

**Table of Contents**

- [Permissions](#permissions)
- [License](#license)
- [Tips](#tips)

## Permissions

### Android

Add the following permissions to your manifest:

```Xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
```

### iOS

Add the following permissions to your Info.plist (replace service type with your own):

```Xml
<key>NSLocalNetworkUsageDescription</key>
<string>Required to discover local network devices</string>
<key>NSBonjourServices</key>
<array>
    <string>_http._tcp</string>
</array>
```

## Usage

One or more servers, and one or more clients, run connected to the same LAN.  (Wifi or ethernet.)

### Most basic

Service:
```dart
import 'package:zeroconnect/zeroconnect.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // This is not needed if the usual `runApp` has already been called
  await ZeroConnect().advertise(serviceId: "YOURSERVICEID", callback: (messageSock, nodeId, serviceId) async {
    print("got message connection from $nodeId");
    var str = await messageSock.recvString();
    print(str);
    await messageSock.sendString("Hello from server");
  });
}
```

Client:
```dart
import 'package:zeroconnect/zeroconnect.dart';

Future<void> main() async {
  var messageSock = await ZeroConnect().connectToFirst(serviceId: "YOURSERVICEID");
  await messageSock?.sendString("Hello from client");
  var str = await messageSock?.recvBytes();
  print(str);
}
```

### Less basic

// You can receive a String as bytes, but note you can't always receive bytes as a string, AFAIK

Service:
```dart
import 'package:zeroconnect/zeroconnect.dart';

const SERVICE_ID = "YOURSERVICEID";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // This is not needed if the usual `runApp` has already been called
  var zc = ZeroConnect(localId: "SERVER_ID");
  await zc.advertise(serviceId: SERVICE_ID, callback: (messageSock, nodeId, serviceId) async {
    print("got message connection from $nodeId");
    // If you also want to spontaneously send messages, pass the socket to e.g. another thread.
    while (true) {
      var str = await messageSock.recvString();
      print("$str");
      switch (str) {
        case "enable jimjabber":
          print("ENABLE JIMJABBER");
          break;
        case "save msg:":
          var toSave = await messageSock.recvBytes();
          print("SAVE MESSAGE $toSave");
          break;
        case "marco":
          await messageSock.sendString("polo");
          print("PING PONGED");
          break;
        case null:  
          print("Connection closed from $nodeId");
          await messageSock.close();
          return;
        default:
          print("Unhandled message: $str");
          break;
      }
      // Use messageSock.sock for e.g. sock.remoteAddress
      // I recommend messageSock.close() after you're done with it - but it'll get closed on zc.close(), at least
    }
  });
  // You may call zc.close(), when you want to shut down existing stuff
}
```

Client:
```dart
import 'package:zeroconnect/zeroconnect.dart';

const SERVICE_ID = "YOURSERVICEID";

Future<void> main() async {
  var zc = ZeroConnect(localId: "CLIENT_ID"); // Technically the nodeId is optional; it'll assign you a random UUID
  
  var ads = await zc.scan(serviceId: SERVICE_ID, time: const Duration(seconds: 5));
  // OR: var ads = await zc.scan(serviceId: SERVICE_ID, nodeId: NODE_ID);
  // An `Ad` contains a `serviceId` and `nodeId` etc.; see `Ad` for details
  var messageSock = await zc.connect(ads.first); // See also (ZeroConnect).connectRaw
  // OR: var messageSock = await zc.connectToFirst(serviceId: SERVICE_ID);
  // OR: var messageSock = await zc.connectToFirst(serviceId: SERVICE_ID, nodeId: NODE_ID, time: const Duration(seconds: 10));
  // Perhaps one day you will be able to specify a nodeId alone, but I had some problems when doing that I haven't fixed, yet.

  await messageSock?.sendString("enable jimjabber");
  await messageSock?.sendString("save msg:");
  await messageSock?.sendString("i love you");
  await messageSock?.sendString("marco");
  print("rx: ${await messageSock?.recvString()}");

  // ...

  await zc.close();
}
```

You can also get raw sockets rather than MessageSockets, if you prefer.
See e.g. (ZeroConnect).advertiseRaw and (ZeroConnect).connectRaw.
...Actually, I haven't tested them, and it's possible that because I initially wrap the Socket with
a MessageSocket for some handshake stuff, that MessageSocket may interfere with using the raw
Socket.  Sorry.
//DUMMY Look into fixing that, and maybe add example code

There's a few other functions you might find useful.  Check autocomplete, look at the source code.

## Tips

Be careful not to have two nodes recv from each other at the same time, or they'll deadlock.
However, you CAN have them send at the same time (at least according to my tests).

`ZeroConnect` is intended to be manipulated via its methods, but it probably won't immediately explode if you
read the data in the fields.

Note that some computers/networks block mdns/nsd/zeroconf, or external connection attempts, etc.

Calling `broadcast` will automatically clean up dead connections.  ...Theoretically.  The once I tested that in Flutter, the send threw no error.

If you close your socket immediately after sending a message, the data may not finish sending.  Not my fault; blame socket.

`broadcast` uses MessageSockets, so if you're using a raw socket, be aware the message will be prefixed with a header, currently
an 8 byte unsigned big-endian long representing the length of the subsequent message.  See `MessageSocket`.

See near the start of zeroconnect.dart to see logging settings, or do like so:
```dart
import 'package:zeroconnect/zeroconnect.dart';

void main() {
  ZC_LOGGING = 10; // 4+ for everything, atm; -1 for nothing except uncaught exceptions
  // ...
}
```
zeroconnect.dart also contains some presets; ERROR/WARN/INFO/VERBOSE/DEBUG atm.

## License

`zeroconnect` is distributed under the terms of the [MIT](https://spdx.org/licenses/MIT.html) license.

## TODO
ssl
lower timeouts?
connect to all, forever?
    connection callback
maybe some automated tests?
.advertiseSingle to get one connection?  for quick stuff?
I don't think either direction detects disconnects, for some reason
