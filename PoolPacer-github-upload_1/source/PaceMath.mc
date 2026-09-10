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

    // unitBaseM is 100.0 for metric, 91.44 for yards (100 yd in metres).
    function paceSec100(splitSec as Float, poolLengthM as Float, unitBaseM as Float) as Float {
        if (poolLengthM <= 0.0) { return 0.0; }
        return splitSec * (unitBaseM / poolLengthM);
    }

    function targetLengthSec(targetPaceSec as Number, poolLengthM as Float, unitBaseM as Float) as Float {
        if (unitBaseM <= 0.0) { return 0.0; }
        return targetPaceSec.toFloat() * (poolLengthM / unitBaseM);
    }

    // delta positive = slower than target.
    function classify(delta as Float, tol as Number, fastThr as Number) as Number {
        var t = tol.toFloat();
        var f = fastThr.toFloat();
        if (delta > t * 2.0)  { return ZONE_VERY_SLOW; }
        if (delta > t)        { return ZONE_SLOW; }
        if (delta < -f)       { return ZONE_VERY_FAST; }
        if (delta < -t)       { return ZONE_FAST; }
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
