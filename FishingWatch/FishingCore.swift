import Foundation

// Pure game rules with no WatchKit, so the tests run on a Mac.

struct Fish {
    let name: String
    let cm: ClosedRange<Int>
    let strength: Double  // 0...1, higher pulls harder
    let minCast: Double   // only bites when the cast reaches this far (m)
    let odds: Double
}

let fishes: [Fish] = [
    Fish(name: "Flip-flop", cm: 22...28, strength: 0.1, minCast: 0, odds: 1),
    Fish(name: "Silver barb", cm: 15...35, strength: 0.3, minCast: 0, odds: 4),
    Fish(name: "Nile tilapia", cm: 20...40, strength: 0.35, minCast: 0, odds: 5),
    Fish(name: "Walking catfish", cm: 25...60, strength: 0.5, minCast: 12, odds: 3),
    Fish(name: "Striped snakehead", cm: 30...70, strength: 0.55, minCast: 15, odds: 3),
    Fish(name: "Barramundi", cm: 40...90, strength: 0.75, minCast: 22, odds: 2),
    Fish(name: "Giant snakehead", cm: 60...110, strength: 0.85, minCast: 28, odds: 1.5),
    Fish(name: "Mekong giant catfish", cm: 120...250, strength: 1.0, minCast: 35, odds: 0.5),
]

struct Catch: Equatable {
    let name: String
    let cm: Int
}

enum Phase: Equatable {
    case ready, waiting, bite, fighting
    case caught(Catch)
    case lost(String)
}

enum Haptic { case cast, nibble, bite, hooked, pull, warn, success, fail }

struct FishingGame {
    // in g, from userAcceleration
    static let castThreshold = 1.5
    static let hookThreshold = 1.2
    // shortcut: units per Digital Crown turn are a guess, tune this after playing on a real watch
    static let reelPerCrown = 1.0

    private(set) var phase = Phase.ready
    private(set) var castDistance = 0.0
    private(set) var distance = 0.0
    private(set) var tension = 0.0
    private(set) var pulling = false
    var random: () -> Double = { .random(in: 0..<1) }

    private var fish: Fish?
    private var fishCm = 0
    private var t = 0.0
    private var biteAt = 0.0
    private var nextNibble = 0.0
    private var nextWarn = 0.0
    private var nextToggle = 0.0
    private var peak = 0.0

    mutating func reset() {
        phase = .ready
        peak = 0
        tension = 0
        pulling = false
    }

    mutating func step(dt: Double, accel: Double, crown: Double) -> [Haptic] {
        t += dt
        switch phase {
        case .ready:
            // wait for the flick to end so the cast uses its peak force
            if accel > Self.castThreshold {
                peak = max(peak, accel)
            } else if peak > 0 {
                castDistance = min(40, 10 + (peak - Self.castThreshold) * 12)
                distance = castDistance
                peak = 0
                biteAt = 2 + random() * 6
                nextNibble = 1 + random() * 1.5
                enter(.waiting)
                return [.cast]
            }
        case .waiting:
            if t > 1 && accel > Self.hookThreshold {
                enter(.lost("You moved too much and scared the fish."))
                return [.fail]
            }
            if t >= biteAt {
                enter(.bite)
                return [.bite]
            }
            if t >= nextNibble && t < biteAt - 0.5 {
                nextNibble = t + 0.8 + random() * 1.5
                return [.nibble]
            }
        case .bite:
            if accel > Self.hookThreshold {
                hook()
                return [.hooked]
            }
            if t > 1.5 {
                enter(.lost("Too slow. The fish stole the bait."))
                return [.fail]
            }
        case .fighting:
            return fight(dt: dt, crown: crown)
        case .caught, .lost:
            // a flick casts the next round; the player is watching the Mac, not the watch buttons
            if t > 1 && accel > Self.castThreshold {
                reset()
                peak = accel
            }
        }
        return []
    }

    private mutating func hook() {
        let pool = fishes.filter { $0.minCast <= castDistance }
        var r = random() * pool.reduce(0) { $0 + $1.odds }
        let f = pool.first { r -= $0.odds; return r < 0 } ?? pool[0]
        fish = f
        fishCm = f.cm.lowerBound + Int(random() * Double(f.cm.count))
        tension = 0.2
        pulling = true
        nextWarn = 0
        nextToggle = 0.6 + random()
        enter(.fighting)
    }

    private mutating func fight(dt: Double, crown: Double) -> [Haptic] {
        guard let fish else { return [] }
        var out: [Haptic] = []
        // pulls come in short bursts; rolling every frame sometimes gave pulls too long to play against
        if t >= nextToggle {
            pulling.toggle()
            nextToggle = t + (pulling ? 0.6 + random() * fish.strength : 0.8 + random() * 1.2)
            if pulling { out.append(.pull) }
        }
        let reel = min(abs(crown) * Self.reelPerCrown, 1.5)
        if pulling {
            distance += fish.strength * 3 * dt
            tension += fish.strength * 0.15 * dt + reel * 0.12
        } else {
            tension += reel * 0.03
        }
        tension = max(0, tension - 0.2 * dt)
        distance -= reel

        if tension >= 1 {
            enter(.lost("Line snapped. You reeled while the fish was pulling."))
            return out + [.fail]
        }
        if distance >= castDistance + 10 {
            enter(.lost("The fish pulled the line free."))
            return out + [.fail]
        }
        if distance <= 0 {
            enter(.caught(Catch(name: fish.name, cm: fishCm)))
            return out + [.success]
        }
        if tension > 0.75 && t >= nextWarn {
            nextWarn = t + 0.5
            out.append(.warn)
        }
        return out
    }

    private mutating func enter(_ p: Phase) {
        phase = p
        t = 0
    }
}
