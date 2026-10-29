using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.WatchUi;


module ScoutScreens {


    const IDLE_MS = 10000;
    var depth = 0;
    var closer = null;

    function push(view, delegate, transition) {
        WatchUi.pushView(view, delegate, transition);
        depth += 1;
        touch();
    }

    function touch() {
        if (closer == null) { closer = new ScoutScreenCloser(); }
        ScoutClock.get().schedule("screensIdle", IDLE_MS, closer.method(:close));
    }

    function closeAll() {
        ScoutClock.get().cancel("screensIdle");
        while (depth > 0) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            depth -= 1;
        }
    }

    function onDashboardShown() {
        depth = 0;
        ScoutClock.get().cancel("screensIdle");
    }

    function pushMenu() {
        var menu = new WatchUi.Menu2({ :title => "G7 Scout" });
        menu.addItem(new WatchUi.MenuItem("Pairing code", codeSubLabel(), :code, null));
        menu.addItem(new WatchUi.MenuItem("Collector", ScoutCollector.label(), :collector, null));
        menu.addItem(new WatchUi.MenuItem("Debug info", null, :debug, null));
        menu.addItem(new WatchUi.MenuItem("Status", null, :status, null));
        push(menu, new ScoutMenuDelegate(), WatchUi.SLIDE_UP);
    }

    function codeSubLabel() {
        var code = ScoutView.getConfiguredPairingCode();
        if (!ScoutView.isUsablePairingCode(code)) { return code + " (pairing off)"; }
        return code + (ScoutView.pairingCodeStored ? "" : " (default)");
    }

    function debugLines() {
        var lines = [];
        lines.add("drop @" + (ScoutView.lastAbortConnectMs >= 0 ? ScoutView.lastAbortConnectMs + "ms" : "--") +
            "  #" + ScoutView.connectionAttemptNumber);
        for (var i = 0; i < ScoutView.DEBUG_LINES; i += 1) {
            var line = ScoutView.debugLine(i);
            if (line == null) { break; }
            lines.add(line);
        }
        if (lines.size() == 1) { lines.add("no events yet"); }
        return lines;
    }

    function statusLines() {
        return [
            ["State", ScoutView.statusTextForUi()],
            ["Build", ScoutApp.buildVersion()],
            ["Last BG", ScoutView.glucoseHasValue ? ScoutView.glucoseValue + " mg/dL" : "--"],
            ["Sensor", ScoutView.targetBound ? ScoutView.targetName : "not bound"],
            ["Code", codeSubLabel()],
            ["Collector", ScoutCollector.label() + " (" + ScoutCollector.lastResult + ")"],
            ["Connects", "" + ScoutView.connectionAttemptNumber],
            ["Watch battery", System.getSystemStats().battery.toNumber() + "%"],
            ["Sensor age", sensorAgeText()],
            ["Saved key", ScoutView.hasSavedAuthKey() ? "#" + ScoutPhoneLink.keyPrint() + (ScoutView.savedKeyUsable() ? " yes" : " not ours") : "no"],
            ["Slot", (ScoutCollector.isBoth() ? "dual" : (ScoutView.forcedDisplayType() != 0 ? "forced" : ScoutView.slotPolicy)) + " (" + ScoutView.g7DisplayType + ")"],
        ];
    }


    function sensorAgeText() {
        if (ScoutView.lastSensorClockSeconds < 0) { return "--"; }
        var seconds = ScoutView.lastSensorClockSeconds +
            (System.getTimer() - ScoutView.lastSensorClockAtMs) / 1000;
        var tenths = seconds / 8640;
        return (tenths / 10) + "." + (tenths % 10) + "d / 10.5d";
    }
}

class ScoutMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        ScoutScreens.touch();
        var id = item.getId();
        if (id == :code) {
            var view = new ScoutCodeView();
            ScoutScreens.push(view, new ScoutCodeDelegate(view, item), WatchUi.SLIDE_LEFT);
        } else if (id == :collector) {

            ScoutCollector.toggle();
            item.setSubLabel(ScoutCollector.label());
        } else if (id == :debug) {
            var view = new ScoutListView("DEBUG", :debug);
            ScoutScreens.push(view, new ScoutListDelegate(view), WatchUi.SLIDE_LEFT);
        } else if (id == :log) {
        } else if (id == :status) {
            var view = new ScoutListView("STATUS", :status);
            ScoutScreens.push(view, new ScoutListDelegate(view), WatchUi.SLIDE_LEFT);
        }
    }
}






class ScoutCodeView extends WatchUi.View {
    static const FOCUS_CANCEL = 0;
    static const FOCUS_SAVE = 5;

    var digits = new [4];
    var focus = 1;

    function initialize() {
        View.initialize();
        var chars = ScoutView.getConfiguredPairingCode().toCharArray();
        for (var i = 0; i < 4; i += 1) {
            digits[i] = chars[i] == '-' ? -1 : chars[i].toNumber() - 48;
        }
    }

    static function symbol(value) {
        return value < 0 ? "-" : "" + value;
    }

    static function stepValue(value, step) {
        return (value + 1 + step + 11) % 11 - 1;
    }

    function code() {
        return symbol(digits[0]) + symbol(digits[1]) + symbol(digits[2]) + symbol(digits[3]);
    }

    function turn(step) {
        if (focus < 1 || focus > 4) { return; }
        digits[focus - 1] = stepValue(digits[focus - 1], step);
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cy = h / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(w / 2, h * 0.12, Graphics.FONT_TINY, "PAIRING CODE", Graphics.TEXT_JUSTIFY_CENTER);

        var boxW = w * 0.13;
        var gap = w * 0.025;
        var arrowW = w * 0.12;
        var arrowGap = w * 0.03;
        var boxH = h * 0.2;
        var x = (w - (2 * arrowW + 2 * arrowGap + 4 * boxW + 3 * gap)) / 2;

        drawCancelArrow(dc, x + arrowW / 2, cy, arrowW * 0.35, focus == FOCUS_CANCEL);
        x += arrowW + arrowGap;
        for (var i = 0; i < 4; i += 1) {
            var focused = focus == i + 1;
            var cx = x + boxW / 2;
            dc.setColor(focused ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - boxH / 2 - 2, Graphics.FONT_XTINY, symbol(stepValue(digits[i], 1)),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(cx, cy + boxH / 2 + 2, Graphics.FONT_XTINY, symbol(stepValue(digits[i], -1)),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setPenWidth(focused ? 3 : 1);
            dc.setColor(focused ? Graphics.COLOR_ORANGE : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(x, cy - boxH * 0.35, boxW, boxH * 0.7, 4);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, Graphics.FONT_MEDIUM, symbol(digits[i]),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            x += boxW + gap;
        }
        x += arrowGap - gap;
        drawEnterArrow(dc, x + arrowW / 2, cy, arrowW * 0.35, focus == FOCUS_SAVE);
        dc.setPenWidth(1);

        var hint = focus == FOCUS_CANCEL ? "START cancels" : "UP/DOWN change";
        if (focus == FOCUS_SAVE) {
            hint = ScoutView.isUsablePairingCode(code()) ? "START saves" : "saves: pairing off";
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.78, Graphics.FONT_XTINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawCancelArrow(dc, cx, cy, s, focused) {
        dc.setPenWidth(focused ? 4 : 2);
        dc.setColor(focused ? Graphics.COLOR_ORANGE : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx + s, cy, cx - s, cy);
        dc.drawLine(cx - s, cy, cx - s * 0.3, cy - s * 0.7);
        dc.drawLine(cx - s, cy, cx - s * 0.3, cy + s * 0.7);
    }

    function drawEnterArrow(dc, cx, cy, s, focused) {
        dc.setPenWidth(focused ? 4 : 2);
        dc.setColor(focused ? Graphics.COLOR_GREEN : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var y = cy + s * 0.4;
        dc.drawLine(cx + s, cy - s, cx + s, y);
        dc.drawLine(cx + s, y, cx - s, y);
        dc.drawLine(cx - s, y, cx - s * 0.3, y - s * 0.7);
        dc.drawLine(cx - s, y, cx - s * 0.3, y + s * 0.7);
    }
}

class ScoutCodeDelegate extends WatchUi.InputDelegate {
    var view;
    var menuItem;

    function initialize(codeView, item) {
        InputDelegate.initialize();
        view = codeView;
        menuItem = item;
    }

    function onKey(keyEvent) {
        ScoutScreens.touch();
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_UP) {
            view.turn(1);
        } else if (key == WatchUi.KEY_DOWN) {
            view.turn(-1);
        } else if (key == WatchUi.KEY_ENTER) {
            if (view.focus == ScoutCodeView.FOCUS_CANCEL) {
                WatchUi.popView(WatchUi.SLIDE_RIGHT);
            } else if (view.focus == ScoutCodeView.FOCUS_SAVE) {
                if (ScoutView.savePairingCode(view.code()) && menuItem != null) {
                    menuItem.setSubLabel(ScoutScreens.codeSubLabel());
                }
                WatchUi.popView(WatchUi.SLIDE_RIGHT);
            } else {
                view.focus += 1;
                WatchUi.requestUpdate();
            }
        } else if (key == WatchUi.KEY_ESC) {
            if (view.focus == ScoutCodeView.FOCUS_CANCEL) {
                WatchUi.popView(WatchUi.SLIDE_RIGHT);
            } else {
                view.focus -= 1;
                WatchUi.requestUpdate();
            }
        } else {
            return false;
        }
        return true;
    }
}


class ScoutListView extends WatchUi.View {
    var title;
    var kind;
    var offset = 0;

    function initialize(viewTitle, listKind) {
        View.initialize();
        title = viewTitle;
        kind = listKind;
    }

    function onShow() {
        ScoutClock.get().schedule("uiRefresh", 1000, method(:refresh));
    }

    function onHide() {
        ScoutClock.get().cancel("uiRefresh");
    }

    function refresh() {
        ScoutClock.get().schedule("uiRefresh", 1000, method(:refresh));
        WatchUi.requestUpdate();
    }

    function lines() {
        return kind == :debug ? ScoutScreens.debugLines() : ScoutScreens.statusLines();
    }

    function scroll(step) {
        var count = lines().size();
        offset += step;
        if (offset > count - 1) { offset = count - 1; }
        if (offset < 0) { offset = 0; }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(w / 2, h * 0.08, Graphics.FONT_TINY, title, Graphics.TEXT_JUSTIFY_CENTER);
        if (kind == :status) {
            drawStatus(dc, w, h);
            return;
        }
        var items = lines();
        var step = dc.getFontHeight(Graphics.FONT_XTINY);
        var y = h * 0.2;
        for (var i = offset; i < items.size() && y + step <= h * 0.9; i += 1) {
            dc.setColor(i == 0 ? Graphics.COLOR_ORANGE : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y, Graphics.FONT_XTINY, items[i], Graphics.TEXT_JUSTIFY_CENTER);
            y += step;
        }
    }




    function drawStatus(dc, w, h) {
        var items = lines();
        var labelH = dc.getFontHeight(Graphics.FONT_XTINY);
        var fonts = [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY];
        var y = h * 0.2;
        for (var i = offset; i < items.size(); i += 1) {
            var valueH = dc.getFontHeight(Graphics.FONT_MEDIUM);
            if (y + labelH + valueH > h * 0.88) { break; }
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y, Graphics.FONT_XTINY, items[i][0], Graphics.TEXT_JUSTIFY_CENTER);
            y += labelH;
            var room = chordWidth(w, h, y, valueH) - 8;
            var font = fonts[0];
            for (var f = 0; f < fonts.size(); f += 1) {
                font = fonts[f];
                if (dc.getTextWidthInPixels(items[i][1], font) <= room) { break; }
            }
            dc.setColor(i == offset ? Graphics.COLOR_ORANGE : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y, font, items[i][1], Graphics.TEXT_JUSTIFY_CENTER);
            y += valueH + 2;
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.89, Graphics.FONT_XTINY, (offset + 1) + "/" + items.size(),
            Graphics.TEXT_JUSTIFY_CENTER);
    }


    static function chordWidth(w, h, top, rowH) {
        if (System.getDeviceSettings().screenShape != System.SCREEN_SHAPE_ROUND) { return w; }
        var r = w / 2.0;
        var d = (top - h / 2.0).abs();
        var d2 = (top + rowH - h / 2.0).abs();
        if (d2 > d) { d = d2; }
        if (d >= r) { return 0; }
        return (2 * Math.sqrt(r * r - d * d)).toNumber();
    }
}

class ScoutListDelegate extends WatchUi.InputDelegate {
    var view;

    function initialize(listView) {
        InputDelegate.initialize();
        view = listView;
    }

    function onKey(keyEvent) {
        ScoutScreens.touch();
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_UP) {
            view.scroll(-1);
            return true;
        } else if (key == WatchUi.KEY_DOWN) {
            view.scroll(1);
            return true;
        }
        return false;
    }
}

class ScoutScreenCloser {
    function initialize() { }
    function close() { ScoutScreens.closeAll(); }
}
