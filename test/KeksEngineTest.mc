using Toybox.Lang;
using Toybox.Test;





(:test)
class KeksTestUtil {
    static function bytes(hex) {
        var out = new [hex.length() / 2]b;
        for (var i = 0; i < out.size(); i += 1) {
            out[i] = hex.substring(2 * i, 2 * i + 2).toNumberWithBase(16);
        }
        return out;
    }

    static function scalar(hex) {
        return KeksP256.fromBytesBE(bytes(hex), 0, 32);
    }

    static function sameBytes(a, b) {
        if (a == null || b == null || a.size() != b.size()) { return false; }
        for (var i = 0; i < a.size(); i += 1) {
            if ((a[i] & 0xFF) != (b[i] & 0xFF)) { return false; }
        }
        return true;
    }

    static function run(task) {
        for (var i = 0; i < 20000 && !task.done; i += 1) { task.step(); }
        return task;
    }

    static function client() { return [0x63,0x6C,0x69,0x65,0x6E,0x74]b; }
    static function server() { return [0x73,0x65,0x72,0x76,0x65,0x72]b; }

    static function parsed(hex) {
        return KeksP256.parsePacket(bytes(hex));
    }
}

(:test)
function testNativeCalibration(logger) {
    var status = KeksP256.calibrateNative();
    logger.debug("calibration=" + status);
    return status.equals("ok") && KeksP256.nativeReady;
}

(:test)
function testByteConversionsRoundTrip(logger) {
    var raw = KeksTestUtil.bytes(KeksEngineVectors.X1);
    var limbs = KeksP256.fromBytesBE(raw, 0, 32);
    var le = new [32]b;
    KeksP256.writeLE(limbs, le, 0);
    return KeksTestUtil.sameBytes(KeksP256.toBytesBE(limbs), raw) &&
        KeksP256.compare(KeksP256.fromBytesLE(le, 0, 32), limbs) == 0;
}

(:test)
function testPasswordIntegerUsesAsciiBytes(logger) {
    var value = KeksP256.passwordInteger("2468");
    var expected = KeksP256.fromBytesBE([0x32,0x34,0x36,0x38]b, 0, 4);
    return KeksP256.compare(value, expected) == 0 &&
        KeksP256.passwordInteger("24a8") == null &&
        KeksP256.passwordInteger("246") == null;
}

(:test)
function testBinaryInverse(logger) {
    var a = KeksTestUtil.scalar(KeksEngineVectors.V1);
    var invP = KeksTestUtil.run(new KeksTestInverse(a, KeksP256.FIELD_P)).result;
    var invQ = KeksTestUtil.run(new KeksTestInverse(a, KeksP256.ORDER_Q)).result;
    var oneP = KeksP256.fromMontP(KeksP256.pMul(KeksP256.toMontP(a), KeksP256.toMontP(invP)));
    var oneQ = KeksP256.mulModQ(a, invQ);
    return KeksP256.isOne(oneP) && KeksP256.isOne(oneQ);
}

(:test)
class KeksTestInverse {
    var inverse;
    var done = false;
    var result = null;

    function initialize(a, modulus) {
        inverse = new KeksInverse(a, modulus);
    }

    function step() {
        done = inverse.step(64);
        result = inverse.result;
    }
}

(:test)
function testRound1And2PacketsMatchReference(logger) {
    KeksP256.calibrateNative();
    var c1 = KeksTestUtil.run(new KeksMakeRound12Task(KeksTestUtil.scalar(KeksEngineVectors.X1),
        KeksTestUtil.scalar(KeksEngineVectors.V1), KeksTestUtil.client()));
    var c2 = KeksTestUtil.run(new KeksMakeRound12Task(KeksTestUtil.scalar(KeksEngineVectors.X2),
        KeksTestUtil.scalar(KeksEngineVectors.V2), KeksTestUtil.client()));
    return c1.result != null && c2.result != null &&
        KeksTestUtil.sameBytes(c1.result[0], KeksTestUtil.bytes(KeksEngineVectors.C1)) &&
        KeksTestUtil.sameBytes(c2.result[0], KeksTestUtil.bytes(KeksEngineVectors.C2));
}

(:test)
function testVerifiesSensorRound12AndRejectsTampering(logger) {
    var s1 = KeksTestUtil.run(new KeksVerifyRound12Task(KeksTestUtil.parsed(KeksEngineVectors.S1), KeksTestUtil.server()));
    var s2 = KeksTestUtil.run(new KeksVerifyRound12Task(KeksTestUtil.parsed(KeksEngineVectors.S2), KeksTestUtil.server()));
    var wrongParty = KeksTestUtil.run(new KeksVerifyRound12Task(KeksTestUtil.parsed(KeksEngineVectors.S1), KeksTestUtil.client()));
    var tampered = KeksTestUtil.bytes(KeksEngineVectors.S1);
    tampered[159] = (tampered[159] ^ 0x01) & 0xFF;
    var bad = KeksTestUtil.run(new KeksVerifyRound12Task(KeksP256.parsePacket(tampered), KeksTestUtil.server()));
    logger.debug("s1=" + s1.result + " s2=" + s2.result + " party=" + wrongParty.failure + " tampered=" + bad.failure);
    return s1.result == true && s2.result == true && wrongParty.result == null && bad.result == null;
}

(:test)
function testRound3PacketAndSharedKeyMatchReference(logger) {
    KeksP256.calibrateNative();
    var x2 = KeksTestUtil.scalar(KeksEngineVectors.X2);
    var x1Point = KeksTestUtil.parsed(KeksEngineVectors.C1)[1];
    var x2Point = KeksTestUtil.parsed(KeksEngineVectors.C2)[1];
    var x3Point = KeksTestUtil.parsed(KeksEngineVectors.S1)[1];
    var x4Point = KeksTestUtil.parsed(KeksEngineVectors.S2)[1];
    var round3 = KeksTestUtil.run(new KeksRound3PacketTask(x1Point, x3Point, x4Point, x2,
        KeksP256.passwordInteger(KeksEngineVectors.PASSWORD),
        KeksTestUtil.scalar(KeksEngineVectors.V3), KeksTestUtil.client()));
    if (round3.result == null || !KeksTestUtil.sameBytes(round3.result, KeksTestUtil.bytes(KeksEngineVectors.C3))) {
        logger.debug("round3 failure=" + round3.failure);
        return false;
    }
    var prep = KeksTestUtil.run(new KeksRound3PrepTask(x1Point, x2Point, x3Point, x4Point, round3.xp, round3.xp1));
    if (prep.result == null) {
        logger.debug("prep failure=" + prep.failure);
        return false;
    }
    var finish = KeksTestUtil.run(new KeksRound3FinishTask(KeksTestUtil.parsed(KeksEngineVectors.S3), prep, x2, KeksTestUtil.server()));
    logger.debug("finish failure=" + finish.failure);
    if (finish.result == null || !KeksTestUtil.sameBytes(finish.result, KeksTestUtil.bytes(KeksEngineVectors.KEY))) {
        return false;
    }

    var tampered = KeksTestUtil.bytes(KeksEngineVectors.S3);
    tampered[150] = (tampered[150] ^ 0x40) & 0xFF;
    var bad = KeksTestUtil.run(new KeksRound3FinishTask(KeksP256.parsePacket(tampered), prep, x2, KeksTestUtil.server()));
    logger.debug("tampered failure=" + bad.failure);
    return bad.result == null && bad.failure != null;
}

(:test)
function testEcdsaMatchesReference(logger) {
    KeksP256.calibrateNative();
    var message = KeksTestUtil.bytes(KeksEngineVectors.MESSAGE);
    var big = KeksTestUtil.run(new KeksSignTask(KeksTestUtil.scalar(KeksEngineVectors.SIG_D), message,
        KeksTestUtil.scalar(KeksEngineVectors.SIG_K)));
    var small = KeksTestUtil.run(new KeksSignTask(KeksP256.small(5), message, KeksP256.small(7)));
    var random = KeksTestUtil.run(new KeksSignTask(KeksP256.small(5), message, null));
    return KeksTestUtil.sameBytes(big.result, KeksTestUtil.bytes(KeksEngineVectors.SIG)) &&
        KeksTestUtil.sameBytes(small.result, KeksTestUtil.bytes(KeksEngineVectors.SIG_SMALL)) &&
        random.result != null && random.result.size() == 64;
}

(:test)
function testNativeScalarGuard(logger) {
    var q = KeksP256.ORDER_Q;
    var qMinus2 = KeksP256.subMod(KeksP256.zero(), KeksP256.small(2), q);
    var qMinus3 = KeksP256.subMod(KeksP256.zero(), KeksP256.small(3), q);
    return !KeksP256.isNativeScalar(KeksP256.small(1)) && KeksP256.isNativeScalar(KeksP256.small(2)) &&
        !KeksP256.isNativeScalar(qMinus2) && KeksP256.isNativeScalar(qMinus3) &&
        KeksP256.nativeBaseMultiply(KeksP256.small(1)) == null;
}
