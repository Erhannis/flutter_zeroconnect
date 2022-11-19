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

Uint8List uint64BigEndianBytes(int value) => Uint8List(8)..buffer.asByteData().setUint64(0, value, Endian.big);
int bigEndianBytesUint64(Uint8List bytes) => bytes.buffer.asByteData().getUint64(0, Endian.big);

/**
    Packages data from a stream into messages, by wrapping messages with a prefixed length.<br/>
    Note: I've added locks on sending and receiving, so message integrity should be safe, but you should
    still be aware of the potential confusion/mixups inherent to having multiple threads communicate over
    a single channel.
 */
class MessageSocket {
    Socket _sock;
    Mutex _sendLock;
    Mutex _recvLock;

    late final ChannelIn<Uint8List?> _rxIn;
    late final ChannelOut<int> _recvCountOut;

    MessageSocket(this._sock): this._sendLock = Mutex(), this._recvLock = Mutex() {
        var _rxChannel = Channel<Uint8List?>();
        this._rxIn = _rxChannel.getIn();
        var rxOut = _rxChannel.getOut();

        var _recvCountChannel = Channel<int>();
        var _recvCountIn = _recvCountChannel.getIn();
        this._recvCountOut = _recvCountChannel.getOut();

        unawaited(Future(() async {
            var sw = Stopwatch();
            var sw_big1 = Stopwatch();
            var sw_big2 = Stopwatch();
            //DO I don't think this handles socket closure
            List<List<int>> pending = [];
            int accumulated = 0;
            int? requested = null;

            // I'm tempted to put a lock around the pending and accumulated code, but I don't THINK it's necessary.

            sw.start();
            sw_big1.start();
            sw_big2.start();
            bool broken = false;

            unawaited(Future(() async {
                while (true) {
                    sw_big2.reset();
                    if (requested == null) {
                        requested = await _recvCountIn.read();
                        if (broken) {
                            await rxOut.write(null);
                            requested = null;
                            continue; //TODO Maybe just return?
                        }
                        //log("MS2 ${sw.lap()} rx request");
                    }
                    if (requested == 0) {
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
                        //log("MS2 ${sw.lap()} collected response");
                        var response = Uint8List.fromList(bb.takeBytes());
                        //log("MS2 ${sw.lap()} built response");
                        await rxOut.write(response); //TODO This seems like a lot of conversions
                        //log("MS2 ${sw.lap()} tx data");
                    } else {
                        await sleep(10);
                        if (broken) {
                            await rxOut.write(null);
                            requested = null;
                            continue; //TODO Maybe just return?
                        }
                    }
                    //log("MS2 ${sw_big2.lap()} send total");
                }
            }));

            try {
                await for (var data in _sock) { //TODO I'm pretty sure data will still accumulate in the Socket; I wish I could backpressure it
                    sw_big1.reset();
                    //log("MS1 ${sw.lap()} rx data");
                    pending.add(data);
                    accumulated += data.length;
                    //log("MS1 ${sw.lap()} added data - acc $accumulated");
                    //log("MS1 ${sw_big1.lap()} read total");
                }
            } catch (e) {
                log("Connection presumably closed: $e");
                broken = true;
            }
        }));
    }

    /**
     * Send a message.
     * `data` should be a list of bytes, or a string (which will then be encoded with utf-8.)
     * Throws exception on socket failure.
     */
    Future<void> sendMsg(Uint8List data) async {
        await _sendLock.acquire();
        try {
            _sock.add(uint64BigEndianBytes(data.length));
            // Send inverse, for validation? ...I THINK we can trust TCP to guarantee ordering and whatnot
            _sock.add(data);
        } finally {
            _sendLock.release();
        }
    }

    /**
     * See `sendMsg`
     */
    Future<void> sendString(String s) async {
        await sendMsg(Uint8List.fromList(s.codeUnits)); //TODO UTF-16???
    }

    /**
     * Result of [] simply means an empty message; result of null implies some kind of failure; likely a disconnect.
     */
    Future<Uint8List?> recvMsg() async {
        await _recvLock.acquire();
        try {
            await _recvCountOut.write(8);
            var lengthbuf = await _rxIn.read();
            if (lengthbuf == null) {
                return null;
            }
            var length = bigEndianBytesUint64(lengthbuf);
            if (length == 0) {
                return Uint8List(0);
            } else {
                await _recvCountOut.write(length);
                return await _rxIn.read();
            }
        } finally {
            _recvLock.release();
        }
    }

    Future<String?> recvString({bool? allowMalformed = true}) async { //THINK Should allowMalformed?
        return utf8.decode((await recvMsg())!, allowMalformed: allowMalformed);
    }

    Future<void> close() async {
        try {
            await _sock.close();
        } catch (e) {
            // Nothing
        }
    }
}