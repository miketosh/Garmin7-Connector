using Toybox.Cryptography;
using Toybox.System;

// Drives queued KeksTask objects from ScoutClock callbacks (one shared app
// timer; clockKey names this runner's entry), in FIFO order. Each callback
// steps the head task until KeksP256.spent reaches the per-device budget or
// WALL_MS of wall time has passed, then yields to the VM.
// doneCallback.invoke(action, task) reports each finished task; it may
// enqueue more work or cancel the runner.
class KeksMathRunner {
    static const WALL_MS = 150;

    var clockKey;
    var holdWhile;
    var queue;
    var active;
    var doneCallback;
    var budget;
    var ticks;
    var taskStartMs;
    var taskStartTick;
    var maxTickSpent;
    var taskHoldAccum;
    var holdStartedAt;
    var taskFirstTickAtMs;

    // hold: optional Method returning true while ticks should wait (null = never).
    function initialize(callback, key, hold) {
        clockKey = key;
        holdWhile = hold;
        queue = [];
        active = false;
        doneCallback = callback;
        budget = tickBudget();
        ticks = 0;
        taskStartMs = 0;
        taskStartTick = 0;
        maxTickSpent = 0;
        taskHoldAccum = 0;
        holdStartedAt = -1;
        taskFirstTickAtMs = -1;
    }

    // SDK 9.3.0 device profiles: the execution watchdog is 240,000 VM
    // instructions on Forerunner 255 Music / 255S Music (006-B3990/B3991)
    // and 120,000 on Forerunner 255 / 255S. A new stage starts only while
    // spent < budget and the costliest stage is ~87k, so the worst callback is
    // ~187k (fr255m) or ~97k (fr255). Simulator sweep: budgets of 160 (fr255m)
    // and 70 (fr255) trip the watchdog; 130 and 55 do not.
    static function tickBudget() {
        var part = System.getDeviceSettings().partNumber;
        if (part != null && (part.equals("006-B3990-00") || part.equals("006-B3991-00"))) {
            return 100;
        }
        return 10;
    }

    function enqueue(task, action) {
        queue.add([task, action, System.getTimer()]);
        if (!active) {
            active = true;
            taskStartMs = System.getTimer();
            taskStartTick = ticks;
            taskHoldAccum = 0;
            holdStartedAt = -1;
            ScoutClock.get().scheduleBackground(clockKey, 1, method(:tick));
        }
    }

    function cancel() {
        ScoutClock.get().cancel(clockKey);
        queue = [];
        active = false;
    }

    function isBusy() {
        return active;
    }

    // Elapsed milliseconds and timer callbacks for the task that just finished.
    function taskElapsedMs() {
        return System.getTimer() - taskStartMs;
    }

    function taskTicks() {
        return ticks - taskStartTick;
    }

    function taskHoldMs() {
        return taskHoldAccum + (holdStartedAt < 0 ? 0 : System.getTimer() - holdStartedAt);
    }

    function taskQueueDelayMs() {
        return taskFirstTickAtMs < 0 ? -1 : taskFirstTickAtMs - taskStartMs;
    }

    function tick() {
        if (!active) { return; }
        if (holdWhile != null && holdWhile.invoke()) {
            if (holdStartedAt < 0) { holdStartedAt = System.getTimer(); }
            ScoutClock.get().scheduleBackground(clockKey, 50, method(:tick));
            return;
        }
        if (holdStartedAt >= 0) {
            taskHoldAccum += System.getTimer() - holdStartedAt;
            holdStartedAt = -1;
        }
        ticks += 1;
        var started = System.getTimer();
        KeksP256.spent = 0;
        while (queue.size() > 0 && KeksP256.spent < budget &&
               System.getTimer() - started < WALL_MS) {
            var entry = queue[0];
            var task = entry[0];
            if (taskFirstTickAtMs < 0) {
                taskStartMs = entry[2];
                taskFirstTickAtMs = System.getTimer();
            }
            task.step();
            if (task.done) {
                queue = queue.slice(1, null);
                if (KeksP256.spent > maxTickSpent) { maxTickSpent = KeksP256.spent; }
                doneCallback.invoke(entry[1], task);
                if (!active) { return; }
                taskStartMs = 0;
                taskStartTick = ticks;
                taskHoldAccum = 0;
                holdStartedAt = -1;
                taskFirstTickAtMs = -1;
            }
        }
        if (KeksP256.spent > maxTickSpent) { maxTickSpent = KeksP256.spent; }
        if (queue.size() == 0) {
            active = false;
            return;
        }
        ScoutClock.get().scheduleBackground(clockKey, 1, method(:tick));
    }
}

// Resumable KEKS math tasks. Each step() runs one bounded stage: at most one
// point formula (11 Montgomery products), one native P-256 call, or one slice
// of a modular inverse. ScoutKeksMathRunner calls step() repeatedly inside a
// timer callback until KeksP256.spent reaches the per-device budget, then
// yields to the VM, so no single callback approaches the watchdog limit.
//
// Native-scalar guard: every scalar handed to KeyPair/ECDH must be in
// [2, q-3]; a derived scalar outside that range (probability ~2^-254) fails
// the task instead of crashing the app.
class KeksTask {
    static const INVERSE_SLICE = 64;

    var stage = 0;
    var done = false;
    var result = null;
    var failure = null;
    var inverse = null;

    function initialize() {
    }

    function fail(reason) {
        failure = reason;
        result = null;
        done = true;
    }

    function finish(value) {
        result = value;
        done = true;
    }

    function step() {
        if (done) { return; }
        if (inverse != null && !inverse.done) {
            inverse.step(INVERSE_SLICE);
            return;
        }
        runStage();
    }

    function runStage() {
        fail("no-stage");
    }

    // 1/inverse.result in Montgomery form; null if the inverse failed.
    function inverseMont() {
        var value = inverse.result;
        inverse = null;
        return value == null ? null : KeksP256.toMontP(value);
    }
}

// Our round-1/round-2 packet: X = x*G, V = v*G (both native), proof
// r = v - H(G, V, X, party) * x mod q. Result: [packet160, X].
class KeksMakeRound12Task extends KeksTask {
    var x;
    var v;
    var party;
    var publicPoint;
    var witness;

    function initialize(privateScalar, exponent, partyBytes) {
        KeksTask.initialize();
        x = privateScalar;
        v = exponent;
        party = partyBytes;
    }

    function runStage() {
        if (stage == 0) {
            publicPoint = KeksP256.nativeBaseMultiply(x);
            if (publicPoint == null) { fail("native-public"); return; }
            stage = 1;
        } else if (stage == 1) {
            witness = KeksP256.nativeBaseMultiply(v);
            if (witness == null) { fail("native-witness"); return; }
            stage = 2;
        } else {
            var h = KeksP256.hashToScalar(KeksP256.generator(), witness, publicPoint, party);
            var proof = KeksP256.subMod(v, KeksP256.mulModQ(h, x), KeksP256.ORDER_Q);
            finish([KeksP256.encodePacket(proof, publicPoint, witness), publicPoint]);
        }
    }
}

// Sensor round-1/round-2 proof check with generator G:
// proof*G + h*X == V  <=>  x(h*X) == x(V - proof*G).
// Comparing x-coordinates accepts V - proof*G = +/-(h*X); the prover still
// needs the discrete log of X, so this keeps the proof's soundness.
// Result: true, or failure.
class KeksVerifyRound12Task extends KeksTask {
    var proof;
    var publicPoint;
    var witness;
    var party;
    var h;
    var proofPoint;
    var hx;

    // packet is the KeksP256.parsePacket() result [proof, X, V].
    function initialize(packet, partyBytes) {
        KeksTask.initialize();
        proof = packet[0];
        publicPoint = packet[1];
        witness = packet[2];
        party = partyBytes;
    }

    function runStage() {
        if (stage == 0) {
            if (!KeksP256.isOnCurve(publicPoint)) { fail("public-not-on-curve"); return; }
            stage = 1;
        } else if (stage == 1) {
            if (!KeksP256.isOnCurve(witness)) { fail("witness-not-on-curve"); return; }
            stage = 2;
        } else if (stage == 2) {
            h = KeksP256.hashToScalar(KeksP256.generator(), witness, publicPoint, party);
            proofPoint = KeksP256.nativeBaseMultiply(proof);
            if (proofPoint == null) { fail("proof-scalar"); return; }
            stage = 3;
        } else if (stage == 3) {
            hx = KeksP256.nativeEcdhX(h, publicPoint);
            if (hx == null) { fail("hash-scalar"); return; }
            stage = 4;
        } else {
            var w = KeksP256.addAffine(KeksP256.toMontPoint(witness),
                KeksP256.toMontPoint(KeksP256.negate(proofPoint)));
            if (w == null || !KeksP256.jacobianHasX(w, hx)) { fail("proof-mismatch"); return; }
            finish(true);
        }
    }
}

// Our round-3 packet (xDrip Calc.getRound3Packet):
//   G3 = X1 + X3 + X4, x' = x2 * s mod q, A = x'*G3, V = v*G3,
//   proof = v - H(G3, V, A, party) * x' mod q.
// A and V are variable-base products: x from native ECDH, y from recoverY.
// One inversion serves both 1/Z (affine G3) and 1/(2*y(G3)).
// Result: packet160. Fields xp/xp1 are reused by KeksRound3PrepTask.
class KeksRound3PacketTask extends KeksTask {
    var x1Point;
    var x3Point;
    var x4Point;
    var x2;
    var password;
    var v;
    var party;
    var xp;
    var xp1;
    var v1;
    var m1;
    var m3;
    var m4;
    var jac;
    var twoY;
    var zInv;
    var inv2Y;
    var g3;
    var g3Mont;
    var g3Y2;
    var inv2g3y;
    var ax;
    var asx;
    var a;
    var vx;
    var vsx;

    function initialize(ourX1, sensorX3, sensorX4, ourX2, passwordValue, exponent, partyBytes) {
        KeksTask.initialize();
        x1Point = ourX1;
        x3Point = sensorX3;
        x4Point = sensorX4;
        x2 = ourX2;
        password = passwordValue;
        v = exponent;
        party = partyBytes;
    }

    function runStage() {
        var q = KeksP256.ORDER_Q;
        if (stage == 0) {
            xp = KeksP256.mulModQ(x2, password);
            xp1 = KeksP256.addMod(xp, KeksP256.ONE, q);
            v1 = KeksP256.addMod(v, KeksP256.ONE, q);
            if (!KeksP256.isNativeScalar(xp) || !KeksP256.isNativeScalar(xp1) ||
                !KeksP256.isNativeScalar(v1)) { fail("scalar-range"); return; }
            stage = 1;
        } else if (stage == 1) {
            m1 = KeksP256.toMontPoint(x1Point);
            m3 = KeksP256.toMontPoint(x3Point);
            m4 = KeksP256.toMontPoint(x4Point);
            stage = 2;
        } else if (stage == 2) {
            jac = KeksP256.addAffine(m1, m3);
            if (jac == null) { fail("generator-degenerate"); return; }
            stage = 3;
        } else if (stage == 3) {
            jac = KeksP256.addMixed(jac, m4);
            if (jac == null) { fail("generator-degenerate"); return; }
            stage = 4;
        } else if (stage == 4) {
            twoY = KeksP256.pAdd(jac[1], jac[1]);
            inverse = new KeksInverse(KeksP256.fromMontP(KeksP256.pMul(jac[2], twoY)), KeksP256.FIELD_P);
            stage = 5;
        } else if (stage == 5) {
            var invM = inverseMont();
            if (invM == null) { fail("inverse"); return; }
            zInv = KeksP256.pMul(invM, twoY);
            inv2Y = KeksP256.pMul(invM, jac[2]);
            stage = 6;
        } else if (stage == 6) {
            var zi2 = KeksP256.pMul(zInv, zInv);
            var gxm = KeksP256.pMul(jac[0], zi2);
            var gym = KeksP256.pMul(jac[1], KeksP256.pMul(zi2, zInv));
            var z3 = KeksP256.pMul(KeksP256.pMul(jac[2], jac[2]), jac[2]);
            inv2g3y = KeksP256.pMul(inv2Y, z3);
            g3Mont = [gxm, gym];
            g3Y2 = KeksP256.pMul(gym, gym);
            g3 = [KeksP256.fromMontP(gxm), KeksP256.fromMontP(gym)];
            stage = 7;
        } else if (stage == 7) {
            ax = KeksP256.nativeEcdhX(xp, g3);
            stage = 8;
        } else if (stage == 8) {
            asx = KeksP256.nativeEcdhX(xp1, g3);
            stage = 9;
        } else if (stage == 9) {
            var ay = KeksP256.recoverY(g3Mont, g3Y2, inv2g3y, ax, asx);
            if (ay == null) { fail("recover-a"); return; }
            a = [ax, ay];
            stage = 10;
        } else if (stage == 10) {
            vx = KeksP256.nativeEcdhX(v, g3);
            stage = 11;
        } else if (stage == 11) {
            vsx = KeksP256.nativeEcdhX(v1, g3);
            stage = 12;
        } else {
            var vy = KeksP256.recoverY(g3Mont, g3Y2, inv2g3y, vx, vsx);
            if (vy == null) { fail("recover-v"); return; }
            var witness = [vx, vy];
            var h = KeksP256.hashToScalar(g3, witness, a, party);
            var proof = KeksP256.subMod(v, KeksP256.mulModQ(h, xp), q);
            finish(KeksP256.encodePacket(proof, a, witness));
        }
    }
}

// Work that depends only on rounds 1-2, done while the sensor computes its
// round-3 packet: T = x'*X4 (for the shared key) and the sensor's round-3
// generator G3v = X1 + X2 + X3 with 1/(2*y(G3v)). One batched inversion
// covers 1/Z, 1/(2Y) and 1/(2*y(X4)). The task itself is the result.
class KeksRound3PrepTask extends KeksTask {
    var x1Point;
    var x2Point;
    var x3Point;
    var x4Point;
    var xp;
    var xp1;
    var tx;
    var tsx;
    var m1;
    var m2;
    var m3;
    var m4;
    var jac;
    var twoY;
    var twoY4;
    var zy;
    var zInv;
    var inv2Y;
    var inv2y4;
    var t;
    var g3v;
    var g3vMont;
    var g3vY2;
    var inv2g3vy;

    function initialize(ourX1, ourX2, sensorX3, sensorX4, xPrime, xPrime1) {
        KeksTask.initialize();
        x1Point = ourX1;
        x2Point = ourX2;
        x3Point = sensorX3;
        x4Point = sensorX4;
        xp = xPrime;
        xp1 = xPrime1;
    }

    function runStage() {
        if (stage == 0) {
            tx = KeksP256.nativeEcdhX(xp, x4Point);
            stage = 1;
        } else if (stage == 1) {
            tsx = KeksP256.nativeEcdhX(xp1, x4Point);
            stage = 2;
        } else if (stage == 2) {
            m4 = KeksP256.toMontPoint(x4Point);
            m1 = KeksP256.toMontPoint(x1Point);
            m2 = KeksP256.toMontPoint(x2Point);
            stage = 3;
        } else if (stage == 3) {
            jac = KeksP256.addAffine(m1, m2);
            if (jac == null) { fail("generator-degenerate"); return; }
            m3 = KeksP256.toMontPoint(x3Point);
            stage = 4;
        } else if (stage == 4) {
            jac = KeksP256.addMixed(jac, m3);
            if (jac == null) { fail("generator-degenerate"); return; }
            stage = 5;
        } else if (stage == 5) {
            twoY4 = KeksP256.pAdd(m4[1], m4[1]);
            twoY = KeksP256.pAdd(jac[1], jac[1]);
            zy = KeksP256.pMul(jac[2], twoY);
            inverse = new KeksInverse(KeksP256.fromMontP(KeksP256.pMul(zy, twoY4)), KeksP256.FIELD_P);
            stage = 6;
        } else if (stage == 6) {
            var invM = inverseMont();
            if (invM == null) { fail("inverse"); return; }
            inv2y4 = KeksP256.pMul(invM, zy);
            var invZY = KeksP256.pMul(invM, twoY4);
            zInv = KeksP256.pMul(invZY, twoY);
            inv2Y = KeksP256.pMul(invZY, jac[2]);
            stage = 7;
        } else if (stage == 7) {
            var zi2 = KeksP256.pMul(zInv, zInv);
            var gxm = KeksP256.pMul(jac[0], zi2);
            var gym = KeksP256.pMul(jac[1], KeksP256.pMul(zi2, zInv));
            var z3 = KeksP256.pMul(KeksP256.pMul(jac[2], jac[2]), jac[2]);
            inv2g3vy = KeksP256.pMul(inv2Y, z3);
            g3vMont = [gxm, gym];
            g3vY2 = KeksP256.pMul(gym, gym);
            g3v = [KeksP256.fromMontP(gxm), KeksP256.fromMontP(gym)];
            stage = 8;
        } else {
            var ty = KeksP256.recoverY(m4, KeksP256.pMul(m4[1], m4[1]), inv2y4, tx, tsx);
            if (ty == null) { fail("recover-t"); return; }
            t = [tx, ty];
            finish(self);
        }
    }
}

// Sensor round-3 proof check and shared key (xDrip validateRound3Packet and
// getSharedKey): proof*G3v + h*B == V, then
// key = SHA-256(x(x2 * (B - T)))[0..16]. Result: the 16-byte key.
class KeksRound3FinishTask extends KeksTask {
    var proof;
    var b;
    var witness;
    var prep;
    var x2;
    var party;
    var proof1;
    var h;
    var p1x;
    var p1sx;
    var p1y;
    var hx;
    var base;

    // packet is the parsed sensor round-3 [proof, B, V].
    function initialize(packet, prepTask, ourX2, partyBytes) {
        KeksTask.initialize();
        proof = packet[0];
        b = packet[1];
        witness = packet[2];
        prep = prepTask;
        x2 = ourX2;
        party = partyBytes;
    }

    function runStage() {
        if (stage == 0) {
            if (!KeksP256.isOnCurve(b)) { fail("public-not-on-curve"); return; }
            stage = 1;
        } else if (stage == 1) {
            if (!KeksP256.isOnCurve(witness)) { fail("witness-not-on-curve"); return; }
            proof1 = KeksP256.addMod(proof, KeksP256.ONE, KeksP256.ORDER_Q);
            if (!KeksP256.isNativeScalar(proof1)) { fail("proof-scalar"); return; }
            stage = 2;
        } else if (stage == 2) {
            h = KeksP256.hashToScalar(prep.g3v, witness, b, party);
            p1x = KeksP256.nativeEcdhX(proof, prep.g3v);
            if (p1x == null) { fail("proof-scalar"); return; }
            stage = 3;
        } else if (stage == 3) {
            p1sx = KeksP256.nativeEcdhX(proof1, prep.g3v);
            stage = 4;
        } else if (stage == 4) {
            p1y = KeksP256.recoverY(prep.g3vMont, prep.g3vY2, prep.inv2g3vy, p1x, p1sx);
            if (p1y == null) { fail("recover-proof-point"); return; }
            stage = 5;
        } else if (stage == 5) {
            hx = KeksP256.nativeEcdhX(h, b);
            if (hx == null) { fail("hash-scalar"); return; }
            stage = 6;
        } else if (stage == 6) {
            base = KeksP256.addAffine(KeksP256.toMontPoint(witness),
                KeksP256.toMontPoint(KeksP256.negate([p1x, p1y])));
            if (base == null) { fail("proof-mismatch"); return; }
            stage = 7;
        } else if (stage == 7) {
            if (!KeksP256.jacobianHasX(base, hx)) { fail("proof-mismatch"); return; }
            stage = 8;
        } else if (stage == 8) {
            base = KeksP256.addAffine(KeksP256.toMontPoint(b),
                KeksP256.toMontPoint(KeksP256.negate(prep.t)));
            if (base == null) { fail("shared-base-degenerate"); return; }
            inverse = new KeksInverse(KeksP256.fromMontP(base[2]), KeksP256.FIELD_P);
            stage = 9;
        } else if (stage == 9) {
            var invM = inverseMont();
            if (invM == null) { fail("inverse"); return; }
            var zi2 = KeksP256.pMul(invM, invM);
            base = [KeksP256.fromMontP(KeksP256.pMul(base[0], zi2)),
                KeksP256.fromMontP(KeksP256.pMul(base[1], KeksP256.pMul(zi2, invM)))];
            stage = 10;
        } else {
            var kx = KeksP256.nativeEcdhX(x2, base);
            if (kx == null) { fail("shared-point"); return; }
            var hash = new Cryptography.Hash({ :algorithm => Cryptography.HASH_SHA256 });
            hash.update(KeksP256.toBytesBE(kx));
            var digest = hash.digest();
            var key = new [16]b;
            for (var i = 0; i < 16; i += 1) { key[i] = digest[i]; }
            finish(key);
        }
    }
}

// ECDSA-SHA256 signature r||s with the xDrip QR part C key (xDrip
// DSAChallenger). k*G is native; 1/k mod q uses the binary inverse.
// nonce is normally null (random); tests pass a fixed value.
class KeksSignTask extends KeksTask {
    var d;
    var message;
    var fixedNonce;
    var z;
    var k;
    var r;
    var attempts = 0;

    function initialize(privateScalar, messageBytes, nonce) {
        KeksTask.initialize();
        d = privateScalar;
        message = messageBytes;
        fixedNonce = nonce;
    }

    function runStage() {
        if (stage == 0) {
            if (!KeksP256.isNativeScalar(d) || message == null) { fail("key"); return; }
            var hash = new Cryptography.Hash({ :algorithm => Cryptography.HASH_SHA256 });
            hash.update(message);
            z = KeksP256.reduceQ(KeksP256.fromBytesBE(hash.digest(), 0, 32));
            stage = 1;
        } else if (stage == 1) {
            attempts += 1;
            if (attempts > 8) { fail("retries"); return; }
            k = fixedNonce != null ? fixedNonce : KeksP256.randomScalar();
            var noncePoint = KeksP256.nativeBaseMultiply(k);
            if (noncePoint == null) { fail("nonce"); return; }
            r = KeksP256.reduceQ(KeksP256.copy(noncePoint[0]));
            if (KeksP256.isZero(r)) { return; }
            inverse = new KeksInverse(k, KeksP256.ORDER_Q);
            stage = 2;
        } else {
            var kInv = inverse.result;
            inverse = null;
            if (kInv == null) { fail("inverse"); return; }
            var q = KeksP256.ORDER_Q;
            var s = KeksP256.mulModQ(kInv, KeksP256.addMod(z, KeksP256.mulModQ(r, d), q));
            if (KeksP256.isZero(s)) {
                stage = 1;
                return;
            }
            var signature = new [64]b;
            KeksP256.writeBE(r, signature, 0);
            KeksP256.writeBE(s, signature, 32);
            finish(signature);
        }
    }
}
