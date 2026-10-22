import CoreMotion
import Observation
import WatchKit

@Observable final class GameModel {
    var game = FishingGame()
    private(set) var best: Catch? = GameModel.loadBest()

    private let motion = CMMotionManager()
    // keeps the sensors running after the wrist drops and the screen dims
    private var session: WKExtendedRuntimeSession?
    private var crown = 0.0
    private var last: TimeInterval?

    private var nibbles = 0
    private var lastSend = 0.0

    // stdout reaches the Mac over the developer connection; line buffering keeps the Mac screen from lagging
    init() { setvbuf(stdout, nil, _IOLBF, 0) }

    func addCrown(_ d: Double) { crown += d }

    func start() {
        if session?.state != .running {
            let s = WKExtendedRuntimeSession()
            s.start()
            session = s
        }
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let m else { return }
            let a = m.userAcceleration
            let dt = min(last.map { m.timestamp - $0 } ?? 0, 0.1)
            last = m.timestamp
            let haptics = game.step(dt: dt, accel: (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot(), crown: crown)
            crown = 0
            haptics.forEach(play)
            if haptics.contains(.nibble) { nibbles += 1 }
            if m.timestamp - lastSend > 1.0 / 15 {
                lastSend = m.timestamp
                send()
            }
            if haptics.contains(.success), case .caught(let c) = game.phase, c.cm > (best?.cm ?? 0) {
                best = c
                UserDefaults.standard.set(c.name, forKey: "bestFish")
                UserDefaults.standard.set(c.cm, forKey: "bestFishCm")
            }
        }
    }

    // shortcut: state goes out through the devicectl console because the watch can't reach the Mac over LAN HTTP.
    // Only works when launched from mac/server.py; playing without a Mac would need an iPhone relay app.
    private func send() {
        var s: [String: Any] = ["cast": game.castDistance, "dist": game.distance, "tension": game.tension,
                                "pulling": game.pulling, "nibbles": nibbles]
        switch game.phase {
        case .ready: s["phase"] = "ready"
        case .waiting: s["phase"] = "waiting"
        case .bite: s["phase"] = "bite"
        case .fighting: s["phase"] = "fighting"
        case .caught(let c):
            s["phase"] = "caught"
            s["fish"] = c.name
            s["cm"] = c.cm
        case .lost(let reason):
            s["phase"] = "lost"
            s["reason"] = reason
        }
        if let best { s["best"] = "\(best.name) \(best.cm) cm" }
        if let data = try? JSONSerialization.data(withJSONObject: s), let line = String(data: data, encoding: .utf8) {
            print("STATE " + line)
        }
    }

    private func play(_ h: Haptic) {
        let type: WKHapticType = switch h {
        case .cast: .start
        case .nibble, .warn: .click
        case .bite: .notification
        case .hooked: .directionUp
        case .pull: .directionDown
        case .success: .success
        case .fail: .failure
        }
        WKInterfaceDevice.current().play(type)
    }

    private static func loadBest() -> Catch? {
        guard let name = UserDefaults.standard.string(forKey: "bestFish") else { return nil }
        return Catch(name: name, cm: UserDefaults.standard.integer(forKey: "bestFishCm"))
    }
}
