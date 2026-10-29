# Building

Requirements: Garmin Connect IQ SDK/Monkey C, Python 3.10+, and your own Garmin developer signing key.

The repository keeps generated KEKS material out of version control. Install dependencies with `python -m pip install -r tools/requirements-keks-inspector.txt`, then run `python tools/embed_g7_keks_qr.py` to generate `source/KeksQrMaterial.mc` locally. Do not commit the generated file or publish artifacts containing it without reviewing licensing and redistribution constraints.

Compile with the SDK installed locally and select a device ID listed in `manifest.xml`. The exact command depends on the SDK version.

Run host-side regression tests with:

```sh
python -m unittest tools.test_keks_round_ack tools.test_gatt_subscriptions tools.test_keks_engine_vectors
```

These tests do not prove real BLE pairing. Current targets include Forerunner 255/255 Music, 265/955/965, Fenix 7/7S/7X, and Epix Gen 2. Confirm product IDs against the installed SDK before adding more devices. Each model needs compilation and physical validation.
