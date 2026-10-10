import LocalAuthentication
import SwiftUI

// Manages the app-level lock state. Inject as @StateObject in LedgerApp and
// pass as .environmentObject so LockView can trigger re-auth from its button.
@MainActor
final class AuthGate: ObservableObject {
    @Published private(set) var isUnlocked = false
    @AppStorage("biometricEnabled") private var biometricEnabled = false

    // Try to authenticate. If biometrics/passcode aren't configured on the
    // device, or the toggle is off, unlock immediately so the app stays usable.
    func authenticate() async {
        guard !isUnlocked else { return }   // Bug 1: don't re-prompt if already open
        guard biometricEnabled else {
            isUnlocked = true
            return
        }

        let context = LAContext()
        var error: NSError?

        // deviceOwnerAuthentication = biometrics first, passcode as fallback.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isUnlocked = true   // no lock configured on this device
            return
        }

        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Ledger"
            )
            isUnlocked = ok
        } catch {
            // User cancelled or biometric failed — remain locked.
        }
    }

    func lock() {
        guard biometricEnabled else { return }
        isUnlocked = false
    }
}

// MARK: - Lock screen

struct LockView: View {
    @EnvironmentObject private var authGate: AuthGate

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: Theme.s24) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.ledgerAccent)

                VStack(spacing: Theme.s8) {
                    Text("Ledger")
                        .font(.largeTitle.bold())
                    Text("Unlock to continue")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await authGate.authenticate() }
                } label: {
                    Label("Unlock", systemImage: "faceid")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.ledgerAccent)
                .controlSize(.large)
            }
        }
        // Attempt biometric automatically on appear.
        .task { await authGate.authenticate() }
    }
}
