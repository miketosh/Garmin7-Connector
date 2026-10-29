using Toybox.Application;
using Toybox.Cryptography;
using Toybox.Lang;

// Phone bridge intentionally disabled in the public standalone test build.
// The saved-key fingerprint is retained only for local watch diagnostics.
class ScoutPhoneLink {
    static const KEY_NAME_KEY = "g7KeyName";
    static var cachedKeyName = null;
    static var printedHex = null;
    static var cachedPrint = "?";

    static function keyNameUpper() { return ""; }

    static function keyPrint() {
        var hex = null;
        try { hex = Application.Storage.getValue("savedAuthKeyHex"); } catch (e) { hex = null; }
        if (hex == null) {
            try { hex = Application.Properties.getValue("savedAuthKeyHex"); } catch (e2) { hex = null; }
        }
        if (!(hex instanceof Lang.String)) { return "?"; }
        if (!hex.equals(printedHex)) {
            printedHex = hex;
            cachedPrint = "?";
            var bytes = ScoutView.parseHexBytes(hex);
            if (bytes != null && bytes.size() == 16) {
                var hash = new Cryptography.Hash({ :algorithm => Cryptography.HASH_SHA256 });
                hash.update(bytes);
                var digest = hash.digest();
                cachedPrint = (digest[0] & 0xFF).format("%02X") + (digest[1] & 0xFF).format("%02X");
            }
        }
        return cachedPrint;
    }
}
