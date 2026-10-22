import SwiftUI

@main
struct FishingApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var model = GameModel()
    @State private var crown = 0.0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        screen
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusable()
            .digitalCrownRotation($crown, from: 0, through: 100, by: nil, sensitivity: .high,
                                  isContinuous: true, isHapticFeedbackEnabled: false)
            .onChange(of: crown) { oldValue, newValue in reel(from: oldValue, to: newValue) }
            .onChange(of: scenePhase, initial: true) { _, phase in
                print("scene", phase)
                if phase != .background { model.start() }  // launched from the Mac with the screen off arrives as inactive, not active
            }
    }

    private func reel(from old: Double, to new: Double) {
        var d = new - old
        if abs(d) > 50 { d -= d > 0 ? 100 : -100 }  // the value wraps from 100 back to 0
        model.addCrown(d)
    }

    @ViewBuilder private var screen: some View {
        let g = model.game
        switch g.phase {
        case .ready:
            VStack(spacing: 8) {
                Image(systemName: "figure.fishing").font(.system(size: 44))
                Text("Flick your wrist\nforward to cast").multilineTextAlignment(.center)
                if let best = model.best {
                    Text("Best: \(best.name), \(best.cm) cm").font(.footnote).foregroundStyle(.secondary)
                }
            }
        case .waiting:
            VStack(spacing: 6) {
                Text("Float at \(Int(g.castDistance)) m").font(.headline)
                Text("Wait for a bite.\nA light tap is a nibble, hold still.")
                    .multilineTextAlignment(.center).font(.footnote).foregroundStyle(.secondary)
            }
        case .bite:
            Text("Strike!").font(.system(size: 44, weight: .heavy)).foregroundStyle(.red)
        case .fighting:
            VStack(spacing: 8) {
                Text(g.pulling ? "Stop reeling, it's pulling" : "Turn the Crown to reel")
                    .font(.headline).foregroundStyle(g.pulling ? .orange : .primary)
                Text("\(Int(max(0, g.distance))) m").font(.system(size: 36, weight: .bold)).monospacedDigit()
                Gauge(value: min(g.tension, 1)) { Text("Tension") }
                    .gaugeStyle(.accessoryLinear)
                    .tint(Gradient(colors: [.green, .yellow, .red]))
            }
            .padding(.horizontal)
        case .caught(let c):
            VStack(spacing: 6) {
                Text("\(c.name)").font(.title3.bold())
                Text("\(c.cm) cm").font(.system(size: 32, weight: .bold))
                if model.best == c { Text("New record").foregroundStyle(.yellow) }
                again
            }
        case .lost(let reason):
            VStack(spacing: 8) {
                Text(reason).multilineTextAlignment(.center)
                again
            }
        }
    }

    // Double Tap also presses this button
    private var again: some View {
        Button("Cast again") { model.game.reset() }
            .handGestureShortcut(.primaryAction)
    }
}
