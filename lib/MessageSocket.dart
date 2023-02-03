// Derived from http://stupidpythonideas.blogspot.com/2013/05/sockets-are-byte-streams-not-message.html
// and then translated from https://github.com/Erhannis/zeroconnect/blob/master/zeroconnect/message_socket.py
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:sync/sync.dart';

import 'csp/Channel.dart';
import 'misc.dart';
import 'zeroconnect.dart';

Uint8List int64BigEndianBytes(int value) => Uint8List(8)..buffer.asByteData().setInt64(0, value, Endian.big);
int bigEndianBytesInt64(Uint8List bytes) => bytes.buffer.asByteData().getInt64(0, Endian.big);

/**
 * Packages data from a stream into messages, by wrapping messages with a prefixed length (and then
 * the length inverted (xor 0xFFF...), for checksum).<br/>
 * Note: I've added locks on sending and receiving, so message integrity should be safe, but you should
 * still be aware of the potential confusion/mixups inherent to having multiple threads communicate over
 * a single channel.<br/>
 */
class MessageSocket {
    Socket sock;
    Mutex _sendLock;
    Mutex _recvLock;

    late final ChannelIn<Uint8List?> _rxIn;
    late final ChannelOut<int> _recvCountOut;

    /**
     * Wraps `sock`, immediately starts reading messages into buffer.<br/>
     * Automatically pings at interval `autoping` (not pinging if autoping is null), flagging connection as
     * broken if the ping fails (which takes like 30 seconds). See [ping].<br/>
     */
    MessageSocket(this.sock, {Duration? autoping = const Duration(seconds: 5)}): this._sendLock = Mutex(), this._recvLock = Mutex() {
        var _rxChannel = Channel<Uint8List?>();
        this._rxIn = _rxChannel.getIn();
        var rxOut = _rxChannel.getOut();

        var _recvCountChannel = Channel<int>();
        var _recvCountIn = _recvCountChannel.getIn();
        this._recvCountOut = _recvCountChannel.getOut();

        //NEXT autoping

        unawaited(Future(() async {
            var sw = Stopwatch();
            var sw_big1 = Stopwatch();
            var sw_big2 = Stopwatch();
            //CHECK I don't think this handles socket closure
            List<List<int>> pending = [];
            int accumulated = 0;
            int? requested = null;

            // I'm tempted to put a lock around the pending and accumulated code, but I don't THINK it's necessary.

            sw.start();
            sw_big1.start();
            sw_big2.start();
            bool broken = false;

            if (autoping != null) {
                unawaited(Future(() async {
                    try {
                        while (!broken) {
                            await sleep(autoping.inMilliseconds);
                            await ping();
                        }
                    } catch (e) {
                        zlog(INFO, "MS autoping failed, probably disconnected: $e");
                        broken = true; //CHECK Should call .close()?
                    }
                }));
            }

            unawaited(Future(() async {
                while (true) {
                    sw_big2.reset();
                    if (requested == null) {
                        requested = await _recvCountIn.read();
                        if (broken) { //DITTO //CHECK Should call .close()?
                            await rxOut.write(null);
                            requested = null;
                            continue; //THINK Maybe just return?  That'd leave the request channel blocked.... //LEAK Leaves this future here, otherwise
                        }
                        zlog(DEBUG, "MS2 ${sw.lap()} rx request");
                    }
                    if (requested == -1) {
                        pending.clear();
                        accumulated = 0;
                        requested = null;
                    } else if (requested == 0) {
                        await rxOut.write(Uint8List(0));
                        requested = null;
                    } else if (accumulated >= requested!) {
                        var bb = BytesBuilder(copy: false);
                        while (requested! > 0 && pending[0].length <= requested!) {
                            var temp = pending.removeAt(0);
                            bb.add(temp);
                            requested = requested! - temp.length;
                            accumulated -= temp.length;
                        }
                        if (requested! > 0) {
                            bb.add(pending[0].sublist(0,requested!));
                            pending[0] = pending[0].sublist(requested!, pending[0].length);
                            accumulated -= requested!;
                        }
                        requested = null;
                        zlog(DEBUG, "MS2 ${sw.lap()} collected response");
                        var response = Uint8List.fromList(bb.takeBytes());
                        zlog(DEBUG, "MS2 ${sw.lap()} built response");
                        await rxOut.write(response); //MISC This seems like a lot of conversions
                        zlog(DEBUG, "MS2 ${sw.lap()} tx data");
                    } else {
                        await sleep(10);
                        if (broken) { //DITTO //CHECK Should call .close()?
                            await rxOut.write(null);
                            requested = null;
                            continue; //DITTO //THINK Maybe just return?
                        }
                    }
                    //zlog(DEBUG, "MS2 ${sw_big2.lap()} send total");
                }
            }));

            try {
                await for (var data in sock) { //THINK I'm pretty sure data will still accumulate in the Socket; I wish I could backpressure it
                    sw_big1.reset();
                    zlog(DEBUG, "MS1 ${sw.lap()} rx data");
                    pending.add(data);
                    accumulated += data.length;
                    zlog(DEBUG, "MS1 ${sw.lap()} added data - acc $accumulated");
                    zlog(DEBUG, "MS1 ${sw_big1.lap()} read total");
                }
                zlog(INFO, "MS1 done; connection presumably closed");
                broken = true;
            } catch (e) {
                zlog(INFO, "MS1 error; connection presumably closed: $e");
                broken = true;
                await close();
            }
        }));
    }

    /**
     * Send a message.<br/>
     * `data` should be a list of bytes, or a string (which will then be encoded with utf-8.)<br/>
     * Throws exception on socket failure.<br/>
     * //DUMMY Doesn't throw.  Just keeps going.  Should probably fix that.<br/>
     */
    Future<void> sendBytes(Uint8List data) async {
        await _sendLock.acquire();
        try {
            List<int> bb = [];
            bb.addAll(int64BigEndianBytes(data.length));
            // Send inverse, for validation
            Uint8List inv = int64BigEndianBytes(data.length);
            for (int i = 0; i < inv.length; i++) {
                inv[i] ^= 0xFF;
            }
            bb.addAll(inv);
            bb.addAll(data);
            sock.add(bb);
            await sock.flush();
        } catch (e) {
            await close();
            rethrow;
        } finally {
            _sendLock.release();
        }
    }

    /**
     * See `sendBytes`
     */
    Future<void> sendString(String s) async {
        await sendBytes(Uint8List.fromList(s.codeUnits)); //TODO UTF-16???
    }

    /**
     * This ping gets no pong.  It relies on the behavior I've so far observed, that if you try to send
     * data on a broken connection, it times out after 30 seconds or so, flagging the connection as broken
     * (and aborting any read attempts in progress, btw).  The data it sends is an 8 byte big endian -1,
     * which would otherwise indicate a subsequent message -1 bytes in length (but is discarded as a ping).<br/>
     */
    Future<void> ping() async {
        await _sendLock.acquire();
        try {
            sock.add(int64BigEndianBytes(-1)); //THINK Should pings get checksummed, too?
            await sock.flush();
        } catch (e) {
            await close();
            rethrow;
        } finally {
            _sendLock.release();
        }
    }

    void _rotateBytes(Uint8List a, Uint8List? b, int c) {
        for (int i = 0; i < a.length-1; i++) {
            a[i] = a[i+1];
        }
        if (b != null) {
            a[a.length-1] = b[0];
            for (int i = 0; i < b.length-1; i++) {
                b[i] = b[i+1];
            }
            b[b.length-1] = c;
        } else {
            a[a.length-1] = c;
        }
    }

    /**
     * Result of [] simply means an empty message; result of null implies some kind of failure; likely a disconnect.
     * //NEXT Update docs
     */ //DUMMY Update python code
    Future<Uint8List?> recvBytes({int maxLen = 1000000, bool tryHard = true}) async { //CHECK How does this handle disconnection?
        zlog(DEBUG, "MS recvBytes -->lock");
        await _recvLock.acquire();
        zlog(DEBUG, "MS recvBytes ---lock");
        try {
            int len = -1;
            Uint8List? lenBuf = null;
            Uint8List? invBuf = null;
            readloop: while (len < 0) {
                if (lenBuf == null) {
                    await _recvCountOut.write(8);
                    lenBuf = await _rxIn.read();
                    if (lenBuf == null) {
                        return null;
                    }
                }
                zlog(DEBUG, "MS rx proc 1 $lenBuf");
                int tempLen = bigEndianBytesInt64(lenBuf);
                // if ping advance and retry
                if (tempLen < 0) { // Any length < 0 is invalid, anyway; though maybe isn't a ping.... //THINK Should pings be checksummed, too?
                    // ...Wait, what's the point of these pings, again?  Oh, right, for some transports it can trigger exposure of a broken connection.
                    if (!tryHard) {
                        zlog(INFO, "MS rx ping");
                        lenBuf = null;
                        invBuf = null;
                    } else { // If messages out of sync, could erroneously identify as ping and discard important bytes
                        zlog(INFO, "MS rx ping?"); //THINK OTOH, if messages IN sync, could correctly identify as ping, then check a bunch of subsequent sequences.  ...I don't think the invalid ones would validate, though, since the ping would mean they'd start with 0xFF.
                        await _recvCountOut.write(1);
                        var nextByte = await _rxIn.read();
                        if (nextByte == null) {
                            return null;
                        }
                        _rotateBytes(lenBuf, invBuf, nextByte[0]);
                    }
                    continue readloop;
                }

                if (invBuf == null) {
                    await _recvCountOut.write(8);
                    invBuf = await _rxIn.read();
                    if (invBuf == null) {
                        return null;
                    }
                }
                zlog(DEBUG, "MS rx proc 2 $lenBuf $invBuf");
                // if bad checksum advance and retry
                for (int i = 0; i < 8; i++) {
                    if (lenBuf![i] ^ invBuf![i] != 0xFF) {
                        zlog(WARN, "MS checksum failed! $lenBuf $invBuf");
                        if (!tryHard) {
                            await _recvCountOut.write(-1); // Clears input buffer
                            lenBuf = null;
                            invBuf = null;
                        } else {
                            await _recvCountOut.write(1);
                            var nextByte = await _rxIn.read();
                            if (nextByte == null) {
                                return null;
                            }
                            _rotateBytes(lenBuf, invBuf, nextByte[0]);
                        }
                        continue readloop;
                    }
                }

                // if too big advance and retry
                if (tempLen > maxLen) {
                    zlog(WARN, "Message bigger than limit: $tempLen");
                    if (!tryHard) {
                        await _recvCountOut.write(-1); // Clears input buffer
                        lenBuf = null;
                        invBuf = null;
                    } else {
                        await _recvCountOut.write(1);
                        var nextByte = await _rxIn.read();
                        if (nextByte == null) {
                            return null;
                        }
                        _rotateBytes(lenBuf!, invBuf, nextByte[0]);
                    }
                    continue readloop;
                }

                len = tempLen;
            }

            if (len == 0) {
                return Uint8List(0);
            } else {
                await _recvCountOut.write(len);
                return await _rxIn.read();
            }
        } finally {
            _recvLock.release();
            zlog(DEBUG, "MS recvBytes <--lock");
        }
    }

    Future<String?> recvString({bool? allowMalformed = true, int maxLen = 1000000, bool tryHard = true}) async { //THINK Should allowMalformed?
        var msg = await recvBytes(maxLen: maxLen, tryHard: tryHard);
        if (msg == null) {
            return null;
        }
        return utf8.decode(msg, allowMalformed: allowMalformed);
    }

    Future<void> close() async {
        try {
            await sock.close();
        } catch (e) {
            // Nothing
        }
    }
}