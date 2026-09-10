import Toybox.Lang;

// Dry-land test harness. The (:debug)/(:release) pair means compute() can call
// debugDistance() unconditionally: in a release build the debug version is
// stripped and the release version (a pass-through) is compiled in instead.
// Do NOT write `if (Debug has :distanceFor)` in compute() — in a release build
// the symbol does not exist at all and that is a compile error, not a no-op.

(:debug)
function debugDistance(realDist as Float, timerMs as Number) as Float {
    // Scripted splits in seconds, cycled: on pace, fast, slow, way slow.
    // Declared inside the function: Monkey C consts must be compile-time
    // scalars, so a module-level const array may not compile.
    var splits = [30.0, 24.0, 36.0, 45.0];
    var pool = 25.0;
    var t = timerMs / 1000.0;
    var dist = 0.0;
    var acc = 0.0;
    var i = 0;
    while (i < 400) {
        var s = splits[i % splits.size()].toFloat();
        if (acc + s > t) { break; }
        acc += s;
        dist += pool;
        i++;
    }
    return dist;
}

(:release)
function debugDistance(realDist as Float, timerMs as Number) as Float {
    return realDist;
}
