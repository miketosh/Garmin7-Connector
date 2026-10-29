using Toybox.Cryptography;

// P-256 support for the xDrip KEKS port.
//
// Point multiplication runs in the watch's native P-256 code (Connect IQ
// API 3.0.0 Cryptography, little-endian key bytes):
//   * k*G    -> KeyPair built from an imported private scalar; its public key.
//   * x(k*P) -> ECDH between that key pair and an imported public point.
//   * y(k*P) -> recoverY() from x(k*P) and x((k+1)*P) plus one inversion.
// Monkey C keeps only small field/scalar work: 9-limb, 30-bit Long numbers,
// Montgomery products (R = 2^270), binary modular inversion, and a few
// point additions. The simulator showed this Long product costs about a
// quarter of the VM instructions of the old 18 x 15-bit Number version.
//
// Callers must keep each timer callback bounded. `spent` approximates the
// VM work done since the runner last reset it, in thousands of instructions.
class KeksP256 {
    static const FIELD_P = [1073741823l,1073741823l,1073741823l,63l,0l,0l,4096l,1073725440l,65535l];
    static const ORDER_Q = [1013130577l,250030859l,830072911l,968797033l,1073741756l,1073741823l,4095l,1073725440l,65535l];
    static const R2_P = [805306368l,0l,0l,1073741820l,1073741759l,1073741759l,1073741823l,1073739775l,20479l];
    static const R2_Q = [143109207l,98111909l,319260128l,707955384l,419916446l,452662872l,612673835l,705609477l,21931l];
    static const B_MONT = [796391180l,526526916l,37970547l,482985283l,900414465l,737616174l,270911618l,504067203l,391l];
    static const GX = [412664470l,310699287l,515062287l,14639179l,608236151l,865834382l,69500811l,880588875l,27415l];
    static const GY = [935285237l,785973664l,857074924l,864867802l,262018603l,531442160l,670677230l,280543110l,20451l];
    static const ONE = [1l,0l,0l,0l,0l,0l,0l,0l,0l];
    static const Q_NPRIME = 771800143l;

    // Approximate cost, in thousands of VM instructions, measured in the
    // simulator watchdog sweep (about 6.2k per product incl. call overhead).
    static const COST_MONTMUL = 7;
    static const COST_NATIVE = 2;

    static var spent = 0;
    // Shared montMul scratch: the VM is single-threaded and montMul never
    // re-enters itself, so one buffer saves an allocation per product.
    static var mmT = new [11];

    static var nativeReady = false;

    // ---- limb basics -----------------------------------------------------

    static function zero() {
        return [0l,0l,0l,0l,0l,0l,0l,0l,0l];
    }

    static function small(value) {
        var out = zero();
        out[0] = value.toLong();
        return out;
    }

    static function copy(a) {
        var out = new [9];
        for (var i = 0; i < 9; i += 1) { out[i] = a[i]; }
        return out;
    }

    static function compare(a, b) {
        for (var i = 8; i >= 0; i -= 1) {
            if (a[i] != b[i]) { return a[i] > b[i] ? 1 : -1; }
        }
        return 0;
    }

    static function isZero(a) {
        for (var i = 0; i < 9; i += 1) {
            if (a[i] != 0l) { return false; }
        }
        return true;
    }

    static function isOne(a) {
        if (a[0] != 1l) { return false; }
        for (var i = 1; i < 9; i += 1) {
            if (a[i] != 0l) { return false; }
        }
        return true;
    }

    // In-place helpers return the outgoing carry/borrow. Callers keep every
    // operand below 2 * modulus < 2^257, well inside 270 bits.
    static function addInPlace(a, b) {
        var c = 0l;
        for (var i = 0; i < 9; i += 1) {
            var v = a[i] + b[i] + c;
            a[i] = v & 0x3FFFFFFFl;
            c = v >> 30;
        }
        return c;
    }

    static function subInPlace(a, b) {
        var borrow = 0l;
        for (var i = 0; i < 9; i += 1) {
            var d = a[i] - b[i] - borrow;
            if (d < 0l) {
                a[i] = d + 0x40000000l;
                borrow = 1l;
            } else {
                a[i] = d;
                borrow = 0l;
            }
        }
        return borrow;
    }

    static function halveInPlace(a) {
        for (var i = 0; i < 8; i += 1) {
            a[i] = (a[i] >> 1) | ((a[i + 1] & 1l) << 29);
        }
        a[8] = a[8] >> 1;
    }

    // (a + b) mod m and (a - b) mod m for a, b < m.
    static function addMod(a, b, m) {
        var out = copy(a);
        if (addInPlace(out, b) != 0l || compare(out, m) >= 0) { subInPlace(out, m); }
        return out;
    }

    static function subMod(a, b, m) {
        var out = copy(a);
        if (subInPlace(out, b) != 0l) { addInPlace(out, m); }
        return out;
    }

    static function pAdd(a, b) { return addMod(a, b, FIELD_P); }
    static function pSub(a, b) { return subMod(a, b, FIELD_P); }

    // Reduce a value below 2^256 (such as a SHA-256 digest) modulo q < 2^256.
    static function reduceQ(a) {
        if (compare(a, ORDER_Q) >= 0) { subInPlace(a, ORDER_Q); }
        return a;
    }

    // ---- Montgomery products ---------------------------------------------

    // Interleaved (CIOS) Montgomery product a*b/R mod m for a, b < m.
    // Products of 30-bit limbs plus carries stay below 2^61.
    static function montMul(a, b, m, nPrime) {
        spent += COST_MONTMUL;
        var t = mmT;
        for (var z = 0; z < 11; z += 1) { t[z] = 0l; }
        for (var i = 0; i < 9; i += 1) {
            var bi = b[i];
            var c = 0l;
            var uv;
            for (var j = 0; j < 9; j += 1) {
                uv = t[j] + a[j] * bi + c;
                t[j] = uv & 0x3FFFFFFFl;
                c = uv >> 30;
            }
            uv = t[9] + c;
            t[9] = uv & 0x3FFFFFFFl;
            t[10] = uv >> 30;
            var mq = (t[0] * nPrime) & 0x3FFFFFFFl;
            c = (t[0] + mq * m[0]) >> 30;
            for (var k = 1; k < 9; k += 1) {
                uv = t[k] + mq * m[k] + c;
                t[k - 1] = uv & 0x3FFFFFFFl;
                c = uv >> 30;
            }
            uv = t[9] + c;
            t[8] = uv & 0x3FFFFFFFl;
            t[9] = t[10] + (uv >> 30);
        }
        var out = new [9];
        for (var o = 0; o < 9; o += 1) { out[o] = t[o]; }
        if (t[9] != 0l || compare(out, m) >= 0) { subInPlace(out, m); }
        return out;
    }

    static function pMul(a, b) { return montMul(a, b, FIELD_P, 1l); }
    static function toMontP(a) { return montMul(a, R2_P, FIELD_P, 1l); }
    static function fromMontP(a) { return montMul(a, ONE, FIELD_P, 1l); }

    // Normal-form (a * b) mod q: (ab/R) * R^2 / R.
    static function mulModQ(a, b) {
        return montMul(montMul(a, b, ORDER_Q, Q_NPRIME), R2_Q, ORDER_Q, Q_NPRIME);
    }

    // ---- byte conversions ------------------------------------------------

    // Unsigned big-endian bytes[offset .. offset+count) -> limbs (count <= 32).
    static function fromBytesBE(bytes, offset, count) {
        var out = zero();
        var acc = 0l;
        var bits = 0;
        var limb = 0;
        for (var i = offset + count - 1; i >= offset; i -= 1) {
            acc = acc | ((bytes[i] & 0xFF).toLong() << bits);
            bits += 8;
            if (bits >= 30) {
                out[limb] = acc & 0x3FFFFFFFl;
                acc = acc >> 30;
                bits -= 30;
                limb += 1;
            }
        }
        if (limb < 9) { out[limb] = acc; }
        spent += 1;
        return out;
    }

    static function fromBytesLE(bytes, offset, count) {
        var out = zero();
        var acc = 0l;
        var bits = 0;
        var limb = 0;
        for (var i = offset; i < offset + count; i += 1) {
            acc = acc | ((bytes[i] & 0xFF).toLong() << bits);
            bits += 8;
            if (bits >= 30) {
                out[limb] = acc & 0x3FFFFFFFl;
                acc = acc >> 30;
                bits -= 30;
                limb += 1;
            }
        }
        if (limb < 9) { out[limb] = acc; }
        spent += 1;
        return out;
    }

    // Write a value below 2^256 as 32 bytes at out[offset].
    static function writeBE(a, out, offset) {
        var acc = 0l;
        var bits = 0;
        var limb = 0;
        for (var i = offset + 31; i >= offset; i -= 1) {
            if (bits < 8) {
                acc = acc | (a[limb] << bits);
                bits += 30;
                limb += 1;
            }
            out[i] = (acc & 0xFFl).toNumber();
            acc = acc >> 8;
            bits -= 8;
        }
        spent += 1;
    }

    static function writeLE(a, out, offset) {
        var acc = 0l;
        var bits = 0;
        var limb = 0;
        for (var i = offset; i < offset + 32; i += 1) {
            if (bits < 8) {
                acc = acc | (a[limb] << bits);
                bits += 30;
                limb += 1;
            }
            out[i] = (acc & 0xFFl).toNumber();
            acc = acc >> 8;
            bits -= 8;
        }
        spent += 1;
    }

    static function toBytesBE(a) {
        var out = new [32]b;
        writeBE(a, out, 0);
        return out;
    }

    // ---- native P-256 ----------------------------------------------------

    // The native key import throws an uncatchable System Error for scalars
    // 1, q-2 and q-1 (simulator, SDK 9.3.0). Only [2, q-3] may be passed.
    static function isNativeScalar(k) {
        if (k == null || isZero(k) || isOne(k)) { return false; }
        var limit = copy(ORDER_Q);
        subInPlace(limit, small(2));
        return compare(k, limit) < 0;
    }

    static function keyPairFor(scalar) {
        var bytes = new [32]b;
        writeLE(scalar, bytes, 0);
        return new Cryptography.KeyPair({
            :algorithm => Cryptography.KEY_PAIR_ELLIPTIC_CURVE_SECP256R1,
            :privateKey => bytes
        });
    }

    // scalar*G as an affine [x, y] in normal form, or null.
    static function nativeBaseMultiply(scalar) {
        if (!isNativeScalar(scalar)) { return null; }
        spent += COST_NATIVE;
        try {
            var pub = keyPairFor(scalar).getPublicKey().getBytes();
            if (pub == null || pub.size() != 64) { return null; }
            return [fromBytesLE(pub, 0, 32), fromBytesLE(pub, 32, 32)];
        } catch (e) {
            return null;
        }
    }

    // x(scalar * affine) in normal form, or null. The point must already be
    // validated with isOnCurve(); ECDH returns the little-endian x-coordinate.
    static function nativeEcdhX(scalar, affine) {
        if (!isNativeScalar(scalar) || affine == null) { return null; }
        spent += COST_NATIVE;
        try {
            var pubBytes = new [64]b;
            writeLE(affine[0], pubBytes, 0);
            writeLE(affine[1], pubBytes, 32);
            var agreement = new Cryptography.KeyAgreement({
                :protocol => Cryptography.KEY_AGREEMENT_ECDH,
                :privateKey => keyPairFor(scalar).getPrivateKey()
            });
            // createPublicKey's declared parameter type is HashAlgorithm, but
            // Garmin documents passing the KEY_PAIR_* curve constant.
            agreement.addKey(Cryptography.createPublicKey(
                Cryptography.KEY_PAIR_ELLIPTIC_CURVE_SECP256R1 as Cryptography.HashAlgorithm,
                pubBytes));
            var secret = agreement.generateSecret();
            if (secret == null || secret.size() != 32) { return null; }
            return fromBytesLE(secret, 0, 32);
        } catch (e) {
            return null;
        }
    }

    // Confirms the native byte conventions on this firmware before any
    // pairing: 2G must match the known vector and ECDH(3, 2G) must equal
    // x(6G). Uses only scalars 2, 3 and 6, which the import accepts.
    static function calibrateNative() {
        nativeReady = false;
        var twoX = [124164472l,405611505l,1059173210l,576354461l,890946496l,148900882l,888662181l,516301632l,31986l];
        var twoY = [578319313l,940760692l,244851353l,527137167l,875617210l,912988797l,755237523l,356792035l,1911l];
        var two = nativeBaseMultiply(small(2));
        if (two == null) { return "base-multiply-failed"; }
        if (compare(two[0], twoX) != 0 || compare(two[1], twoY) != 0) { return "base-multiply-mismatch"; }
        var six = nativeBaseMultiply(small(6));
        var sixX = nativeEcdhX(small(3), two);
        if (six == null || sixX == null) { return "ecdh-failed"; }
        if (compare(six[0], sixX) != 0) { return "ecdh-mismatch"; }
        nativeReady = true;
        return "ok";
    }

    // ---- curve and points --------------------------------------------------

    static function generator() {
        return [GX, GY];
    }

    // x^3 - 3x + b for Montgomery-form x.
    static function curveRhsMont(xm) {
        var x3 = pMul(pMul(xm, xm), xm);
        var threeX = pAdd(pAdd(xm, xm), xm);
        return pAdd(pSub(x3, threeX), B_MONT);
    }

    // Affine normal-form point validation (range plus curve equation).
    static function isOnCurve(p) {
        if (p == null || p.size() != 2 || compare(p[0], FIELD_P) >= 0 ||
            compare(p[1], FIELD_P) >= 0) { return false; }
        var ym = toMontP(p[1]);
        return compare(pMul(ym, ym), curveRhsMont(toMontP(p[0]))) == 0;
    }

    static function toMontPoint(p) {
        return [toMontP(p[0]), toMontP(p[1])];
    }

    static function negate(p) {
        return [p[0], pSub(zero(), p[1])];
    }

    // Sum of two Montgomery affine points as Jacobian [X, Y, Z]
    // (mmadd-2007-bl, 6 products). Null when p == q or p == -q; the
    // protocol never needs those cases and treats them as failures.
    static function addAffine(p, q) {
        var h = pSub(q[0], p[0]);
        if (isZero(h)) { return null; }
        var r = pSub(q[1], p[1]);
        r = pAdd(r, r);
        var hh = pMul(h, h);
        var i = pAdd(hh, hh);
        i = pAdd(i, i);
        var j = pMul(h, i);
        var v = pMul(p[0], i);
        var x3 = pSub(pSub(pMul(r, r), j), pAdd(v, v));
        var yj = pMul(p[1], j);
        var y3 = pSub(pMul(r, pSub(v, x3)), pAdd(yj, yj));
        return [x3, y3, pAdd(h, h)];
    }

    // Jacobian + Montgomery affine (madd-2007-bl, 11 products), null when
    // the x-coordinates coincide.
    static function addMixed(jp, q) {
        var z1z1 = pMul(jp[2], jp[2]);
        var u2 = pMul(q[0], z1z1);
        var s2 = pMul(q[1], pMul(jp[2], z1z1));
        var h = pSub(u2, jp[0]);
        if (isZero(h)) { return null; }
        var r = pSub(s2, jp[1]);
        r = pAdd(r, r);
        var hh = pMul(h, h);
        var i = pAdd(hh, hh);
        i = pAdd(i, i);
        var j = pMul(h, i);
        var v = pMul(jp[0], i);
        var x3 = pSub(pSub(pMul(r, r), j), pAdd(v, v));
        var yj = pMul(jp[1], j);
        var y3 = pSub(pMul(r, pSub(v, x3)), pAdd(yj, yj));
        var zh = pAdd(jp[2], h);
        var z3 = pSub(pSub(pMul(zh, zh), z1z1), hh);
        return [x3, y3, z3];
    }

    // True when Jacobian point jp has affine x-coordinate xNormal.
    static function jacobianHasX(jp, xNormal) {
        return compare(pMul(toMontP(xNormal), pMul(jp[2], jp[2])), jp[0]) == 0;
    }

    // y-coordinate of Q = k*P from qx = x(k*P) and sx = x((k+1)*P).
    // From x(Q+P) = lambda^2 - qx - px with lambda = (qy - py)/(qx - px):
    //   (qy - py)^2 = (sx + qx + px)(qx - px)^2
    //   qy = (qx^3 - 3qx + b + py^2 - (sx + qx + px)(qx - px)^2) / (2 py)
    // pm is P in Montgomery form, py2m = py^2 (Montgomery), inv2pyM = 1/(2 py)
    // (Montgomery). The final curve check rejects inconsistent x inputs.
    static function recoverY(pm, py2m, inv2pyM, qx, sx) {
        if (qx == null || sx == null) { return null; }
        var qxm = toMontP(qx);
        var d = pSub(qxm, pm[0]);
        if (isZero(d)) { return null; }
        var t = pMul(pAdd(pAdd(toMontP(sx), qxm), pm[0]), pMul(d, d));
        var qy2 = curveRhsMont(qxm);
        var qym = pMul(pSub(pAdd(qy2, py2m), t), inv2pyM);
        if (compare(pMul(qym, qym), qy2) != 0) { return null; }
        return fromMontP(qym);
    }

    // ---- protocol helpers ------------------------------------------------

    // xDrip Calc.getZeroKnowledgeHash: SHA-256 over four-byte big-endian
    // lengths plus SEC1 uncompressed g, gv, gx and the party identifier,
    // reduced modulo q.
    static function hashToScalar(g, gv, gx, party) {
        var data = new [3 * 69 + 4 + party.size()]b;
        var off = 0;
        var points = [g, gv, gx];
        for (var i = 0; i < 3; i += 1) {
            data[off + 3] = 65;
            data[off + 4] = 0x04;
            writeBE(points[i][0], data, off + 5);
            writeBE(points[i][1], data, off + 37);
            off += 69;
        }
        data[off + 3] = party.size();
        for (var p = 0; p < party.size(); p += 1) { data[off + 4 + p] = party[p]; }
        var hash = new Cryptography.Hash({ :algorithm => Cryptography.HASH_SHA256 });
        hash.update(data);
        spent += 2;
        return reduceQ(fromBytesBE(hash.digest(), 0, 32));
    }

    // xDrip Context.getPasswordBigInteger: the code's UTF-8 bytes as one
    // unsigned big-endian integer (not the decimal value). Six-character
    // codes take an ASCII "00" prefix; four-character codes do not.
    static function passwordInteger(password) {
        if (password == null || (password.length() != 4 && password.length() != 6)) { return null; }
        var chars = password.toCharArray();
        var bytes = new [password.length() + (password.length() == 6 ? 2 : 0)]b;
        var off = 0;
        if (password.length() == 6) {
            bytes[0] = 0x30;
            bytes[1] = 0x30;
            off = 2;
        }
        for (var i = 0; i < chars.size(); i += 1) {
            var c = chars[i].toNumber();
            if (c < 0x30 || c > 0x39) { return null; }
            bytes[off + i] = c;
        }
        return fromBytesBE(bytes, 0, bytes.size());
    }

    // Decode xDrip Packet.parse(): five unsigned 32-byte big-endian fields
    // X1, Y1, X2, Y2, proof. Returns [proof, publicPoint, witnessPoint] after
    // range checks only; curve membership is checked by the verify task.
    static function parsePacket(bytes) {
        if (bytes == null || bytes.size() != 160) { return null; }
        var publicPoint = [fromBytesBE(bytes, 0, 32), fromBytesBE(bytes, 32, 32)];
        var witnessPoint = [fromBytesBE(bytes, 64, 32), fromBytesBE(bytes, 96, 32)];
        var proof = fromBytesBE(bytes, 128, 32);
        if (compare(publicPoint[0], FIELD_P) >= 0 || compare(publicPoint[1], FIELD_P) >= 0 ||
            compare(witnessPoint[0], FIELD_P) >= 0 || compare(witnessPoint[1], FIELD_P) >= 0 ||
            compare(proof, ORDER_Q) >= 0) { return null; }
        return [proof, publicPoint, witnessPoint];
    }

    // Wire format: X1||Y1||X2||Y2||proof, no SEC1 prefix.
    static function encodePacket(proof, publicPoint, witnessPoint) {
        var out = new [160]b;
        writeBE(publicPoint[0], out, 0);
        writeBE(publicPoint[1], out, 32);
        writeBE(witnessPoint[0], out, 64);
        writeBE(witnessPoint[1], out, 96);
        writeBE(proof, out, 128);
        return out;
    }

    // Uniform scalar in [2, q-3] by rejection sampling (no modulo bias).
    static function randomScalar() {
        for (var attempt = 0; attempt < 16; attempt += 1) {
            var bytes = Cryptography.randomBytes(32);
            if (bytes == null || bytes.size() != 32) { return null; }
            var scalar = fromBytesBE(bytes, 0, 32);
            if (isNativeScalar(scalar)) { return scalar; }
        }
        return null;
    }

    // The 32-byte private scalar OCTET STRING (04 20 ...) inside the DER
    // PKCS#8 key from xDrip QR part C. Never log the key or the scalar.
    static function extractPrivateScalarPkcs8(der) {
        if (der == null || der.size() < 40 || der.size() > 4096) { return null; }
        for (var i = 0; i + 34 <= der.size(); i += 1) {
            if ((der[i] & 0xFF) == 0x04 && (der[i + 1] & 0xFF) == 0x20) {
                var scalar = fromBytesBE(der, i + 2, 32);
                if (isNativeScalar(scalar)) { return scalar; }
            }
        }
        return null;
    }
}

// Binary extended-Euclid modular inverse for an odd prime modulus, resumable
// in bounded slices. About 768 micro-steps for 256-bit operands; each costs a
// few hundred VM instructions, so a full inverse is far cheaper than the
// ~270-product Fermat exponentiation it replaces.
class KeksInverse {
    var u;
    var v;
    var x1;
    var x2;
    var m;
    var done;
    var result;

    function initialize(a, modulus) {
        m = modulus;
        done = false;
        result = null;
        if (a == null || KeksP256.isZero(a) || KeksP256.compare(a, modulus) >= 0) {
            done = true;
            return;
        }
        u = KeksP256.copy(a);
        v = KeksP256.copy(modulus);
        x1 = KeksP256.small(1);
        x2 = KeksP256.zero();
    }

    // Runs up to maxSteps micro-steps; returns true once finished.
    // Invariants: x1 * a == u and x2 * a == v (mod m).
    function step(maxSteps) {
        var steps = 0;
        while (!done && steps < maxSteps) {
            steps += 1;
            if (KeksP256.isOne(u)) {
                result = x1;
                done = true;
            } else if (KeksP256.isOne(v)) {
                result = x2;
                done = true;
            } else if ((u[0] & 1l) == 0l) {
                KeksP256.halveInPlace(u);
                if ((x1[0] & 1l) != 0l) { KeksP256.addInPlace(x1, m); }
                KeksP256.halveInPlace(x1);
            } else if ((v[0] & 1l) == 0l) {
                KeksP256.halveInPlace(v);
                if ((x2[0] & 1l) != 0l) { KeksP256.addInPlace(x2, m); }
                KeksP256.halveInPlace(x2);
            } else if (KeksP256.compare(u, v) >= 0) {
                KeksP256.subInPlace(u, v);
                if (KeksP256.subInPlace(x1, x2) != 0l) { KeksP256.addInPlace(x1, m); }
            } else {
                KeksP256.subInPlace(v, u);
                if (KeksP256.subInPlace(x2, x1) != 0l) { KeksP256.addInPlace(x2, m); }
            }
        }
        KeksP256.spent += steps / 2 + 1;
        return done;
    }
}
