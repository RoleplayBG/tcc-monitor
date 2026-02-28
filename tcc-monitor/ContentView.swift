import SwiftUI

struct ContentView: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        NavigationView {
            List {
                // Status Section
                Section("System Status") {
                    HStack {
                        Text("Available Memory")
                        Spacer()
                        Text("\(Int(monitor.currentAvailableMB)) MB")
                            .foregroundColor(monitor.currentAvailableMB < 200 ? .red : .green)
                            .bold()
                    }
                    HStack {
                        Text("Physical Memory")
                        Spacer()
                        Text("\(Int(monitor.physicalMemoryMB)) MB")
                    }
                    HStack {
                        Text("Thermal State")
                        Spacer()
                        Text(monitor.thermalStateString)
                            .foregroundColor(monitor.thermalStateString == "nominal" ? .green : .orange)
                    }
                    if monitor.baselineMemory > 0 {
                        HStack {
                            Text("Drop from Baseline")
                            Spacer()
                            let drop = monitor.baselineMemory - monitor.currentAvailableMB
                            Text("\(Int(drop)) MB")
                                .foregroundColor(drop > 200 ? .red : .primary)
                        }
                    }
                }

                // Webhook Config
                Section("Beacon Webhook") {
                    TextField("webhook.site token", text: $monitor.webhookToken)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(.body, design: .monospaced))
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(monitor.lastBeaconStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button("Send Test Beacon") {
                        monitor.sendBeacon(event: "manual_test")
                    }
                }

                // Alert
                if monitor.alertTriggered {
                    Section("ALERT") {
                        Text(monitor.alertMessage)
                            .foregroundColor(.red)
                            .bold()
                    }
                }

                // Recent Readings
                Section("Recent Readings (\(monitor.readings.count))") {
                    ForEach(monitor.readings.suffix(20).reversed()) { reading in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(reading.timestamp, style: .time)
                                    .font(.caption)
                                Spacer()
                                Text(reading.memoryPressure)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(pressureColor(reading.memoryPressure).opacity(0.2))
                                    .cornerRadius(4)
                            }
                            HStack {
                                Text("Avail: \(Int(reading.availableMemoryMB))MB")
                                    .font(.system(.caption, design: .monospaced))
                                Text("Used: \(Int(reading.usedMemoryMB))MB")
                                    .font(.system(.caption, design: .monospaced))
                                Text(reading.thermalState)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                }

                // Export
                Section {
                    Button("Copy Log to Clipboard") {
                        UIPasteboard.general.string = monitor.exportLog()
                    }
                    ShareLink("Export Log", item: monitor.exportLog())
                }
            }
            .navigationTitle("TCC Monitor")
        }
    }

    func pressureColor(_ pressure: String) -> Color {
        switch pressure {
        case "CRITICAL", "SPIKE_DROP": return .red
        case "HIGH": return .orange
        case "ELEVATED": return .yellow
        default: return .green
        }
    }
}
