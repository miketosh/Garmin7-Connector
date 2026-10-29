"""Host-side transcript reference for the xDrip+ G7 KEKS protocol.

Independent test oracle only. It is not production crypto and must never be used
to handle live sensor credentials.
"""
from __future__ import annotations
import hashlib
from keks_p256_reference import G, N, P, Point, is_on_curve, point_add, scalar_multiply

PARTY_CLIENT = b"client"
PARTY_SERVER = b"server"
FIELD_BYTES = 32
PACKET_BYTES = 160

def encode_point_uncompressed(point: Point) -> bytes:
    if point is None or not is_on_curve(point):
        raise ValueError("invalid or infinite P-256 point")
    x, y = point
    return b"\x04" + x.to_bytes(FIELD_BYTES, "big") + y.to_bytes(FIELD_BYTES, "big")

def length_prefix(data: bytes) -> bytes:
    return len(data).to_bytes(4, "big") + data

def zkp_hash_scalar(generator: Point, witness: Point, public_point: Point, party: bytes) -> int:
    transcript = b"".join(length_prefix(item) for item in (
        encode_point_uncompressed(generator),
        encode_point_uncompressed(witness),
        encode_point_uncompressed(public_point),
        party,
    ))
    return int.from_bytes(hashlib.sha256(transcript).digest(), "big") % N


def password_integer(password: str) -> int:
    """Match xDrip Context.getPasswordBigInteger byte interpretation."""
    if not (password.isascii() and password.isdigit() and len(password) in (4, 6)):
        raise ValueError("expected a four- or six-digit ASCII pairing code")
    raw = password.encode("ascii")
    if len(password) == 6:
        raw = b"00" + raw  # xDrip's PREFIX is two ASCII zero bytes for six digits
    return int.from_bytes(raw, "big")


def round3_private_scalar(round2_private: int, password: str) -> int:
    """xDrip round-3 private scalar: round2Private * passwordInteger mod q."""
    if not (0 <= round2_private < N):
        raise ValueError("private scalar outside subgroup order")
    return (round2_private * password_integer(password)) % N

def make_zkp_packet(generator: Point, private_scalar: int, exponent: int, party: bytes):
    if not (1 <= private_scalar < N and 1 <= exponent < N):
        raise ValueError("scalars must be in [1, q-1]")
    public_point = scalar_multiply(private_scalar, generator)
    witness = scalar_multiply(exponent, generator)
    h = zkp_hash_scalar(generator, witness, public_point, party)
    proof = (exponent - h * private_scalar) % N
    return proof, public_point, witness


def derive_shared_key(round2_private: int, password: str, remote_round2, remote_round3) -> bytes:
    """Port xDrip Calc.getSharedKey/getShortSharedKey for test transcripts."""
    password_value = password_integer(password)
    private_times_password = (round2_private * password_value) % N
    remote_round2_public = remote_round2[1]
    remote_round3_public = remote_round3[1]
    subtraction_point = scalar_multiply(private_times_password, remote_round2_public)
    if subtraction_point is None:
        raise ValueError("degenerate transcript")
    negated = (subtraction_point[0], (-subtraction_point[1]) % P)
    shared_base = point_add(remote_round3_public, negated)
    shared_point = scalar_multiply(round2_private, shared_base)
    if shared_point is None:
        raise ValueError("degenerate shared point")
    return hashlib.sha256(shared_point[0].to_bytes(FIELD_BYTES, "big")).digest()[:16]


def ecdsa_sign_with_nonce(private_scalar: int, nonce: int, message: bytes) -> bytes:
    """Deterministic ECDSA-SHA256 vector helper; host-test oracle only."""
    if not (1 <= private_scalar < N and 1 <= nonce < N):
        raise ValueError("private scalar and nonce must be in [1, q-1]")
    digest = int.from_bytes(hashlib.sha256(message).digest(), "big") % N
    nonce_point = scalar_multiply(nonce, G)
    assert nonce_point is not None
    r = nonce_point[0] % N
    s = (pow(nonce, -1, N) * (digest + r * private_scalar)) % N
    if r == 0 or s == 0:
        raise ValueError("degenerate ECDSA signature")
    return r.to_bytes(32, "big") + s.to_bytes(32, "big")


def verify_zkp(generator: Point, public_point: Point, witness: Point, proof: int, party: bytes) -> bool:
    if generator is None or public_point is None or witness is None or not (0 <= proof < N):
        return False
    h = zkp_hash_scalar(generator, witness, public_point, party)
    lhs = point_add(scalar_multiply(proof, generator), scalar_multiply(h, public_point))
    return lhs == witness

def serialize_packet(proof: int, public_point: Point, witness: Point) -> bytes:
    if not 0 <= proof < N:
        raise ValueError("proof must fit the P-256 subgroup order")
    if public_point is None or witness is None:
        raise ValueError("packet points must not be infinity")
    if not is_on_curve(public_point) or not is_on_curve(witness):
        raise ValueError("packet points must be valid P-256 points")
    x1, y1 = public_point
    x2, y2 = witness
    packet = b"".join(value.to_bytes(FIELD_BYTES, "big") for value in (x1, y1, x2, y2, proof))
    if len(packet) != PACKET_BYTES:
        raise AssertionError("internal packet framing error")
    return packet

def parse_packet(packet: bytes) -> tuple[int, Point, Point]:
    if len(packet) < PACKET_BYTES:
        raise ValueError("incomplete KEKS packet")
    packet = packet[:PACKET_BYTES]  # upstream parses the first fixed-size frame
    values = [int.from_bytes(packet[offset:offset+FIELD_BYTES], "big")
              for offset in range(0, PACKET_BYTES, FIELD_BYTES)]
    public_point, witness, proof = (values[0], values[1]), (values[2], values[3]), values[4]
    if not is_on_curve(public_point) or not is_on_curve(witness):
        raise ValueError("packet includes a non-curve point")
    if proof >= N:
        raise ValueError("proof outside the scalar subgroup")
    return proof, public_point, witness
