using Toybox.Application;
using Toybox.Attention;
using Toybox.BluetoothLowEnergy as Ble;
using Toybox.Cryptography;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.StringUtil;
using Toybox.System;
using Toybox.Time;
using Toybox.Timer;
using Toybox.WatchUi;

class ScoutApp extends Application.AppBase {

    static function buildVersion() {
        return "local-dev";
    }

    static function splashBuildLabel() {
        return "b-local";
    }

    function initialize() {
        AppBase.initialize();
        ScoutLog.println("BV" + buildVersion());
        ScoutView.runCryptoSelfTest();
        ScoutView.loadSlotPolicy();
        ScoutView.loadTargetBinding();
        ScoutReadingSync.restore();
        ScoutView.initializeGattProfiles();
    }

    function getInitialView() {
        return [ new ScoutSplashView(), new ScoutInputDelegate() ];
    }
}


class ScoutBacklightController {
    var deadline;

    function initialize() {
        deadline = 0;
    }

    function light() {
        deadline = System.getTimer() + 10000;
        if (!ScoutClock.get().isScheduled("backlight")) { tick(); }
    }

    function tick() {
        if (System.getTimer() - deadline >= 0) { return; }
        try {
            Attention.backlight(true);
            ScoutClock.get().schedule("backlight", 1000, method(:tick));
        } catch (exception) {
            ScoutLog.println("BL" + exception);
        }
    }
}

class ScoutInputDelegate extends WatchUi.InputDelegate {
    function initialize() {
        InputDelegate.initialize();
    }

    function onKey(keyEvent) {
        if (keyEvent.getKey() == WatchUi.KEY_ENTER) {
            ScoutView.lightBacklight();
            if (ScoutView.dashboardShown) { ScoutScreens.pushMenu(); }
            return true;
        }
        return false;
    }
}

class ScoutSplashView extends WatchUi.View {
    var splashIcon;

    function initialize() {
        View.initialize();
        splashIcon = null;
    }

    function onShow() {
        splashIcon = WatchUi.loadResource(Rez.Drawables.SplashIcon);
        ScoutClock.get().schedule("splash", 3000, method(:showDashboard));
    }

    function onHide() {
        ScoutClock.get().cancel("splash");
    }

    function showDashboard() {
        ScoutClock.get().cancel("splash");
        WatchUi.switchToView(new ScoutView(), new ScoutInputDelegate(), WatchUi.SLIDE_IMMEDIATE);

        if (!ScoutView.isUsablePairingCode(ScoutView.getConfiguredPairingCode())) {
            var codeView = new ScoutCodeView();
            WatchUi.pushView(codeView, new ScoutCodeDelegate(codeView, null), WatchUi.SLIDE_IMMEDIATE);
        }
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        dc.drawBitmap((width - 96) / 2, height * 0.08, splashIcon);
        dc.drawText(centerX, height * 0.59, Graphics.FONT_LARGE,
            "G7 Scout", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(centerX, height * 0.76, Graphics.FONT_SMALL,
            ScoutApp.splashBuildLabel(), Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class ScoutBleDelegate extends Ble.BleDelegate {
    function initialize() {
        BleDelegate.initialize();
    }



    function onScanResults(scanResults) {
        var result = scanResults.next();
        while (result != null) {
            var scanResult = result as Ble.ScanResult;
            var name = scanResult.getDeviceName();
            if (ScoutView.targetBound) {
                ScoutView.onBoundScanResult(scanResult, name);
            } else {
                var rssi = scanResult.getRssi();
                var index = ScoutView.updateDevice(scanResult, name, rssi);
                var label = (name == null || name.length() == 0) ? "<>" : name;

                var hasFebc = false;
                var uuids = scanResult.getServiceUuids();
                for (var uuid = uuids.next(); uuid != null && !hasFebc; uuid = uuids.next()) {
                    hasFebc = ScoutView.UUID_FEBC.equals(uuid);
                }

                var hits = index >= 0 ? ScoutView.deviceHits[index] : 0;
                var normalizedName = name == null ? "" : name.toUpper();
                if (ScoutView.TARGET_NAME_UPPER.length() > 0 && normalizedName.equals(ScoutView.TARGET_NAME_UPPER)) {
                    if (ScoutView.targetScanResult == null && !ScoutView.connectionAttempted) {
                        ScoutView.onTargetFound(scanResult, name, rssi);
                    } else if (ScoutView.targetScanResult != null) {
                        ScoutView.targetRssi = rssi;
                    }
                } else if (ScoutView.TARGET_NAME_UPPER.length() == 0 && normalizedName.length() >= 4 &&
                    normalizedName.substring(0, 4).equals("DXCM")) {
                    ScoutView.offerUnboundCandidate(scanResult, name, rssi);
                }


                var isDxcmPrefix = normalizedName.length() >= 4 &&
                    normalizedName.substring(0, 4).equals("DXCM");
                var isLegacyDexcomName = normalizedName.length() >= 6 &&
                    normalizedName.substring(0, 6).equals("DEXCOM");
                var isG7Candidate = isDxcmPrefix || (hasFebc && !isLegacyDexcomName);



                if (isG7Candidate) {
                    if (hits == 1 || hits % 20 == 0) {
                        var reason = isDxcmPrefix ? "P" : "U";
                        var rawData = scanResult.getRawData();
                        ScoutLog.println("SE" + label +
                            ":" + rssi + ":" + hits + ":" + reason +
                            ":" + (hasFebc ? "FEBC" : "-") +
                            ":" + ScoutView.bytesToHex(rawData));
                    }
                } else if (hits == 1 || hits % 100 == 0) {
                    ScoutLog.fileOnly("OB" + label +
                        ":" + rssi + ":" + hits + ScoutView.serviceUuidSuffix(scanResult));
                }
            }
            result = scanResults.next();
        }
        WatchUi.requestUpdate();
    }

    function onScanStateChange(scanState, status) {
        ScoutLog.println("SC" + scanState + ":" + status);
        if (scanState == Ble.SCAN_STATE_SCANNING) {
            if (status != Ble.STATUS_SUCCESS) {
                ScoutView.scanning = false;
                ScoutView.retryScanActive = true;
                var retryMs = ScoutView.scanErrorRetryMs();
                ScoutView.connectionTimerPurpose = "RETRY_DELAY";
                ScoutView.connectionWatchdog.start(retryMs);
                ScoutView.scanStatus = "SCAN ERROR";
                ScoutLog.println("SZ" + status + ":" + retryMs);
            } else {
                ScoutView.setScanState(true, status);
            }
        } else {
            ScoutView.scanning = false;


            if (ScoutView.awaitingConnect && ScoutView.targetScanResult != null) {
                ScoutView.scanStatus = "CONN PENDING";
            } else if (!ScoutView.connectionAttempted && !ScoutView.connectionInFlight) {
                var preserveStatus = ScoutView.scanStatus.equals("RETRY TARGET NOT SEEN; ENTER SCAN") ||
                    ScoutView.scanStatus.equals("SCAN START FAILED") ||
                    ScoutView.scanStatus.equals("SCAN START EXCEPTION") ||
                    ScoutView.scanStatus.equals("CONNECT FAILED; ENTER SCAN") ||
                    ScoutView.scanStatus.equals("SCAN DONE; ENTER CONNECT") ||
                    ScoutView.scanStatus.equals("SCAN DONE; ENTER RESCAN") ||
                    ScoutView.scanStatus.equals("SCAN STOPPED; ENTER CONNECT") ||
                    ScoutView.scanStatus.equals("SCAN STOPPED; ENTER RESCAN");
                if (!preserveStatus) {
                    ScoutView.setScanState(false, status);
                }
            }
        }
        WatchUi.requestUpdate();
    }

    function onProfileRegister(uuid, status) {
        if (ScoutView.profileRegistrationFailed) {
            ScoutLog.println("PZ" + ScoutView.shortUuid(uuid) + ":" + status +
                ":true:" + ScoutView.profileRegistrationFailureReason);
            WatchUi.requestUpdate();
            return;
        }

        ScoutView.profilesRegistered += 1;
        if (status != Ble.STATUS_SUCCESS) {
            ScoutView.profileRegistrationFailed = true;
            ScoutView.profileRegistrationFailureReason = "CALLBACK_STATUS";
            ScoutView.profileRegistrationWatchdog.stop();
            if (ScoutView.awaitingConnect && ScoutView.targetScanResult != null) {
                ScoutView.awaitingConnect = false;
                ScoutView.retryScanActive = true;
                ScoutView.scanStatus = "PROFILE ERR";
                ScoutView.connectionTimerPurpose = "RETRY_DELAY";
                ScoutView.connectionWatchdog.start(240000);
                ScoutLog.println("AAprofile-registration-status:240");
            }
        }
        ScoutView.profilesReady = ScoutView.profilesRegistered >= 2 &&
            !ScoutView.profileRegistrationFailed;
        if (ScoutView.profilesReady) {
            ScoutView.profileRegistrationWatchdog.stop();
        }
        ScoutLog.println("PD" + ScoutView.shortUuid(uuid) + ":" + status +
            ":" + ScoutView.profilesRegistered +
            ":" + ScoutView.profilesReady);
        if (ScoutView.profilesReady && ScoutView.awaitingConnect &&
            ScoutView.targetScanResult != null && !ScoutView.connectionAttempted) {
            ScoutLog.println("ARprofiles-ready");
            ScoutView.connectTarget();
        }
        WatchUi.requestUpdate();
    }

    function onConnectedStateChanged(connectedDevice, state) {
        var name = connectedDevice.getName();
        ScoutLog.println("LS");
        if (state == Ble.CONNECTION_STATE_CONNECTED) {
            ScoutView.lightBacklight();
            ScoutView.markConnected(connectedDevice, "CONNECTION_CALLBACK");
        } else if (state == Ble.CONNECTION_STATE_DISCONNECTED) {
            ScoutView.onSavedAuthLinkLost();
            ScoutView.onLinkLost();
            if (ScoutView.connectionInFlight) {
                ScoutView.handleConnectFailure("DISCONNECTED_CALLBACK");
            } else {
                ScoutView.device = null;
                ScoutView.connectionAttempted = false;
                ScoutView.awaitingConnect = false;
                ScoutView.targetScanResult = null;
                ScoutView.targetRssi = 0;
                ScoutView.retryScanActive = true;
                ScoutView.scanStatus = "DISCONNECTED";
                var gotReading = ScoutView.sessionGotReading;
                ScoutLog.println("DR" + gotReading);
                ScoutView.noteDebug("LINK DOWN " + (System.getTimer() - ScoutView.connectedAtMs) + "ms");
                if (!gotReading) {  }
                ScoutView.rescanAfterSession(gotReading);
            }
        } else {
            ScoutView.scanStatus = "CONN STATE " + state;
        }
        WatchUi.requestUpdate();
    }

    function onCharacteristicChanged(characteristic, value) {
        ScoutView.keksWriteScheduler.noteLink();
        var uuid = characteristic.getUuid();
        var isAuth = ScoutView.UUID_AUTH.equals(uuid);
        if (ScoutView.isFreshKeksActive() && (isAuth || ScoutView.UUID_EXTRA.equals(uuid))) {
            ScoutView.keksWriteScheduler.onSensorResponse();
        }
        if (isAuth && ScoutView.isFreshKeksActive()) {



            ScoutView.handleFreshKeksAuthMessage(value);
            ScoutView.lightBacklight();
            WatchUi.requestUpdate();
            return;
        }
        if (isAuth) {

            var authOpcode = (value != null && value.size() > 0) ? (value[0] & 0xFF) : -1;




            var answered = false;
            if (authOpcode == 0x03 && value != null && value.size() >= 17) {
                answered = ScoutView.sendSavedKeyChallengeResponse(value);
            }
            ScoutLog.println("GA" + authOpcode + ":" + (value == null ? 0 : value.size()));
            ScoutView.authProbeResponseSeen = true;
            ScoutView.authProbeWatchdog.stop();
            if (authOpcode == 0x03 && value != null && value.size() >= 17) {

                ScoutLog.println("K28:8:9");
                if (!answered) {
                    ScoutView.scanStatus = "NEED KEKS";
                }
            } else if (authOpcode == 0x03) {
                ScoutView.scanStatus = "AUTH SHORT";
                ScoutLog.println("K3short:" + (value == null ? 0 : value.size()));
            } else if (authOpcode == 0x05 && value != null && value.size() >= 3) {
                var authByte = value[1] & 0xFF;
                var bondedByte = value[2] & 0xFF;
                ScoutView.g7Authenticated = authByte == 1;


                var locallyBonded = false;
                try { locallyBonded = ScoutView.device != null && ScoutView.device.isBonded(); } catch (bondQuery) { locallyBonded = false; }
                ScoutView.g7Bonded = bondedByte == 1 || (bondedByte == 2 && locallyBonded);
                ScoutLog.println("AS" + ScoutView.g7Authenticated + ":" + ScoutView.g7Bonded + ":" + bondedByte + ":" + (bondedByte == 3) + ":wire-status-only");
                ScoutView.noteDebug("AUTH 05 a" + authByte + " b" + bondedByte);
                ScoutView.onSavedAuthSlotOutcome(ScoutView.g7Authenticated,
                    bondedByte == 3 ? "refresh" : "rejected");
                if (ScoutView.g7Authenticated && ScoutView.g7Bonded && !ScoutView.sessionTerminal) {
                    ScoutView.bindTargetDevice("saved-key");
                    ScoutView.enableCharacteristicIndications(ScoutView.device, ScoutView.UUID_CONTROL, "CONTROL", 0x02);
                    ScoutView.scanStatus = "AUTH OK";
                } else if (ScoutView.g7Authenticated && !ScoutView.sessionTerminal) {




                    ScoutLog.println("SN" + bondedByte +
                        ":" + (System.getTimer() - ScoutView.connectedAtMs));
                    ScoutView.beginSavedKeyCertificates();
                } else if (bondedByte == 3) {
                    ScoutView.scanStatus = "AUTH REFRESH";
                } else {
                    ScoutView.scanStatus = "NEED AUTH";
                }
            } else {
                ScoutView.scanStatus = "AUTH OP " + authOpcode;
                ScoutLog.println("KV" + authOpcode + ":" + (value == null ? 0 : value.size()));
            }
        } else if (ScoutView.UUID_CONTROL.equals(uuid)) {
            ScoutLog.println("GICONTROL:" + (value == null ? 0 : value.size()));
            ScoutView.handleG7ControlMessage(value);
        } else if (ScoutView.UUID_EXTRA.equals(uuid)) {
            if (ScoutView.isFreshKeksActive()) {
                ScoutView.handleFreshKeksExtraData(value);
            } else {

                ScoutLog.println("XI" + (value == null ? 0 : value.size()) +
                    ":" + ScoutView.freshKeksState);
            }
        }


        ScoutView.lightBacklight();
        WatchUi.requestUpdate();
    }

    function onDescriptorWrite(descriptor, status) {
        ScoutView.keksWriteScheduler.noteLink();
        ScoutView.lightBacklight();
        var uuid = descriptor.getCharacteristic().getUuid();
        ScoutLog.println("WR" + ScoutView.shortUuid(uuid) + ":" + status);
        if (ScoutView.UUID_CONTROL.equals(uuid)) {




            if (status == Ble.STATUS_SUCCESS) {
                ScoutView.requestGlucose();
            } else {
                ScoutView.scanStatus = "SUB-C FAILED";
            }
        } else if (ScoutView.UUID_EXTRA.equals(uuid)) {
            if (status == Ble.STATUS_SUCCESS) {
                ScoutView.extraDataCccdReady = true;
                ScoutView.enableCharacteristicIndications(ScoutView.device,
                    ScoutView.UUID_AUTH, "AUTH", 0x02);
            } else {
                ScoutView.scanStatus = "SUB-X FAILED";
                ScoutLog.println("KAextra-cccd-write-failed:" + status);
            }
        } else if (ScoutView.UUID_AUTH.equals(uuid)) {
            if (status == Ble.STATUS_SUCCESS) {
                ScoutView.authCccdReady = true;


                if (!ScoutCollector.isWatch()) {
                    ScoutView.scanStatus = "PHONE HAS G7";
                    ScoutLog.println("CBphone-collector:auth-cccd");
                } else if (ScoutView.isUsablePairingCode(ScoutView.getConfiguredPairingCode())) {


                    if (ScoutView.savedKeyUsable()) {
                        ScoutView.sendAuthRequestProbe();
                    } else {
                        ScoutView.tryBeginConfiguredFreshKeks("auth-cccd-ready");
                    }
                } else {
                    ScoutView.scanStatus = "NO CODE";
                    ScoutLog.println("KNno-pairing-code");
                }
            } else {
                ScoutView.scanStatus = "SUB-A FAILED";
            }
        }
    }



    function onCharacteristicWrite(characteristic, status) {
        if (status != Ble.STATUS_SUCCESS) {
            ScoutLog.println("GW" + characteristic.getUuid() + ":" + status);
        }
        ScoutView.keksWriteScheduler.onWriteComplete(status);
    }

    function onCharacteristicRead(characteristic, status, value) {
        ScoutView.keksWriteScheduler.onReadComplete(status);
    }

    function onEncryptionStatus(connectedDevice, status) {
        var bonded = false;
        try {
            bonded = connectedDevice.isBonded();
        } catch (exception) {
            ScoutLog.println("BQ" + exception);
        }
        ScoutLog.println("EN" + status + ":" + connectedDevice.isConnected() + ":" + bonded + ":BLE_LINK_SECURITY_NOT_G7_APP_AUTH");
        if (status == Ble.STATUS_SUCCESS && bonded &&
            ScoutView.freshKeksState.equals("WAIT_BLE_BOND") && ScoutView.g7Authenticated) {
            ScoutView.g7Bonded = true;
            ScoutView.finishFreshKeks("ble-bond-confirmed");
            ScoutView.enableCharacteristicIndications(connectedDevice,
                ScoutView.UUID_CONTROL, "CONTROL", 0x02);
        } else {
            ScoutView.scanStatus = status == Ble.STATUS_SUCCESS ? "LINK SECURE" : "LINK ERR " + status;
        }
        WatchUi.requestUpdate();
    }
}

class ScoutAuthProbeWatchdog {
    function initialize() { }
    function start(delayMs) { ScoutClock.get().schedule("authProbe", delayMs, method(:onTimeout)); }
    function stop() { ScoutClock.get().cancel("authProbe"); }
    function onTimeout() { ScoutView.onAuthProbeTimeout(); }
}

class ScoutConnectionWatchdog {
    function initialize() { }
    function start(delayMs) { ScoutClock.get().schedule("connection", delayMs, method(:onTimeout)); }
    function onTimeout() { ScoutView.onConnectionTimer(); }
}

class ScoutProfileRegistrationWatchdog {
    function initialize() { }
    function start(delayMs) { ScoutClock.get().schedule("profileRegistration", delayMs, method(:onTimeout)); }
    function stop() { ScoutClock.get().cancel("profileRegistration"); }
    function onTimeout() { ScoutView.onProfileRegistrationTimeout(); }
}
















class ScoutKeksWriteScheduler {
    static const MAX_QUEUED = 4;





    static const CHUNK_CALLBACK_MS = 1000;








    static var chunksWithResponse = false;
    static var chunkResponseRefused = false;
    static var keksAttempts = 0;














    static var settleMode = 0;
    static const SETTLE_MS = 50;
    static const PING_TIMEOUT_MS = 4000;


    static const CHUNK_RESPONSE_MS = 8000;




    static const CHUNK_RESPONSE_FAST_MS = 1000;
    static const FAST_ACK_MS = 1000;





    static const COMMAND_CALLBACK_MS = 15000;
    static const BUSY_RETRIES = 60;

    var pending;
    var packet;
    var command;
    var commandUuid;
    var purpose;
    var offset;
    var active;
    var awaiting;
    var busyRetries;
    var chunkCallbacksMissed;
    var commandSentMs = 0;
    var chunkSize = 0;
    var chunkSentMs = 0;
    var payloadStartMs = 0;

    var lastLinkMs = 0;
    var commandGapMs = 0;


    var lastAckMs = COMMAND_CALLBACK_MS;
    var chunkResent = false;

    function initialize() {
        pending = [];
        cancel();
    }

    function queue(packetBytes, commandBytes, label, commandTarget) {
        var hasPayload = packetBytes != null && packetBytes.size() > 0;
        var hasCommand = commandBytes != null && commandBytes.size() > 0;
        if ((!hasPayload && !hasCommand) || pending.size() >= MAX_QUEUED) { return false; }
        pending.add([hasPayload ? packetBytes : null, hasCommand ? commandBytes : null, label, commandTarget]);
        if (!active) { startNext(); }
        return true;
    }

    function cancel() {
        ScoutClock.get().cancel("keksWrite");
        pending = [];
        packet = null;
        command = null;
        commandUuid = null;
        purpose = "";
        offset = 0;
        active = false;
        awaiting = 0;
        busyRetries = 0;
        chunkCallbacksMissed = 0;
        lastAckMs = COMMAND_CALLBACK_MS;
        chunkResent = false;
    }

    function startNext() {
        if (pending.size() == 0) {
            active = false;
            return;
        }
        var next = pending[0];
        pending = pending.slice(1, null);
        packet = next[0];
        command = next[1];
        purpose = next[2];
        commandUuid = next[3];
        offset = 0;
        awaiting = 0;
        busyRetries = 0;
        chunkCallbacksMissed = 0;
        payloadStartMs = System.getTimer();
        active = true;
        send();
    }

    function noteLink() {
        lastLinkMs = System.getTimer();
    }


    function send() {
        if (!active || awaiting != 0) { return; }
        if (ScoutView.device == null || !ScoutView.device.isConnected()) {
            fail("link-lost");
            return;
        }
        var isChunk = packet != null && offset < packet.size();
        if (!isChunk && command == null) {
            finishTransaction();
            return;
        }
        var characteristic = ScoutView.findCharacteristic(isChunk ? ScoutView.UUID_EXTRA : commandUuid);
        if (characteristic == null) {
            fail("characteristic-missing");
            return;
        }
        try {
            if (isChunk) {
                var size = packet.size() - offset;
                if (size > 20) { size = 20; }
                characteristic.requestWrite(packet.slice(offset, offset + size),
                    { :writeType => chunksWithResponse ? Ble.WRITE_TYPE_WITH_RESPONSE : Ble.WRITE_TYPE_DEFAULT });
                offset += size;
                chunkSize = size;
                chunkSentMs = System.getTimer();
                awaiting = 1;
                ScoutClock.get().schedule("keksWrite", !chunksWithResponse ? CHUNK_CALLBACK_MS :
                    (lastAckMs < FAST_ACK_MS ? CHUNK_RESPONSE_FAST_MS : CHUNK_RESPONSE_MS),
                    method(:onCallbackTimeout));
            } else {
                characteristic.requestWrite(command, { :writeType => Ble.WRITE_TYPE_WITH_RESPONSE });
                awaiting = 2;
                commandSentMs = System.getTimer();
                commandGapMs = commandSentMs - lastLinkMs;
                ScoutClock.get().schedule("keksWrite", COMMAND_CALLBACK_MS, method(:onCallbackTimeout));
            }
        } catch (exception) {

            busyRetries += 1;
            if (busyRetries > BUSY_RETRIES) {
                fail("write-exception");
                return;
            }
            ScoutClock.get().schedule("keksWrite", 50, method(:send));
        }
    }

    function onWriteComplete(status) {
        noteLink();
        if (!active || awaiting == 0) { return; }
        ScoutClock.get().cancel("keksWrite");
        var wasCommand = awaiting == 2;
        awaiting = 0;
        if (status != Ble.STATUS_SUCCESS && !wasCommand && chunksWithResponse) {


            chunksWithResponse = false;
            chunkResponseRefused = true;
            offset -= chunkSize;
            ScoutLog.println("KF" + status + ":" + purpose + ":" + offset);
            ScoutView.noteDebug("CHUNK WR " + status);
            send();
            return;
        }
        if (status != Ble.STATUS_SUCCESS) {
            fail("gatt-write-status-" + status);
            return;
        }
        if (wasCommand) {
            completeCommand("ack");
            return;
        }


        if (chunksWithResponse) {
            ScoutLog.println("KD" + ((offset - chunkSize) / 20) + ":" + (System.getTimer() - chunkSentMs));
        }
        chunkResent = false;
        scheduleAfterChunk();
    }


    function onSensorResponse() {
        if (active && awaiting == 2) {
            ScoutClock.get().cancel("keksWrite");
            awaiting = 0;
            completeCommand("sensor-reply");
        }
    }

    function completeCommand(source) {
        var label = purpose;
        var size = command.size();
        var target = commandUuid;
        command = null;
        if (source.equals("ack")) { lastAckMs = System.getTimer() - commandSentMs; }
        ScoutLog.println("KC" + label + ":" + size +
            ":" + source + ":" + (System.getTimer() - commandSentMs) +
            ":" + commandGapMs);

        var shortLabel = label.equals("START_ROUND1") ? "0A00" :
            (label.equals("ROUND1") ? "0A01" : (label.equals("ROUND2") ? "0A02" :
            label.substring(0, label.length() < 9 ? label.length() : 9)));
        ScoutView.noteDebug("ACK " + shortLabel + " " + (System.getTimer() - commandSentMs) + "ms");
        ScoutView.onKeksCommandWritten(label, target);
        startNext();
    }


    var pingSentMs = 0;

    function ping() {
        var control = ScoutView.findCharacteristic(ScoutView.UUID_CONTROL);
        if (control == null) { return false; }
        try {
            control.requestRead();
        } catch (exception) {
            return false;
        }
        awaiting = 3;
        pingSentMs = System.getTimer();
        ScoutClock.get().schedule("keksWrite", PING_TIMEOUT_MS, method(:onCallbackTimeout));
        return true;
    }

    function onReadComplete(status) {
        noteLink();
        if (!active || awaiting != 3) { return; }
        ScoutClock.get().cancel("keksWrite");
        awaiting = 0;
        ScoutLog.println("K0" + status + ":" + (System.getTimer() - pingSentMs));
        send();
    }

    function onCallbackTimeout() {
        if (!active || awaiting == 0) { return; }
        if (awaiting == 3) {
            awaiting = 0;
            ScoutLog.println("K0timeout:" + (System.getTimer() - pingSentMs));
            send();
            return;
        }
        if (awaiting == 2) {
            awaiting = 0;
            completeCommand("none");
            return;
        }
        awaiting = 0;
        chunkCallbacksMissed += 1;
        var resend = !chunkResent;
        ScoutLog.println("KX" + ((offset - chunkSize) / 20) + ":" + (System.getTimer() - chunkSentMs) +
            ":" + resend);
        if (resend) {

            chunkResent = true;
            offset -= chunkSize;
            send();
            return;
        }
        chunkResent = false;
        scheduleAfterChunk();
    }




    function isSendingPayload() {
        return active && packet != null &&
            (awaiting == 1 || offset < packet.size() || (command != null && awaiting != 2));
    }

    function scheduleAfterChunk() {
        if (offset < packet.size()) {

            send();
        } else if (command != null) {
            ScoutLog.println("KP" + purpose + ":" + packet.size() +
                ":" + chunkCallbacksMissed + ":" + busyRetries +
                ":" + (System.getTimer() - payloadStartMs) + ":" + chunksWithResponse +
                ":command");
            if (settleMode == 1) {
                ScoutClock.get().schedule("keksWrite", SETTLE_MS, method(:send));
            } else if (settleMode != 2 || !ping()) {
                send();
            }
        } else {
            finishTransaction();
        }
    }

    function finishTransaction() {
        var label = purpose;
        ScoutLog.println("KP" + label + ":" + (packet == null ? 0 : packet.size()) +
            ":" + chunkCallbacksMissed + ":" + (System.getTimer() - payloadStartMs) +
            ":" + chunksWithResponse);
        packet = null;
        ScoutView.onKeksPayloadSent(label);
        startNext();
    }

    function fail(reason) {
        var label = purpose;
        cancel();
        ScoutView.onWriteFailed(label, reason);
    }
}


class ScoutKeksMathListener {
    function initialize() { }
    function onDone(action, task) { ScoutView.onKeksMathComplete(action, task); }
}

class ScoutKeksWatchdog {
    function initialize() { }
    function start(delayMs) { ScoutClock.get().schedule("keksWatchdog", delayMs, method(:onTimeout)); }
    function stop() { ScoutClock.get().cancel("keksWatchdog"); }
    function onTimeout() { ScoutView.onFreshKeksTimeout(); }
}

class ScoutView extends WatchUi.View {
    static var scanning = false;
    static var backlightController = new ScoutBacklightController();

    static function lightBacklight() {
        backlightController.light();
    }
    static var scanStatus = "ENTER: SCAN";
    static var deviceCount = 0;
    static var seenResults = [];
    static var deviceNames = [];
    static var deviceRssi = [];
    static var deviceHits = [];





    static var targetName = "";
    static var TARGET_NAME_UPPER = "";
    static var targetBound = false;







    static const ALTERNATE_WAIT_MS = 12000;
    static const PASS_OVER_SPAN_MS = 60000;


    static const WRONG_NAMES_KEY = "g7WrongNames2";
    static var seenCandidates = [];
    static var lastTriedName = "";
    static var passedOverMs = null;
    static var lookedForOthers = false;
    static var lastWrongSkip = "";
    static var lastKeySkip = "";
    static var wrongNames = null;





    static const RESCAN_AFTER_FAILURE_MS = 50;
    static const SCAN_ERROR_RETRY_MS = 1000;
    static const MAX_FAST_SCAN_ERRORS = 3;
    static const RETRY_DELAY_MS = 240000;
    static var scanErrorCount = 0;
    static var instantConnectFailures = 0;







    static const G7_WAKE_PERIOD_MS = 300000;
    static const WAKE_LEAD_MS = 20000;
    static const WAKE_LATE_MS = 60000;
    static const SAME_WAKE_SCAN_MS = 30000;
    static const MAX_MISSED_WAKES = 3;
    static const WAKE_ANCHOR_MAX_MS = 1800000;
    static var lastWakeMs = null;
    static var missedWakes = 0;
    static var sessionGotReading = false;
    static var pendingScanWindowMs = 0;


    static var UUID_FEBC = Ble.stringToUuid("0000FEBC-0000-1000-8000-00805F9B34FB");
    static var UUID_CONTROL = Ble.stringToUuid("F8083534-849E-531C-C594-30F1F86A4EA5");
    static var UUID_AUTH = Ble.stringToUuid("F8083535-849E-531C-C594-30F1F86A4EA5");
    static var UUID_EXTRA = Ble.stringToUuid("F8083538-849E-531C-C594-30F1F86A4EA5");
    static var G7_SERVICE = Ble.stringToUuid("F8083532-849E-531C-C594-30F1F86A4EA5");
    static var targetScanResult = null;

    static function shortUuid(uuid) {
        if (UUID_EXTRA.equals(uuid)) { return "EXTRA"; }
        if (UUID_AUTH.equals(uuid)) { return "AUTH"; }
        if (UUID_CONTROL.equals(uuid)) { return "CONTROL"; }
        return uuid.toString().substring(4, 8);
    }
    static var targetRssi = 0;
    static var awaitingConnect = false;
    static var connectionAttempted = false;
    static var connectionInFlight = false;
    static var connectionAttemptNumber = 0;
    static var maxConnectionAttempts = 2;
    static var connectionWatchdog = new ScoutConnectionWatchdog();
    static var connectionTimerPurpose = "NONE";
    static var retryScanActive = false;
    static var device = null;
    static var bondAttempted = false;
    static var authIndicationsRequested = false;
    static var authRequestSent = false;
    static var authProbeResponseSeen = false;


    static var savedAuthDisplayType = 0;
    static var authProbeWatchdog = new ScoutAuthProbeWatchdog();
    static var controlIndicationsRequested = false;
    static var extraDataIndicationsRequested = false;
    static var g7Authenticated = false;
    static var g7Bonded = false;
    static var sessionTerminal = false;
    static var sessionTerminalReason = "NONE";
    static var freshKeksState = "OFF";
    static var keksMath = null;


    static var keksPassword = null;
    static var keksX1 = null;
    static var keksX2 = null;
    static var keksLocal1 = null;
    static var keksLocal2 = null;
    static var keksLocal3 = null;
    static var keksRemote1 = null;
    static var keksRemote2 = null;
    static var keksRemote3 = null;
    static var keksPrepTask = null;
    static var keksFinishStarted = false;
    static var keksPendingSend = 0;
    static var keksPendingAuthReply = null;
    static var keksAuthRequestSent = false;
    static var freshKeksSharedKey = null;
    static var freshKeksAuthToken = null;
    static var freshKeksPartA = null;
    static var freshKeksPartB = null;
    static var freshKeksPartC = null;
    static var freshKeksPrivateScalar = null;

    static var keksRxBuffer = null;
    static var keksRxCount = 0;


    static var keksRoundRxFirstAtMs = -1;

    static var keksRoundAckAtMs = -1;


    static var connectedAtMs = 0;
    static var lastAbortConnectMs = -1;

    static var dashboardShown = false;


    static var lastSensorClockSeconds = -1;
    static var lastSensorClockAtMs = 0;


    static const DEBUG_LINES = 10;
    static var debugLines = new [DEBUG_LINES];
    static var debugNext = 0;

    static function noteDebug(text) {
        var t = System.getClockTime();
        debugLines[debugNext] = twoDigits(t.hour) + ":" + twoDigits(t.min) + ":" +
            twoDigits(t.sec) + " " + text;
        debugNext = (debugNext + 1) % DEBUG_LINES;
    }

    static function debugLine(i) {
        return debugLines[(debugNext - 1 - i + 2 * DEBUG_LINES) % DEBUG_LINES];
    }



    static var g7DisplayType = 0x02;
    static var slotPolicy = "watch-probe";
    static var extraDataCccdReady = false;
    static var authCccdReady = false;
    static var keksWriteScheduler = new ScoutKeksWriteScheduler();
    static var keksWatchdog = new ScoutKeksWatchdog();
    static var glucoseHasValue = false;
    static var glucoseValue = -1;
    static var glucoseAgeSeconds = -1;
    static var glucoseAlgorithmState = -1;
    static var glucoseSequence = -1;
    static var previousGlucoseValue = -1;

    static var glucoseTrendDirection = 0;
    static var glucoseReceivedAtMs = -1;

    static var profilesRegistered = 0;
    static var profilesReady = false;
    static var profileRegistrationFailed = false;
    static var profileRegistrationFailureReason = "NONE";
    static var profileRegistrationWatchdog = new ScoutProfileRegistrationWatchdog();


    static var manualBondProbeEnabled = false;
    static var delegate = new ScoutBleDelegate();

    static function initializeGattProfiles() {
        Ble.setDelegate(delegate);
        profilesRegistered = 0;
        profilesReady = false;
        profileRegistrationFailed = false;
        profileRegistrationFailureReason = "NONE";
        profileRegistrationWatchdog.start(10000);
        ScoutLog.println("PS2:10000");
        try {
            var cccd = Ble.cccdUuid();


            Ble.registerProfile({
                :uuid => Ble.stringToUuid("F8083532-849E-531C-C594-30F1F86A4EA5"),
                :characteristics => [



                    { :uuid => Ble.stringToUuid("F8083533-849E-531C-C594-30F1F86A4EA5"), :descriptors => [] },
                    { :uuid => Ble.stringToUuid("F8083534-849E-531C-C594-30F1F86A4EA5"), :descriptors => [cccd] },
                    { :uuid => Ble.stringToUuid("F8083535-849E-531C-C594-30F1F86A4EA5"), :descriptors => [cccd] },
                    { :uuid => Ble.stringToUuid("F8083536-849E-531C-C594-30F1F86A4EA5"), :descriptors => [cccd] },
                    { :uuid => Ble.stringToUuid("F8083538-849E-531C-C594-30F1F86A4EA5"), :descriptors => [cccd] }
                ]
            });
            Ble.registerProfile({
                :uuid => Ble.stringToUuid("F8084532-849E-531C-C594-30F1F86A4EA5"),
                :characteristics => [
                    { :uuid => Ble.stringToUuid("F8084533-849E-531C-C594-30F1F86A4EA5"), :descriptors => [] },
                    { :uuid => Ble.stringToUuid("F8084534-849E-531C-C594-30F1F86A4EA5"), :descriptors => [] }
                ]
            });
            ScoutLog.println("PQ2");
        } catch (exception) {
            profileRegistrationFailed = true;
            profileRegistrationFailureReason = "EXCEPTION";
            profileRegistrationWatchdog.stop();
            scanStatus = "PROFILE ERR";
            ScoutLog.println("PX" + exception);
        }
    }

    static function onProfileRegistrationTimeout() {
        if (profilesReady || profileRegistrationFailed) {
            return;
        }
        profileRegistrationFailed = true;
        profileRegistrationFailureReason = "TIMEOUT";
        scanStatus = "PROFILE T/O";
        ScoutLog.println("PT" + profilesRegistered +
            ":2:" + (targetScanResult != null));
        if (awaitingConnect && targetScanResult != null) {
            awaitingConnect = false;
            retryScanActive = true;
            connectionTimerPurpose = "RETRY_DELAY";
            connectionWatchdog.start(240000);
            ScoutLog.println("AAprofile-registration-timeout:240");
        }
        WatchUi.requestUpdate();
    }

    static function startScan(resetAttemptCount, isAutomaticRetry, reason) {


        if (sessionTerminal) {
            scanStatus = "NO SESSION";
            ScoutLog.println("SBsensor-reported-terminal-state:" + sessionTerminalReason);
            return;
        }
        if (device != null && device.isConnected()) {
            scanStatus = "CONNECTED";
            ScoutLog.println("SAalready-connected");
            return;
        }


        if (!isUsablePairingCode(getConfiguredPairingCode())) {
            scanStatus = "NO CODE";
            retryScanActive = false;
            ScoutLog.println("SAno-pairing-code:" + reason);
            return;
        }
        if (!ScoutCollector.isWatch()) {
            scanStatus = "PHONE HAS G7";
            retryScanActive = false;
            ScoutLog.println("CBphone-collector:" + reason);
            return;
        }

        if (scanning || connectionInFlight ||
            (device != null && device.isConnected())) {
            return;
        }
        if (!targetBound && targetName.length() > 0) {
            var released = targetName;
            targetName = "";
            TARGET_NAME_UPPER = "";
            var unpaired = unpairAllDevices();
            ScoutLog.println("DX" + released +
                ":" + seenCandidates.size() + ":" + unpaired);
        }
        if (resetAttemptCount) {
            connectionAttemptNumber = 0;
        }

        seenResults = [];
        deviceNames = [];
        deviceRssi = [];
        deviceHits = [];
        deviceCount = 0;
        targetScanResult = null;
        targetRssi = 0;
        awaitingConnect = false;
        connectionAttempted = false;
        connectionInFlight = false;
        device = null;
        bondAttempted = false;
        g7Authenticated = false;
        g7Bonded = false;


        retryScanActive = isAutomaticRetry;
        scanStatus = isAutomaticRetry ? "RESCANNING" : "SCANNING";

        connectionTimerPurpose = "NONE";
        ScoutLog.println("SS" + reason + ":" + isAutomaticRetry + ":until-target");
        try {
            Ble.setDelegate(delegate);
            Ble.setScanState(Ble.SCAN_STATE_SCANNING);
        } catch (exception) {
            scanning = false;
            retryScanActive = true;
            var retryMs = scanErrorRetryMs();
            connectionTimerPurpose = "RETRY_DELAY";
            connectionWatchdog.start(retryMs);
            scanStatus = "SCAN ERROR";
            ScoutLog.println("SY" + exception + ":" + retryMs);
        }
    }

    static function loadTargetBinding() {
        var stored = null;
        try { stored = Application.Storage.getValue("g7DeviceName"); } catch (e) { stored = null; }
        var code = getConfiguredPairingCode();
        if (stored instanceof Lang.String && stored.length() >= 5 && stored.substring(0, 4).toUpper().equals("DXCM")) {
            targetName = stored;
        } else {
            targetName = "";
        }
        targetBound = targetName.length() > 0;
        TARGET_NAME_UPPER = targetName.toUpper();
        seenCandidates = loadSeenNames(code);


        var lastTried = null;
        try { lastTried = Application.Storage.getValue("g7LastTriedName"); } catch (e) { lastTried = null; }
        lastTriedName = lastTried instanceof Lang.String ? lastTried : "";
        passedOverMs = null;
        lookedForOthers = false;
        lastWrongSkip = "";
        wrongNames = null;
        ScoutLog.println("DB" + targetBound);
    }

    static function onTargetFound(scanResult, name, rssi) {
        lastWakeMs = System.getTimer();
        missedWakes = 0;
        targetScanResult = scanResult;
        targetRssi = rssi;
        lightBacklight();
        retryScanActive = false;
        awaitingConnect = true;
        scanStatus = "G7 FOUND";
        ScoutLog.println("TS:" + rssi);
        noteDebug("SEEN " + rssi + "dBm");
        connectionTimerPurpose = "NONE";
        Ble.setScanState(Ble.SCAN_STATE_OFF);



        connectTarget();
    }


    static function scanErrorRetryMs() {
        scanErrorCount += 1;
        return scanErrorCount <= MAX_FAST_SCAN_ERRORS ? SCAN_ERROR_RETRY_MS : RETRY_DELAY_MS;
    }




    static function offerUnboundCandidate(scanResult, name, rssi) {
        if (targetScanResult != null || connectionAttempted || name == null) { return; }
        var upper = name.toUpper();


        var keyName = ScoutPhoneLink.keyNameUpper();
        if (keyName.length() > 0 && !upper.equals(keyName)) {
            if (!upper.equals(lastKeySkip)) {
                lastKeySkip = upper;
                ScoutLog.println("DK");
            }
            return;
        }
        if (isWrongName(upper)) {
            if (!upper.equals(lastWrongSkip)) {
                lastWrongSkip = upper;
                ScoutLog.println("DW");
            }
            return;
        }
        if (seenCandidates.indexOf(upper) < 0) {
            seenCandidates.add(upper);
            saveSeenNames();
        }






        if (keyName.length() == 0 && upper.equals(lastTriedName) && (seenCandidates.size() > 1 || !lookedForOthers)) {



            if (passedOverMs == null || System.getTimer() - passedOverMs > PASS_OVER_SPAN_MS) {
                passedOverMs = System.getTimer();
                ScoutLog.println("DA:" + ALTERNATE_WAIT_MS);
                return;
            }
            if (System.getTimer() - passedOverMs < ALTERNATE_WAIT_MS) { return; }
            if (seenCandidates.size() == 1) { lookedForOthers = true; }
        }
        passedOverMs = null;
        lastTriedName = upper;
        try { Application.Storage.setValue("g7LastTriedName", upper); } catch (e) { }
        targetName = name;
        TARGET_NAME_UPPER = upper;
        ScoutLog.println("DC");
        noteDebug("TRY " + name);
        onTargetFound(scanResult, name, rssi);
    }


    static const SEEN_NAMES_KEY = "g7SeenNames";
    static const MAX_SEEN_NAMES = 4;

    static function loadSeenNames(code) {
        var stored = null;
        try { stored = Application.Storage.getValue(SEEN_NAMES_KEY); } catch (e) { stored = null; }
        if (stored instanceof Lang.Array && stored.size() == 2 && code.equals(stored[0]) &&
                stored[1] instanceof Lang.Array) {
            return stored[1];
        }
        return [];
    }

    static function saveSeenNames() {
        while (seenCandidates.size() > MAX_SEEN_NAMES) { seenCandidates.remove(seenCandidates[0]); }
        try { Application.Storage.setValue(SEEN_NAMES_KEY, [getConfiguredPairingCode(), seenCandidates]); } catch (e) { }
    }

    static function wrongNameList() {
        var code = getConfiguredPairingCode();
        if (wrongNames == null || !code.equals(wrongNames[0])) {
            var stored = null;
            try { stored = Application.Storage.getValue(WRONG_NAMES_KEY); } catch (e) { stored = null; }
            wrongNames = (stored instanceof Lang.Array && stored.size() == 2 && code.equals(stored[0]) &&
                stored[1] instanceof Lang.Array) ? stored : [code, []];
        }
        return wrongNames[1];
    }

    static function isWrongName(upper) {
        return wrongNameList().indexOf(upper) >= 0;
    }


    static function markWrongName() {
        if (targetBound || TARGET_NAME_UPPER.length() == 0) { return; }
        var list = wrongNameList();
        if (list.indexOf(TARGET_NAME_UPPER) < 0) {
            list.add(TARGET_NAME_UPPER);
            try { Application.Storage.setValue(WRONG_NAMES_KEY, wrongNames); } catch (e) { }
        }
        seenCandidates.remove(TARGET_NAME_UPPER);
        saveSeenNames();
        ScoutLog.println("DN:" + list.size());
        noteDebug("NOT " + targetName);
    }


    static function unpairAllDevices() {
        var unpaired = 0;
        try {
            var paired = Ble.getPairedDevices();
            for (var d = paired.next(); d != null; d = paired.next()) {
                Ble.unpairDevice(d as Ble.Device);
                unpaired += 1;
            }
        } catch (e) {
            ScoutLog.println("DU" + e);
        }
        return unpaired;
    }

    static function bindTargetDevice(source) {
        if (targetName.length() == 0) { return; }
        var stored = null;
        try { stored = Application.Storage.getValue("g7DeviceName"); } catch (e) { stored = null; }
        if (stored instanceof Lang.String && stored.equals(targetName)) { return; }
        try { Application.Storage.setValue("g7DeviceName", targetName); } catch (e2) { return; }
        targetBound = true;
        var code = getConfiguredPairingCode();
        ScoutLog.println("DD");
        noteDebug("BOUND " + targetName);
    }


    static function stopForPhoneCollector() {
        if (scanning) {
            try { Ble.setScanState(Ble.SCAN_STATE_OFF); } catch (e) { }
        }
        var released = (device != null && device.isConnected()) ? unpairAllDevices() : 0;
        device = null;
        targetScanResult = null;
        connectionInFlight = false;
        connectionAttempted = false;
        awaitingConnect = false;
        retryScanActive = false;
        connectionTimerPurpose = "NONE";
        scanStatus = "PHONE HAS G7";
        ScoutLog.println("CBphone-collector:released-" + released);
    }



    static function forgetTargetDevice() {
        try { Application.Storage.deleteValue("g7DeviceName"); } catch (e) { }
        var unpaired = unpairAllDevices();
        if (scanning) {
            try { Ble.setScanState(Ble.SCAN_STATE_OFF); } catch (e3) { }
        }
        device = null;
        targetScanResult = null;
        connectionInFlight = false;
        connectionAttempted = false;
        awaitingConnect = false;
        retryScanActive = false;
        connectionTimerPurpose = "NONE";
        ScoutLog.println("DF" + unpaired);
        noteDebug("FORGOT G7");
        loadTargetBinding();
    }

    static function connectTarget() {
        if (sessionTerminal) {
            scanStatus = "NO SESSION";
            ScoutLog.println("CAsensor-reported-terminal-state:" + sessionTerminalReason);
            return;
        }

        if (!isUsablePairingCode(getConfiguredPairingCode())) {
            scanStatus = "NO CODE";
            awaitingConnect = false;
            retryScanActive = false;
            if (scanning) { Ble.setScanState(Ble.SCAN_STATE_OFF); }
            ScoutLog.println("CAno-pairing-code");
            return;
        }
        if (!ScoutCollector.isWatch()) {
            scanStatus = "PHONE HAS G7";
            awaitingConnect = false;
            retryScanActive = false;
            if (scanning) { Ble.setScanState(Ble.SCAN_STATE_OFF); }
            ScoutLog.println("CBphone-collector:connect");
            return;
        }
        if (connectionAttempted || connectionInFlight) {
            ScoutLog.println("CSattempt-already-made:" + connectionInFlight);
            return;
        }
        if (targetScanResult == null) {
            scanStatus = "G7 NOT FOUND";
            ScoutLog.println("CAtarget-not-seen");
            return;
        }
        if (!profilesReady) {
            if (profileRegistrationFailed) {
                awaitingConnect = false;
                retryScanActive = true;
                scanStatus = "PROFILE ERR";
                connectionTimerPurpose = "RETRY_DELAY";
                connectionWatchdog.start(240000);
                ScoutLog.println("CAprofile-registration-failed:240");
            } else {
                awaitingConnect = true;
                scanStatus = "WAIT PROFILE";
                ScoutLog.println("CDfalse:on-profile-callback");
            }
            return;
        }
        awaitingConnect = false;
        retryScanActive = false;
        connectionAttemptNumber += 1;
        connectionAttempted = true;
        connectionInFlight = true;
        scanStatus = "CONNECT " + connectionAttemptNumber;
        connectionTimerPurpose = "CONNECT";




        connectionWatchdog.start(30000);
        ScoutLog.println("CQ:" + connectionAttemptNumber);
        try {
            Ble.setConnectionStrategy(Ble.CONNECTION_STRATEGY_DEFAULT);
            Ble.setDelegate(delegate);
            device = Ble.pairDevice(targetScanResult);
            if (device == null) {
                ScoutLog.println("CNtrue:" + connectionAttemptNumber);
                handleConnectFailure("RETURN_NULL");
            } else {
                ScoutLog.println("CNfalse:" + device.isConnected() +
                    ":" + connectionAttemptNumber +
                    ":connected-false-is-pending-until-callback");
                if (device.isConnected()) {
                    markConnected(device, "PAIR_RETURN_CONNECTED");
                }
            }
        } catch (exception) {
            ScoutLog.println("CX" + connectionAttemptNumber + ":" + exception);
            handleConnectFailure("EXCEPTION");
        }
    }

    static function onConnectionTimer() {
        var purpose = connectionTimerPurpose;
        connectionTimerPurpose = "NONE";

        if (purpose.equals("CONNECT")) {
            if (!connectionInFlight) {
                return;
            }
            if (device != null && device.isConnected()) {
                markConnected(device, "WATCHDOG_CHECK");
            } else {
                handleConnectFailure("TIMEOUT_NO_CALLBACK");
            }
        } else if (purpose.equals("RETRY_DELAY")) {
            var windowMs = pendingScanWindowMs;
            pendingScanWindowMs = 0;
            if (retryScanActive && !connectionInFlight &&
                (device == null || !device.isConnected())) {
                startScan(false, true, "retry");
                startScanWindow("SAME_WAKE_END", windowMs);
            }
        } else if (purpose.equals("WAKE_WAIT")) {
            if (!connectionInFlight && (device == null || !device.isConnected())) {
                startScan(false, true, "next-wake");
                startScanWindow("WAKE_SCAN_END", WAKE_LEAD_MS + WAKE_LATE_MS);
            }
        } else if (purpose.equals("SAME_WAKE_END") || purpose.equals("WAKE_SCAN_END")) {
            if (targetScanResult == null && !connectionInFlight &&
                (device == null || !device.isConnected())) {
                endScanWindow(purpose.equals("WAKE_SCAN_END"));
            }
        }
        WatchUi.requestUpdate();
    }


    static function startScanWindow(purpose, windowMs) {
        if (windowMs > 0 && connectionTimerPurpose.equals("NONE") && !connectionInFlight) {
            connectionTimerPurpose = purpose;
            connectionWatchdog.start(windowMs);
        }
    }

    static function handleConnectFailure(reason) {
        connectionInFlight = false;
        connectionAttempted = false;
        awaitingConnect = false;
        device = null;
        retryScanActive = false;

        targetScanResult = null;
        targetRssi = 0;
        scanStatus = "CONN FAILED";
        retryScanActive = true;
        var retryMs = RESCAN_AFTER_FAILURE_MS;
        if (reason.equals("RETURN_NULL") || reason.equals("EXCEPTION")) {
            instantConnectFailures += 1;
            retryMs = instantConnectFailures <= MAX_FAST_SCAN_ERRORS ? SCAN_ERROR_RETRY_MS : RETRY_DELAY_MS;
        }
        ScoutLog.println("CF" + reason + ":" + connectionAttemptNumber +
            ":" + retryMs);
        noteDebug(reason.equals("TIMEOUT_NO_CALLBACK") ? "CONN TIMEOUT" : "CONN FAIL");
        
        if (retryMs == RESCAN_AFTER_FAILURE_MS) {
            rescanAfterSession(false);
        } else {
            connectionTimerPurpose = "RETRY_DELAY";
            connectionWatchdog.start(retryMs);
        }
    }



    static function rescanAfterSession(gotReading) {
        if (gotReading && targetBound && scheduleNextWake()) { return; }
        pendingScanWindowMs = (targetBound && wakeAnchored()) ? SAME_WAKE_SCAN_MS : 0;
        connectionTimerPurpose = "RETRY_DELAY";
        connectionWatchdog.start(RESCAN_AFTER_FAILURE_MS);
    }

    static function wakeAnchored() {
        return lastWakeMs != null && System.getTimer() - lastWakeMs < WAKE_ANCHOR_MAX_MS;
    }


    static function scheduleNextWake() {
        if (!wakeAnchored()) { return false; }
        var now = System.getTimer();
        var next = lastWakeMs + G7_WAKE_PERIOD_MS;
        while (next - WAKE_LEAD_MS - now <= 0) { next += G7_WAKE_PERIOD_MS; }
        var waitMs = next - WAKE_LEAD_MS - now;
        retryScanActive = true;
        connectionTimerPurpose = "WAKE_WAIT";
        connectionWatchdog.start(waitMs);
        ScoutLog.println("WW" + waitMs +
            ":" + (now - lastWakeMs) + ":" + missedWakes);
        return true;
    }

    static function endScanWindow(wakeScan) {
        if (wakeScan) { missedWakes += 1; }
        if (wakeScan && missedWakes >= MAX_MISSED_WAKES) {
            ScoutLog.println("WL" + missedWakes + ":scan-until-seen");
            lastWakeMs = null;
            missedWakes = 0;
            return;
        }
        if (!wakeAnchored()) { return; }
        try { Ble.setScanState(Ble.SCAN_STATE_OFF); } catch (e) { }
        scanning = false;
        scheduleNextWake();
    }


    static function onBoundScanResult(scanResult, name) {
        if (name == null || name.length() != TARGET_NAME_UPPER.length() ||
            !name.toUpper().equals(TARGET_NAME_UPPER)) {
            return;
        }
        var rssi = scanResult.getRssi();
        if (targetScanResult != null) {
            targetRssi = rssi;
            return;
        }
        if (connectionAttempted) { return; }
        ScoutLog.println("SE:" + rssi);
        onTargetFound(scanResult, name, rssi);
    }

    static function markConnected(connectedDevice, source) {
        connectedAtMs = System.getTimer();
        instantConnectFailures = 0;
        sessionGotReading = false;
        if (lastWakeMs == null || connectedAtMs - lastWakeMs > SAME_WAKE_SCAN_MS) {
            lastWakeMs = connectedAtMs;
            missedWakes = 0;
        }
        connectionTimerPurpose = "NONE";
        connectionInFlight = false;
        connectionAttempted = true;
        awaitingConnect = false;
        retryScanActive = false;
        device = connectedDevice;
        bondAttempted = false;
        authIndicationsRequested = false;
        extraDataCccdReady = false;
        authCccdReady = false;
        keksWriteScheduler.cancel();
        mathRunner().cancel();
        keksWatchdog.stop();
        freshKeksState = "OFF";
        clearFreshKeksSecrets();
        authRequestSent = false;
        authProbeResponseSeen = false;
        savedAuthDisplayType = 0;
        authProbeWatchdog.stop();
        controlIndicationsRequested = false;
        extraDataIndicationsRequested = false;
        g7Authenticated = false;
        g7Bonded = false;



        if (scanning) {
            Ble.setScanState(Ble.SCAN_STATE_OFF);
        }
        scanning = false;
        scanStatus = "CONNECTED";
        ScoutLog.println("CC" + source +
            ":" + targetName + ":" + connectionAttemptNumber);
        noteDebug("CONNECTED #" + connectionAttemptNumber);
        describeGatt(connectedDevice);




        enableCharacteristicIndications(connectedDevice, UUID_EXTRA, "EXTRA", 0x01);
    }

    static function enableCharacteristicIndications(connectedDevice, characteristicUuid, label, cccdValue) {
        if (label.equals("AUTH")) {
            if (authIndicationsRequested) { return; }
            authIndicationsRequested = true;
        } else if (label.equals("CONTROL")) {
            if (controlIndicationsRequested) { return; }
            controlIndicationsRequested = true;
        } else if (label.equals("EXTRA")) {
            if (extraDataIndicationsRequested) { return; }
            extraDataIndicationsRequested = true;
        }
        try {
            var characteristic = findCharacteristic(characteristicUuid);
            if (characteristic == null) {
                ScoutLog.println("WC" + label + ":" + shortUuid(characteristicUuid));
                return;
            }
            var cccd = characteristic.getDescriptor(Ble.cccdUuid());
            if (cccd == null) {
                ScoutLog.println("WM" + label + ":" + shortUuid(characteristicUuid));
                return;
            }
            ScoutLog.println("WQ" + label + ":" + cccdValue);
            cccd.requestWrite([cccdValue, 0x00]b);
        } catch (exception) {
            ScoutLog.println("WX" + label + ":" + exception);
        }
    }




    static function runCryptoSelfTest() {
        var started = System.getTimer();
        var shaOk = false;
        var aesOk = false;
        try {
            var hash = new Cryptography.Hash({ :algorithm => Cryptography.HASH_SHA256 });
            hash.update([]b);
            shaOk = bytesToHex(hash.digest()).equals(
                "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855");
        } catch (eSha) {
            ScoutLog.println("XS" + eSha);
        }
        try {
            var key = [0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,
                0x08,0x09,0x0A,0x0B,0x0C,0x0D,0x0E,0x0F]b;
            var plain = [0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,
                0x88,0x99,0xAA,0xBB,0xCC,0xDD,0xEE,0xFF]b;
            var cipher = new Cryptography.Cipher({
                :algorithm => Cryptography.CIPHER_AES128,
                :mode => Cryptography.MODE_ECB,
                :key => key
            });
            aesOk = bytesToHex(cipher.encrypt(plain)).equals("69C4E0D86A7B0430D8CDB78070B4C55A");
        } catch (eAes) {
            ScoutLog.println("XA" + eAes);
        }

        ScoutLog.println("EC");
        var nativeStatus = KeksP256.calibrateNative();
        ScoutLog.println("CT" + shaOk +
            ":" + aesOk + ":" + nativeStatus +
            ":" + (System.getTimer() - started) +
            ":" + KeksMathRunner.tickBudget() +
            ":" + System.getDeviceSettings().partNumber);
    }









    static const SLOT_RETRY_S = 24 * 3600;
    static const SLOT_REFUSED_AT_KEY = "g7SlotRefusedAt";

    static function loadSlotPolicy() {
        var stored = null;
        try { stored = Application.Storage.getValue("g7SlotPolicy"); } catch (e) { stored = null; }
        slotPolicy = (stored != null && (stored.equals("watch") || stored.equals("phone"))) ? stored : "watch-probe";
        g7DisplayType = policyDisplayType();
        ScoutLog.println("SP" + slotPolicy +
            ":" + g7DisplayType);
        retryWatchSlotIfDue();
    }


    static function retryWatchSlotIfDue() {
        if (!slotPolicy.equals("phone")) { return; }
        var at = null;
        try { at = Application.Storage.getValue(SLOT_REFUSED_AT_KEY); } catch (e) { at = null; }
        var legacy = !(at instanceof Lang.Number);
        if (!legacy && Time.now().value() - at < SLOT_RETRY_S) { return; }
        resetSlotPolicy(legacy ? "retry-no-refusal-recorded" : "retry-after-24h");
    }

    static function resetSlotPolicy(reason) {
        try { Application.Storage.deleteValue("g7SlotPolicy"); } catch (e) { }
        try { Application.Storage.deleteValue(SLOT_REFUSED_AT_KEY); } catch (e2) { }
        if (slotPolicy.equals("watch-probe")) { return; }
        slotPolicy = "watch-probe";
        g7DisplayType = policyDisplayType();
        ScoutLog.println("SG" + slotPolicy +
            ":" + g7DisplayType + ":" + reason);
    }



    static const SLOT_FORCE_KEY = "g7SlotForce";
    static var forcedSlot = null;

    static function forcedDisplayType() {
        if (forcedSlot == null) {
            var stored = null;
            try { stored = Application.Storage.getValue(SLOT_FORCE_KEY); } catch (e) { stored = null; }
            forcedSlot = (stored instanceof Lang.String && (stored.equals("02") || stored.equals("03"))) ? stored : "auto";
        }
        return forcedSlot.equals("02") ? 0x02 : (forcedSlot.equals("03") ? 0x03 : 0);
    }

    static function policyDisplayType() {
        if (ScoutCollector.isBoth()) { return 0x03; }
        var forced = forcedDisplayType();
        if (forced != 0) { return forced; }
        return slotPolicy.equals("phone") ? 0x02 : 0x03;
    }

    static function onPhoneSlot(choice) {
        if (!(choice instanceof Lang.String) || !(choice.equals("auto") || choice.equals("02") || choice.equals("03"))) {
            ScoutLog.println("SOformat:" + g7DisplayType);
            return;
        }
        try { Application.Storage.setValue(SLOT_FORCE_KEY, choice); } catch (e) { }
        forcedSlot = choice;
        applySlotChoice("phone-" + choice);
    }

    static function applySlotChoice(reason) {
        g7DisplayType = policyDisplayType();
        ScoutLog.println("SO" + forcedSlot + ":" + g7DisplayType + ":" + reason);
        noteDebug("SLOT " + g7DisplayType);
    }

    static function saveSlotPolicy(policy, reason) {
        if (slotPolicy.equals(policy)) { return; }
        slotPolicy = policy;
        g7DisplayType = policyDisplayType();
        try { Application.Storage.setValue("g7SlotPolicy", policy); } catch (e) { }
        if (policy.equals("phone")) {
            try { Application.Storage.setValue(SLOT_REFUSED_AT_KEY, Time.now().value()); } catch (e2) { }
        }
        ScoutLog.println("SG" + policy +
            ":" + g7DisplayType + ":" + reason);
    }

    static function mathRunner() {
        if (keksMath == null) {
            keksMath = new KeksMathRunner(new ScoutKeksMathListener().method(:onDone), "keksMath",
                keksWriteScheduler.method(:isSendingPayload));
        }
        return keksMath;
    }

    static function bytesEqual(a, b) {
        if (a == null || b == null || a.size() != b.size()) { return false; }
        for (var i = 0; i < a.size(); i += 1) {
            if ((a[i] & 0xFF) != (b[i] & 0xFF)) { return false; }
        }
        return true;
    }













    static var charExtra = null;
    static var charAuth = null;
    static var charControl = null;

    static function rememberCharacteristic(uuid, characteristic) {
        if (UUID_EXTRA.equals(uuid)) { charExtra = characteristic; }
        else if (UUID_AUTH.equals(uuid)) { charAuth = characteristic; }
        else if (UUID_CONTROL.equals(uuid)) { charControl = characteristic; }
    }

    static function forgetCharacteristics() {
        charExtra = null;
        charAuth = null;
        charControl = null;
    }

    static function findCharacteristic(characteristicUuid) {
        if (device == null || characteristicUuid == null) { return null; }
        var cached = UUID_EXTRA.equals(characteristicUuid) ? charExtra :
            (UUID_AUTH.equals(characteristicUuid) ? charAuth :
            (UUID_CONTROL.equals(characteristicUuid) ? charControl : null));
        if (cached != null) { return cached; }
        try {
            var services = device.getServices();
            for (var service = services.next(); service != null; service = services.next()) {
                var chars = service.getCharacteristics();
                for (var characteristic = chars.next(); characteristic != null; characteristic = chars.next()) {
                    if (characteristic.getUuid().equals(characteristicUuid)) {
                        rememberCharacteristic(characteristicUuid, characteristic);
                        return characteristic;
                    }
                }
            }
        } catch (exception) {
            return null;
        }
        return null;
    }





    static const DEFAULT_PAIRING_CODE = "----";
    static var pairingCode = null;
    static var pairingCodeStored = false;

    static function getConfiguredPairingCode() {
        if (pairingCode == null) {
            var stored = null;
            try { stored = Application.Storage.getValue("g7PairingCode"); } catch (e) { stored = null; }
            pairingCodeStored = isStorablePairingCode(stored);
            pairingCode = pairingCodeStored ? stored : DEFAULT_PAIRING_CODE;
        }
        return pairingCode;
    }

    static function isStorablePairingCode(code) {
        if (!(code instanceof Lang.String) || code.length() != 4) { return false; }
        var chars = code.toCharArray();
        for (var i = 0; i < chars.size(); i += 1) {
            if (chars[i] != '-' && (chars[i] < '0' || chars[i] > '9')) { return false; }
        }
        return true;
    }

    static function isUsablePairingCode(code) {
        return isStorablePairingCode(code) && code.find("-") == null;
    }



    static function savePairingCode(code) {
        if (!isStorablePairingCode(code)) { return false; }
        var previous = getConfiguredPairingCode();
        try {
            Application.Storage.setValue("g7PairingCode", code);
        } catch (e) {
            ScoutLog.println("PE" + e);
            return false;
        }
        pairingCode = code;
        pairingCodeStored = true;
        var changed = !code.equals(previous);
        if (changed) {
            try { Application.Storage.deleteValue("savedAuthKeyHex"); } catch (e2) { }
            try { Application.Properties.setValue("savedAuthKeyHex", ""); } catch (e3) { }
            try { Application.Storage.deleteValue("g7SlotPolicy"); } catch (e4) { }
            try { Application.Storage.deleteValue(WRONG_NAMES_KEY); } catch (e5) { }
            try { Application.Storage.deleteValue(ScoutPhoneLink.KEY_NAME_KEY); } catch (e6) { }
            ScoutPhoneLink.cachedKeyName = null;
            loadSlotPolicy();
            forgetTargetDevice();
            ScoutReadingSync.onCleared();
        }
        ScoutLog.println("PC" + changed + ":" + isUsablePairingCode(code));
        noteDebug("CODE SET");
        return true;
    }


    static function tryBeginConfiguredFreshKeks(source) {
        var code = getConfiguredPairingCode();
        if (!isUsablePairingCode(code) || !authCccdReady || !extraDataCccdReady ||
            device == null || !device.isConnected()) {
            return;
        }
        ScoutLog.println("KT" + source);
        beginFreshKeks(code);
    }




    static function configuredQrBytes(partName, maxBytes) {
        var value = null;
        if (partName.equals("A")) {
            value = ScoutKeksQrMaterial.partA();
        } else if (partName.equals("B")) {
            value = ScoutKeksQrMaterial.partB();
        } else if (partName.equals("C")) {
            value = ScoutKeksQrMaterial.partC();
        }
        if (value == null || value.size() == 0 || value.size() > maxBytes) {
            return null;
        }
        return value;
    }

    static function isFourDigitPairingCode(code) {
        if (code == null || code.length() != 4) { return false; }
        for (var i = 0; i < 4; i += 1) {
            var c = code.substring(i, i + 1);
            if (!c.equals("0") && !c.equals("1") && !c.equals("2") &&
                !c.equals("3") && !c.equals("4") && !c.equals("5") &&
                !c.equals("6") && !c.equals("7") && !c.equals("8") &&
                !c.equals("9")) { return false; }
        }
        return true;
    }

    static var freshKeksActive = false;



    static const MATH_TIMEOUT_MS = 60000;

    static function isFreshKeksActive() {
        return freshKeksActive;
    }

    static function keksClientParty() {
        return [0x63,0x6C,0x69,0x65,0x6E,0x74]b;
    }

    static function keksServerParty() {
        return [0x73,0x65,0x72,0x76,0x65,0x72]b;
    }











    static function beginFreshKeks(code) {
        if (!extraDataCccdReady || !authCccdReady || device == null || !device.isConnected()) {
            scanStatus = "SUBS NOT RDY";
            ScoutLog.println("KNsubscriptions-not-ready");
            return;
        }
        if (!isFourDigitPairingCode(code)) {
            scanStatus = "BAD PAIRCODE";
            ScoutLog.println("KNpairing-code-format");
            return;
        }
        if (!KeksP256.nativeReady) {
            scanStatus = "NO NATIVE EC";
            ScoutLog.println("KNnative-ec-calibration-failed");
            return;
        }
        var partA = configuredQrBytes("A", 4096);
        var partB = configuredQrBytes("B", 4096);
        var partC = configuredQrBytes("C", 4096);
        if (partA == null || partB == null || partC == null ||
            partA.size() <= 100 || partB.size() <= 100 || partC.size() <= 32) {
            scanStatus = "NEED QR DATA";
            ScoutLog.println("KNsetup-qr-material-missing-or-invalid");
            return;
        }



        var privateScalar = KeksP256.extractPrivateScalarPkcs8(partC);
        var x1 = KeksP256.randomScalar();
        var x2 = KeksP256.randomScalar();
        var v1 = KeksP256.randomScalar();
        var v2 = KeksP256.randomScalar();
        if (privateScalar == null || x1 == null || x2 == null || v1 == null || v2 == null) {
            scanStatus = "SETUP FAILED";
            ScoutLog.println("KNscalar-setup");
            return;
        }
        clearFreshKeksSecrets();
        keksPassword = KeksP256.passwordInteger(code);
        keksX1 = x1;
        keksX2 = x2;
        freshKeksPartA = partA;
        freshKeksPartB = partB;
        freshKeksPartC = partC;
        freshKeksPrivateScalar = privateScalar;
        authProbeWatchdog.stop();
        freshKeksActive = true;
        keksRoundRxFirstAtMs = -1;
        keksRoundAckAtMs = -1;
        freshKeksState = "WAIT_ROUND1";
        scanStatus = "KEKS R1";
        var runner = mathRunner();
        runner.cancel();
        runner.enqueue(new KeksMakeRound12Task(x1, v1, keksClientParty()), "LOCAL_ROUND1");
        runner.enqueue(new KeksMakeRound12Task(x2, v2, keksClientParty()), "LOCAL_ROUND2");
        ScoutKeksWriteScheduler.keksAttempts += 1;





        ScoutKeksWriteScheduler.chunksWithResponse = false;
        ScoutKeksWriteScheduler.settleMode = 0;
        ScoutLog.println("KB" + (pairingCodeStored ? "stored" : "default") +
            ":" + slotPolicy + "/" + g7DisplayType + ":" + ScoutKeksWriteScheduler.chunksWithResponse +
            ":" + ScoutKeksWriteScheduler.settleMode);


        queueKeks(null, [0x0A,0x00]b, "START_ROUND1");
        WatchUi.requestUpdate();
    }

    static function queueKeks(payload, commandBytes, label) {
        if (!keksWriteScheduler.queue(payload, commandBytes, label, UUID_AUTH)) {
            abortFreshKeks(label.toLower() + "-write-queue-full");
            return false;
        }
        return true;
    }

    static function onKeksPayloadSent(purpose) {
        if (freshKeksActive) { keksWatchdog.start(20000); }
    }

    static function onKeksCommandWritten(purpose, target) {
        if (target == UUID_CONTROL) {
            scanStatus = "AUTH OK";
            WatchUi.requestUpdate();
            return;
        }
        if (freshKeksActive) {
            var timeoutMs = purpose.equals("TIME_EXTENDED_AFTER_BOND_TRIGGER") ? 30000 : 20000;
            keksWatchdog.start(timeoutMs);
            ScoutLog.println("KW" + freshKeksState + ":" + timeoutMs +
                ":" + purpose);
        }
    }

    static function onWriteFailed(purpose, reason) {
        if (freshKeksActive) {
            abortFreshKeks("write-" + purpose.toLower() + "-" + reason);
        } else {
            ScoutLog.println("GF" + purpose +
                ":" + reason);
        }
    }

    static function onFreshKeksTimeout() {
        if (freshKeksActive) {
            abortFreshKeks("timeout-" + freshKeksState.toLower());
        }
    }

    static function onLinkLost() {
        forgetCharacteristics();
        keksWriteScheduler.cancel();
        if (freshKeksActive) { abortFreshKeks("link-lost"); }
    }




    static function beginSavedKeyCertificates() {
        var partA = configuredQrBytes("A", 4096);
        var partB = configuredQrBytes("B", 4096);
        var partC = configuredQrBytes("C", 4096);
        var privateScalar = (partC == null || partC.size() <= 32) ? null : KeksP256.extractPrivateScalarPkcs8(partC);
        if (partA == null || partB == null || partA.size() <= 100 || partB.size() <= 100 || privateScalar == null) {
            scanStatus = "NEED QR DATA";
            ScoutLog.println("KNsetup-qr-material-missing-or-invalid");
            return;
        }
        clearFreshKeksSecrets();
        freshKeksPartA = partA;
        freshKeksPartB = partB;
        freshKeksPartC = partC;
        freshKeksPrivateScalar = privateScalar;
        authProbeWatchdog.stop();
        freshKeksActive = true;
        ScoutLog.println("SF" + (System.getTimer() - connectedAtMs));
        noteDebug("SAVED CERTS");
        queueCertificateRequest(0, partA);
    }

    static function clearFreshKeksSecrets() {
        keksPassword = null;
        keksX1 = null;
        keksX2 = null;
        keksLocal1 = null;
        keksLocal2 = null;
        keksLocal3 = null;
        keksRemote1 = null;
        keksRemote2 = null;
        keksRemote3 = null;
        keksPrepTask = null;
        keksFinishStarted = false;
        keksPendingSend = 0;
        keksPendingAuthReply = null;
        keksAuthRequestSent = false;
        freshKeksSharedKey = null;
        freshKeksAuthToken = null;
        freshKeksPartA = null;
        freshKeksPartB = null;
        freshKeksPartC = null;
        freshKeksPrivateScalar = null;
        keksRxBuffer = null;
        keksRxCount = 0;
    }

    static function abortFreshKeks(reason) {


        var watchSlotFailed = freshKeksActive && keksAuthRequestSent && g7DisplayType == 0x03 &&
            (reason.equals("sensor-authentication-rejected") || reason.equals("sensor-auth-refresh-required"));


        var abortedState = freshKeksState;
        var rxBytes = keksRxCount;
        keksWatchdog.stop();
        keksWriteScheduler.cancel();
        mathRunner().cancel();
        freshKeksActive = false;
        freshKeksState = "ABORTED";
        clearFreshKeksSecrets();
        scanStatus = "KEKS ABORTED";
        ScoutLog.println("KA" + reason +
            ":" + abortedState + ":" + rxBytes +
            ":" + (System.getTimer() - connectedAtMs));
        lastAbortConnectMs = System.getTimer() - connectedAtMs;
        
        var shortState = abortedState.find("WAIT_") == 0 ?
            abortedState.substring(5, abortedState.length()) : abortedState;
        if (shortState.length() > 10) { shortState = shortState.substring(0, 10); }
        noteDebug("ABORT " + shortState + " " + lastAbortConnectMs);
        if (watchSlotFailed) { saveSlotPolicy("phone", "watch-slot-" + reason); }
        WatchUi.requestUpdate();
    }

    static function finishFreshKeks(source) {
        keksWatchdog.stop();
        mathRunner().cancel();
        var keyPersisted = false;
        if (freshKeksSharedKey != null && freshKeksSharedKey.size() == 16) {
            var keyText = bytesToHex(freshKeksSharedKey);
            try {
                Application.Storage.setValue("savedAuthKeyHex", keyText);
                keyPersisted = true;
            } catch (storageException) {
                try {
                    Application.Properties.setValue("savedAuthKeyHex", keyText);
                    keyPersisted = true;
                } catch (propertyException) {
                    keyPersisted = false;
                }
            }
        }
        if (g7DisplayType == 0x03) { saveSlotPolicy("watch", "accepted-" + source); }
        freshKeksActive = false;
        freshKeksState = "COMPLETE";
        clearFreshKeksSecrets();
        scanStatus = "AUTH OK";
        ScoutLog.println("KO" + g7Authenticated +
            ":" + g7Bonded + ":" + keyPersisted +
            ":" + g7DisplayType + ":" + source);
        noteDebug("KEKS OK slot" + g7DisplayType);
        bindTargetDevice("pairing");
        WatchUi.requestUpdate();
    }


    static function appendRx(value) {
        var room = keksRxBuffer.size() - keksRxCount;
        var take = value.size() < room ? value.size() : room;
        for (var i = 0; i < take; i += 1) { keksRxBuffer[keksRxCount + i] = value[i]; }
        keksRxCount += take;
        return value.size() - take;
    }

    static function handleFreshKeksExtraData(value) {
        if (value == null || value.size() == 0) { return; }

        if (freshKeksState.equals("WAIT_REMOTE_CERT_A") ||
            freshKeksState.equals("WAIT_REMOTE_CERT_B")) {
            if (keksRxBuffer == null || appendRx(value) > 0) {
                abortFreshKeks("remote-certificate-oversize");
                return;
            }
            if (keksRxCount < keksRxBuffer.size()) { return; }
            var receivedSize = keksRxCount;
            keksRxBuffer = null;
            keksRxCount = 0;
            keksWatchdog.stop();
            ScoutLog.println("KEtrue:" + receivedSize);
            if (freshKeksState.equals("WAIT_REMOTE_CERT_A")) {
                queueCertificateRequest(1, freshKeksPartB);
            } else {
                var nonce = Cryptography.randomBytes(16);
                if (nonce == null || nonce.size() != 16) {
                    abortFreshKeks("sign-challenge-nonce-generation-failed");
                    return;
                }
                var request = [0x0C]b;
                request.addAll(nonce);
                freshKeksState = "WAIT_SIGN_CHALLENGE";
                scanStatus = "KWAIT SIGN-r";
                queueKeks(null, request, "SIGN_CHALLENGE_REQUEST");
            }
            return;
        }

        if (!freshKeksState.equals("WAIT_ROUND1") &&
            !freshKeksState.equals("WAIT_ROUND2") &&
            !freshKeksState.equals("WAIT_ROUND3")) {
            ScoutLog.println("KZ" + freshKeksState + ":" + value.size());
            return;
        }
        if (keksRxBuffer == null) {
            keksRxBuffer = new [160]b;
            keksRxCount = 0;
            if (freshKeksState.equals("WAIT_ROUND1") || freshKeksState.equals("WAIT_ROUND2") ||
                freshKeksState.equals("WAIT_ROUND3")) {
                keksRoundRxFirstAtMs = System.getTimer();
            }

            ScoutLog.println("K1" + freshKeksState + ":" + value.size());
        }

        var extra = appendRx(value);
        if (extra > 0) {
            ScoutLog.println("KY" + extra);
        }
        if (keksRxCount < 160) { return; }
        var frame = keksRxBuffer;
        keksRxBuffer = null;
        keksRxCount = 0;
        handleFreshKeksRoundPacket(frame);
    }

    static function queueCertificateRequest(which, certificateBytes) {
        if (certificateBytes == null || certificateBytes.size() <= 100) {
            abortFreshKeks("configured-certificate-unavailable");
            return;
        }
        var request = [0x0B, which & 0xFF]b;
        var length = certificateBytes.size();
        request.add(length & 0xFF);
        request.add((length >> 8) & 0xFF);
        request.add((length >> 16) & 0xFF);
        request.add((length >> 24) & 0xFF);
        keksRxBuffer = null;
        keksRxCount = 0;
        freshKeksState = which == 0 ? "WAIT_CERT_A_HEADER" : "WAIT_CERT_B_HEADER";
        scanStatus = which == 0 ? "KWAIT CERT-A" : "KWAIT CERT-B";
        queueKeks(null, request, which == 0 ? "CERT_QUERY_A" : "CERT_QUERY_B");
    }

    static function handleFreshKeksRoundPacket(frame) {
        keksWatchdog.stop();





        var roundState = freshKeksState;
        if (roundState.equals("WAIT_ROUND1")) {
            sendLocalRound(1);


            ScoutLog.println("ABsend-queued:1:" +
                (keksRoundRxFirstAtMs < 0 ? -1 : System.getTimer() - keksRoundRxFirstAtMs));

            ScoutLog.println("ABack-queue:1:" +
                (keksRoundAckAtMs < 0 ? -1 : System.getTimer() - keksRoundAckAtMs));
        } else if (roundState.equals("WAIT_ROUND2")) {
            sendLocalRound(2);
            ScoutLog.println("ABsend-queued:2:" +
                (keksRoundRxFirstAtMs < 0 ? -1 : System.getTimer() - keksRoundRxFirstAtMs));
        }
        var parsed = KeksP256.parsePacket(frame);
        if (parsed == null) {
            abortFreshKeks("round-packet-parse-failed");
            return;
        }
        var runner = mathRunner();
        if (roundState.equals("WAIT_ROUND1")) {
            keksRemote1 = parsed;
            runner.enqueue(new KeksVerifyRound12Task(parsed, keksServerParty()), "VERIFY_ROUND1");
        } else if (roundState.equals("WAIT_ROUND2")) {
            keksRemote2 = parsed;
            var v3 = KeksP256.randomScalar();
            if (v3 == null) {
                abortFreshKeks("round3-random-scalar-failed");
                return;
            }
            runner.enqueue(new KeksRound3PacketTask(keksLocal1[1], keksRemote1[1], parsed[1],
                keksX2, keksPassword, v3, keksClientParty()), "LOCAL_ROUND3");
            runner.enqueue(new KeksVerifyRound12Task(parsed, keksServerParty()), "VERIFY_ROUND2");
        } else {
            keksRemote3 = parsed;
            maybeStartFinish();
            sendLocalRound(3);
        }
    }


    static function sendLocalRound(n) {
        var packet = n == 1 ? (keksLocal1 == null ? null : keksLocal1[0]) :
            (n == 2 ? (keksLocal2 == null ? null : keksLocal2[0]) : keksLocal3);
        if (packet == null) {
            keksPendingSend = n;
            freshKeksState = "SEND_ROUND" + n;
            scanStatus = "KEKS CALC";
            keksWatchdog.start(MATH_TIMEOUT_MS);
            ScoutLog.println("KL" + n);
            return;
        }
        keksPendingSend = 0;
        if (!queueLocalRound(n, packet)) { return; }
        if (n == 1) {
            freshKeksState = "WAIT_ROUND2";
            scanStatus = "KEKS R2";
        } else if (n == 2) {
            freshKeksState = "WAIT_ROUND3";
            scanStatus = "KEKS R3";
        } else {
            freshKeksState = "WAIT_AUTH_REPLY";
            scanStatus = "KWAIT AUTH-r";
        }
    }


    static function queueLocalRound(n, packet) {
        if (n == 1) { return queueKeks(packet, [0x0A,0x01]b, "ROUND1"); }
        if (n == 2) { return queueKeks(packet, [0x0A,0x02]b, "ROUND2"); }
        var token = Cryptography.randomBytes(8);
        if (token == null || token.size() != 8) {
            abortFreshKeks("auth-token-generation-failed");
            return false;
        }
        freshKeksAuthToken = token;

        var authRequest = [0x02]b;
        authRequest.addAll(token);
        authRequest.add(g7DisplayType);
        keksAuthRequestSent = true;
        ScoutLog.println("KQ8:" + g7DisplayType);
        return queueKeks(packet, authRequest, "AUTH_REQUEST");
    }

    static function maybeStartFinish() {
        if (keksFinishStarted || keksPrepTask == null || !keksPrepTask.done || keksRemote3 == null) {
            return;
        }
        keksFinishStarted = true;
        mathRunner().enqueue(new KeksRound3FinishTask(keksRemote3, keksPrepTask, keksX2, keksServerParty()),
            "ROUND3_FINISH");
    }

    static function onKeksMathComplete(action, task) {
        if (!freshKeksActive) { return; }
        var runner = mathRunner();
        ScoutLog.println("KM" + action +
            ":" + (task.result != null) + ":" + runner.taskElapsedMs() +
            ":" + runner.taskTicks() + ":" + runner.maxTickSpent);
        if (action.find("VERIFY") != null) {
            var verifiedRound = action.equals("VERIFY_ROUND1") ? 1 : 2;
            ScoutLog.println("ABproof-done:" + verifiedRound + ":" +
                (keksRoundRxFirstAtMs < 0 ? -1 : System.getTimer() - keksRoundRxFirstAtMs));
            noteDebug(action.substring(7, action.length()) + (task.result != null ? " OK" : " BAD"));
        }
        if (task.result == null) {
            abortFreshKeks(action.toLower() + "-" + task.failure);
            return;
        }
        if (action.equals("LOCAL_ROUND1")) {
            keksLocal1 = task.result;
            if (keksPendingSend == 1) { sendLocalRound(1); }
        } else if (action.equals("LOCAL_ROUND2")) {
            keksLocal2 = task.result;
            if (keksPendingSend == 2) { sendLocalRound(2); }
        } else if (action.equals("LOCAL_ROUND3")) {
            keksLocal3 = task.result;
            keksPrepTask = new KeksRound3PrepTask(keksLocal1[1], keksLocal2[1],
                keksRemote1[1], keksRemote2[1], task.xp, task.xp1);
            runner.enqueue(keksPrepTask, "ROUND3_PREP");
            if (keksPendingSend == 3) { sendLocalRound(3); }
        } else if (action.equals("ROUND3_PREP")) {
            maybeStartFinish();
        } else if (action.equals("ROUND3_FINISH")) {
            freshKeksSharedKey = task.result;
            if (keksPendingAuthReply != null) {
                var reply = keksPendingAuthReply;
                keksPendingAuthReply = null;
                processAuthReply(reply);
            }
        } else if (action.equals("SIGN_CHALLENGE")) {
            freshKeksState = "WAIT_POST_CHALLENGE";
            scanStatus = "KEKS SIGN-s";
            queueKeks(task.result, [0x0D,0x00,0x02]b, "SIGNATURE_RESPONSE");
        }


    }



    static function processAuthReply(value) {
        var tokenPlain = new [16]b;
        for (var i = 0; i < 8; i += 1) {
            tokenPlain[i] = freshKeksAuthToken[i];
            tokenPlain[i + 8] = freshKeksAuthToken[i];
        }
        var cipher = new Cryptography.Cipher({
            :algorithm => Cryptography.CIPHER_AES128,
            :mode => Cryptography.MODE_ECB,
            :key => freshKeksSharedKey
        });
        var expected = cipher.encrypt(tokenPlain);
        if (expected == null || expected.size() < 8) {
            abortFreshKeks("auth-proof-encryption-failed");
            return;
        }
        for (var k = 0; k < 8; k += 1) {
            if ((expected[k] & 0xFF) != (value[k + 1] & 0xFF)) {

                markWrongName();
                abortFreshKeks("auth-challenge-proof-mismatch");
                return;
            }
        }
        var challengePlain = new [16]b;
        for (var c = 0; c < 8; c += 1) {
            challengePlain[c] = value[c + 9];
            challengePlain[c + 8] = value[c + 9];
        }
        var response = cipher.encrypt(challengePlain);
        if (response == null || response.size() < 8) {
            abortFreshKeks("auth-challenge-encryption-failed");
            return;
        }
        var reply = [0x04]b;
        reply.addAll(response.slice(0, 8));
        ScoutLog.println("KH" + g7DisplayType);
        freshKeksState = "WAIT_AUTH_STATUS";
        scanStatus = "KWAIT STAT-r";
        queueKeks(null, reply, "AUTH_CHALLENGE");
    }

    static function handleFreshKeksAuthMessage(value) {
        if (value == null || value.size() < 1) {
            abortFreshKeks("empty-auth-indication");
            return;
        }
        var opcode = value[0] & 0xFF;
        ScoutLog.println("KI" + opcode + ":" + value.size() +
            ":" + freshKeksState);





        if (opcode == 0x0A &&
            (freshKeksState.equals("WAIT_ROUND1") ||
             freshKeksState.equals("WAIT_ROUND2") ||
             freshKeksState.equals("WAIT_ROUND3"))) {
            var expectedRound = freshKeksState.equals("WAIT_ROUND1") ? 0 :
                (freshKeksState.equals("WAIT_ROUND2") ? 1 : 2);
            var ackStatus = value.size() > 1 ? (value[1] & 0xFF) : -1;
            var ackRound = value.size() > 2 ? (value[2] & 0xFF) : -1;
            var matched = value.size() == 3 && ackStatus == 0 && ackRound == expectedRound;
            if (matched && freshKeksState.equals("WAIT_ROUND1")) {
                keksRoundAckAtMs = System.getTimer();
            }
            ScoutLog.println("KR" + matched + ":" + value.size() +
                ":" + ackStatus + ":" + ackRound +
                ":" + expectedRound + ":" + keksRxCount +
                ":" + freshKeksState);


            if (ackStatus != 0) { noteDebug("0A ERR s" + ackStatus + " p" + ackRound); }


            return;
        }

        if (freshKeksState.equals("WAIT_CERT_A_HEADER") ||
            freshKeksState.equals("WAIT_CERT_B_HEADER")) {
            var expectedWhich = freshKeksState.equals("WAIT_CERT_A_HEADER") ? 0 : 1;
            if (value.size() != 7 || opcode != 0x0B ||
                (value[1] & 0xFF) != 0 || (value[2] & 0xFF) != expectedWhich) {
                abortFreshKeks("invalid-certificate-header");
                return;
            }
            var remoteSize = (value[3] & 0xFF) | ((value[4] & 0xFF) << 8);
            if (remoteSize <= 100 || remoteSize > 16384) {
                abortFreshKeks("remote-certificate-size-invalid");
                return;
            }
            keksWatchdog.stop();
            keksRxBuffer = new [remoteSize]b;
            keksRxCount = 0;
            if (expectedWhich == 0) {
                freshKeksState = "WAIT_REMOTE_CERT_A";
                queueKeks(freshKeksPartA, null, "CERT_A_DATA");
            } else {
                freshKeksState = "WAIT_REMOTE_CERT_B";
                queueKeks(freshKeksPartB, null, "CERT_B_DATA");
            }
            scanStatus = expectedWhich == 0 ? "KSEND CERT-A" : "KSEND CERT-B";
            return;
        }

        if (freshKeksState.equals("WAIT_SIGN_CHALLENGE")) {


            if (value.size() < 18 || (value[1] & 0xFF) != 0 ||
                freshKeksPrivateScalar == null) {
                abortFreshKeks("invalid-sign-challenge");
                return;
            }
            keksWatchdog.start(MATH_TIMEOUT_MS);
            freshKeksState = "SIGNING";
            scanStatus = "KEKS CALC";
            mathRunner().enqueue(new KeksSignTask(freshKeksPrivateScalar, value.slice(2, 18), null),
                "SIGN_CHALLENGE");
            return;
        }

        if (freshKeksState.equals("WAIT_BLE_BOND")) {
            if (opcode == 0x05 && value.size() >= 3) {
                g7Authenticated = (value[1] & 0xFF) == 1;
            }
            ScoutLog.println("K8" + value.size() +
                ":" + g7Authenticated);
            return;
        }

        if (freshKeksState.equals("WAIT_POST_CHALLENGE") ||
            freshKeksState.equals("WAIT_BOND_TRIGGER")) {
            var bondSignal = (value.size() == 2 && bytesEqual(value, [0x06,0x19]b)) ||
                (value.size() == 3 && bytesEqual(value, [0xFF,0x06,0x01]b)) ||
                (value.size() == 2 && bytesEqual(value, [0x06,0x00]b));
            if (bondSignal) {
                var markerArrivedBeforeTimeExtended = freshKeksState.equals("WAIT_POST_CHALLENGE");
                keksWatchdog.stop();
                var alreadyBonded = false;
                try { alreadyBonded = device != null && device.isBonded(); } catch (bondQueryError) { alreadyBonded = false; }
                if (alreadyBonded) {
                    g7Bonded = true;
                    finishFreshKeks("ble-already-bonded-after-keks");
                    enableCharacteristicIndications(device, UUID_CONTROL, "CONTROL", 0x02);
                    return;
                }
                if (!requestBond()) {
                    abortFreshKeks("ble-bond-request-failed");
                    return;
                }
                freshKeksState = "WAIT_BLE_BOND";
                scanStatus = "KWAIT BOND";
                keksWatchdog.start(30000);
                if (markerArrivedBeforeTimeExtended) {
                    queueKeks(null, [0x06,0x19]b, "TIME_EXTENDED_AFTER_BOND_TRIGGER");
                }
                return;
            }

            if (freshKeksState.equals("WAIT_POST_CHALLENGE")) {



                freshKeksState = "WAIT_BOND_TRIGGER";
                scanStatus = "KWAIT TRIG";
                queueKeks(null, [0x06,0x19]b, "TIME_EXTENDED_BOND_STEP");
                return;
            }

            ScoutLog.println("K9" + value.size());
            return;
        }

        if (freshKeksState.equals("WAIT_AUTH_REPLY")) {
            if (opcode != 0x03 || value.size() < 17 || freshKeksAuthToken == null) {
                abortFreshKeks("unexpected-auth-reply");
                return;
            }
            keksWatchdog.stop();
            if (freshKeksSharedKey == null) {


                keksPendingAuthReply = value;
                keksWatchdog.start(MATH_TIMEOUT_MS);
                ScoutLog.println("KUshared-key-pending");
                return;
            }
            processAuthReply(value);
            return;
        }

        if (freshKeksState.equals("WAIT_AUTH_STATUS")) {
            if (opcode != 0x05 || value.size() < 3) {
                abortFreshKeks("unexpected-auth-status");
                return;
            }
            var authenticated = (value[1] & 0xFF) == 1;
            var bondedByte = value[2] & 0xFF;
            var bonded = bondedByte == 1;
            g7Authenticated = authenticated;
            g7Bonded = bonded;
            keksWatchdog.stop();
            ScoutLog.println("KS" + authenticated + ":" + bonded +
                ":" + bondedByte + ":" + g7DisplayType);
            if (authenticated && bonded) {
                finishFreshKeks("g7-auth-status-bonded");
                enableCharacteristicIndications(device, UUID_CONTROL, "CONTROL", 0x02);
            } else if (authenticated) {
                ScoutLog.println("KGtrue:false:validated");


                keksPassword = null;
                keksX1 = null;
                keksX2 = null;
                queueCertificateRequest(0, freshKeksPartA);
            } else {
                abortFreshKeks(bondedByte == 3 ? "sensor-auth-refresh-required" : "sensor-authentication-rejected");
            }
            WatchUi.requestUpdate();
            return;
        }
        abortFreshKeks("auth-indication-in-wrong-state");
    }


    static function requestGlucose() {
        if (device == null || !device.isConnected() || sessionTerminal) { return; }
        if (!keksWriteScheduler.queue(null, [0x4E]b, "GLUCOSE_REQUEST", UUID_CONTROL)) {
            ScoutLog.println("GSwrite-queue-full");
            return;
        }
        scanStatus = "G7 DATA-s";
        ScoutLog.println("GQ4E");
    }




    static const SAVED_KEY_AUTH_TIMEOUT_MS = 15000;

    static function sendAuthRequestProbe() {
        if (authRequestSent || sessionTerminal || device == null || !device.isConnected()) { return; }
        authRequestSent = true;
        var packet = [0x02]b;
        savedAuthToken = Cryptography.randomBytes(8);
        packet.addAll(savedAuthToken);


        retryWatchSlotIfDue();
        savedAuthDisplayType = g7DisplayType;
        packet.add(savedAuthDisplayType);

        savedKeyCipher = loadSavedKeyCipher();
        if (!keksWriteScheduler.queue(null, packet, "SAVED_AUTH_REQUEST", UUID_AUTH)) {
            ScoutLog.println("SVwrite-queue-full");
            return;
        }
        scanStatus = "SAVED AUTH";
        authProbeWatchdog.start(SAVED_KEY_AUTH_TIMEOUT_MS);
        ScoutLog.println("SK02:8:" + savedAuthDisplayType + ":" +
            (System.getTimer() - connectedAtMs));
        noteDebug("SAVED AUTH");
        WatchUi.requestUpdate();
    }


    static function onSavedAuthSlotOutcome(accepted, reason) {
        if (savedAuthDisplayType != 0x03) { return; }
        savedAuthDisplayType = 0;
        if (accepted) {
            saveSlotPolicy("watch", "saved-key-accepted");
        } else if (reason.equals("rejected") || reason.equals("refresh")) {
            saveSlotPolicy("phone", "watch-slot-saved-" + reason);
        } else {

            ScoutLog.println("SG" + slotPolicy + ":" + g7DisplayType + ":kept-after-" + reason);
        }
    }

    static function onSavedAuthLinkLost() {
        if (authRequestSent && !g7Authenticated && !freshKeksActive) {
            onSavedAuthSlotOutcome(false, authProbeResponseSeen ? "drop-after-reply" : "drop");
        }
    }

    static function onAuthProbeTimeout() {
        if (authProbeResponseSeen || sessionTerminal || device == null || !device.isConnected()) { return; }
        onSavedAuthSlotOutcome(false, "timeout");
        scanStatus = "AUTH NO ANS";
        ScoutLog.println("ST" + SAVED_KEY_AUTH_TIMEOUT_MS +
            ":" + (System.getTimer() - connectedAtMs));
        noteDebug("AUTH NO ANS");
        WatchUi.requestUpdate();
    }






    static function hasSavedAuthKey() {
        var keyText = null;
        try { keyText = Application.Storage.getValue("savedAuthKeyHex"); } catch (e) { keyText = null; }
        if (keyText == null) {
            try { keyText = Application.Properties.getValue("savedAuthKeyHex"); } catch (e2) { keyText = null; }
        }
        return keyText instanceof Lang.String && keyText.length() == 32;
    }


    static var savedKeyCipher = null;
    static var savedAuthToken = null;

    static function loadSavedKeyCipher() {
        var keyText = null;
        try { keyText = Application.Storage.getValue("savedAuthKeyHex"); } catch (storageError) { keyText = null; }
        if (keyText == null) {
            try { keyText = Application.Properties.getValue("savedAuthKeyHex"); } catch (propertyError) { keyText = null; }
        }
        if (!(keyText instanceof Lang.String) || keyText.length() != 32) { return null; }
        var key = parseHexBytes(keyText);
        if (key == null || key.size() != 16) { return null; }
        return new Cryptography.Cipher({
            :algorithm => Cryptography.CIPHER_AES128,
            :mode => Cryptography.MODE_ECB,
            :key => key
        });
    }

    static function sendSavedKeyChallengeResponse(authReply) {
        try {
            var cipher = savedKeyCipher != null ? savedKeyCipher : loadSavedKeyCipher();
            if (cipher == null) {
                ScoutLog.println("KJtrue");
                return false;
            }
            if (authReply == null || authReply.size() < 17) {
                ScoutLog.println("KK");
                return false;
            }




            if (!savedKeyProofMatches(cipher, authReply)) {
                refuseSavedKeyForWatch();
                return false;
            }
            var plain = new [16]b;
            for (var i = 0; i < 8; i += 1) {
                plain[i] = authReply[i + 9];
                plain[i + 8] = authReply[i + 9];
            }
            var encrypted = cipher.encrypt(plain);
            if (encrypted == null || encrypted.size() < 8) {
                ScoutLog.println("K7");
                return false;
            }
            var packet = new [9]b;
            packet[0] = 0x04;
            for (var n = 0; n < 8; n += 1) {
                packet[n + 1] = encrypted[n];
            }
            if (keksWriteScheduler.queue(null, packet, "SAVED_AUTH_CHALLENGE", UUID_AUTH)) {
                scanStatus = "AUTH ANS-s";
                ScoutLog.println("K404:8:saved-persistence-key");
                WatchUi.requestUpdate();
                return true;
            }
            ScoutLog.println("K6write-queue-full");
        } catch (exception) {
            ScoutLog.println("K5" + exception);
        }
        return false;
    }



    static function savedKeyProofMatches(cipher, authReply) {
        if (savedAuthToken == null || savedAuthToken.size() != 8) {
            ScoutLog.println("SMunknown");
            return false;
        }
        var plain = new [16]b;
        for (var i = 0; i < 8; i += 1) {
            plain[i] = savedAuthToken[i];
            plain[i + 8] = savedAuthToken[i];
        }
        var expected = cipher.encrypt(plain);
        var match = expected != null && expected.size() >= 8;
        for (var k = 0; match && k < 8; k += 1) {
            if ((expected[k] & 0xFF) != (authReply[k + 1] & 0xFF)) { match = false; }
        }
        ScoutLog.println("SM" + match);
        noteDebug(match ? "KEY MATCHES" : "KEY MISMATCH");
        return match;
    }




    static const KEY_REFUSED_KEY = "g7SavedKeyRefused";

    static function refuseSavedKeyForWatch() {
        var print = ScoutPhoneLink.keyPrint();
        try { Application.Storage.setValue(KEY_REFUSED_KEY, print); } catch (e) { }
        scanStatus = "OWN PAIRING";
        ScoutLog.println("SX" + print);
        noteDebug("OWN PAIRING");
    }

    static function savedKeyUsable() {
        if (!hasSavedAuthKey()) { return false; }
        var refused = null;
        try { refused = Application.Storage.getValue(KEY_REFUSED_KEY); } catch (e) { refused = null; }
        return !(refused instanceof Lang.String && refused.equals(ScoutPhoneLink.keyPrint()));
    }

    static function parseHexBytes(hexText) {
        if (hexText == null || hexText.length() % 2 != 0) { return null; }
        var out = []b;
        for (var i = 0; i < hexText.length(); i += 2) {
            var hi = hexNibble(hexText.substring(i, i + 1));
            var lo = hexNibble(hexText.substring(i + 1, i + 2));
            if (hi < 0 || lo < 0) { return null; }
            out.add((hi << 4) | lo);
        }
        return out;
    }

    static function hexNibble(ch) {
        var digits = "0123456789ABCDEF";
        var upper = ch.toUpper();
        for (var i = 0; i < 16; i += 1) {
            if (upper.equals(digits.substring(i, i + 1))) { return i; }
        }
        return -1;
    }


    static function readUInt16LE(bytes, offset) {
        return (bytes[offset] & 0xFF) | ((bytes[offset + 1] & 0xFF) << 8);
    }

    static function readUInt32LE(bytes, offset) {
        return (bytes[offset] & 0xFF) |
            ((bytes[offset + 1] & 0xFF) << 8) |
            ((bytes[offset + 2] & 0xFF) << 16) |
            ((bytes[offset + 3] & 0xFF) << 24);
    }

    static function handleG7ControlMessage(bytes) {
        if (sessionTerminal) {
            ScoutLog.println("MIsession-terminal:" + sessionTerminalReason);
            return;
        }
        if (!g7Authenticated || !g7Bonded) {
            ScoutLog.println("MInot-authenticated-and-bonded");
            return;
        }
        if (bytes == null || bytes.size() < 1) {
            ScoutLog.println("MRempty");
            return;
        }
        var opcode = bytes[0] & 0xFF;
        if (opcode != 0x4E) {
            ScoutLog.println("CO" + opcode + ":" + bytes.size());
            return;
        }
        if (bytes.size() < 19 || (bytes[1] & 0xFF) != 0) {
            ScoutLog.println("GR" + bytes.size() +
                ":" + (bytes.size() > 1 ? (bytes[1] & 0xFF) : -1));
            return;
        }

        var sensorClock = readUInt32LE(bytes, 2);
        var sequence = readUInt16LE(bytes, 6);
        var age = readUInt16LE(bytes, 10);
        var rawGlucose = readUInt16LE(bytes, 12);
        var algorithmState = bytes[14] & 0xFF;
        var rawTrend = bytes[15] & 0xFF;
        var signedTrend = rawTrend > 127 ? rawTrend - 256 : rawTrend;
        var rawPredicted = readUInt16LE(bytes, 16);
        var calibration = bytes[18] & 0xFF;
        var glucoseIsDisplayOnly = (calibration & 0x10) != 0;


        var terminal = algorithmState == 1 || algorithmState == 15 ||
            algorithmState == 16 || algorithmState == 17 ||
            algorithmState == 22 || algorithmState == 24 ||
            algorithmState == 25 || algorithmState == 26;
        if (terminal) {
            sessionTerminal = true;
            sessionTerminalReason = "" + algorithmState;
            glucoseHasValue = false;
            glucoseValue = -1;
            glucoseAgeSeconds = -1;
            glucoseReceivedAtMs = -1;
            glucoseSequence = -1;
            previousGlucoseValue = -1;
            glucoseTrendDirection = 0;
            if (algorithmState == 26 || algorithmState == 15 ||
                algorithmState == 24 || algorithmState == 1) {
                scanStatus = "SESSION END";
            } else {
                scanStatus = "SESSION FAIL";
            }
            ScoutLog.println("TM" + algorithmState +
                ":" + sequence + ":mark-inactive-no-restart-no-reconnect");
            ScoutReadingSync.onCleared();
            return;
        }

        var priorGlucoseHasValue = glucoseHasValue;
        var priorGlucoseValue = glucoseValue;
        var priorGlucoseSequence = glucoseSequence;
        var priorGlucoseAge = effectiveGlucoseAgeSeconds();

        glucoseAlgorithmState = algorithmState;
        glucoseAgeSeconds = age;
        glucoseReceivedAtMs = System.getTimer();
        glucoseHasValue = false;
        glucoseValue = -1;



        if (algorithmState == 6 && rawGlucose != 0xFFFF && age <= 900 &&
            !glucoseIsDisplayOnly) {
            var nextGlucoseValue = rawGlucose & 0x0FFF;
            if (priorGlucoseHasValue && priorGlucoseAge >= 0 && priorGlucoseAge <= 900 &&
                sequence != priorGlucoseSequence) {
                previousGlucoseValue = priorGlucoseValue;
                if (nextGlucoseValue > priorGlucoseValue) {
                    glucoseTrendDirection = 1;
                } else if (nextGlucoseValue < priorGlucoseValue) {
                    glucoseTrendDirection = -1;
                } else {
                    glucoseTrendDirection = 0;
                }
            } else if (!priorGlucoseHasValue || priorGlucoseAge > 900) {
                previousGlucoseValue = -1;
                glucoseTrendDirection = 0;
            }
            glucoseValue = nextGlucoseValue;
            glucoseSequence = sequence;
            glucoseHasValue = true;
            sessionGotReading = true;
            scanStatus = "G7 DATA";
            ScoutReadingSync.onAccepted(glucoseValue, glucoseTrendDirection, sequence, age);
            ScoutGlucoseSender.send(targetName, sequence, glucoseValue, age, signedTrend,
                rawPredicted, algorithmState, glucoseIsDisplayOnly);
        } else if (algorithmState == 6 && glucoseIsDisplayOnly) {
            scanStatus = "DISPLAY ONLY";
        } else if (algorithmState == 6 && age > 900) {
            scanStatus = "DATA STALE";
        } else {
            scanStatus = "G7 STATE " + algorithmState;
        }

        lastSensorClockSeconds = sensorClock;
        lastSensorClockAtMs = System.getTimer();
        noteDebug("BG " + (glucoseHasValue ? glucoseValue : -1) + " state " + algorithmState);
        WatchUi.requestUpdate();
        ScoutLog.println("GL" + sequence + ":" + age + ":" + glucoseIsDisplayOnly + ":" + algorithmState);
    }

    static function requestBond() {
        if (device == null || !device.isConnected()) {
            scanStatus = "BOND ABORT";
            ScoutLog.println("BAnot-connected");
            return false;
        }
        if (bondAttempted) {
            scanStatus = "BOND TRIED";
            ScoutLog.println("BAalready-attempted");
            return false;
        }
        bondAttempted = true;
        try {


            device.requestBond();
            ScoutLog.println("BRpost-keks-protocol-signal");
            return true;
        } catch (exception) {
            scanStatus = "BOND EXCEPT";
            ScoutLog.println("BX" + exception);
            return false;
        }
    }




    static function describeGatt(connectedDevice) {
        forgetCharacteristics();
        try {
            var services = connectedDevice.getServices();
            var service = services.next();
            var serviceCount = 0;
            var summary = "";
            while (service != null) {
                serviceCount += 1;
                var serviceUuid = service.getUuid();
                summary += (serviceCount > 1 ? ";" : "") +
                    (G7_SERVICE.equals(serviceUuid) ? shortUuid(serviceUuid) : serviceUuid.toString()) + "[";
                var chars = service.getCharacteristics();
                var characteristic = chars.next();
                var first = true;
                while (characteristic != null) {
                    var charUuid = characteristic.getUuid();
                    rememberCharacteristic(charUuid, characteristic);
                    summary += (first ? "" : ",") + shortUuid(charUuid) + ".";
                    first = false;
                    try {
                        var descriptors = characteristic.getDescriptors();
                        var descriptor = descriptors.next();
                        var descriptorCount = 0;
                        while (descriptor != null) {
                            descriptorCount += 1;
                            descriptor = descriptors.next();
                        }
                        summary += descriptorCount;
                    } catch (descriptorException) {
                        summary += "?";
                        ScoutLog.println("GD" + shortUuid(charUuid) +
                            ":" + descriptorException);
                    }
                    characteristic = chars.next();
                }
                summary += "]";
                service = services.next();
            }
            ScoutLog.println("GE" + serviceCount + ":" + summary);
            scanStatus = serviceCount > 0 ? "GATT OK" : "NO SERVICES";
        } catch (exception) {
            scanStatus = "GATT ERR";
            ScoutLog.println("GX" + exception);
        }
    }

    static function effectiveGlucoseAgeSeconds() {
        if (glucoseAgeSeconds < 0) { return -1; }
        var age = glucoseAgeSeconds;
        if (glucoseReceivedAtMs >= 0) {
            var elapsedMs = System.getTimer() - glucoseReceivedAtMs;

            if (elapsedMs > 0) {
                age += (elapsedMs / 1000).toNumber();
            }
        }
        return age;
    }

    static function hasCurrentGlucose() {
        var age = effectiveGlucoseAgeSeconds();
        return glucoseHasValue && age >= 0 && age <= 900;
    }


    static function retryRemainingMs() {
        if (!connectionTimerPurpose.equals("RETRY_DELAY") && !connectionTimerPurpose.equals("WAKE_WAIT")) { return -1; }
        return ScoutClock.get().remainingMs("connection");
    }


    static function drawStatusText(dc, centerX, y, maxWidth, text) {
        var fonts = retryRemainingMs() >= 0 ?
            [Graphics.FONT_TINY, Graphics.FONT_XTINY] :
            [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];
        var font = fonts[fonts.size() - 1];
        for (var i = 0; i < fonts.size(); i += 1) {
            if (dc.getTextWidthInPixels(text, fonts[i]) <= maxWidth) {
                font = fonts[i];
                break;
            }
        }
        dc.drawText(centerX, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    static function statusTextForUi() {
        if (sessionTerminal) { return scanStatus; }
        if (connectionInFlight) { return "CONNECTING"; }
        if (device != null && device.isConnected() && !freshKeksState.equals("OFF")) {
            return scanStatus;
        }
        if (scanning && (device == null || !device.isConnected())) { return "SCANNING"; }
        var retryMs = retryRemainingMs();
        if (retryMs >= 0) {
            var retrySec = (retryMs + 999) / 1000;
            return (connectionTimerPurpose.equals("WAKE_WAIT") ? "NEXT G7 " : "RETRY IN ") +
                (retrySec / 60) + ":" + twoDigits(retrySec % 60);
        }
        var age = effectiveGlucoseAgeSeconds();
        if ((glucoseHasValue && age > 900) || scanStatus.equals("DATA STALE")) {

            return (device != null && device.isConnected()) ? "CONNECTED" : "WAIT SENSOR";
        }
        if (device != null && device.isConnected() && hasCurrentGlucose()) { return "G7 DATA"; }
        if (device != null && device.isConnected() && scanStatus.equals("DISPLAY ONLY")) {
            return "DISPLAY ONLY";
        }
        return scanStatus;
    }


    static function statusRowText() {
        var text = statusTextForUi();
        var age = effectiveGlucoseAgeSeconds();
        if (glucoseHasValue && age >= 0) {
            if (age < 60) {
                text += "  <1m";
            } else if (age >= 3600) {
                text += "  " + (age / 3600).toNumber() + "h";
            } else {
                text += "  " + (age / 60).toNumber() + "m";
            }
        }
        return text;
    }

    static function drawTrendIndicator(dc, x, y) {
        var middleY = y + 7;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        if (glucoseTrendDirection > 0) {
            dc.drawLine(x, middleY + 5, x, middleY - 4);
            dc.drawLine(x, middleY - 4, x - 4, middleY);
            dc.drawLine(x, middleY - 4, x + 4, middleY);
        } else if (glucoseTrendDirection < 0) {
            dc.drawLine(x, middleY - 4, x, middleY + 5);
            dc.drawLine(x, middleY + 5, x - 4, middleY + 1);
            dc.drawLine(x, middleY + 5, x + 4, middleY + 1);
        } else {
            dc.drawLine(x - 5, middleY, x + 4, middleY);
            dc.drawLine(x + 4, middleY, x, middleY - 3);
            dc.drawLine(x + 4, middleY, x, middleY + 3);
        }
    }

    static const UI_REFRESH_MS = 1000;

    function initialize() {
        View.initialize();
    }

    function refreshUi() {
        ScoutClock.get().schedule("uiRefresh", UI_REFRESH_MS, method(:refreshUi));
        WatchUi.requestUpdate();
    }

    static function timestamp() {


        var t = System.getClockTime();
        return twoDigits(t.hour) + ":" + twoDigits(t.min) + ":" +
            twoDigits(t.sec);
    }

    static function logTimestamp() {

        return timestamp() + "+" + System.getTimer();
    }

    static function twoDigits(value) {
        return value < 10 ? "0" + value : "" + value;
    }

    static function bytesToHex(bytes) {
        if (bytes == null) {
            return "<null>";
        }


        return (StringUtil.convertEncodedString(bytes, {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_HEX
        }) as Lang.String).toUpper();
    }




    static const MAX_TRACKED_DEVICES = 48;

    static function updateDevice(scanResult, name, rssi) {
        var index = -1;
        for (var i = 0; i < seenResults.size(); i += 1) {
            if (scanResult.isSameDevice(seenResults[i])) {
                index = i;
                break;
            }
        }
        if (index < 0) {
            if (seenResults.size() >= MAX_TRACKED_DEVICES) { return -1; }
            index = seenResults.size();
            seenResults.add(scanResult);
            deviceNames.add(name == null || name.length() == 0 ? "<>" : name);
            deviceRssi.add(rssi);
            deviceHits.add(0);
            deviceCount = seenResults.size();

            var upper = deviceNames[index].toUpper();
            if ((upper.length() >= 4 && upper.substring(0, 4).equals("DXCM")) ||
                (upper.length() >= 6 && upper.substring(0, 6).equals("DEXCOM"))) {
                ScoutLog.println("NW" + index +
                    ":" + deviceNames[index] + ":" + rssi);
            } else {
                ScoutLog.fileOnly("NW" + index +
                    ":" + deviceNames[index] + ":" + rssi);
            }
        }
        deviceRssi[index] = rssi;
        deviceHits[index] += 1;
        return index;
    }

    static function serviceUuidSuffix(scanResult) {
        var line = "";
        var uuids = scanResult.getServiceUuids();
        for (var uuid = uuids.next(); uuid != null; uuid = uuids.next()) {
            line += (line.length() == 0 ? ":" : ",") + uuid;
        }
        return line;
    }

    static function setScanState(active, status) {
        scanning = active;
        if (active) {
            scanErrorCount = 0;
            scanStatus = "SCANNING";
        } else if (status == Ble.STATUS_SUCCESS) {
            scanStatus = "SCAN STOPPED";
        } else {
            scanStatus = "BLE ERR " + status;
        }
    }

    function onShow() {
        dashboardShown = true;
        ScoutScreens.onDashboardShown();
        ScoutClock.get().schedule("uiRefresh", UI_REFRESH_MS, method(:refreshUi));
        Ble.setDelegate(ScoutView.delegate);
        ScoutLog.println("VS" + scanning +
            ":" + (device != null && device.isConnected()) +
            ":" + retryScanActive);




        if (!scanning && !connectionInFlight && !retryScanActive &&
            !sessionTerminal && (device == null || !device.isConnected())) {
            startScan(false, false, "view-resume");
        }
    }

    function onHide() {
        dashboardShown = false;
        ScoutClock.get().cancel("uiRefresh");



        ScoutLog.println("VH" + scanning +
            ":" + (device != null && device.isConnected()));
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var showValue = hasCurrentGlucose();
        dc.setColor(showValue ? Graphics.COLOR_RED : Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(centerX, height * 0.07, Graphics.FONT_NUMBER_HOT,
            showValue ? ("" + glucoseValue) : "--", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(centerX - 8, height * 0.32, Graphics.FONT_SMALL,
            "mg/dL", Graphics.TEXT_JUSTIFY_CENTER);
        if (showValue && previousGlucoseValue >= 0) {
            drawTrendIndicator(dc, centerX + 35, height * 0.32);
        }



        dc.drawLine(width * 0.22, height * 0.46, width * 0.78, height * 0.46);
        dc.drawText(centerX, height * 0.49, Graphics.FONT_NUMBER_MILD,
            timestamp(), Graphics.TEXT_JUSTIFY_CENTER);
        drawStatusText(dc, centerX, height * 0.71, width * 0.72, statusRowText());
    }
}
