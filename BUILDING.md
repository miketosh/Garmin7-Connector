# Building

Requirements: Garmin Connect IQ SDK/Monkey C, Python 3.10+, and your own Garmin developer signing key.

The repository keeps generated KEKS material out of version control. Install dependencies with `python -m pip install -r tools/requirements-keks-inspector.txt`, then run `python tools/embed_g7_keks_qr.py` to generate `source/KeksQrMaterial.mc` locally. Do not commit the generated file or publish artifacts containing it without reviewing licensing and redistribution constraints.

Compile with the SDK installed locally and select a device ID listed in `manifest.xml`. The exact command depends on the SDK version.

Run host-side regression tests with:

```sh
python -m unittest tools.test_keks_round_ack tools.test_gatt_subscriptions tools.test_keks_engine_vectors
```

These tests do not prove real BLE pairing. The manifest includes a broad set of targets, including Forerunner 165/170/255/265/570/955/965/970, Fenix 7/8/9 variants, Fenix E, Epix Gen 2/Pro, Enduro 3, Instinct 3, Venu 3/4, and vívoactive 5/6. Confirm product IDs against the installed SDK before adding more devices. Each model needs compilation and physical validation.
