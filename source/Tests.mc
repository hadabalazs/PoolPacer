import Toybox.Lang;
import Toybox.Test;

(:test)
function testSnap25(logger as Logger) as Boolean {
    return PaceMath.snapPoolLength(24.7) == 25.0;
}

(:test)
function testSnapYardPool(logger as Logger) as Boolean {
    return PaceMath.snapPoolLength(22.9) == 22.86;
}

(:test)
function testSnapGarbage(logger as Logger) as Boolean {
    return PaceMath.snapPoolLength(7.4) == 7.4;
}

(:test)
function testPace(logger as Logger) as Boolean {
    // 30 s for 25 m = 2:00 /100 m
    var p = PaceMath.paceSec100(30.0, 25.0, 100.0);
    return (p > 119.9) && (p < 120.1);
}

(:test)
function testClassifyBoundaries(logger as Logger) as Boolean {
    return PaceMath.classify(3.0, 3, 8) == PaceMath.ZONE_ON
        && PaceMath.classify(3.1, 3, 8) == PaceMath.ZONE_SLOW
        && PaceMath.classify(6.1, 3, 8) == PaceMath.ZONE_VERY_SLOW
        && PaceMath.classify(-8.0, 3, 8) == PaceMath.ZONE_ON
        && PaceMath.classify(-8.1, 3, 8) == PaceMath.ZONE_FAST
        && PaceMath.classify(-16.1, 3, 8) == PaceMath.ZONE_VERY_FAST;
}

// The bug this locks in: with the app's SHIPPED defaults (tolerance 12,
// fast-threshold 8 -- i.e. fastThr < tol), the old classify() made ZONE_FAST
// unreachable because it checked the fast-threshold multiple before the
// tolerance-derived one, regardless of which was actually larger. FAST must
// be reachable no matter which of the two settings the user sets larger.
(:test)
function testFastZoneReachableRegardlessOfSettingOrder(logger as Logger) as Boolean {
    return PaceMath.classify(-7.0, 12, 8) == PaceMath.ZONE_ON
        && PaceMath.classify(-9.0, 12, 8) == PaceMath.ZONE_FAST
        && PaceMath.classify(-17.0, 12, 8) == PaceMath.ZONE_VERY_FAST;
}

(:test)
function testFormat(logger as Logger) as Boolean {
    return PaceMath.formatPace(125.0).equals("2:05")
        && PaceMath.formatSigned(-7.0).equals("-7s");
}

// --- pool length presets: every Garmin size, both units ---

(:test)
function testAllGarminPresetsSnapExactly(logger as Logger) as Boolean {
    var presets = [18.288, 20.0, 22.86, 25.0, 30.48, 33.3333, 45.72, 50.0];
    for (var i = 0; i < presets.size(); i++) {
        var p = presets[i].toFloat();
        if (PaceMath.snapPoolLength(p) != p) { return false; }
    }
    return true;
}

(:test)
function testYardMetreNeighboursDoNotCollide(logger as Logger) as Boolean {
    // each yard preset must not be pulled to its metre neighbour, or vice versa
    return PaceMath.snapPoolLength(22.9)  == 22.86    // 25 yd stays 25 yd
        && PaceMath.snapPoolLength(24.9)  == 25.0     // 25 m  stays 25 m
        && PaceMath.snapPoolLength(45.8)  == 45.72    // 50 yd stays 50 yd
        && PaceMath.snapPoolLength(49.8)  == 50.0     // 50 m  stays 50 m
        && PaceMath.snapPoolLength(30.5)  == 30.48    // 33y   stays 33y
        && PaceMath.snapPoolLength(18.3)  == 18.288;  // 20 yd stays 20 yd
}

(:test)
function testCustomPoolPassesThrough(logger as Logger) as Boolean {
    // custom sizes must NOT be snapped to a nearby preset
    return PaceMath.snapPoolLength(21.0) == 21.0
        && PaceMath.snapPoolLength(35.0) == 35.0
        && PaceMath.snapPoolLength(15.0) == 15.0;
}

(:test)
function testFormatPoolLength(logger as Logger) as Boolean {
    return PaceMath.formatPoolLength(25.0, 0).equals("25m")
        && PaceMath.formatPoolLength(22.86, 1).equals("25y")
        && PaceMath.formatPoolLength(45.72, 1).equals("50y")
        && PaceMath.formatPoolLength(0.0, 0).equals("?");
}

// --- free-form target pace: any time over any distance ---

(:test)
function testTargetPaceMetric(logger as Logger) as Boolean {
    // 20:00 for 1000 m  ->  2:00 /100 m
    return PaceMath.targetPaceSec100(1200, 1000, 0, 100.0) == 120
        // 1:45 for 100 m -> 1:45 /100 m, entered directly
        && PaceMath.targetPaceSec100(105, 100, 0, 100.0) == 105
        // 8:00 for 400 m -> 2:00 /100 m
        && PaceMath.targetPaceSec100(480, 400, 0, 100.0) == 120;
}

(:test)
function testTargetPaceYards(logger as Logger) as Boolean {
    // the yard factor must cancel: 10:00 for 1000 y is exactly 1:00 /100 y
    return PaceMath.targetPaceSec100(600, 1000, 1, 91.44) == 60
        && PaceMath.targetPaceSec100(1200, 1000, 1, 91.44) == 120
        && PaceMath.targetPaceSec100(90, 100, 1, 91.44) == 90;
}

(:test)
function testTargetPaceRejectsNonsense(logger as Logger) as Boolean {
    return PaceMath.targetPaceSec100(0, 1000, 0, 100.0) == 0
        && PaceMath.targetPaceSec100(1200, 0, 0, 100.0) == 0
        && PaceMath.targetPaceSec100(-5, 100, 0, 100.0) == 0;
}

(:test)
function testFormatDistanceValue(logger as Logger) as Boolean {
    return PaceMath.formatDistanceValue(1250.0, 0).equals("1250")
        && PaceMath.formatDistanceValue(0.0, 0).equals("0")
        && PaceMath.formatDistanceValue(914.4, 1).equals("1000");
}
