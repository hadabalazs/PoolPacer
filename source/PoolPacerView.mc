import Toybox.Activity;
import Toybox.Application;
import Toybox.Attention;
import Toybox.FitContributor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

class PoolPacerView extends WatchUi.DataField {

    // ---- constants -------------------------------------------------------
    const UNIT_BASE_METRIC  = 100.0;
    const UNIT_BASE_YARDS   = 91.44;
    const ARC_HALF_SPAN_DEG = 78.0;   // wider = more visible band; keep < 90 so it never points straight down

    const FIT_PACE_DELTA   = 0;
    const FIT_LAP_DELTA    = 1;
    const FIT_ON_PACE_PCT  = 2;

    const FOOTER_DISTANCE = 0;
    const FOOTER_TIME     = 1;
    const FOOTER_BOTH     = 2;

    // ---- settings --------------------------------------------------------
    hidden var sTargetPaceSec  as Number = 120;
    hidden var sUnits          as Number = 0;      // 0 = m, 1 = yd
    hidden var sPoolPresetM    as Float  = 0.0;   // 0 = auto-detect
    hidden var sTolerance      as Number = 12;
    hidden var sFastThreshold  as Number = 8;
    hidden var sHaptics        as Boolean = true;
    hidden var sHapticsOnPace  as Boolean = true;
    hidden var sGaugeRange     as Number = 15;
    hidden var sVibeIntensity  as Number = 80;
    hidden var sBuzzOnPace     as Number = 1;
    hidden var sBuzzSlow       as Number = 2;
    hidden var sBuzzFast       as Number = 3;
    hidden var sBuzzGapMs      as Number = 150;
    hidden var sFooterMode     as Number = FOOTER_DISTANCE;
    hidden var unitBaseM       as Float  = 100.0;

    // ---- runtime state -----------------------------------------------
    hidden var poolLengthM     as Float  = 0.0;
    hidden var lastDistanceM   as Float  = 0.0;
    hidden var sessionDistanceM as Float = 0.0;
    hidden var lastLengthMs    as Number = 0;
    hidden var lengthCount     as Number = 0;
    hidden var nowMs           as Number = 0;
    hidden var lastPaceSec100  as Float  = 0.0;
    hidden var lastDelta       as Float  = 0.0;
    hidden var liveDelta       as Float  = 0.0;
    hidden var hasLiveSpeed    as Boolean = false;
    hidden var lapDeltaSum     as Float  = 0.0;
    hidden var lapLengths      as Number = 0;
    hidden var onPaceCount     as Number = 0;
    hidden var scoredLengths   as Number = 0;
    hidden var zone            as Number = PaceMath.ZONE_ON;
    hidden var hasData         as Boolean = false;

    // ---- cached layout -----------------------------------------------
    hidden var cx as Number = 0;
    hidden var cy as Number = 0;
    hidden var arcR as Number = 0;
    hidden var arcPenThin as Number = 10;
    hidden var centreBottomY as Number = 0;
    hidden var arcPenThick as Number = 26;
    hidden var bigFont;
    hidden var smallFont = Graphics.FONT_XTINY;
    hidden var footerFont = Graphics.FONT_MEDIUM;
    hidden var compact as Boolean = false;

    // ---- cached haptics ------------------------------------------------
    hidden var vibeOnPace as Array<Attention.VibeProfile>?;
    hidden var vibeSlow   as Array<Attention.VibeProfile>?;
    hidden var vibeFast   as Array<Attention.VibeProfile>?;

    // ---- FIT fields ------------------------------------------------------
    hidden var fPaceDelta   as FitContributor.Field?;
    hidden var fLapDelta    as FitContributor.Field?;
    hidden var fOnPacePct   as FitContributor.Field?;

    // =====================================================================
    function initialize() {
        DataField.initialize();
        bigFont = Graphics.FONT_NUMBER_MEDIUM;
        loadSettings();
        createFitFields();
    }

    function loadSettings() as Void {
        sTargetPaceSec = propNum("targetPaceSec", 120);
        sUnits         = propNum("units", 0);
        sPoolPresetM   = propNum("poolPresetCm", 0).toFloat() / 100.0;
        sTolerance     = propNum("toleranceSec", 12);
        sFastThreshold = propNum("fastThresholdSec", 8);
        sGaugeRange    = propNum("gaugeRangeSec", 15);
        sVibeIntensity = propNum("vibeIntensity", 80);
        sHaptics       = propBool("hapticsEnabled", true);
        sHapticsOnPace = propBool("hapticsOnPace", true);
        sBuzzOnPace    = propNum("buzzCountOnPace", 1);
        sBuzzSlow      = propNum("buzzCountSlow", 2);
        sBuzzFast      = propNum("buzzCountFast", 3);
        sBuzzGapMs     = propNum("buzzGapMs", 150);
        sFooterMode    = propNum("footerMode", FOOTER_DISTANCE);
        unitBaseM = (sUnits == 1) ? UNIT_BASE_YARDS : UNIT_BASE_METRIC;
        if (sPoolPresetM > 0.0) { poolLengthM = sPoolPresetM; }
        buildHaptics();
    }

    hidden function propNum(key as String, dflt as Number) as Number {
        var v = Application.Properties.getValue(key);
        if (v == null) { return dflt; }
        return v.toNumber();
    }

    hidden function propBool(key as String, dflt as Boolean) as Boolean {
        var v = Application.Properties.getValue(key);
        if (v == null) { return dflt; }
        return v;
    }

    // Buzz counts (on-pace / slow / fast) and the gap between pulses are all
    // user-configurable in settings. A count of 0 disables that zone's
    // haptics entirely (buildVibePattern returns null, and fireHaptics()
    // already no-ops on a null pattern).
    //
    // The on-pace single buzz is deliberately longer (700ms) than a lone
    // slow/fast buzz (400ms) so it feels distinct on the wrist even before
    // you've consciously counted pulses -- "that was the long one, I'm on
    // pace" vs. having to count 1 vs 2 vs 3 every time.
    hidden function buildHaptics() as Void {
        if (!(Attention has :vibrate)) { return; }
        vibeOnPace = buildVibePattern(sBuzzOnPace, 700);
        vibeSlow   = buildVibePattern(sBuzzSlow, 400);
        vibeFast   = buildVibePattern(sBuzzFast, 400);
    }

    hidden function buildVibePattern(count as Number, singleMs as Number) as Array<Attention.VibeProfile>? {
        var d = sVibeIntensity;
        var c = count;
        if (c < 0) { c = 0; }
        if (c > 6) { c = 6; }   // sanity cap even though settings.xml already limits to 5
        if (c == 0) { return null; }
        if (c == 1) { return [ new Attention.VibeProfile(d, singleMs) ]; }
        var gap = sBuzzGapMs;
        if (gap < 0) { gap = 0; }
        var n = c * 2 - 1;
        var arr = new [n];
        for (var i = 0; i < c; i++) {
            arr[i * 2] = new Attention.VibeProfile(d, 200);
            if (i < c - 1) {
                arr[i * 2 + 1] = new Attention.VibeProfile(0, gap);
            }
        }
        return arr as Array<Attention.VibeProfile>;
    }

    hidden function createFitFields() as Void {
        fPaceDelta = createField("pace_delta", FIT_PACE_DELTA,
            FitContributor.DATA_TYPE_SINT16,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "s/100" });
        fLapDelta = createField("interval_avg_delta", FIT_LAP_DELTA,
            FitContributor.DATA_TYPE_SINT16,
            { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "s/100" });
        fOnPacePct = createField("on_pace_pct", FIT_ON_PACE_PCT,
            FitContributor.DATA_TYPE_UINT8,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "%" });
    }

    // =====================================================================
    function onLayout(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        cx = w / 2;
        compact = (h < w * 0.55);
        if (compact) { return; }
        cy = (h * 0.44).toNumber();
        arcR = ((w < h ? w : h) * 0.40).toNumber();
        arcPenThin = (h * 0.055).toNumber();
        if (arcPenThin < 8) { arcPenThin = 8; }
        arcPenThick = (arcPenThin * 2.6).toNumber();
        bigFont = pickBigFont();
        smallFont = Graphics.FONT_XTINY;
        footerFont = Graphics.FONT_LARGE;
    }

    hidden function pickBigFont() {
        if (Graphics has :FONT_NUMBER_THAI_HOT) { return Graphics.FONT_NUMBER_THAI_HOT; }
        if (Graphics has :FONT_NUMBER_HOT)      { return Graphics.FONT_NUMBER_HOT; }
        return Graphics.FONT_NUMBER_MEDIUM;
    }

    // =====================================================================
    function compute(info as Activity.Info) as Void {
        if (info == null) { return; }

        var ts = (info has :timerState) ? info.timerState : null;
        if (ts != null && ts != Activity.TIMER_STATE_ON) { return; }

        updateLiveSpeed(info);

        var dist = (info.elapsedDistance != null) ? info.elapsedDistance : 0.0;
        var now  = (info.timerTime != null) ? info.timerTime : 0;
        nowMs = now;
        sessionDistanceM = dist;

        // DEBUG HARNESS: uncomment for dry-land testing. Safe to leave
        // uncommented -- in a release build debugDistance() is a pass-through.
        // dist = debugDistance(dist, now);

        var advanced = dist - lastDistanceM;

        if (poolLengthM <= 0.0 && advanced > 1.0) {
            poolLengthM = PaceMath.snapPoolLength(advanced);
        }

        if (poolLengthM > 0.0 && advanced >= poolLengthM * 0.5) {
            var n = ((advanced / poolLengthM) + 0.5).toNumber();
            if (n < 1) { n = 1; }
            if (n > 8) { n = 8; }   // guard against a distance glitch
            onLengthComplete(n, now - lastLengthMs);
            lastDistanceM = dist;
            lastLengthMs = now;
        }

        // There is deliberately NO rest detection. Stop without pausing and
        // that time counts against the split, exactly as it counts against
        // you in a set. Pausing the timer is what stops the clock: timerTime
        // freezes while paused, so a paused break never lands in a split,
        // and onTimerResume() re-stamps the length start on the way back in.
    }

    // EXPERIMENTAL: currentSpeed is a generic, documented Activity.Info field
    // (metres/sec) and is believed to be what Garmin's own native "Current
    // Pace" swim field reads from -- a continuously-updating reading, unlike
    // elapsedDistance below which only jumps once a length is detected.
    // Pool swim has no GPS though, so whether this is actually populated
    // smoothly mid-length (vs. staying at 0, or only updating at wall
    // touches) is NOT yet confirmed on this hardware. If it turns out to be
    // unreliable in the pool, the needle just falls back to the last
    // completed length's pace (see drawGauge()) -- nothing else depends on
    // this being accurate, so it's safe to leave in and verify on a real
    // swim.
    hidden function updateLiveSpeed(info as Activity.Info) as Void {
        if (!(info has :currentSpeed) || info.currentSpeed == null || info.currentSpeed <= 0.0) {
            hasLiveSpeed = false;
            return;
        }
        var pace100 = unitBaseM / info.currentSpeed;
        liveDelta = pace100 - sTargetPaceSec.toFloat();
        hasLiveSpeed = true;
    }

    // compute() samples at 1 Hz, so every split quantises to a whole second.
    // One second of split error is (unitBase / poolLength) seconds per 100 --
    // 4 s/100 in a 25 m pool, 5 s/100 in a 20 m pool. If the user's
    // tolerance/threshold is tighter than that, a perfectly paced swimmer
    // sees the zone flicker at random. Never let either band be tighter
    // than one sample. Shared by both the slow-side tolerance and the
    // fast-side threshold so they're guarded identically.
    hidden function quantizeGuard(raw as Number) as Number {
        var q = 0.0;
        if (poolLengthM > 0.0) { q = unitBaseM / poolLengthM; }
        if (q > raw.toFloat()) { return (q + 0.5).toNumber(); }
        return raw;
    }

    hidden function effectiveTolerance() as Number { return quantizeGuard(sTolerance); }
    hidden function effectiveFastThreshold() as Number { return quantizeGuard(sFastThreshold); }

    // Two separate accounting streams, and keeping them separate matters:
    //
    //   lengthCount  -- lengths SWUM. A fact: the wall was touched n times.
    //                   Counted unconditionally.
    //   scoredLengths/lapLengths/lapDeltaSum/onPaceCount -- lengths we have
    //                   a USABLE split for, and so an honest pace.
    //
    // These used to be the same loop, sitting below the plausibility guard,
    // so an unusable split dropped the length from the distance total as
    // well as from the pace stats -- the swim silently came up short.
    hidden function onLengthComplete(n as Number, totalMs as Number) as Void {
        for (var i = 0; i < n; i++) { lengthCount++; }

        var splitSec = (totalMs.toFloat() / n.toFloat()) / 1000.0;
        if (!PaceMath.isPlausibleSplit(splitSec)) { return; }

        lastPaceSec100 = PaceMath.paceSec100(splitSec, poolLengthM, unitBaseM);
        lastDelta = lastPaceSec100 - sTargetPaceSec.toFloat();
        zone = PaceMath.classify(lastDelta, effectiveTolerance(), effectiveFastThreshold());

        for (var i = 0; i < n; i++) {
            lapLengths++;
            scoredLengths++;
            lapDeltaSum += lastDelta;
        }
        if (zone == PaceMath.ZONE_ON) { onPaceCount += n; }
        hasData = true;

        writeFit();
        fireHaptics();
    }

    // Float->Number truncates toward zero, not to nearest -- round explicitly
    // so e.g. a 7.9s delta is recorded as 8s, not 7s.
    hidden function roundToInt(f as Float) as Number {
        if (f >= 0.0) { return (f + 0.5).toNumber(); }
        return -((-f + 0.5).toNumber());
    }

    hidden function writeFit() as Void {
        if (fPaceDelta != null) { fPaceDelta.setData(roundToInt(lastDelta)); }
        if (fLapDelta != null && lapLengths > 0) {
            var avg = lapDeltaSum / lapLengths;
            fLapDelta.setData(roundToInt(avg));
        }
        if (fOnPacePct != null && scoredLengths > 0) {
            fOnPacePct.setData((onPaceCount * 100) / scoredLengths);
        }
    }

    hidden function fireHaptics() as Void {
        if (!sHaptics) { return; }
        if (!(Attention has :vibrate)) { return; }
        if (zone == PaceMath.ZONE_ON && !sHapticsOnPace) { return; }
        var ds = System.getDeviceSettings();
        if (ds has :vibrateOn && !ds.vibrateOn) { return; }

        var pattern = vibeOnPace;
        if (zone == PaceMath.ZONE_SLOW || zone == PaceMath.ZONE_VERY_SLOW) {
            pattern = vibeSlow;
        } else if (zone == PaceMath.ZONE_FAST || zone == PaceMath.ZONE_VERY_FAST) {
            pattern = vibeFast;
        }
        if (pattern != null && pattern.size() > 0) { Attention.vibrate(pattern); }
    }

    // =====================================================================
    function onTimerStart() as Void { resetSession(); }
    function onTimerReset() as Void { resetSession(); }

    // Session FIT values are kept current on every length, so by the time the
    // timer stops they are already written. This is a belt-and-braces flush;
    // writing session data for the first time in onTimerReset() is too late.
    function onTimerStop() as Void { writeFit(); }

    function onTimerResume() as Void {
        var info = Activity.getActivityInfo();
        if (info != null && info.timerTime != null) {
            lastLengthMs = info.timerTime;
        }
    }

    function onTimerLap() as Void {
        lapDeltaSum = 0.0;
        lapLengths = 0;
    }

    hidden function resetSession() as Void {
        lastDistanceM = 0.0;
        sessionDistanceM = 0.0;
        lastLengthMs = 0;
        lengthCount = 0;
        nowMs = 0;
        lapLengths = 0;
        lastPaceSec100 = 0.0;
        lastDelta = 0.0;
        liveDelta = 0.0;
        hasLiveSpeed = false;
        lapDeltaSum = 0.0;
        onPaceCount = 0;
        scoredLengths = 0;
        hasData = false;
        if (sPoolPresetM <= 0.0) { poolLengthM = 0.0; }
    }

    // =====================================================================
    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();

        if (compact) { drawCompact(dc); return; }

        // Gauge first, then everything else on top of it -- the gauge is
        // wide/thick enough that it would otherwise cover text sitting
        // inside its open middle.
        drawGauge(dc);
        drawCentre(dc);
        drawFooter(dc);
    }

    // Which of the three zones (slow / on-pace / fast) a delta falls into,
    // for gauge-highlighting purposes. Coarser than PaceMath.classify() --
    // this only needs to pick one of the three coloured bands, not the
    // very-slow/very-fast split.
    hidden function zoneFor(delta as Float, slowTol as Number, fastThr as Number) as Number {
        var s = slowTol.toFloat();
        var f = fastThr.toFloat();
        if (delta > s)  { return 0; }   // slow  (red)
        if (delta < -f) { return 2; }   // fast  (orange)
        return 1;                       // on pace (green)
    }

    // Arc spans ARC_HALF_SPAN_DEG either side of 90 (on pace, top) -- e.g.
    // 168 deg (slow end, left) through 90 to 12 deg (fast end, right).
    //
    // Slow = red, on pace = green, fast = orange. The red/green edge sits at
    // the tolerance setting and the green/orange edge sits at the fast-
    // threshold setting -- the SAME two numbers that drive the haptic
    // buzzes (see classify()/fireHaptics()), so the gauge and the buzz you
    // feel always agree, even though the two edges are usually different
    // distances from centre (that's the point -- you can be more forgiving
    // of running slow than of going out too fast, or vice versa). Whichever
    // zone you're CURRENTLY in renders at arcPenThick, the other two at
    // arcPenThin, so your status is obvious at a glance.
    hidden function drawGauge(dc as Graphics.Dc) as Void {
        var range = sGaugeRange.toFloat();
        var tol = effectiveTolerance().toFloat();
        var fastThr = effectiveFastThreshold().toFloat();

        // A live reading wins while one is available; otherwise the gauge
        // parks on the last completed length, which still answers "how did
        // that one go?". It never blanks out.
        var haveReading  = hasLiveSpeed || hasData;
        var needleDelta  = hasLiveSpeed ? liveDelta : lastDelta;
        var activeZone   = -1;
        if (haveReading) {
            activeZone = zoneFor(needleDelta, effectiveTolerance(), effectiveFastThreshold());
        }

        drawSeg(dc, range,  tol,      range,  Graphics.COLOR_RED,    activeZone == 0);
        drawSeg(dc, range, -fastThr,  tol,    Graphics.COLOR_GREEN,  activeZone == 1);
        drawSeg(dc, range, -range,   -fastThr,Graphics.COLOR_ORANGE, activeZone == 2);

        // No needle. The thick segment already says which zone you're in,
        // and a pointer parked at the end of the scale -- which is where it
        // sits for any pace more than gaugeRange off target -- read as a
        // stray line rather than an indicator. drawNeedle() is kept below;
        // call it here with needleDelta to put the pointer back.
    }

    hidden function deltaToAngle(delta as Float, range as Float) as Float {
        var d = delta;
        if (d > range)  { d = range; }
        if (d < -range) { d = -range; }
        return 90.0 + (d / range) * ARC_HALF_SPAN_DEG;
    }

    // dFrom is always the smaller (more negative / faster) delta of the pair.
    // Larger delta maps to a LARGER angle, and ARC_CLOCKWISE sweeps from the
    // larger angle down to the smaller one, so start at angle(dTo).
    hidden function drawSeg(dc as Graphics.Dc, range as Float,
                            dFrom as Float, dTo as Float, colour as Number,
                            active as Boolean) as Void {
        var aStart = deltaToAngle(dTo, range);    // larger angle
        var aEnd   = deltaToAngle(dFrom, range);  // smaller angle
        if (aStart <= aEnd) { return; }
        dc.setPenWidth(active ? arcPenThick : arcPenThin);
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, arcR, Graphics.ARC_CLOCKWISE, aStart, aEnd);
    }

    hidden function drawNeedle(dc as Graphics.Dc, range as Float, delta as Float) as Void {
        var a = deltaToAngle(delta, range) * Math.PI / 180.0;
        var rIn  = arcR - arcPenThick;
        var rOut = arcR + arcPenThick;
        var x1 = cx + rIn  * Math.cos(a);
        var y1 = cy - rIn  * Math.sin(a);
        var x2 = cx + rOut * Math.cos(a);
        var y2 = cy - rOut * Math.sin(a);
        dc.setPenWidth(7);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x1, y1, x2, y2);
        dc.setPenWidth(3);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x1, y1, x2, y2);
    }

    // The pace number is the single most important thing on screen and is
    // ALWAYS visible once the first length has completed -- it never flashes
    // or reverts to "--:--" again for the rest of the swim. It always shows
    // the most recently completed length's pace (not a session average), so
    // you can check "am I hitting my target" at any point between turns, not
    // just the instant it updates. A small caption underneath states which
    // pool length that reading covers and what the target is, replacing the
    // separate "TGT" line that used to sit up near the arc's tips.
    hidden function drawCentre(dc as Graphics.Dc) as Void {
        // bigFont is a FONT_NUMBER_* face. Those carry digits, ':', '.', '-'
        // and space -- and NO letters, so any word drawn with it renders as
        // nothing at all, with no error. This is exactly how the pace number
        // used to vanish mid-swim: the centre text was once swapped to
        // the word "REST" and silently drew blank. txt must
        // therefore stay numeric forever -- never a word, in any state.
        var txt = hasData ? PaceMath.formatPace(lastPaceSec100) : "--:--";

        var unit = (sUnits == 1) ? "/100y" : "/100m";
        var caption = "TGT " + PaceMath.formatPace(sTargetPaceSec.toFloat()) + unit;
        // The caption tucks up under the arc tips and the number sits
        // directly beneath it. Measured off arcR rather than a screen
        // fraction so 43 mm and 51 mm keep the same relationship to the arc.
        var capH = dc.getFontHeight(smallFont);
        var capY = cy - (arcR * 0.28).toNumber();
        var numY = capY + capH + 2;

        // Where the footer is allowed to start. The big numeric font is tall
        // and its height differs per device, so this is MEASURED and handed
        // to drawFooter() rather than both ends guessing at screen fractions
        // -- that guess is what had the pace number overlapping the distance.
        centreBottomY = numY + dc.getFontHeight(bigFont);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, capY, smallFont, caption, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, numY, bigFont, txt, Graphics.TEXT_JUSTIFY_CENTER);
    }
    // Bottom readout: total distance (the default), total elapsed time, or
    // both on one line. No caption under it -- "25m" and "2:55" already say
    // what they are. Width is MEASURED, never assumed: the worst case
    // ("3000m  1:02:33") is more than twice the length of the opening "0m",
    // so the font steps down rather than running off a 43 mm screen. The
    // vertical position is measured too, off the bottom of the pace number.
    hidden function drawFooter(dc as Graphics.Dc) as Void {
        var h = dc.getHeight();

        // The watch's own elapsedDistance, not lengthCount x poolLength --
        // it is authoritative, needs no pool-length guess, and cannot drift
        // out of step with the total if a length is ever miscounted.
        var distTxt = PaceMath.formatDistance(sessionDistanceM, sUnits);
        var timeTxt = PaceMath.formatElapsed(nowMs.toFloat() / 1000.0);

        var valueTxt = distTxt;
        if (sFooterMode == FOOTER_TIME) {
            valueTxt = timeTxt;
        } else if (sFooterMode == FOOTER_BOTH) {
            valueTxt = distTxt + "  " + timeTxt;
        }

        var font = fitFont(dc, valueTxt);
        var fh = dc.getFontHeight(font);

        // Sit just under the pace number, but never run off the bottom of the
        // screen -- whichever constraint binds first wins.
        var vy = centreBottomY + (h * 0.02).toNumber();
        var maxY = h - fh - (h * 0.10).toNumber();
        if (vy > maxY) { vy = maxY; }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, vy, font, valueTxt, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Largest font, footerFont downwards, whose rendering of txt still fits
    // across the bottom of the screen.
    hidden function fitFont(dc as Graphics.Dc, txt as String) {
        var maxW = dc.getWidth() * 0.80;
        if (dc.getTextWidthInPixels(txt, footerFont) <= maxW) { return footerFont; }
        if (dc.getTextWidthInPixels(txt, Graphics.FONT_MEDIUM) <= maxW) {
            return Graphics.FONT_MEDIUM;
        }
        return Graphics.FONT_SMALL;
    }
    // Same numeric-font constraint as drawCentre: FONT_NUMBER_MEDIUM has no
    // letters, so the old "v"/"^"/"=" zone glyphs were drawing as blank
    // space. The zone rides on the COLOUR of the number instead, which reads
    // faster in a small field anyway.
    hidden function drawCompact(dc as Graphics.Dc) as Void {
        var col = Graphics.COLOR_WHITE;
        if (hasData) {
            if (zone == PaceMath.ZONE_SLOW || zone == PaceMath.ZONE_VERY_SLOW) {
                col = Graphics.COLOR_RED;
            } else if (zone == PaceMath.ZONE_FAST || zone == PaceMath.ZONE_VERY_FAST) {
                col = Graphics.COLOR_ORANGE;
            } else {
                col = Graphics.COLOR_GREEN;
            }
        }
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        var txt = hasData ? PaceMath.formatPace(lastPaceSec100) : "--:--";
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2,
            Graphics.FONT_NUMBER_MEDIUM, txt,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
