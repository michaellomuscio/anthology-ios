import SwiftUI

struct PairingView: View {
    @EnvironmentObject var store: BridgeStore
    @State private var showScanner = false
    @State private var host: String = ""
    @State private var portText: String = "17872"
    @State private var code: String = ""
    @State private var deviceLabel: String = UIDevice.current.name
    @State private var isPairing = false
    @State private var pairError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    VStack(spacing: 12) {
                        Button(action: { showScanner = true }) {
                            Label("Scan QR code", systemImage: "qrcode.viewfinder")
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    Divider().overlay(Text("or enter manually").font(.caption2).foregroundStyle(.secondary))

                    manualForm
                }
                .padding(20)
            }
            .navigationTitle("Pair with your Mac")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showScanner) {
                QRScannerView { result in
                    showScanner = false
                    if let url = PairingURL(from: result) {
                        host = url.host
                        portText = String(url.port)
                        code = url.code
                        Task { await submit() }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome to Anthology")
                .font(.title2.bold())
            Text("Open Anthology on your Mac, click the phone icon in the top bar, and tap **Pair new device**.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var manualForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Mac address (host or IP)", text: $host, placeholder: "100.92.18.4 or my-mac.local", keyboard: .URL)
            HStack(spacing: 10) {
                field("Port", text: $portText, placeholder: "17872", keyboard: .numberPad)
                    .frame(maxWidth: 130)
                field("Pairing code", text: $code, placeholder: "6 digits", keyboard: .numberPad)
            }
            field("Device label", text: $deviceLabel, placeholder: "iPhone")

            if let err = pairError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(action: { Task { await submit() } }) {
                if isPairing {
                    ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Text("Pair").frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSubmit || isPairing)
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String = "", keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var canSubmit: Bool {
        !host.isEmpty && Int(portText) != nil && code.count == 6
    }

    private func submit() async {
        guard let port = Int(portText) else { return }
        isPairing = true
        pairError = nil
        defer { isPairing = false }
        do {
            try await store.pair(host: host, port: port, code: code, label: deviceLabel)
        } catch let err as PairingError {
            pairError = pairing(error: err.error)
        } catch {
            pairError = error.localizedDescription
        }
    }

    private func pairing(error code: String) -> String {
        switch code {
        case "invalid_code": return "Wrong pairing code. Check the screen on your Mac."
        case "expired": return "Pairing code expired. Generate a new one on your Mac."
        case "no_active_code": return "No active pairing on the Mac. Click Pair new device on the Mac first."
        case "rate_limited": return "Too many tries — wait a minute and try again."
        default: return "Pairing failed: \(code)"
        }
    }
}
