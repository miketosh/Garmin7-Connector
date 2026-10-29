"""Independent, dependency-free P-256 arithmetic oracle for the Garmin port.

This is a host-side reference, not production cryptography. It deliberately uses
Python big integers so Monkey C implementations can be checked against known
vectors. Never use this module to handle real sensor credentials.
"""
from __future__ import annotations

from typing import Optional, Tuple

P = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF
A = P - 3
B = 0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B
GX = 0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296
GY = 0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5
N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
Point = Optional[Tuple[int, int]]
G: Point = (GX, GY)


def is_on_curve(point: Point) -> bool:
    if point is None:
        return True
    x, y = point
    if not (0 <= x < P and 0 <= y < P):
        return False
    return (y * y - (x * x * x + A * x + B)) % P == 0


def point_add(left: Point, right: Point) -> Point:
    """Affine group addition; None represents the point at infinity."""
    if left is None:
        return right
    if right is None:
        return left
    x1, y1 = left
    x2, y2 = right
    if not is_on_curve(left) or not is_on_curve(right):
        raise ValueError("point is not on P-256")
    if x1 == x2 and (y1 + y2) % P == 0:
        return None
    if left == right:
        if y1 == 0:
            return None
        slope = ((3 * x1 * x1 + A) * pow(2 * y1, -1, P)) % P
    else:
        slope = ((y2 - y1) * pow((x2 - x1) % P, -1, P)) % P
    x3 = (slope * slope - x1 - x2) % P
    y3 = (slope * (x1 - x3) - y1) % P
    return (x3, y3)


def scalar_multiply(scalar: int, point: Point = G) -> Point:
    """Reference double-and-add. Not constant-time; never use for secrets."""
    if not isinstance(scalar, int) or scalar < 0:
        raise ValueError("scalar must be a non-negative integer")
    if point is not None and not is_on_curve(point):
        raise ValueError("point is not on P-256")
    result: Point = None
    addend = point
    k = scalar
    while k:
        if k & 1:
            result = point_add(result, addend)
        addend = point_add(addend, addend)
        k >>= 1
    return result


def encode_uncompressed(point: Point) -> bytes:
    if point is None or not is_on_curve(point):
        raise ValueError("cannot encode point at infinity or invalid point")
    x, y = point
    return b"\x04" + x.to_bytes(32, "big") + y.to_bytes(32, "big")


def decode_uncompressed(data: bytes) -> Point:
    if len(data) != 65 or data[0] != 4:
        raise ValueError("expected a 65-byte uncompressed P-256 point")
    point = (int.from_bytes(data[1:33], "big"), int.from_bytes(data[33:65], "big"))
    if not is_on_curve(point):
        raise ValueError("encoded point is not on P-256")
    return point
