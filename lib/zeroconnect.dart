library zeroconnect;

import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:sync/waitgroup.dart';
import 'package:uuid/uuid.dart';

import 'MessageSocket.dart';

// Translated from https://github.com/Erhannis/zeroconnect/blob/master/zeroconnect/zeroconnect.py


// https://stackoverflow.com/a/166591/513038
Future<List<Address>> getAddresses() async { //THINK IPv6?
    await NetworkInterface.list();
    //await NetworkInfo().getWifiIP();
    var addresses = {};
    for ifaceName in interfaces() {
        for i in ifaddresses(ifaceName).setdefault(AF_INET, []):
        if "addr" in i:
        addresses.add(socket.inet_aton(i["addr"]))
    }
    return addresses
}

String? _serviceToKey(String? serviceId) {
    if (serviceId == null) {
        return null;
    } else {
        return "_$serviceId._http._tcp.local"; //CHECK Check
    }
}

String? _nodeToKey(String? nodeId) {
    if (nodeId == null) {
        return null;
    } else {
        return "$nodeId._http._tcp.local"; //CHECK //DITTO
    }
}

String _typeToService(String type_) { // This is kindof horrible, and brittle, and MAY be subject to accidental bad data
    return type_.substring("_".length, type_.length-("._http._tcp.local.").length); //CHECK //DITTO
}

String _nameToNode(String name) {
    return name.substring("".length, type_.length-("._http._tcp.local.").length); //CHECK //DITTO
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
    static Ad fromInfo(info) {
        final type_ = info.type;
        final name = info.name;
        final addresses = tuple([socket.inet_ntoa(addr) for addr in info.addresses]);
        final port = info.port;
        final serviceId = _typeToService(type_);
        final nodeId = _nameToNode(name);
        return Ad(type_, name, addresses, port, serviceId, nodeId);
    }

    //DUMMY Set types
    final type;
    final name;
    final addresses;
    final port;
    final String serviceId;
    final String nodeId;

    Ad(this.type, this.name, this.addresses, this.port, this.serviceId, this.nodeId);

    Pair<SomethingType, String> getKey(self) {
        return (type, name);
    }

    @override
    String toString() {
        return "Ad('$type','$name',$addresses,$port,'$serviceId','$nodeId')";
    }

    bool operator ==(o) {
        return o is Ad
            && this.type == o.type
            && this.name == o.name
            && (const ListEquality().equals)(this.addresses, o.addresses)
            && this.port == o.port
            && this.serviceId == o.serviceId
            && this.nodeId == o.nodeId;
    }

    int get hashCode => Object.hash(type, name, (const ListEquality().hash)(addresses), port, serviceId, nodeId);
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
        this.localAds = <Ad>{};
        this.remoteAds = FilterMap(2); // (type_, name) = set{Ad} //TODO Should we even PERMIT multiple ads per keypair?
        this.incameConnections = FilterMap(2); // (service, node) = list[messageSocket]
        this.outgoneConnections = FilterMap(2); // (service, node) = list[messageSocket]
    }

    //DUMMY These are all wrong
    void __update_service(self, zc: Zeroconf, type_: str, name: str) {
        info = zc.get_service_info(type_, name)
        zlog(INFO, f"Service {name} updated, service info: {info}")
        if info != None:
            ad = Ad.fromInfo(info)
            if ad not in self.localAds:
                self.remoteAds[ad.getKey()] = set()
            self.remoteAds[ad.getKey()].add(ad) # Not even sure this is correct.  Should I remove the old record?  CAN I?
        //TODO Anything else?
    }

    void __remove_service(self, zc: Zeroconf, type_: str, name: str) {
        zlog(INFO, f"Service {name} removed")
    }

    void __add_service(self, zc: Zeroconf, type_: str, name: str) {
        info = zc.get_service_info(type_, name)
        zlog(INFO, f"Service {name} added, service info: {info}")
        if info != None:
            ad = Ad.fromInfo(info)
            if ad not in self.localAds:
                self.remoteAds[ad.getKey()] = set()
            self.remoteAds[ad.getKey()].add(ad)
    }

    /**
     * Advertise a service, and send new connections to `callback`.<br/>
     * `callback` is called on its own (daemon) thread.  If you want to loop forever, go for it.<br/>
     * Be warned that you should only have one adveristement running (locally?) with a given name - zeroconf
     * throws an exception otherwise.  However, if you create another ZeroConnect with a different name, it works fine.<br/>
     */
    void advertise(callback, {required String serviceId, int port=0, String host="0.0.0.0", SocketMode mode=SocketMode.MESSAGES}) { //THINK Have an ugly default serviceId?
        def socketCallback(sock, addr):
            messageSock = MessageSocket(sock)
            messageSock.sendMsg(self.localId) # It appears both sides can send a message at the same time.  Different comms may give different results, though.
            messageSock.sendMsg(serviceId)
            clientNodeId = messageSock.recvMsg().decode("utf-8")
            clientServiceId = messageSock.recvMsg().decode("utf-8") # Note that this might be empty
            if not clientNodeId and not clientServiceId:
                # Connection was canceled (or was invalid)
                zlog(INFO, f"connection canceled from {addr}")
                messageSock.close()
                return
            # The client might report different IDs than its service - is that problematic?
            # ...Actually, clients don't need to have an advertised service in the first place.  So, no.
            if (clientNodeId, clientServiceId) not in self.incameConnections:
                self.incameConnections[(clientNodeId, clientServiceId)] = []
            self.incameConnections[(clientNodeId, clientServiceId)].append(messageSock)
            if mode == SocketMode.Raw:
                callback(sock, clientNodeId, clientServiceId)
            elif mode == SocketMode.Messages:
                callback(messageSock, clientNodeId, clientServiceId)

        port = listen(socketCallback, port, host) #TODO Multiple interfaces?

        service_string = serviceToKey(serviceId)
        node_string = nodeToKey(self.localId)
        info = ServiceInfo(
            service_string,
            node_string,
            addresses=getAddresses(),
            port=port
        )
        self.localAds.add(Ad.fromInfo(info))
        self.zeroconf.register_service(info)
    }

    /**
     * Scans for `time` seconds, and returns matching services.  `[Ad]`<br/>
     * If `time` is zero, begin scanning (and DON'T STOP), and return previously discovered services.<br/>
     * If `time` is negative, DON'T scan, and instead just return previously discovered services.<br/>
     */
    Future<Something> scan({String? serviceId, String? nodeId, int time=30}) async { //THINK time in ms?
        browser = None
        service_key = serviceToKey(serviceId)
        node_key = nodeToKey(nodeId)
        if time >= 0:
            if serviceId == None:
                browser = ServiceBrowser(self.zeroconf, f"_http._tcp.local.", self.zcListener)
            else:
                browser = ServiceBrowser(self.zeroconf, service_key, self.zcListener)
            sleep(time)
            if time > 0:
                browser.cancel()
        ads = []
        for aSet in self.remoteAds.getFilter((service_key, node_key)):
            ads += list(aSet)
        return ads;
    }
    /**
     * Generator version of `scan`.<br/>
     */
    Future<Something> scanGen({String? serviceId, String? nodeId, int time=30}) async {
        browser = None
        service_key = serviceToKey(serviceId)
        node_key = nodeToKey(nodeId)

        totalAds = set()

        for aSet in self.remoteAds.getFilter((service_key, node_key)):
            for ad in aSet:
                totalAds.add(ad)
                yield ad

        if time >= 0:
            lock = threading.Lock()
            newAds = []

            class LocalListener(ServiceListener):
                def __init__(self, delegate):
                    self.delegate = delegate

                def update_service(self, zc: Zeroconf, type_: str, name: str) -> None:
                    info = zc.get_service_info(type_, name)
                    zlog(VERBOSE, f"0Service {name} updated, service info: {info}")
                    if info != None:
                        ad = Ad.fromInfo(info)
                        lock.acquire()
                        if ad not in totalAds:
                            totalAds.add(ad)
                            newAds.append(ad)
                        lock.release()
                    self.delegate.update_service(zc, type_, name)

                def remove_service(self, zc: Zeroconf, type_: str, name: str) -> None:
                    zlog(VERBOSE, f"0Service {name} removed")
                    self.delegate.remove_service(zc, type_, name)

                def add_service(self, zc: Zeroconf, type_: str, name: str) -> None:
                    info = zc.get_service_info(type_, name)
                    zlog(VERBOSE, f"0Service {name} added, service info: {info}")
                    if info != None:
                        ad = Ad.fromInfo(info)
                        lock.acquire()
                        if ad not in totalAds:
                            totalAds.add(ad)
                            newAds.append(ad)
                        lock.release()
                    self.delegate.add_service(zc, type_, name)

            localListener = LocalListener(self.zcListener)

            if serviceId == None:
                browser = ServiceBrowser(self.zeroconf, f"_http._tcp.local.", localListener)
            else:
                browser = ServiceBrowser(self.zeroconf, service_key, localListener)

            endTime = currentSeconds() + time
            while currentSeconds() < endTime:
                sleep(0.5)
                lock.acquire()
                adCopy = list(newAds)
                newAds.clear()
                lock.release()
                for ad in adCopy:
                    yield ad

            if time > 0:
                browser.cancel()
    }

    /**
     * Scan for anything that matches the IDs, try to connect to them all, and return the first
     * one that succeeds.<br/>
     * Note that this may leave extraneous dead connections in `outgoneConnections`!<br/>
     * Returns `(sock, Ad)`, or None if the timeout expires first.<br/>
     * If timeout == -1, don't scan, only use cached services.<br/>
     */
    Future<Something> connectToFirst({String? serviceId, String? nodeId, String localServiceId="", SocketMode mode=SocketMode.MESSAGES, int timeout=30}) async { //THINK Timeout in ms?
        if serviceId == None and nodeId == None:
            raise Exception("Must have at least one id")

        lock = threading.Lock()
        sockSet = threading.Event()
        sock = None

        def tryConnect(ad):
            nonlocal sock
            localsock = self.connect(ad, localServiceId, mode)
            if localsock == None:
                return
            lock.acquire()
            try:
                if sock == None:
                    sock = localsock
                    sockSet.set()
                else:
                    localsock.close()
            finally:
                lock.release()

        def startScanning():
            for ad in self.scanGen(serviceId, nodeId, timeout):
                threading.Thread(target=tryConnect, args=(ad,), daemon=True).start()

        threading.Thread(target=startScanning, args=(), daemon=True).start() # Otherwise it blocks until timeout regardless of success

        sockSet.wait(timeout) # Note that this doesn't wait for the threads to finish.  I *think* that's ok.

        return sock
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
    Future<Something> connect(Ad ad, {String localServiceId="", SocketMode mode=SocketMode.MESSAGES}) async {
        lock = threading.Lock()
        sockSet = threading.Event()
        sock = None

        def tryConnect(addr, port):
            nonlocal sock
            localsock = connectOutbound(addr, port)
            if localsock == None:
                return
            lock.acquire()
            shouldClose = False
            try:
                messageSock = MessageSocket(localsock)
                if sock == None:
                    messageSock.sendMsg(self.localId) # It appears both sides can send a message at the same time.  Different comms may give different results, though.
                    messageSock.sendMsg(localServiceId)
                    clientNodeId = messageSock.recvMsg().decode("utf-8")
                    clientServiceId = messageSock.recvMsg().decode("utf-8") # Note that this might be empty
                    if not clientNodeId and not clientServiceId:
                        # Connection was canceled (or was invalid)
                        zlog(INFO, f"connection canceled from {addr}")
                        messageSock.close()
                    else:
                        # The client might report different IDs than its service - is that problematic?
                        # ...Actually, clients don't need to have an advertised service in the first place.  So, no.
                        if (clientNodeId, clientServiceId) not in self.outgoneConnections:
                            self.outgoneConnections[(clientNodeId, clientServiceId)] = []
                        self.outgoneConnections[(clientNodeId, clientServiceId)].append(messageSock)
                        if mode == SocketMode.Raw:
                            sock = localsock
                        elif mode == SocketMode.Messages:
                            sock = messageSock
                        sockSet.set()
                else:
                    zlog(INFO, f"{addr} {port} Beaten to the punch; closing outgoing connection")
                    messageSock.sendMsg("")
                    messageSock.sendMsg("")
                    shouldClose = True
            except Exception:
                zerr(WARN, f"An error occured in connection-forming code")
                if WARN <= getLogLevel():
                    print("raising")
                    raise
                else:
                    return
            finally:
                lock.release()
                if shouldClose:
                    sleep(0.1) # If I close immediately after sending, the messages don't get through before the close.  Sigh.
                    messageSock.close()

        for addr in ad.addresses:
            threading.Thread(target=tryConnect, args=(addr, ad.port), daemon=True).start()

        sockSet.wait() # Note that this doesn't wait for the threads to finish.  I *think* that's ok.

        return sock
    }

    /**
     * Send message to all existing connections (matching service/node filter).<br/>
     */
    Future<Something> broadcast(Something message, {String? serviceId, String? nodeId}) async {
        for connections in (self.incameConnections[(serviceId, nodeId)] + self.outgoneConnections[(serviceId, nodeId)]):
            for connection in list(connections):
                try:
                    connection.sendMsg(message)
                except:
                    zerr(WARN, f"A connection errored; removing: {connection}")
                    connections.remove(connection)
    }

    /**
     * Returns a map of `{(SERVICE, NODE) : [MESSAGE_SOCKET]}`.<br/>
     * If you need to distinguish between connections that came in and connections that went out, see
     * `incameConnections` and `outgoneConnections`.<br/>
     */
    Map<Something> getConnections() {
        cons = {}
        cons.update(self.incameConnections)
        for key in self.outgoneConnections:
            if key not in cons:
                cons[key] = []
            cons[key] += self.outgoneConnections.getExact(key)
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