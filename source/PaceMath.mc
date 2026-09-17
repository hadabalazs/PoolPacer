import Toybox.Lang;

module PaceMath {

    enum {
        ZONE_VERY_FAST = 0,
        ZONE_FAST      = 1,
        ZONE_ON        = 2,
        ZONE_SLOW      = 3,
        ZONE_VERY_SLOW = 4
    }

    // Every Garmin preset pool size, expressed in METRES, because
    // Activity.Info.elapsedDistance is always metric regardless of the user's
    // display units. Order does not matter — the search is nearest-match.
    //
    //   18.288 = 20 yd     20.0   = 20 m
    //   22.86  = 25 yd     25.0   = 25 m
    //   30.48  = 33 1/3 yd 33.333 = 33 1/3 m
    //   45.72  = 50 yd     50.0   = 50 m
    //
    // Snap band is 2%. The tightest gap between neighbouring presets is 9.36%
    // (every yard/metre pair), so 2% is collision-free with room to spare. It
    // must stay tight for a second reason: the watch derives elapsedDistance
    // from its own configured pool size, so the raw increment is already the
    // exact pool length. Snapping only cleans up float noise — it is not a
    // guess. A wide band would corrupt CUSTOM pool sizes, which must pass
    // through untouched.
    function snapPoolLength(raw as Float) as Float {
        var known = [18.288, 20.0, 22.86, 25.0, 30.48, 33.3333, 45.72, 50.0];
        var best = raw;
        var bestDiff = 999999.0;
        for (var i = 0; i < known.size(); i++) {
            var k = known[i].toFloat();
            var diff = raw - k;
            if (diff < 0) { diff = -diff; }
            if (diff <= k * 0.02 && diff < bestDiff) {
                best = k;
                bestDiff = diff;
            }
        }
        return best;
    }

    // Format a pool length in metres for display in the user's units.
    // sUnits: 0 = metres, 1 = yards.
    function formatPoolLength(metres as Float, units as Number) as String {
        if (metres <= 0.0) { return "?"; }
        return formatDistance(metres, units);
    }

    // Same unit conversion as formatPoolLength(), but 0 is a real, valid
    // distance here (e.g. "0m" before the first length of a swim), not an
    // "unknown" state, so it is a separate function rather than reusing the
    // "<= 0 -> ?" guard above.
    function formatDistance(metres as Float, units as Number) as String {
        if (metres < 0.0) { metres = 0.0; }
        if (units == 1) {
            var yd = metres / 0.9144;
            return yd.format("%.0f") + "y";
        }
        return metres.format("%.0f") + "m";
    }

    // Turn a free-form target -- "20:00 for 1000 m", "10:00 for 1000 y",
    // "1:45 for 100 m" -- into the per-100-unit pace the rest of the app
    // works in, so every downstream consumer (delta, classify, the gauge,
    // the FIT fields) is unchanged by how the target was entered.
    //
    // targetDist is in the user's DISPLAY units, because that is how they
    // typed it; units 0 = metres, 1 = yards. For yards the yard-to-metre
    // factor cancels against unitBaseM and this reduces exactly to
    // totalSec * 100 / targetDist, which is the identity you want: 10:00
    // for 1000 y is 1:00 /100 y, no rounding drift.
    //
    // Returns 0 for a nonsensical target (zero time or zero distance);
    // the caller substitutes its own default rather than dividing by it.
    function targetPaceSec100(totalSec as Number, targetDist as Number,
                              units as Number, unitBaseM as Float) as Number {
        if (totalSec <= 0 || targetDist <= 0) { return 0; }
        var distM = targetDist.toFloat() * ((units == 1) ? 0.9144 : 1.0);
        if (distM <= 0.0) { return 0; }
        return ((totalSec.toFloat() * unitBaseM / distM) + 0.5).toNumber();
    }

    // Just the numeric part of a distance, with no unit letter, for drawing
    // in a FONT_NUMBER_* face (which carries digits but no letters).
    function formatDistanceValue(metres as Float, units as Number) as String {
        if (metres < 0.0) { metres = 0.0; }
        if (units == 1) { return (metres / 0.9144).format("%.0f"); }
        return metres.format("%.0f");
    }

    // unitBaseM is 100.0 for metric, 91.44 for yards (100 yd in metres).
    function paceSec100(splitSec as Float, poolLengthM as Float, unitBaseM as Float) as Float {
        if (poolLengthM <= 0.0) { return 0.0; }
        return splitSec * (unitBaseM / poolLengthM);
    }

    function targetLengthSec(targetPaceSec as Number, poolLengthM as Float, unitBaseM as Float) as Float {
        if (unitBaseM <= 0.0) { return 0.0; }
        return targetPaceSec.toFloat() * (poolLengthM / unitBaseM);
    }

    // delta positive = slower than target. tol and fastThr are independent
    // settings (a user can set either one larger than the other), so each
    // side of the scale is checked against its OWN "very" multiple rather
    // than against the other side's threshold -- that used to make the
    // FAST tier unreachable whenever fastThr was set smaller than tol
    // (which is exactly the shipped default), because a delta extreme
    // enough to be VERY_FAST on the old shared scale always got caught by
    // the fast check before the slow-derived one. Symmetric 2x-per-side
    // multiples fix that for any combination of settings.
    function classify(delta as Float, tol as Number, fastThr as Number) as Number {
        var t = tol.toFloat();
        var f = fastThr.toFloat();
        if (delta > t * 2.0)  { return ZONE_VERY_SLOW; }
        if (delta > t)        { return ZONE_SLOW; }
        if (delta < -f * 2.0) { return ZONE_VERY_FAST; }
        if (delta < -f)       { return ZONE_FAST; }
        return ZONE_ON;
    }

    // Reject implausible splits (activity started mid-pool, sensor glitch).
    function isPlausibleSplit(splitSec as Float) as Boolean {
        return (splitSec >= 8.0) && (splitSec <= 240.0);
    }

    function formatPace(sec as Float) as String {
        var s = sec.toNumber();
        if (s < 0) { s = 0; }
        if (s > 5999) { s = 5999; }
        var m = s / 60;
        var r = s % 60;
        return m.format("%d") + ":" + r.format("%02d");
    }

    // Elapsed time (any non-negative number of seconds) as M:SS, or
    // H:MM:SS once it reaches an hour -- pool swims are usually well under
    // an hour, but this keeps a long session legible instead of wrapping.
    function formatElapsed(sec as Float) as String {
        var s = sec.toNumber();
        if (s < 0) { s = 0; }
        var h = s / 3600;
        var m = (s % 3600) / 60;
        var r = s % 60;
        if (h > 0) {
            return h.format("%d") + ":" + m.format("%02d") + ":" + r.format("%02d");
        }
        return m.format("%d") + ":" + r.format("%02d");
    }

    function formatSigned(sec as Float) as String {
        var s = sec.toNumber();
        if (s >= 0) {
            return "+" + s.format("%d") + "s";
        }
        return "-" + (-s).format("%d") + "s";
    }
}
