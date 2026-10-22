// Run on a Mac: swiftc FishingWatch/FishingCore.swift Tests/main.swift -o /tmp/fishtest && /tmp/fishtest

func seeded(_ seed: UInt64) -> () -> Double {
    var s = seed
    return {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Double(s >> 11) / Double(1 << 53)
    }
}

let dt = 0.02

// cast, wait for the bite, then strike on the strong buzz
func castAndHook(_ g: inout FishingGame) {
    _ = g.step(dt: dt, accel: 2.5, crown: 0)
    _ = g.step(dt: dt, accel: 0, crown: 0)
    assert(g.phase == .waiting && g.castDistance > 20)
    var n = 0
    while g.phase == .waiting { _ = g.step(dt: dt, accel: 0, crown: 0); n += 1; assert(n < 1000) }
    assert(g.phase == .bite)
    _ = g.step(dt: dt, accel: 2, crown: 0)
    assert(g.phase == .fighting)
}

// good play: reel only while the fish rests, must land every fish
for seed in 1...50 {
    var g = FishingGame()
    g.random = seeded(UInt64(seed))
    castAndHook(&g)
    var n = 0
    while g.phase == .fighting { _ = g.step(dt: dt, accel: 0, crown: g.pulling ? 0 : 0.15); n += 1; assert(n < 6000) }
    guard case .caught = g.phase else { fatalError("seed \(seed): \(g.phase)") }
}

// reeling nonstop through pulls must snap the line
var greedy = FishingGame()
greedy.random = seeded(7)
castAndHook(&greedy)
while greedy.phase == .fighting { _ = greedy.step(dt: dt, accel: 0, crown: 1) }
assert(greedy.phase == .lost("Line snapped. You reeled while the fish was pulling."))

// striking before the bite scares the fish
var jumpy = FishingGame()
jumpy.random = seeded(3)
_ = jumpy.step(dt: dt, accel: 2.5, crown: 0)
_ = jumpy.step(dt: dt, accel: 0, crown: 0)
for _ in 0..<60 { _ = jumpy.step(dt: dt, accel: 0, crown: 0) }
_ = jumpy.step(dt: dt, accel: 2, crown: 0)
assert(jumpy.phase == .lost("You moved too much and scared the fish."))

// after a round ends, a flick must cast again
for _ in 0..<60 { _ = jumpy.step(dt: dt, accel: 0, crown: 0) }
_ = jumpy.step(dt: dt, accel: 2.5, crown: 0)
_ = jumpy.step(dt: dt, accel: 0, crown: 0)
assert(jumpy.phase == .waiting)

print("ok")
