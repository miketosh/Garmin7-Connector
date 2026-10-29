
"""
Safely inspect xDrip's public G7 keks setup QR or an xDrip preference export.

Accepted inputs:
  * the official QR image URL or a downloaded image (PNG/JPEG)
  * decoded QR text beginning with xdp2:
  * an xDrip preferences XML export containing keks_p1/keks_p2/keks_p3
  * a plain text file with keks_p1=<hex>, keks_p2=<hex>, keks_p3=<hex>

The report includes metadata and consistency checks only. It never prints,
writes, or logs the certificate contents, private scalar, or QR payload.

Dependencies for QR image decoding and X.509/PKCS#8 inspection:
  python -m pip install -r tools/requirements-keks-inspector.txt
"""

from __future__ import annotations

import argparse
import base64
import gzip
import io
import re
import struct
import sys
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict


OFFICIAL_QR_URL = (
    "https://navid200.github.io/xDrip/docs/Dexcom/images/G7_keks_QR.png"
)
PART_NAMES = ("keks_p1", "keks_p2", "keks_p3")
MAX_INPUT_BYTES = 4 * 1024 * 1024
MAX_DECOMPRESSED_BYTES = 1024 * 1024


class InspectError(Exception):
    pass


def decode_xdp2(text: str) -> Dict[str, bytes]:
    """Decode xDrip QRcodeUtils' xdp2: base64 -> gzip -> binary prefs map."""
    encoded = text.strip()
    if not encoded.startswith("xdp2:"):
        raise InspectError("QR text does not start with the expected xdp2: marker.")
    encoded = re.sub(r"\s+", "", encoded[len("xdp2:"):])
    encoded += "=" * (-len(encoded) % 4)
    try:
        packed = base64.b64decode(encoded, validate=False)

        with gzip.GzipFile(fileobj=io.BytesIO(packed), mode="rb") as zipped:
            raw = zipped.read(MAX_DECOMPRESSED_BYTES + 1)
        if len(raw) > MAX_DECOMPRESSED_BYTES:
            raise InspectError("Decoded settings map exceeds the 1 MiB safety limit.")
    except InspectError:
        raise
    except Exception as exc:
        raise InspectError("Could not decode the xdp2 base64/gzip payload.") from exc

    if len(raw) < 2:
        raise InspectError("The decoded binary settings map is too short.")
    count = struct.unpack_from(">H", raw, 0)[0]
    offset = 2
    entries: Dict[str, bytes] = {}
    for _ in range(count):
        if offset + 2 > len(raw):
            raise InspectError("Truncated key length in binary settings map.")
        key_len = struct.unpack_from(">H", raw, offset)[0]
        offset += 2
        if offset + key_len + 2 > len(raw):
            raise InspectError("Truncated key or value length in binary settings map.")
        key = raw[offset:offset + key_len].decode("utf-8")
        offset += key_len
        value_len = struct.unpack_from(">H", raw, offset)[0]
        offset += 2
        if offset + value_len > len(raw):
            raise InspectError("Truncated value in binary settings map.")
        value = raw[offset:offset + value_len]
        offset += value_len

        if key.startswith("b__"):
            entries[key[3:]] = value
    if offset != len(raw):
        raise InspectError("Unexpected trailing bytes in the decoded settings map.")

    parts = {name: entries[name] for name in PART_NAMES if name in entries}
    if len(parts) != 3:
        found = ", ".join(sorted(parts)) or "(none)"
        raise InspectError(
            "QR decoded, but it did not contain all three expected binary "
            f"preferences; found: {found}."
        )
    return parts


def decode_xml_or_text(text: str) -> Dict[str, bytes]:
    parts: Dict[str, bytes] = {}
    try:
        root = ET.fromstring(text)
        for element in root.iter("string"):
            name = element.get("name", "")
            if name in PART_NAMES:
                parts[name] = parse_hex(element.text or "")
    except ET.ParseError:

        for line in text.splitlines():
            match = re.match(
                r"^\s*(keks_p[123])\s*[=:]\s*([0-9A-Fa-f:\t ]+)\s*$",
                line,
            )
            if match:
                parts[match.group(1)] = parse_hex(match.group(2))

    if len(parts) != 3 or any(not parts.get(name) for name in PART_NAMES):
        raise InspectError(
            "Input was neither xdp2: QR text nor an export containing all "
            "keks_p1/keks_p2/keks_p3 values."
        )
    return parts


def parse_hex(value: str) -> bytes:
    clean = re.sub(r"[^0-9A-Fa-f]", "", value)
    if not clean or len(clean) % 2:
        raise InspectError("A certificate/key value is empty or has odd-length hex.")
    try:
        return bytes.fromhex(clean)
    except ValueError as exc:
        raise InspectError("A certificate/key value is not valid hex.") from exc


def read_source(source: str) -> tuple[bytes | None, str | None]:
    """Return (image bytes, decoded text) for a URL or local input."""
    if source.startswith(("https://", "http://")):
        request = urllib.request.Request(
            source, headers={"User-Agent": "G7-keks-inspector/1.0"}
        )
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                data = response.read(MAX_INPUT_BYTES + 1)
        except Exception as exc:
            raise InspectError(f"Could not download input URL: {exc}") from exc
        if len(data) > MAX_INPUT_BYTES:
            raise InspectError("Downloaded input exceeds the 4 MiB safety limit.")
    else:
        try:
            data = Path(source).read_bytes()
        except OSError as exc:
            raise InspectError(f"Could not read input file: {exc}") from exc
        if len(data) > MAX_INPUT_BYTES:
            raise InspectError("Input file exceeds the 4 MiB safety limit.")

    try:
        text = data.decode("utf-8-sig").strip()
    except UnicodeDecodeError:
        text = None
    if text and (
        text.startswith("xdp2:")
        or text.startswith("<")
        or any(line.strip().startswith(("keks_p1=", "keks_p1:")) for line in text.splitlines())
    ):
        return None, text
    return data, None


def decode_image(image_bytes: bytes) -> str:
    try:
        import cv2
        import numpy as np
    except ImportError as exc:
        raise InspectError(
            "QR image decoding needs OpenCV. Install tools/requirements-keks-inspector.txt, "
            "or pass decoded xdp2: text/an xDrip XML export instead."
        ) from exc

    image = cv2.imdecode(np.frombuffer(image_bytes, dtype=np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise InspectError("Input is not a readable image.")
    detector = cv2.QRCodeDetector()
    decoded, points, _ = detector.detectAndDecode(image)
    if not decoded:

        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        decoded, points, _ = detector.detectAndDecode(gray)
    if not decoded:
        raise InspectError(
            "OpenCV could not decode the QR image. Try a saved full-resolution PNG "
            "or scan it to decoded text on a trusted local device."
        )
    return decoded.strip()


def inspect_parts(parts: Dict[str, bytes]) -> int:
    try:
        from cryptography import x509
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import ec
    except ImportError as exc:
        raise InspectError(
            "Certificate/key inspection needs cryptography. Install "
            "tools/requirements-keks-inspector.txt."
        ) from exc

    for name in PART_NAMES:
        if not parts.get(name):
            raise InspectError(f"Missing {name}.")
    cert_a_bytes, cert_b_bytes, key_bytes = (
        parts["keks_p1"], parts["keks_p2"], parts["keks_p3"]
    )
    if len(cert_a_bytes) <= 100 or len(cert_b_bytes) <= 100:
        raise InspectError("Certificate A/B sizes are below xDrip keks's expected minimum.")

    try:
        cert_a = x509.load_der_x509_certificate(cert_a_bytes)
        cert_b = x509.load_der_x509_certificate(cert_b_bytes)
        private_key = serialization.load_der_private_key(key_bytes, password=None)
    except Exception as exc:
        raise InspectError(
            "The three values were found, but one or more is not valid DER X.509/PKCS#8."
        ) from exc

    if not isinstance(private_key, ec.EllipticCurvePrivateKey):
        raise InspectError("keks_p3 is not an elliptic-curve private key.")
    curve_name = private_key.curve.name
    pair_matches = (
        isinstance(cert_b.public_key(), ec.EllipticCurvePublicKey)
        and cert_b.public_key().public_numbers()
        == private_key.public_key().public_numbers()
    )
    issuer_matches = cert_b.issuer == cert_a.subject

    signature_verified = False
    try:
        issuer_public_key = cert_a.public_key()
        if isinstance(issuer_public_key, ec.EllipticCurvePublicKey):
            issuer_public_key.verify(
                cert_b.signature,
                cert_b.tbs_certificate_bytes,
                ec.ECDSA(cert_b.signature_hash_algorithm),
            )
            signature_verified = True
    except Exception:
        signature_verified = False

    now = datetime.now(timezone.utc)
    expired = cert_b.not_valid_after_utc < now
    print("xDrip G7 keks material inspection")
    print("--------------------------------")
    print("No raw QR payload, certificate bytes, private key, or scalar will be printed.")
    print()
    print(f"keks_p1 / certificate A: {len(cert_a_bytes)} bytes")
    print(f"  Subject:   {cert_a.subject.rfc4514_string()}")
    print(f"  Issuer:    {cert_a.issuer.rfc4514_string()}")
    print(f"  Valid from: {cert_a.not_valid_before_utc.isoformat()}")
    print(f"  Valid until:{cert_a.not_valid_after_utc.isoformat()}")
    print()
    print(f"keks_p2 / certificate B: {len(cert_b_bytes)} bytes")
    print(f"  Subject:   {cert_b.subject.rfc4514_string()}")
    print(f"  Issuer:    {cert_b.issuer.rfc4514_string()}")
    print(f"  Valid from: {cert_b.not_valid_before_utc.isoformat()}")
    print(f"  Valid until:{cert_b.not_valid_after_utc.isoformat()}")
    print(f"  Expired according to this computer's clock: {'YES' if expired else 'NO'}")
    print()
    print(f"keks_p3 / PKCS#8 private key: {len(key_bytes)} bytes")
    print(f"  Curve: {curve_name}")
    print(f"  Certificate B public key matches private key: {'YES' if pair_matches else 'NO'}")
    print(f"  Certificate B issuer matches certificate A subject: {'YES' if issuer_matches else 'NO'}")
    print(f"  Certificate B signature verifies under certificate A: {'YES' if signature_verified else 'NO'}")
    print()
    if expired:
        print(
            "WARNING: certificate B's validity date is in the past. This reports the X.509 "
            "date only; it does not prove the sensor checks expiry or that the active xDrip "
            "QR still contains this certificate."
        )
    if curve_name != "secp256r1" or not pair_matches or not issuer_matches or not signature_verified:
        print("RESULT: one or more consistency checks failed.")
        return 2
    print("RESULT: DER formats and certificate/key relationships are internally consistent.")
    print("This does not prove that the sensor accepts this identity today.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "source",
        nargs="?",
        default=OFFICIAL_QR_URL,
        help="official QR URL, local QR image, xdp2: text file, or xDrip preferences XML",
    )
    args = parser.parse_args()
    try:
        image_bytes, decoded_text = read_source(args.source)
        if decoded_text is None:
            decoded_text = decode_image(image_bytes or b"")
        if decoded_text.startswith("xdp2:"):
            parts = decode_xdp2(decoded_text)
        else:
            parts = decode_xml_or_text(decoded_text)
        return inspect_parts(parts)
    except InspectError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
