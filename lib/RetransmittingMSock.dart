import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:zeroconnect/MessageSocket.dart';

Uint8List int32BigEndianBytes(int value) => Uint8List(4)..buffer.asByteData().setInt32(0, value, Endian.big);
int bigEndianBytesInt32(Uint8List bytes) => bytes.buffer.asByteData().getInt32(0, Endian.big);
Uint8List float64BigEndianBytes(double value) => Uint8List(8)..buffer.asByteData().setFloat64(0, value, Endian.big);
double bigEndianBytesFloat64(Uint8List bytes) => bytes.buffer.asByteData().getFloat64(0, Endian.big);

class FailureCounter {
    int lastSuccess = 0;
    int consecutiveFailures = 0;

    bool fail() {
        consecutiveFailures++;
        if (lastSuccess == 0) {
            lastSuccess = currentMillis();
        } else if (currentMillis() - lastSuccess >= 30000) { //RAINY Optionize
            if (consecutiveFailures >= 5) { //RAINY Optionize
                return true;
            }
        }
        return false;
    }

    void succeed() {
        lastSuccess = currentMillis();
        consecutiveFailures = 0;
    }
}

//CHECK Y'know...usually retransmission is applied to PACKETS, not messages.  Hmm. - That might also solve the "reTX requests are only processed when recvBytes is called" problem.
/**
Subclass of MessageSocket that tracks what messages have been received, and retransmits ones that haven't been.  Not SUPER robust, and not super efficient, but it's much better than nothing.
*/
class RetransmittingMSock extends MessageSocket {
    RetransmittingMSock(Socket sock) : super(sock);

    /*
    Ok, so.  We need to keep track of how many messages have been sent, and when we get a message, check their vector timestamp, and if they've missed a message,
    resend the one they've missed.  (The one after their reported timestamp.)
    If WE missed a message...hmm.  There's not really a way to request a message yet.
    I guess we encode that into the timestamp layer.
    T1:1[message]
    R1
     */

    Map<int, Uint8List> _unconfirmedTransmissions = {};

    bool _hasSentStartup = false;
    int _rxCount = 0;
    int _txCount = 0;

    int _rxOld = 0;
    int _rxGood = 0;
    int _rxFuture = 0;
    int _rxBehind = 0;
    int _rxRequest = 0;
    int _rxReset = 0;
    int _rxBad = 0;

    //NEXT Make sure I didn't miss any `await`s in translation

    Future<bool> sendBytes(Uint8List data, {bool important = true}) async {
        if (mSendLock.locked && !mSendLock.inLock && !important) {
            return false;
        }
        return await mSendLock.synchronized(() async {
            await _maybeSendStartup();
            _txCount++; //MISC Handle wraparound? //NEXT Check all places where _txCount is updated, and read
            _unconfirmedTransmissions[_txCount] = data;
            log("RMS initial tx: $_txCount");
            return await _sendBytes(_txCount, data, important: true); // Side effects have occurred, so this message gets sent
        });
    }

    Future<bool> _sendBytes(int txId, Uint8List data, {bool important = true}) async {
        if (mSendLock.locked && !mSendLock.inLock && !important) {
            return false;
        }
        return await mSendLock.synchronized(() async {
            await _maybeSendStartup();
            List<int> bb = [];
            bb.add(0x54); // 'T'
            bb.addAll(int32BigEndianBytes(txId));
            //THINK Waaait a minute - should we discard messages rx that evidence remotely missed local messages?  ...Proooobably not.  That'd involve like, canceling messages or something, and ech.
            //NEXT Check all places _rxCount is updated, and read
            bb.addAll(int32BigEndianBytes(_rxCount)); // _rxCount might change mid-function...but we want the most up-to-date value here, regardless, so.
            bb.addAll(data);
            log("RMS txId: $txId");
            return await super.sendBytes(Uint8List.fromList(bb), important: important); //THINK No side effects yet, so...should important be set true or no?
        });
    }

    Future<void> _requestReTX(int rxId) async {
        await mSendLock.synchronized(() async {
            await _maybeSendStartup();
            List<int> bb = [];
            bb.add(0x52); // 'R'
            bb.addAll(int32BigEndianBytes(rxId));
            //THINK Waaait a minute - are we discarding messages rx that evidence remotely missed local messages?  ...Proooobably not.  That'd involve like, canceling messages or something, and ech.
            log("RMS request reTX: $rxId");
            await super.sendBytes(Uint8List.fromList(bb), important: true);
        });
    }

    Future<void> _maybeSendStartup() async {
        if (!_hasSentStartup) {
            await _sendStartup();
            _hasSentStartup = true; //THINK Move that into _sendStartup?
        }
    }

    Future<void> _sendStartup() async {
        await mSendLock.synchronized(() async {
            log("RMS send startup"); //CHECK Wait, what if the startup is missed (duh)
            await super.sendBytes(Uint8List.fromList([0x58]), important: true); // 'X'
        });
    }

    Future<void> _triggerReset() async {
        log("RMS trigger reset");
        await mSendLock.synchronized(() async {
            _txCount = 0;
            _rxCount = 0;
            _unconfirmedTransmissions.clear();
            await _sendStartup();
            _resetTimeout.succeed();
        });
    }

    FailureCounter _resetTimeout = FailureCounter();

    Future<Uint8List?> recvBytes({int maxLen = 1000000, bool tryHard = true}) async {
        return await mRecvLock.synchronized(() async { //NEXT //CHECK I switched from synchronized method so tx/rx don't block each other, but I had some thought whether the numbers might matter...like, if a msg comes in while waiting to tx, the tx is now invalid, or something
            //DUMMY A ReTX request won't be processed until recvBytes gets called....
            //NEXT Waitaminute - if a node reboots, its counts are reset, and that could lock things up
            retry:
            while (true) {
                try {
                    var data = await super.recvBytes(maxLen: maxLen, tryHard: tryHard);
                    if (data != null) {
                        switch (data[0]) {
                            case 0x54:
                                { // 'T'
                                    int rxId = bigEndianBytesInt32(data.sublist(1, 1 + 4));
                                    int txId = bigEndianBytesInt32(data.sublist(1 + 4, 1 + 4 + 4));
                                    log("RMS rxId: $rxId/$_rxCount (txId: $txId/$_txCount)");
                                    if (rxId < _rxCount + 1) { //CHECK Maybe not +1?
                                        // Old message, ignore
                                        _rxOld++;
                                        continue retry;
                                    } else if (rxId > _rxCount + 1) {
                                        // We're missing a message
                                        // Requesting reTX also triggers reTX of subsequent (already sent) messages
                                        await _requestReTX(_rxCount + 1);
                                        //NEXT //CHECK Also reTX missing local messages?
                                        _rxFuture++;
                                        continue retry;
                                    }
                                    if (txId != _txCount) { //NEXT what if _txCount changes mid function
                                        // They're missing a message
                                        // Retransmit
                                        //RAINY Combine with explicit reTX?
                                        //NEXT At some point, retransmissions dominate and the network is frozen.  Should there be a clear-all protocol?
                                        for (int i = txId + 1; i <= _txCount; i++) { //THINK This seems network-cloggy - I think, even without explicit looping, the system would get up-to-date eventually...but that would probably involve a lot of invalid messages, so.
                                            var bytes = _unconfirmedTransmissions[i];
                                            if (bytes != null) {
                                                log("RMS remote missed msg; reTX: $i (vs $_txCount)");
                                                await this._sendBytes(i, bytes, important: true); //CHECK asynchronously? //NEXT Update numbers?? (just store normal data, call local sendBytes?)  Wait - but the message has to have the old tx number, at least
                                            } else {
                                                log("RMS remote missed msg; unstored: $i vs $_txCount");
                                                if (_resetTimeout.fail()) {
                                                    await _triggerReset();
                                                }
                                            }
                                        }
                                        _rxBehind++;
                                        // This received message probably still counts, though
                                    } else {
                                        // Valid message; remove unneeded cache
                                        _unconfirmedTransmissions.removeWhere((k, v) => k <= txId);
                                        _resetTimeout.succeed(); //THINK Should success be counted in other cases?  Could a restart loop happen?
                                        _rxGood++;
                                    }
                                    _rxCount++;
                                    return data.sublist(9);
                                }
                            case 0x52:
                                { // 'R'
                                    int txId = bigEndianBytesInt32(data.sublist(1, 1 + 4));
                                    // Retransmit
                                    for (int i = txId; i <= _txCount; i++) { //THINK This seems network-cloggy - I think, even without explicit looping, the system would get up-to-date eventually...but that would probably involve a lot of invalid messages, so.
                                        var bytes = _unconfirmedTransmissions[i];
                                        if (bytes != null) {
                                            log("RMS remote requested reTX: $i (vs $_txCount)");
                                            await this._sendBytes(i, bytes, important: true); //CHECK asynchronously? //NEXT Update numbers?? (just store normal data, call local sendBytes?)
                                        } else {
                                            log("RMS remote requested reTX of unstored data: $i vs $_txCount");
                                            if (_resetTimeout.fail()) {
                                                await _triggerReset();
                                            }
                                        }
                                    }
                                    _rxRequest++;
                                    continue retry;
                                }
                            case 0x58:
                                { // 'X'
                                    // Remote startup - reset
                                    //NEXT Is there another way it could get locked up?
                                    log("RMS rx reset request");
                                    await mSendLock.synchronized(() async {
                                        _txCount = 0;
                                        _rxCount = 0;
                                        _unconfirmedTransmissions.clear();
                                        _resetTimeout.succeed();
                                    });
                                    _rxReset++;
                                    continue retry;
                                }
                            default:
                                log("RMS Unhandled message flag, assuming corrupt message"); //THINK At this point, is that a safe assumption to make?
                                _rxBad++;
                                continue retry;
                        }
                    } else {
                        return null;
                    }
                } finally {
                    //THINK Clear on reset?
                    log("RMS stats rxOld $_rxOld ; rxGood $_rxGood ; rxFuture $_rxFuture ; rxBehind $_rxBehind ; rxRequest $_rxRequest ; rxReset $_rxReset ; rxBad $_rxBad");
                }
            }
        });
    }
}

int currentMillis() {
    return DateTime.now().millisecondsSinceEpoch;
}