"""Guards for the xDrip-Watch phone link (docs/PHONE_BRIDGE.md)."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
LINK = (ROOT / "source" / "ScoutPhoneLink.mc").read_text(encoding="utf-8")
APP = (ROOT / "source" / "ScoutApp.mc").read_text(encoding="utf-8")


class PhoneLinkTests(unittest.TestCase):
    def test_both_manifests_request_communications(self):
        for name in ("manifest.xml", "sim/manifest.xml"):
            self.assertRegex((ROOT / name).read_text(encoding="utf-8"), r'<iq:uses-permission id="Communications"\s*/>')

    def test_link_registers_once_at_startup(self):
        self.assertIn("ScoutPhoneLink.start();", APP)
        self.assertIn("Communications.registerForPhoneAppMessages(instance.method(:onMessage));", LINK)
        self.assertIn("if (instance != null) { return; }", LINK)

    def test_message_contents_are_never_logged(self):
        # Later phases carry the sensor key; only type and field count may be logged.
        for line in re.findall(r'(?:System|ScoutLog)\.println\((.*?)\);', LINK, re.S):
            self.assertNotIn("data", line.replace("PHONE_MSG", ""))
            self.assertNotIn("message", line)

    def test_key_message_is_validated_and_stored_like_a_watch_pairing(self):
        self.assertIn('if (type.equals("key")) { storeKey(data); }', LINK)
        self.assertIn('if (!(key instanceof Lang.String) || !isHex32(key)) {', LINK)
        self.assertIn('Application.Storage.setValue("savedAuthKeyHex", key.toUpper());', LINK)
        for line in re.findall(r'(?:System|ScoutLog)\.println\((.*?)\);', LINK, re.S):
            self.assertNotIn("+ key", line)

    def test_saved_key_challenge_is_answered_before_logging(self):
        # Build 302: our 04 left 76 ms after the G7's challenge; xDrip answers in 1 ms.
        changed = APP[APP.index("function onCharacteristicChanged(characteristic, value)"):]
        self.assertLess(changed.index("answered = ScoutView.sendSavedKeyChallengeResponse(value);"),
                        changed.index('ScoutLog.println("GA" + authOpcode'))
        self.assertIn("savedKeyCipher = loadSavedKeyCipher();", APP)
        answer = APP[APP.index("static function sendSavedKeyChallengeResponse(authReply)"):APP.index("static function parseHexBytes(")]
        self.assertNotIn("parseHexBytes", answer)
        self.assertLess(answer.index("keksWriteScheduler.queue(null, packet"), answer.index('ScoutLog.println("K404'))
        self.assertIn('Application.Storage.setValue("g7LastTriedName", candidateName);', APP)

    def test_saved_key_proof_is_checked_before_answering_like_juggluco(self):
        # Phone bug report 18:00: the proof matches xDrip's key on its bonded
        # logins and not on the watch's, so a mismatch means "not for this watch".
        answer = APP[APP.index("static function sendSavedKeyChallengeResponse(authReply)"):APP.index("static function savedKeyProofMatches(")]
        self.assertLess(answer.index("if (!savedKeyProofMatches(cipher, authReply)) {"), answer.index("keksWriteScheduler.queue(null, packet"))
        self.assertLess(answer.index("refuseSavedKeyForWatch();"), answer.index("keksWriteScheduler.queue(null, packet"))
        self.assertIn("savedAuthToken = Cryptography.randomBytes(8);", APP)
        proof = APP[APP.index("static function savedKeyProofMatches("):APP.index("static function refuseSavedKeyForWatch(")]
        self.assertIn('ScoutLog.println("SM" + match);', proof)
        self.assertNotIn("markWrongName", proof)

    def test_a_refused_key_sends_the_watch_to_its_own_pairing(self):
        usable = APP[APP.index("static function savedKeyUsable()"):APP.index("static function parseHexBytes(")]
        self.assertIn("refused.equals(ScoutPhoneLink.keyPrint())", usable)
        self.assertIn("if (ScoutView.savedKeyUsable()) {", APP)
        self.assertIn('ScoutView.tryBeginConfiguredFreshKeks("auth-cccd-ready");', APP)
        self.assertLess(LINK.index("Application.Storage.deleteValue(ScoutView.WRONG_NAMES_KEY);"), LINK.index('ScoutLog.println("PK16:"'))

    def test_collector_switch_keeps_the_watch_off_while_the_phone_collects(self):
        # Owner (2026-10-26): like xDrip's Force Wear, one side collects; the
        # watch menu and xDrip's switch set it, the newer change wins.
        col = (ROOT / "source" / "ScoutCollector.mc").read_text(encoding="utf-8")
        self.assertIn('static const KEY = "g7Collector";', col)
        self.assertIn('"t" => "collector", "v" => 1', col)
        self.assertIn("if (ts < changedAt) {", col)
        self.assertIn("ScoutView.stopForPhoneCollector();", col)
        # Build 314: a never-set watch asks at start; xDrip's answer wins the tie.
        self.assertIn("if (pending || (changedAt == 0 && ScoutPlatform.PHONE_QUERY_AT_START)) { sendToPhone(); }", col)
        self.assertIn("ScoutCollector.onStart();", (ROOT / "source" / "ScoutPhoneLink.mc").read_text(encoding="utf-8"))
        self.assertIn("if (ts == changedAt && wanted.equals(mode)) { return; }", col)
        scan = APP[APP.index("static function startScan("):APP.index("static function startScan(") + 1500]
        self.assertLess(scan.index("isUsablePairingCode"), scan.index("if (!ScoutCollector.isWatch()) {"))
        self.assertIn('ScoutLog.println("CBphone-collector:connect");', APP)
        self.assertIn('ScoutLog.println("CBphone-collector:auth-cccd");', APP)
        link = (ROOT / "source" / "ScoutPhoneLink.mc").read_text(encoding="utf-8")
        self.assertIn('if (type.equals("collector")) { ScoutCollector.onPhoneMessage(data); }', link)
        screens = (ROOT / "source" / "ScoutScreens.mc").read_text(encoding="utf-8")
        self.assertIn('new WatchUi.MenuItem("Collector", ScoutCollector.label(), :collector, null)', screens)

    def test_phone_key_sensor_name_keeps_case_but_matches_prefix_case_insensitively(self):
        store = LINK[LINK.index('var name = data["name"];'):LINK.index("cachedKeyName = null;", LINK.index('var name = data["name"];'))]
        self.assertIn('name.substring(0, 4).toUpper().equals("DXCM")', store)
        self.assertIn("? name : null;", store)
        self.assertIn("Application.Storage.setValue(KEY_NAME_KEY, keyName);", store)
        self.assertNotIn("name.toUpper()", store)

    def test_phone_key_names_its_sensor_and_only_that_name_is_tried(self):
        # Owner (2026-10-26): the phone provides the name its key belongs to.
        link = (ROOT / "source" / "ScoutPhoneLink.mc").read_text(encoding="utf-8")
        self.assertIn('static const KEY_NAME_KEY = "g7KeyName";', link)
        self.assertIn('var name = data["name"];', link)
        pick = APP[APP.index("static function offerUnboundCandidate("):APP.index("static function wrongNameList()")]
        self.assertIn("var keyName = ScoutPhoneLink.keyName();", pick)
        self.assertLess(pick.index("if (keyName.length() > 0 && !namesMatch(candidateName, keyName)) {"), pick.index("if (isWrongName(candidateName)) {"))
        self.assertIn('ScoutLog.println("DK");', pick)
        self.assertIn("if (keyName.length() == 0 && namesMatch(candidateName, lastTriedName)", pick)
        save = APP[APP.index("static function savePairingCode(code)"):APP.index("static function tryBeginConfiguredFreshKeks(")]
        self.assertIn("Application.Storage.deleteValue(ScoutPhoneLink.KEY_NAME_KEY);", save)

    def test_collector_mode_sets_the_slot(self):
        # Owner (2026-10-30): one setting, five modes; the slot follows the mode.
        col = (ROOT / "source" / "ScoutCollector.mc").read_text(encoding="utf-8")
        for value in ("none", "phone", "watch02", "watch03", "dual"):
            self.assertIn('value.equals("' + value + '")', col)
        self.assertIn('return mode.equals("watch02") ? 0x02 : 0x03;', col)
        self.assertIn('return mode.equals("watch02") || mode.equals("watch03") || mode.equals("dual");', col)
        policy = APP[APP.index("static function policyDisplayType()"):APP.index("static function applySlotChoice(")]
        self.assertIn("return ScoutCollector.displayType();", policy)
        self.assertNotIn("forcedDisplayType", APP)
        # Migration of the builds 313-421 storage.
        self.assertIn('mode = fromLegacy(stored[0] ? "watch" : "phone");', col)
        self.assertIn('return (slot instanceof Lang.String && slot.equals("02")) ? "watch02" : "watch03";', col)
        self.assertIn('if (value.equals("both")) { return "dual"; }', col)
        self.assertIn("if (wasType != displayType()) { ScoutView.applySlotChoice(", col)
        # Older xDrip: legacy values out, slot messages ignored.
        self.assertIn('if (ScoutPhoneLink.supportsPhoneField("collector.c", 2)) { return mode; }', col)
        link = (ROOT / "source" / "ScoutPhoneLink.mc").read_text(encoding="utf-8")
        self.assertNotIn('type.equals("slot")', link)
        self.assertNotIn('"t" => "slot"', link)
        self.assertIn("collector.c=2", link)
        self.assertNotIn("slot.s=", link)

    def test_status_shows_when_the_last_phone_key_arrived(self):
        # Owner (2026-10-26): the watch should show the key send's outcome and time.
        self.assertIn('noteKey("stored");', LINK)
        self.assertIn('noteKey("rejected");', LINK)
        self.assertIn('Application.Storage.setValue("g7PhoneKeyStatus", text);', LINK)
        screens = (ROOT / "source" / "ScoutScreens.mc").read_text(encoding="utf-8")
        self.assertIn('["Phone key", ScoutPhoneLink.keyStatus()],', screens)
        self.assertIn('["Key sensor", ScoutPhoneLink.keyName().length() > 0 ? ScoutPhoneLink.keyName() : "any"],', screens)

    def test_stored_key_selects_the_saved_key_login(self):
        self.assertIn("if (ScoutView.savedKeyUsable()) {", APP)
        self.assertIn('keksWriteScheduler.queue(null, packet, "SAVED_AUTH_REQUEST", UUID_AUTH)', APP)
        self.assertIn('keksWriteScheduler.queue(null, packet, "SAVED_AUTH_CHALLENGE", UUID_AUTH)', APP)
        # One request on the phone slot; no 2.5 s retry on slot 0x01 any more.
        self.assertNotIn("sendAuthRequestVariant", APP)
        self.assertIn("static const SAVED_KEY_AUTH_TIMEOUT_MS = 15000;", APP)

    def test_accepted_readings_go_to_the_phone_as_glucose_v1(self):
        # xDrip-Watch LOCAL_DATA_EXCHANGE_ARCHITECTURE.md 6.3; only fields
        # the phone advertises are emitted by the watch.
        sender = (ROOT / "source" / "ScoutGlucoseSender.mc").read_text(encoding="utf-8")
        for key in ('"t" => "glucose"', '"v" => 1', '"tx" =>', '"sq" =>', '"mg" =>', '"st" => now - ageSeconds',
                    '"rt" => now', '"tr" =>', '"rel" => true'):
            self.assertIn(key, sender)
        for field in ("alg", "do", "pr"):
            self.assertIn('supportsPhoneField("glucose.' + field + '", 2)', sender)
            self.assertIn('message["' + field + '"]', sender)
        self.assertIn("Communications.transmit(message, null, instance);", sender)
        self.assertIn("if (seq == lastSentSequence", sender)
        accepted = APP[APP.index("ScoutReadingSync.onAccepted(glucoseValue"):]
        self.assertTrue(accepted.split("\n", 1)[1].lstrip().startswith("ScoutGlucoseSender.send(targetName, sequence, glucoseValue, age, signedTrend,"))
        self.assertEqual(1, APP.count("ScoutGlucoseSender.send("))

    def test_saved_key_login_without_a_bond_runs_certificates_and_bonds(self):
        # Juggluco's Wear OS path (DexGattCallback.authenticate): auth 1 and
        # not bonded -> certificates, key challenge, the watch's own bond.
        self.assertIn("ScoutView.g7Bonded = bondedByte == 1 || (bondedByte == 2 && locallyBonded);", APP)
        self.assertIn("ScoutView.beginSavedKeyCertificates();", APP)
        self.assertNotIn("SAVED_AUTH_KEEPALIVE", APP)
        begin = APP[APP.index("static function beginSavedKeyCertificates()"):APP.index("static function clearFreshKeksSecrets()")]
        self.assertIn("freshKeksActive = true;", begin)
        self.assertIn("queueCertificateRequest(0, partA);", begin)
        self.assertIn("freshKeksPrivateScalar = privateScalar;", begin)
        self.assertNotIn("keksPassword =", begin)
        self.assertNotIn("savedAuthKeyHex", begin)

    def test_every_transmit_listener_is_a_connection_listener(self):
        # 2026-10-30 14:42:48: transmit() with a non-ConnectionListener raised
        # an uncatchable "Invalid Value" (ScoutPhoneLink.sendSlotChoice).
        import re
        for path in sorted((ROOT / "source").glob("*.mc")):
            text = path.read_text(encoding="utf-8")
            for match in re.finditer(r"^class (\w+)([^{]*)\{", text, re.M):
                body_start = match.end()
                next_class = re.search(r"^class \w+", text[body_start:], re.M)
                body = text[body_start:body_start + (next_class.start() if next_class else len(text))]
                if "function onComplete() as Void" in body or "function onError() as Void" in body:
                    self.assertIn("Communications.ConnectionListener", match.group(2), (path.name, match.group(1)))
        self.assertIn("null, capsListener);", LINK)

    def test_field_capabilities_gate_newer_fields_for_legacy_peers(self):
        self.assertIn('"t" => "caps", "v" => 1, "f" => LOCAL_FIELD_VERSIONS', LINK)
        self.assertIn("phoneFieldVersions = parseFieldVersions(fields);", LINK)
        self.assertIn('if (type.equals("caps")) { onPhoneCapabilities(data); }', LINK)
        self.assertIn('if (!(wireVersion instanceof Lang.Number) || wireVersion != 1) { return; }', LINK)
        # The five collector modes are collector.c version 2; an older xDrip
        # that does not advertise them gets "watch"/"phone"/"both".
        self.assertIn('collector.c=2', LINK)
        self.assertIn('key.name=2', LINK)
        self.assertIn('return version <= 1;', LINK)
        self.assertIn("version <= 255", LINK)
        self.assertIn("return supported instanceof Lang.Number && supported >= version;", LINK)
        # Review 2026-10-30: each side asks the other at start and answers once.
        self.assertIn('if (requestReply) { message["r"] = 1; }', LINK)
        self.assertIn("if (replyWanted instanceof Lang.Number && replyWanted == 1) { sendCapabilities(false); }", LINK)
        self.assertIn("if (ScoutPlatform.PHONE_QUERY_AT_START) { sendCapabilities(true); }", LINK)
        sender = (ROOT / "source" / "ScoutGlucoseSender.mc").read_text(encoding="utf-8")
        for field in ("glucose.alg", "glucose.do", "glucose.pr"):
            self.assertIn('supportsPhoneField("' + field + '", 2)', sender)


if __name__ == "__main__":
    unittest.main()
