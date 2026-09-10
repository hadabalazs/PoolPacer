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
    const REST_THRESHOLD_MS = 12000;
    const UNIT_BASE_METRIC  = 100.0;
    const UNIT_BASE_YARDS   = 91.44;
    const ARC_HALF_SPAN_DEG = 78.0;   // wider = more visible band; keep < 90 so it never points straight down

    const FIT_PACE_DELTA   = 0;
    const FIT_BANKED       = 1;
    const FIT_LAP_DELTA    = 2;
    const FIT_ON_PACE_PCT  = 3;
    const FIT_FINAL_BANKED = 4;

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
    hidden var sTimeMode       as Number = 0;      // 0 = session total, 1 = current lap
    hidden var unitBaseM       as Float  = 100.0;

    // ---- runtime state -----------------------------------------------
    hidden var poolLengthM     as Float  = 0.0;
    hidden var lastDistanceM   as Float  = 0.0;
    hidden var lastLengthMs    as Number = 0;
    hidden var restStartMs     as Number = 0;
    hidden var lengthCount     as Number = 0;
    hidden var nowMs           as Number = 0;
    hidden var lapStartMs      as Number = 0;
    hidden var lastPaceSec100  as Float  = 0.0;
    hidden var lastDelta       as Float  = 0.0;
    hidden var liveDelta       as Float  = 0.0;
    hidden var hasLiveSpeed    as Boolean = false;
    hidden var bankedSec       as Float  = 0.0;
    hidden var lapBankedSec    as Float  = 0.0;
    hidden var lapLengths      as Number = 0;
    hidden var onPaceCount     as Number = 0;
    hidden var scoredLengths   as Number = 0;
    hidden var zone            as Number = PaceMath.ZONE_ON;
    hidden var isResting       as Boolean = false;
    hidden var hasData         as Boolean = false;

    // ---- cached layout -----------------------------------------------
    hidden var cx as Number = 0;
    hidden var cy as Number = 0;
    hidden var arcR as Number = 0;
    hidden var arcPen as Number = 10;
    hidden var bigFont;
    hidden var smallFont = Graphics.FONT_XTINY;
    hidden var compact as Boolean = false;

    // ---- cached haptics ------------------------------------------------
    hidden var vibeOnPace as Array<Attention.VibeProfile>?;
    hidden var vibeSlow   as Array<Attention.VibeProfile>?;
    hidden var vibeFast   as Array<Attention.VibeProfile>?;

    // ---- FIT fields ------------------------------------------------------
    hidden var fPaceDelta   as FitContributor.Field?;
    hidden var fBanked      as FitContributor.Field?;
    hidden var fLapDelta    as FitContributor.Field?;
    hidden var fOnPacePct   as FitContributor.Field?;
    hidden var fFinalBanked as FitContributor.Field?;

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
        sTimeMode      = propNum("timeDisplayMode", 0);
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

    // Buzz counts (on-pace / slow / fast) are user-configurable in settings.
    // A count of 0 disables that zone's haptics entirely (buildVibePattern
    // returns null, and fireHaptics() already no-ops on a null pattern).
    hidden function buildHaptics() as Void {
        if (!(Attention has :vibrate)) { return; }
        vibeOnPace = buildVibePattern(sBuzzOnPace);
        vibeSlow   = buildVibePattern(sBuzzSlow);
        vibeFast   = buildVibePattern(sBuzzFast);
    }

    hidden function buildVibePattern(count as Number) as Array<Attention.VibeProfile>? {
        var d = sVibeIntensity;
        var c = count;
        if (c < 0) { c = 0; }
        if (c > 6) { c = 6; }   // sanity cap even though settings.xml already limits to 5
        if (c == 0) { return null; }
        if (c == 1) { return [ new Attention.VibeProfile(d, 400) ]; }
        var n = c * 2 - 1;
        var arr = new [n];
        for (var i = 0; i < c; i++) {
            arr[i * 2] = new Attention.VibeProfile(d, 200);
            if (i < c - 1) {
                arr[i * 2 + 1] = new Attention.VibeProfile(0, 150);
            }
        }
        return arr as Array<Attention.VibeProfile>;
    }

    hidden function createFitFields() as Void {
        fPaceDelta = createField("pace_delta", FIT_PACE_DELTA,
            FitContributor.DATA_TYPE_SINT16,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "s/100" });
        fBanked = createField("banked_sec", FIT_BANKED,
            FitContributor.DATA_TYPE_SINT16,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "s" });
        fLapDelta = createField("interval_avg_delta", FIT_LAP_DELTA,
            FitContributor.DATA_TYPE_SINT16,
            { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "s/100" });
        fOnPacePct = createField("on_pace_pct", FIT_ON_PACE_PCT,
            FitContributor.DATA_TYPE_UINT8,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "%" });
        fFinalBanked = createField("final_banked_sec", FIT_FINAL_BANKED,
            FitContributor.DATA_TYPE_SINT16,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s" });
    }

    // =====================================================================
    function onLayout(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        cx = w / 2;
        compact = (h < w * 0.55);
        if (compact) { return; }
        cy = (h * 0.46).toNumber();
        arcR = ((w < h ? w : h) * 0.40).toNumber();
        arcPen = (h * 0.075).toNumber();
        if (arcPen < 10) { arcPen = 10; }
        bigFont = pickBigFont();
        smallFont = Graphics.FONT_XTINY;
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
            restStartMs = now;
            isResting = false;
        } else if (hasData && (now - restStartMs > REST_THRESHOLD_MS)) {
            // hasData guard: before the first length completes there is no
            // rest to detect, otherwise the field shows REST for the opening
            // length of every swim.
            isResting = true;
        }
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
    // 4 s/100 in a 25 m pool, 5 s/100 in a 20 m pool. If the user's tolerance
    // is tighter than that, a perfectly paced swimmer sees the zone flicker
    // between ON and SLOW at random. Never let the band be tighter than one
    // sample.
    hidden function effectiveTolerance() as Number {
        var q = 0.0;
        if (poolLengthM > 0.0) { q = unitBaseM / poolLengthM; }
        if (q > sTolerance.toFloat()) { return (q + 0.5).toNumber(); }
        return sTolerance;
    }

    hidden function onLengthComplete(n as Number, totalMs as Number) as Void {
        var splitSec = (totalMs.toFloat() / n.toFloat()) / 1000.0;
        if (!PaceMath.isPlausibleSplit(splitSec)) { return; }

        var tgtLen = PaceMath.targetLengthSec(sTargetPaceSec, poolLengthM, unitBaseM);

        for (var i = 0; i < n; i++) {
            bankedSec += (tgtLen - splitSec);
            lapBankedSec += (tgtLen - splitSec);
            lengthCount++;
            lapLengths++;
            scoredLengths++;
        }

        lastPaceSec100 = PaceMath.paceSec100(splitSec, poolLengthM, unitBaseM);
        lastDelta = lastPaceSec100 - sTargetPaceSec.toFloat();
        zone = PaceMath.classify(lastDelta, effectiveTolerance(), sFastThreshold);
        if (zone == PaceMath.ZONE_ON) { onPaceCount += n; }
        hasData = true;

        writeFit();
        fireHaptics();
    }

    hidden function writeFit() as Void {
        if (fPaceDelta != null) { fPaceDelta.setData(lastDelta.toNumber()); }
        if (fBanked != null)    { fBanked.setData(bankedSec.toNumber()); }
        if (fLapDelta != null && lapLengths > 0) {
            var avg = -(lapBankedSec / lapLengths) * (unitBaseM / poolLengthM);
            fLapDelta.setData(avg.toNumber());
        }
        if (fOnPacePct != null && scoredLengths > 0) {
            fOnPacePct.setData((onPaceCount * 100) / scoredLengths);
        }
        if (fFinalBanked != null) { fFinalBanked.setData(bankedSec.toNumber()); }
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
            restStartMs = info.timerTime;
        }
    }

    function onTimerLap() as Void {
        lapBankedSec = 0.0;
        lapLengths = 0;
        var info = Activity.getActivityInfo();
        if (info != null && info.timerTime != null) {
            lapStartMs = info.timerTime;
        }
    }

    hidden function resetSession() as Void {
        lastDistanceM = 0.0;
        lastLengthMs = 0;
        restStartMs = 0;
        lengthCount = 0;
        nowMs = 0;
        lapStartMs = 0;
        lapLengths = 0;
        lastPaceSec100 = 0.0;
        lastDelta = 0.0;
        liveDelta = 0.0;
        hasLiveSpeed = false;
        bankedSec = 0.0;
        lapBankedSec = 0.0;
        onPaceCount = 0;
        scoredLengths = 0;
        isResting = false;
        hasData = false;
        if (sPoolPresetM <= 0.0) { poolLengthM = 0.0; }
    }

    // =====================================================================
    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();

        if (compact) { drawCompact(dc); return; }

        // Gauge first, then everything else on top of it -- the gauge is
        // now wide/thick enough that it would otherwise cover text sitting
        // inside its open middle.
        drawGauge(dc);
        drawBanked(dc);
        drawTarget(dc);
        drawCentre(dc);
        drawFooter(dc);
    }

    // Sits in the open middle of the gauge, above the TGT line -- there is
    // plenty of empty space directly under the arc's topmost point (the arc
    // curves away toward its low side tips), so this doesn't compete with
    // the arc or the target text below it.
    hidden function drawBanked(dc as Graphics.Dc) as Void {
        var colour = (bankedSec >= 0) ? Graphics.COLOR_GREEN : Graphics.COLOR_RED;
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        var y = cy - (arcR - arcPen) + (dc.getHeight() * 0.02);
        dc.drawText(cx, y, Graphics.FONT_MEDIUM,
            PaceMath.formatSigned(bankedSec), Graphics.TEXT_JUSTIFY_CENTER);
    }

    hidden function drawTarget(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var unit = (sUnits == 1) ? "/100y" : "/100m";
        // Level with the arc's own open ends (the two tips of the arch),
        // not the top of the screen -- sin() of the lower end angle gives
        // how far below the arc's topmost point those tips sit.
        var endAngleRad = (90.0 - ARC_HALF_SPAN_DEG) * Math.PI / 180.0;
        var y = cy - arcR * Math.sin(endAngleRad);
        dc.drawText(cx, y,
            smallFont,
            "TGT " + PaceMath.formatPace(sTargetPaceSec.toFloat()) + unit,
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Arc spans ARC_HALF_SPAN_DEG either side of 90 (on pace, top) -- e.g.
    // 168 deg (slow end, left) through 90 to 12 deg (fast end, right).
    hidden function drawGauge(dc as Graphics.Dc) as Void {
        dc.setPenWidth(arcPen);

        // Green/red boundary is the SAME effectiveTolerance() used by
        // PaceMath.classify() in onLengthComplete() -- so the gauge always
        // matches what actually triggers a "slow"/"fast" buzz. Tightening
        // or relaxing the "On-pace tolerance" setting directly narrows or
        // widens the green band.
        var range = sGaugeRange.toFloat();
        var tol = effectiveTolerance().toFloat();

        drawSeg(dc, range,  tol,   range,  Graphics.COLOR_RED);
        drawSeg(dc, range, -tol,   tol,    Graphics.COLOR_GREEN);
        drawSeg(dc, range, -range, -tol,   Graphics.COLOR_RED);

        // Needle prefers a live, continuously-updating reading (see
        // updateLiveSpeed()) so it tracks your tendency stroke-by-stroke,
        // the way a running pace gauge does, and falls back to the last
        // completed length's pace when a live reading isn't available yet
        // (e.g. the first few seconds of a swim, or if currentSpeed turns
        // out not to be populated for pool swim on this device).
        if (!isResting) {
            if (hasLiveSpeed) {
                drawNeedle(dc, range, liveDelta);
            } else if (hasData) {
                drawNeedle(dc, range, lastDelta);
            }
        }
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
                            dFrom as Float, dTo as Float, colour as Number) as Void {
        var aStart = deltaToAngle(dTo, range);    // larger angle
        var aEnd   = deltaToAngle(dFrom, range);  // smaller angle
        if (aStart <= aEnd) { return; }
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, arcR, Graphics.ARC_CLOCKWISE, aStart, aEnd);
    }

    hidden function drawNeedle(dc as Graphics.Dc, range as Float, delta as Float) as Void {
        var a = deltaToAngle(delta, range) * Math.PI / 180.0;
        var rIn  = arcR - arcPen;
        var rOut = arcR + arcPen;
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

    hidden function drawCentre(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var txt = hasData ? PaceMath.formatPace(lastPaceSec100) : "--:--";
        if (isResting) { txt = "REST"; }
        dc.drawText(cx, cy + (arcR * 0.08), bigFont, txt,
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    hidden function drawFooter(dc as Graphics.Dc) as Void {
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        // Total distance covered so far, in whichever unit the pool-size
        // setting uses -- 0 lengths still shows "0m"/"0y" rather than "?",
        // which is reserved for a genuinely unknown (not-yet-detected) pool
        // length.
        var distTxt = "?";
        if (poolLengthM > 0.0) {
            distTxt = PaceMath.formatDistance(lengthCount.toFloat() * poolLengthM, sUnits);
        }

        // Either/or per settings: full session elapsed time, or time since
        // the last lap marker. Never both at once.
        var timeBaseMs = (sTimeMode == 1) ? (nowMs - lapStartMs) : nowMs;
        if (timeBaseMs < 0) { timeBaseMs = 0; }
        var timeTxt = PaceMath.formatElapsed(timeBaseMs.toFloat() / 1000.0);

        dc.drawText(cx, h * 0.88, smallFont,
            distTxt + "  " + timeTxt,
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    hidden function drawCompact(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var glyph = "=";
        if (zone == PaceMath.ZONE_SLOW || zone == PaceMath.ZONE_VERY_SLOW) { glyph = "v"; }
        if (zone == PaceMath.ZONE_FAST || zone == PaceMath.ZONE_VERY_FAST) { glyph = "^"; }
        var txt = hasData ? (PaceMath.formatPace(lastPaceSec100) + " " + glyph) : "--:--";
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2,
            Graphics.FONT_NUMBER_MEDIUM, txt,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
