library zeroconnect;

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:sync/sync.dart';
import 'package:sync/waitgroup.dart';
import 'package:uuid/uuid.dart';
import 'package:nsd/nsd.dart';

import 'FilterMap.dart';
import 'MessageSocket.dart';
import 'misc.dart';

// Translated from https://github.com/Erhannis/zeroconnect/blob/master/zeroconnect/zeroconnect.py

var ZC_LOGGING = 1; // Higher is noisier, up to, like, 10
const ERROR = 0;
const WARN = 1;
const INFO = 2;
const VERBOSE = 3;
const DEBUG = 4;

void zlog(int level, String msg) {
    if (level <= ZC_LOGGING) {
        log(msg);
    }
}

void zerr(int level, String msg) {
    zlog(level, msg); // Originally logged to stderr instead
}


// // https://stackoverflow.com/a/166591/513038
// Future<List<Address>> getAddresses() async { //THINK IPv6?
//     await NetworkInterface.list();
//     //await NetworkInfo().getWifiIP();
//     var addresses = {};
//     for ifaceName in interfaces() {
//         for i in ifaddresses(ifaceName).setdefault(AF_INET, []):
//         if "addr" in i:
//         addresses.add(socket.inet_aton(i["addr"]))
//     }
//     return addresses
// }

String? _serviceToKey(String? serviceId) {
    if (serviceId == null) {
        return null;
    } else {
        return "_$serviceId._tcp"; //CHECK Check
    }
}

String? _nodeToKey(String? nodeId) {
    if (nodeId == null) {
        return null;
    } else {
        return "$nodeId._tcp"; //CHECK //DITTO
    }
}

String _typeToService(String type_) { // This is kindof horrible, and brittle, and MAY be subject to accidental bad data
    return type_.substring("_".length, type_.length-("._tcp.").length); //CHECK //DITTO
}

String _nameToNode(String name) {
    return name.substring("".length, name.length-("._tcp.").length); //CHECK //DITTO
}

class ZeroConnect {

}




//DUMMY This is almost definitely wrong
class DelegateListener extends ServiceListener {
    DelegateListener(this.update_service, this.remove_service, this.add_service);
}

enum SocketMode {
    RAW,
    MESSAGES,
}

/**
 * Represents a node's zeroconf advertisement.<br/>
 */
class Ad { // Man, this feels like LanCopy all over
    /**
     * Like, the zc.get_service_info info<br/>
     */
    static Ad fromInfo(Service info) {
        //CHECK Maybe don't throw on nulls?
        final type = info.type!;
        final name = info.name!;
        final addresses = {info.host!}; //THINK Maybe ip addresses //tuple([socket.inet_ntoa(addr) for addr in info.addresses]);
        final port = info.port!;
        final serviceId = _typeToService(type);
        final nodeId = _nameToNode(name);
        return Ad(type, name, addresses, port, serviceId, nodeId);
    }

    final String type;
    final String name;
    final Set<String> addresses; //CHECK what type
    final int port;
    final String serviceId;
    final String nodeId;

    Ad(this.type, this.name, this.addresses, this.port, this.serviceId, this.nodeId);

    List<String> getKey() {
        return [type, name];
    }

    @override
    String toString() {
        return "Ad('$type','$name',$addresses,$port,'$serviceId','$nodeId')";
    }

    @override
    bool operator ==(other) {
        return other is Ad
            && this.type == other.type
            && this.name == other.name
            && (const SetEquality().equals)(this.addresses, other.addresses)
            && this.port == other.port
            && this.serviceId == other.serviceId
            && this.nodeId == other.nodeId;
    }

    int get hashCode => Object.hash(type, name, (const SetEquality().hash)(addresses), port, serviceId, nodeId);
}

//TODO Note: I'm not sure there aren't any race conditions in this.  I've been writing in Dart's strict threading model for months, and it took me a while to remember that race conditions exist
/**
 * Uses zeroconf to automatically connect devices on a network.<br/>
 * Here's some basic examples; check the README or source code for further info.
 *
 * Service:    //DUMMY Translate to dart
 * ```python
 * from zeroconnect import ZeroConnect
 *
 * def rxMessageConnection(messageSock, nodeId, serviceId):
 * print(f"got message connection from {nodeId}")
 * data = messageSock.recvMsg()
 * print(data)
 * messageSock.sendMsg(b"Hello from server")
 *
 * ZeroConnect().advertise(rxMessageConnection, "YOUR_SERVICE_ID_HERE")
 * ```
 *
 * Client:    //DITTO
 * ```python
 * from zeroconnect import ZeroConnect
 * messageSock = ZeroConnect().connectToFirst("YOUR_SERVICE_ID_HERE")
 * messageSock.sendMsg(b"Test message")
 * data = messageSock.recvMsg()
 * ```
 */
class ZeroConnect {
    final String localId;

    var localAds = <Ad>{};
    var remoteAds = FilterMap<String, Set<Ad>>(2); // (type_, name) = set{Ad} //TODO Should we even PERMIT multiple ads per keypair?
    var incameConnections = FilterMap<String, List<MessageSocket>>(2); // (service, node) = list[messageSocket]
    var outgoneConnections = FilterMap<String, List<MessageSocket>>(2); // (service, node) = list[messageSocket]

    ZeroConnect({String? localId = null}) : this.localId = localId ?? const Uuid().v4() {
        log("create client");
        final MDnsClient client = MDnsClient(rawDatagramSocketFactory: (dynamic host, int port, {bool? reuseAddress, bool? reusePort, int ttl = 1}) {
            log("rawDatagramSocketFactory $host $port $reuseAddress $reusePort $ttl");
            return RawDatagramSocket.bind(host, port, reuseAddress: true, reusePort: false, ttl: ttl);
        });

        log("start client");
        client.start().then((value) {
            asdf; //NEXT
        }, onError: (e){log(e);}); //THINK ???


        this.zeroconf = Zeroconf(ip_version=IPVersion.V4Only); //TODO All IPv?
        this.zcListener = DelegateListener(self.__update_service, self.__remove_service, self.__add_service);
    }

    //DUMMY These are all wrong
    void __update_service(Service service) {
        zlog(INFO, "Service updated: $service");
        var ad = Ad.fromInfo(service);
        if (!localAds.contains(ad)) { //THINK SHOULD I ignore stuff in localAds?
            var ras = remoteAds.getExact(ad.getKey());
            if (ras == null) {
                ras = {};
                remoteAds[ad.getKey()] = ras;
            }
            ras.add(ad); // Not even sure this is correct.  Should I remove existing old records?  CAN I?
        }
    }

    void __remove_service(Service service) {
        zlog(INFO, "Service removed: $service");
        //MISC Maybe should remove from list?
    }

    void __add_service(Service service) {
        zlog(INFO, "Service added: $service");
        var ad = Ad.fromInfo(service);
        if (!localAds.contains(ad)) { //THINK SHOULD I ignore stuff in localAds?
            var ras = remoteAds.getExact(ad.getKey());
            if (ras == null) {
                ras = {};
                remoteAds[ad.getKey()] = ras;
            }
            ras.add(ad); // Not even sure this is correct.  Should I remove existing old records?  CAN I?
        }
    }

    /**
     * Advertise a service, and send new connections to `callback`.<br/>
     * `callback` is called on its own (daemon) thread.  If you want to loop forever, go for it.<br/>
     * Be warned that you should only have one adveristement running (locally?) with a given name - zeroconf
     * throws an exception otherwise.  However, if you create another ZeroConnect with a different name, it works fine.<br/>
     */
    Future<void> advertise(void Function(MessageSocket sock, String nodeId, String serviceId) callback, {required String serviceId, int port=0, String host="0.0.0.0", SocketMode mode=SocketMode.MESSAGES}) async { //THINK Have an ugly default serviceId?
        Future<void> socketCallback(Socket sock) async {
            var messageSock = MessageSocket(sock);
            await messageSock.sendString(localId); // It appears both sides can send a message at the same time.  Different comms may give different results, though.
            await messageSock.sendString(serviceId);
            var clientNodeId = await messageSock.recvString();
            var clientServiceId = await messageSock.recvString(); // Note that this might be empty
            if ((clientNodeId == null || clientServiceId == null) || (clientNodeId.isEmpty && clientServiceId.isEmpty)) {
                // Connection was canceled (or was invalid)
                zlog(INFO, "connection canceled from $sock"); //CHECK Check for any e.g. {addr} instead of $addr
                messageSock.close();
                return;
            }
            // The client might report different IDs than its service - is that problematic?
            // ...Actually, clients don't need to have an advertised service in the first place.  So, no.
            if (incameConnections[[clientNodeId, clientServiceId]].isEmpty) {
                incameConnections[[clientNodeId, clientServiceId]] = [];
            }
            incameConnections.getExact([clientNodeId, clientServiceId])!.add(messageSock);
            if (mode == SocketMode.RAW) {
                callback(sock, clientNodeId, clientServiceId);
            } else if (mode == SocketMode.MESSAGES) {
                callback(messageSock, clientNodeId, clientServiceId);
            }
        }

        final ssock = await ServerSocket.bind(InternetAddress.anyIPv4, port); //THINK All IPvX?  //THINK Multiple interfaces?
        var lsub = ssock.listen(socketCallback); //LEAK This never exits, there's no way to cancel the advertisement
        port = ssock.port;

        register(Service(name: localId, type: _serviceToKey(serviceId), port: port)).then((registration) {
            zlog(INFO, "registered: $registration");
            localAds.add(Ad(_serviceToKey(serviceId)!, localId, {registration.service.host!}, port, serviceId, localId)); // Can `host` be null?
        }).onError((e, st) {
            zlog(INFO, "registration error: $e @ $st");
        });
    }

    /**
     * Scans for `time`, and returns matching services.<br/>
     * If `time` is zero, begin scanning (and DON'T STOP), and return previously discovered services.<br/>
     * If `time` is negative, DON'T scan, and instead just return previously discovered services.<br/>
     * <br/>
     * //DUMMY Requires you to provide a serviceId, unlike the python code<br/>
     */
    Future<Set<Ad>> scan({required String serviceId, String? nodeId, Duration time=const Duration(seconds: 30)}) async {
        var service_key = _serviceToKey(serviceId)!;
        var node_key = _nodeToKey(nodeId);

        if (time.inMicroseconds >= 0) {
            var discovery = await startDiscovery(service_key);
            zlog(INFO, "discovery started");
            discovery.addServiceListener((service, status) {
                zlog(INFO, "discovery service update: $service $status");
                switch (status) {
                    case ServiceStatus.found:
                        __add_service(service);
                        break;
                    case ServiceStatus.lost:
                        __remove_service(service);
                        break;
                }
            });
            if (time.inMicroseconds > 0) {
                await Future.delayed(time);
                await stopDiscovery(discovery);
            }
        }

        var r = remoteAds.getFilter([service_key, node_key]).fold(Set<Ad>(), (a, b) => a..addAll(b));
        return r;
    }
    /**
     * Stream version of `scan`.<br/>
     * If `time` is 0, though, the returned stream will not complete, and instead just keep returning results.<br/>
     * <br/>
     * //DITTO //DUMMY Requires you to provide a serviceId, unlike the python code<br/>
     */
    Stream<Ad> scanGen({required String serviceId, String? nodeId, Duration time=const Duration(seconds: 30)}) async* {
        var service_key = _serviceToKey(serviceId)!;
        var node_key = _nodeToKey(nodeId);

        var totalAds = Set<Ad>();

        for (var aSet in remoteAds.getFilter([service_key, node_key])) {
            for (var ad in aSet) {
                totalAds.add(ad);
                yield ad;
            }
        }

        if (time.inMicroseconds >= 0) {
            var newAds = StreamController<Ad>();

            var discovery = await startDiscovery(service_key);
            zlog(INFO, "discovery started");
            discovery.addServiceListener((service, status) {
                zlog(INFO, "discovery service update: $service $status");
                switch (status) {
                    case ServiceStatus.found:
                        var ad = Ad.fromInfo(service);
                        if (!totalAds.contains(ad)) {
                            totalAds.add(ad);
                            newAds.add(ad);
                        }
                        __add_service(service);
                        break;
                    case ServiceStatus.lost:
                        __remove_service(service);
                        break;
                }
            });
            if (time.inMicroseconds > 0) {
                Future.delayed(time).then((_) async {
                    await stopDiscovery(discovery);
                    await newAds.close();
                });
            }
            yield* newAds.stream;
        }
    }

    /**
     * Scan for anything that matches the IDs, try to connect to them all, and return the first
     * one that succeeds.<br/>
     * Note that this may leave extraneous dead connections in `outgoneConnections`!<br/>
     * Returns `(sock, Ad)`, or None if the timeout expires first.<br/>
     * If timeout < 0, don't scan, only use cached services.<br/>
     * <br/>
     * //DITTO //DUMMY Requires you to provide a serviceId, unlike the python code<br/>
     */
    Future<MessageSocket?> connectToFirst({required String serviceId, String? nodeId, String localServiceId="", SocketMode mode=SocketMode.MESSAGES, Duration timeout=const Duration(seconds: 30)}) async { //THINK Timeout in ms?
        // if serviceId == None and nodeId == None:
        //     raise Exception("Must have at least one id")

        var sockSet = WaitGroup()..add(1);
        bool done = false;
        MessageSocket? sock = null;

        Future<void> tryConnect(ad) async {
            var localsock = await connect(ad, localServiceId: localServiceId, mode: mode);
            if (localsock == null) {
                return;
            }
            if (!done) {
                sock = localsock;
                sockSet.done();
                done = true;
            } else {
                localsock.close();
            }
        }

        unawaited(Future(() async {
            await for (var ad in scanGen(serviceId: serviceId, nodeId: nodeId, time: timeout)) {
                unawaited(tryConnect(ad));
            }
        }));

        await sockSet.wait().timeout(timeout, onTimeout: () async {
            zlog(INFO, "connectToFirst timed out");
            done = true;
        }); // Note that this doesn't wait for the threads to finish.  I *think* that's ok.

        return sock;
    }

    /**
     * Attempts to connect to every address in the ad, but only uses the first success, and closes the rest.<br/>
     * <br/>
     * Returns a raw socket, or message socket, according to mode.<br/>
     * If no connection succeeded, returns None.<br/>
     * Please close the socket once you're done with it.<br/>
     * <br/>
     * (localServiceId is a nicety, to optionally tell the server what service you're associated with.)<br/>
     */
    Future<MessageSocket?> connect(Ad ad, {String localServiceId="", SocketMode mode=SocketMode.MESSAGES}) async {
        var lock = Mutex();
        var sockSet = WaitGroup()..add(1);
        MessageSocket? sock = null;

        Future<void> tryConnect(String addr, int port) async {
            var localsock = await connectOutbound(addr, port);
            if (localsock == null) {
                return;
            }
            await lock.acquire();
            var shouldClose = false;
            MessageSocket? messageSock;
            try {
                messageSock = MessageSocket(localsock);
                if (sock == null) {
                    await messageSock.sendString(localId); // It appears both sides can send a message at the same time.  Different comms may give different results, though.
                    await messageSock.sendString(localServiceId);
                    var clientNodeId = await messageSock.recvString();
                    var clientServiceId = await messageSock.recvString(); // Note that this might be empty
                    if ((clientNodeId == null || clientServiceId == null) || (clientNodeId.isEmpty && clientServiceId.isEmpty)) {
                        // Connection was canceled (or was invalid)
                        zlog(INFO, "connection canceled from $addr");
                        messageSock.close();
                    } else {
                        // The client might report different IDs than its service - is that problematic?
                        // ...Actually, clients don't need to have an advertised service in the first place.  So, no.
                        if (outgoneConnections[[clientNodeId, clientServiceId]].isEmpty) {
                            outgoneConnections[[clientNodeId, clientServiceId]] = [];
                        }
                        outgoneConnections.getExact([clientNodeId, clientServiceId])!.add(messageSock);
                        switch (mode) {
                            case SocketMode.RAW:
                                sock = localsock;
                                break;
                            case SocketMode.MESSAGES:
                                sock = messageSock;
                                break;
                        }
                        sockSet.done();
                    }
                } else {
                    zlog(INFO, "$addr $port Beaten to the punch; closing outgoing connection");
                    await messageSock.sendString("");
                    await messageSock.sendString("");
                    shouldClose = true;
                }
            } catch (e) {
                zerr(WARN, "An error occured in connection-forming code: $e");
                return;
            } finally {
                lock.release();
                if (shouldClose) {
                    Future.delayed(const Duration(milliseconds: 100)); // If I close immediately after sending, the messages don't get through before the close.  (At least in python, probably here, too.)  Sigh.
                    await messageSock?.close();
                }
            }
        }

        for (var addr in ad.addresses) {
            unawaited(tryConnect(addr, ad.port));
        }

        sockSet.wait(); // Note that this doesn't wait for the threads to finish.

        return sock;
    }

    /**
     * Send message to all existing connections (matching service/node filter).<br/>
     */
    Future<void> broadcast(Uint8List message, {String? serviceId, String? nodeId}) async { //NEXT broadcastString
        for (var connections in (incameConnections.getFilter([serviceId, nodeId]) + outgoneConnections.getFilter([serviceId, nodeId]))) {
            for (var connection in connections) {
                try {
                    connection.sendMsg(message);
                } catch (e) {
                    zerr(WARN, "A connection errored; removing: $connection");
                    connections.remove(connection);
                }
            }
        }
    }

    /**
     * Returns a map of `{(SERVICE, NODE) : [MESSAGE_SOCKET]}`.<br/>
     * If you need to distinguish between connections that came in and connections that went out, see
     * `incameConnections` and `outgoneConnections`.<br/>
     */
    Map<List<String>, List<MessageSocket>> getConnections() {
        Map<List<String>, List<MessageSocket>> cons = {};
        cons.addEntries(incameConnections.entries());
        for (var e in outgoneConnections.entries()) {
            if (!cons.containsKey(e.key)) {
                cons[e.key] = [];
            }
            cons[e.key]!.addAll(e.value);
        }
        return cons;
    }

    /**
     * Unregisters and closes zeroconf, and closes all connections.<br/>
     */
    Future<void> close() async {
        try:
            self.zeroconf.unregister_all_services()
        except:
            zerr(WARN, f"An error occurred in zeroconf.unregister_all_services()")
        try:
            self.zeroconf.close()
        except:
            zerr(WARN, f"An error occurred in zeroconf.close()")
        for connections in (self.incameConnections[(None,None)] + self.outgoneConnections[(None,None)]):
            for connection in list(connections):
                try:
                    connection.close()
                except:
                    zerr(WARN, f"An error occurred closing connection {connection}")
    }
}

//RAINY Replace all references to "zeroconf" with "mdns".


Future<MessageSocket?> autoconnect() async {

    var addresses = <InternetAddress>{};
    int port = -1;
    log("await ptr");
    await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(_SERVICE))) {
        log("in ptr lookup");

        print("await srv1");
        await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))) {
            print("in srv1");
            print('instance found at ${srv.target}:${srv.port}.');
            port = srv.port;
        }

        log("await addr lookup");
        await for (final IPAddressResourceRecord addr in client.lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(ptr.domainName))) {
            log("in addr lookup");
            log("$addr");
            addresses.add(addr.address);
        }
    }
    log("$addresses $port");

    if (port == -1) {
        return null;
    }

    var wg = WaitGroup();
    wg.add(1);

    MessageSocket? mSock = null;

    for (var addr in addresses) {
        unawaited(Future(() async {
            Socket? localSocket = null;
            try {
                localSocket = await Socket.connect(addr.address, port);

                if (mSock != null) {
                    localSocket.close();
                    return;
                }

                log('connected via ${addr.address} $port');
                mSock = MessageSocket(localSocket);

                wg.done();
            } catch (e) {
                print("error connecting: ${addr.address} $port $e");
                if (localSocket != null) {
                    localSocket.close();
                }
            }
        }));
    }

    await wg.wait().timeout(Duration(seconds: 15), onTimeout: () {}); //TODO Time?

    log("stop client");
    client.stop();
    log("done");

    final lSock = mSock;
    if (lSock != null) {
        await lSock.sendString(localId); // nodeId
        await lSock.sendString("");      // serviceId
        log("remote    nodeId ${String.fromCharCodes((await lSock.recvMsg())!)}"); // nodeId
        log("remote serviceId ${String.fromCharCodes((await lSock.recvMsg())!)}"); // serviceId
    }

    return lSock;
}