using Toybox.Application;
using Toybox.BluetoothLowEnergy as Ble;
using Toybox.Cryptography;
using Toybox.Lang;
using Toybox.System;
using Toybox.Timer;
using Toybox.WatchUi;



















class ScoutSimApp extends ScoutApp {
    function initialize() {
        ScoutApp.initialize();
        try { Application.Storage.deleteValue("g7SlotPolicy"); } catch (e) { }


        try { Application.Storage.deleteValue("savedAuthKeyHex"); } catch (e) { }

        try { Application.Storage.deleteValue("g7DeviceName"); } catch (e) { }
        ScoutView.loadSlotPolicy();
        ScoutView.loadTargetBinding();
    }

    function getInitialView() {
        var sensor = new ScoutSimSensor();
        return [ new ScoutSimView(sensor), new ScoutInputDelegate() ];
    }
}

class ScoutSimView extends ScoutView {
    var sensor;

    function initialize(simSensor) {
        ScoutView.initialize();
        sensor = simSensor;
    }

    function onShow() {
        ScoutView.onShow();
        sensor.start();
    }
}

class SimBusyException extends Lang.Exception {
    function initialize() { Exception.initialize(); }
}

class SimIterator {
    var items;
    var index = 0;
    function initialize(list) { items = list; }
    function next() {
        if (index >= items.size()) { return null; }
        index += 1;
        return items[index - 1];
    }
}

class SimDescriptor {
    var characteristic;
    function initialize(owner) { characteristic = owner; }
    function getCharacteristic() { return characteristic; }
    function getUuid() { return Ble.cccdUuid(); }
    function requestWrite(value) { characteristic.sensor.onCccdWrite(self, value); }
}

class SimCharacteristic {
    var uuid;
    var sensor;
    var cccd;
    function initialize(text, owner, withCccd) {
        uuid = Ble.stringToUuid(text);
        sensor = owner;
        cccd = withCccd ? new SimDescriptor(self) : null;
    }
    function getUuid() { return uuid; }
    function getDescriptor(descriptorUuid) { return cccd; }
    function getDescriptors() { return new SimIterator(cccd == null ? [] : [cccd]); }
    function requestWrite(value, options) { sensor.onWrite(self, value); }
    function requestRead() { sensor.onRead(self); }
}

class SimService {
    var uuid;
    var characteristics;
    function initialize(text, list) {
        uuid = Ble.stringToUuid(text);
        characteristics = list;
    }
    function getUuid() { return uuid; }
    function getCharacteristics() { return new SimIterator(characteristics); }
}

class SimDevice {
    var services;
    var connected = true;
    var bonded = false;
    var sensor;
    function initialize(owner, list) {
        sensor = owner;
        services = list;
    }
    function isConnected() { return connected; }
    function getServices() { return new SimIterator(services); }
    function getName() { return "DXCMz8"; }
    function isBonded() { return bonded; }
    function requestBond() { sensor.onBondRequest(); }
}

class ScoutSimSensor {


    static const AUTH_ACK_DELAY_MS = 3200;
    var timer;
    var events = [];
    var requestPending = false;
    var device;
    var control;
    var auth;
    var extra;
    var runner;
    var session = 0;
    var rx = []b;
    var client1;
    var client2;
    var serverX3;
    var serverX4;
    var round3;
    var prep;
    var key;
    var token;
    var challenge;
    var expectedRx = 0;


    var extraCccd = 0;
    var extraStalled = false;


    var roundsStarted = false;
    var loggedIn = false;

    var bondedOnce = false;


    var loseChunkPending = true;

    function initialize() {
        timer = new Timer.Timer();
        runner = new KeksMathRunner(method(:onMath), "simMath", method(:appIsSending));
    }



    function appIsSending() {
        return ScoutView.keksWriteScheduler.isSendingPayload();
    }

    static function hexBytes(hex) {
        var out = new [hex.length() / 2]b;
        for (var i = 0; i < out.size(); i += 1) {
            out[i] = hex.substring(2 * i, 2 * i + 2).toNumberWithBase(16);
        }
        return out;
    }

    function log(text) {
        System.println("[SIM] " + ScoutView.logTimestamp() + " " + text);
    }

    function start() {
        if (session == 0) {
            session = 1;
            connect();
        }
    }

    function connect() {
        control = new SimCharacteristic("F8083534-849E-531C-C594-30F1F86A4EA5", self, true);
        auth = new SimCharacteristic("F8083535-849E-531C-C594-30F1F86A4EA5", self, true);
        extra = new SimCharacteristic("F8083538-849E-531C-C594-30F1F86A4EA5", self, true);
        var primary = new SimService("F8083532-849E-531C-C594-30F1F86A4EA5", [control, auth, extra]);
        device = new SimDevice(self, [primary]);
        rx = []b;
        requestPending = false;
        events = [];
        extraCccd = 0;
        extraStalled = false;
        roundsStarted = false;
        loggedIn = false;
        log("CONNECT session=" + session);
        ScoutView.markConnected(device, "SIM_SENSOR");
    }


    var refuseSlot = false;

    function post(event) {
        events.add(event);
        if (events.size() == 1) { timer.start(method(:deliver), delayOf(event), false); }
    }


    function delayOf(event) {
        var delay = event.size() > 3 ? event[3] : ScoutClock.MIN_DELAY_MS;
        return delay > ScoutClock.MIN_DELAY_MS ? delay : ScoutClock.MIN_DELAY_MS;
    }

    function deliver() {
        if (events.size() == 0) { return; }
        var event = events[0];
        events = events.slice(1, null);
        var kind = event[0];
        if (kind == 0) {
            requestPending = false;
            ScoutView.delegate.onCharacteristicWrite(event[1], Ble.STATUS_SUCCESS);
        } else if (kind == 1) {
            requestPending = false;
            ScoutView.delegate.onDescriptorWrite(event[1], Ble.STATUS_SUCCESS);
        } else if (kind == 2) {
            if (device.connected) { ScoutView.delegate.onCharacteristicChanged(event[1], event[2]); }
        } else if (kind == 3) {
            ScoutView.delegate.onEncryptionStatus(device, Ble.STATUS_SUCCESS);
        } else if (kind == 5) {
            requestPending = false;

            ScoutView.delegate.onCharacteristicRead(event[1], 2, []b);
        } else if (kind == 4) {
            device.connected = false;
            ScoutView.delegate.onConnectedStateChanged(device, Ble.CONNECTION_STATE_DISCONNECTED);
            events = [];
            session += 1;
            timer.start(method(:connect), 2000, false);
            return;
        }
        if (events.size() > 0) { timer.start(method(:deliver), delayOf(events[0]), false); }
    }

    function notify(characteristic, bytes) {
        if (characteristic == extra && extraCccd != 0x01) {


            if (extraStalled) { return; }
            extraStalled = true;
            log("FAIL ExtraData CCCD=" + extraCccd + " (xDrip uses notifications, 0x01); stalling after this chunk");
        }
        post([2, characteristic, bytes]);
    }

    function notifyExtraRange(bytes, start, end) {
        for (var off = start; off < end; off += 20) {
            var chunkEnd = off + 20 < end ? off + 20 : end;
            notify(extra, bytes.slice(off, chunkEnd));
        }
    }

    function notifyExtra(bytes) {
        notifyExtraRange(bytes, 0, bytes.size());
    }



    function notifyRound1WithAuthAck(bytes) {
        if (bytes == null || bytes.size() != 160) {
            log("FAIL round-0 fixture size=" + (bytes == null ? 0 : bytes.size()));
            return;
        }
        notifyExtraRange(bytes, 0, 120);
        log("ROUND_ACK_SENT opcode=0A status=0 phase=0 afterBytes=120");
        notify(auth, [0x0A,0x00,0x00]b);
        notifyExtraRange(bytes, 120, bytes.size());
    }

    function guardRequest() {
        if (requestPending) {
            log("FAIL second GATT request while one is pending");
            throw new SimBusyException();
        }
        requestPending = true;
    }


    function onCccdWrite(descriptor, value) {
        guardRequest();
        if (descriptor.getCharacteristic() == extra) { extraCccd = value[0] & 0xFF; }
        post([1, descriptor]);
    }

    function onRead(characteristic) {
        guardRequest();
        post([5, characteristic]);
    }

    function onWrite(characteristic, value) {
        if (characteristic == extra && roundsStarted && loseChunkPending) {
            loseChunkPending = false;
            log("LOSE_CHUNK bytes=" + value.size() + " no callback");
            return;
        }
        guardRequest();
        post(characteristic == auth ? [0, characteristic, null, AUTH_ACK_DELAY_MS] : [0, characteristic]);
        if (characteristic == extra) {
            rx.addAll(value);
            if (expectedRx > 0 && rx.size() == expectedRx) {
                expectedRx = 0;
                log("CERT_RX bytes=" + rx.size());
                rx = []b;
                notifyExtra(fakeCertificate());
            }
        } else if (characteristic == auth) {
            onAuthCommand(value);
        } else if (characteristic == control) {
            if (value.size() == 1 && (value[0] & 0xFF) == 0x4E) {
                log("GLUCOSE_REQUEST_RX");
                notify(control, [0x4E, 0x00, 0x10, 0x27, 0x00, 0x00, 0x2A, 0x00, 0x00, 0x00,
                    0x3C, 0x00, 0x7B, 0x00, 0x06, 0x05, 0xFF, 0xFF, 0x00]b);
                log("SESSION_COMPLETE session=" + session);
                if (session == 2) {
                    log("RECONNECT expecting the saved-key login");
                    post([4, null, null, 1000]);
                } else if (session == 3) {





                    log("RECONNECT as a watch holding the phone's key, not bonded");
                    bondedOnce = false;
                    try { Application.Storage.deleteValue("g7SlotPolicy"); } catch (e) { }
                    ScoutView.loadSlotPolicy();
                    post([4, null, null, 1000]);
                }
            }
        }
    }

    function onAuthCommand(value) {
        var op = value[0] & 0xFF;
        if (op == 0x0A) {
            var param = value[1] & 0xFF;
            log("ROUND_COMMAND param=" + param + " clientBytes=" + rx.size());
            if (param == 0) {
                roundsStarted = true;
                rx = []b;
                notifyRound1WithAuthAck(hexBytes(KeksEngineVectors.S1));
            } else if (param == 1) {
                client1 = KeksP256.parsePacket(rx);
                rx = []b;
                runner.enqueue(new KeksVerifyRound12Task(client1, ScoutView.keksClientParty()), "VERIFY_C1");
            } else {
                client2 = KeksP256.parsePacket(rx);
                rx = []b;
                runner.enqueue(new KeksVerifyRound12Task(client2, ScoutView.keksClientParty()), "VERIFY_C2");
            }
        } else if (op == 0x02) {
            var displayType = value[9] & 0xFF;
            log("AUTH_REQUEST displayType=" + displayType + " round3Bytes=" + rx.size());



            refuseSlot = displayType == 0x03;
            token = value.slice(1, 9);
            if (!roundsStarted && key != null) {

                log("SAVED_KEY_AUTH_RX slot=" + displayType);
                challenge = Cryptography.randomBytes(8);
                var reply = [0x03]b;
                reply.addAll(aes(token).slice(0, 8));
                reply.addAll(challenge);
                notify(auth, reply);
                return;
            }
            var client3 = KeksP256.parsePacket(rx);
            rx = []b;
            runner.enqueue(new KeksRound3FinishTask(client3, prep, KeksP256.fromBytesBE(hexBytes(KeksEngineVectors.B2), 0, 32),
                ScoutView.keksClientParty()), "SERVER_KEY");
        } else if (op == 0x04) {
            var expected = aes(challenge);
            var ok = ScoutView.bytesEqual(value.slice(1, 9), expected.slice(0, 8));
            log("AUTH_CHALLENGE_RX ok=" + ok + " bondedOnce=" + bondedOnce);
            if (refuseSlot) {
                log("REFUSE_WATCH_SLOT status=050001");
                notify(auth, [0x05, 0x00, 0x01]b);

                post([4]);
                return;
            }
            loggedIn = ok;

            notify(auth, [0x05, ok ? 0x01 : 0x00, bondedOnce ? 0x01 : 0x02]b);
        } else if (op == 0x0B) {
            var which = value[1] & 0xFF;
            expectedRx = (value[2] & 0xFF) | ((value[3] & 0xFF) << 8);
            rx = []b;
            notify(auth, [0x0B, 0x00, which, 150, 0x00, 0x00, 0x00]b);
        } else if (op == 0x0C) {
            notify(auth, [0x0C, 0x00, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]b);
        } else if (op == 0x0D) {
            log("SIGNATURE_RX bytes=" + rx.size());
            rx = []b;
            notify(auth, [0x0D, 0x00]b);
        } else if (op == 0x06) {
            if (!roundsStarted && !loggedIn) {


                log("FAIL keep-alive before round 1; dropping link like the G7");
                post([4]);
                return;
            }
            notify(auth, [0x06, 0x19]b);
        }
    }

    function onBondRequest() {
        log("BOND_REQUEST");
        device.bonded = true;
        bondedOnce = true;
        post([3]);
    }


    function onMath(action, task) {
        log("MATH " + action + " ok=" + (task.result != null) + " failure=" + task.failure +
            " ms=" + runner.taskElapsedMs() + " ticks=" + runner.taskTicks());
        if (task.result == null) { return; }
        var password = KeksP256.passwordInteger(ScoutView.getConfiguredPairingCode());
        var b2 = KeksP256.fromBytesBE(hexBytes(KeksEngineVectors.B2), 0, 32);
        if (action.equals("VERIFY_C1")) {
            serverX3 = KeksP256.parsePacket(hexBytes(KeksEngineVectors.S1))[1];
            serverX4 = KeksP256.parsePacket(hexBytes(KeksEngineVectors.S2))[1];
            notifyExtra(hexBytes(KeksEngineVectors.S2));
        } else if (action.equals("VERIFY_C2")) {
            round3 = new KeksRound3PacketTask(serverX3, client1[1], client2[1], b2, password,
                KeksP256.fromBytesBE(hexBytes(KeksEngineVectors.W3), 0, 32), ScoutView.keksServerParty());
            runner.enqueue(round3, "SERVER_ROUND3");
        } else if (action.equals("SERVER_ROUND3")) {
            notifyExtra(task.result);
            prep = new KeksRound3PrepTask(serverX3, serverX4, client1[1], client2[1], round3.xp, round3.xp1);
            runner.enqueue(prep, "SERVER_PREP");
        } else if (action.equals("SERVER_KEY")) {
            key = task.result;
            challenge = Cryptography.randomBytes(8);
            var reply = [0x03]b;
            reply.addAll(aes(token).slice(0, 8));
            reply.addAll(challenge);
            notify(auth, reply);
        }
    }

    function aes(eight) {
        var plain = new [16]b;
        for (var i = 0; i < 8; i += 1) {
            plain[i] = eight[i];
            plain[i + 8] = eight[i];
        }
        var cipher = new Cryptography.Cipher({
            :algorithm => Cryptography.CIPHER_AES128,
            :mode => Cryptography.MODE_ECB,
            :key => key
        });
        return cipher.encrypt(plain);
    }

    function fakeCertificate() {
        var cert = new [150]b;
        for (var i = 0; i < 150; i += 1) { cert[i] = (i * 7) & 0xFF; }
        return cert;
    }
}
