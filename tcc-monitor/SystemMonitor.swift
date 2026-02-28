import Foundation
import UIKit
import Combine

// os_proc_available_memory() is available via Darwin
@_silgen_name("os_proc_available_memory")
func os_proc_available_memory() -> UInt64

struct MemoryReading: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let availableMemoryMB: Double
    let usedMemoryMB: Double
    let thermalState: String
    let memoryPressure: String

    init(available: Double, used: Double, thermal: String, pressure: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.availableMemoryMB = available
        self.usedMemoryMB = used
        self.thermalState = thermal
        self.memoryPressure = pressure
    }
}

class SystemMonitor: ObservableObject {
    @Published var readings: [MemoryReading] = []
    @Published var isRunning = false
    @Published var webhookToken: String = ""
    @Published var lastBeaconStatus: String = "Not started"
    @Published var alertTriggered = false
    @Published var alertMessage = ""

    private var timer: Timer?
    private var beaconTimer: Timer?
    private let maxReadings = 500
    var baselineMemory: Double = 0
    private var previousAvailable: Double = 0

    // Memory thresholds (MB)
    private let criticalDropMB: Double = 200  // Alert if memory drops 200MB between readings
    private let criticalLowMB: Double = 150   // Alert if available memory below 150MB

    var currentAvailableMB: Double {
        Double(os_proc_available_memory()) / 1024 / 1024
    }

    var physicalMemoryMB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024
    }

    var thermalStateString: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "CRITICAL"
        @unknown default: return "unknown"
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        baselineMemory = currentAvailableMB
        previousAvailable = baselineMemory

        // Sample every 2 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.takeSample()
        }

        // Beacon every 30 seconds
        beaconTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.sendBeacon()
        }

        // Memory pressure notifications
        NotificationCenter.default.addObserver(
            self, selector: #selector(didReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification, object: nil
        )

        // Thermal state notifications
        NotificationCenter.default.addObserver(
            self, selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification, object: nil
        )

        takeSample()
        sendBeacon()
    }

    func stop() {
        timer?.invalidate()
        beaconTimer?.invalidate()
        timer = nil
        beaconTimer = nil
        isRunning = false
        NotificationCenter.default.removeObserver(self)
    }

    private func takeSample() {
        let available = currentAvailableMB
        let used = physicalMemoryMB - available

        let pressure: String
        let dropFromPrevious = previousAvailable - available
        let dropFromBaseline = baselineMemory - available

        if available < criticalLowMB {
            pressure = "CRITICAL"
        } else if dropFromPrevious > criticalDropMB {
            pressure = "SPIKE_DROP"
        } else if dropFromBaseline > 500 {
            pressure = "HIGH"
        } else if dropFromBaseline > 200 {
            pressure = "ELEVATED"
        } else {
            pressure = "normal"
        }

        let reading = MemoryReading(
            available: available,
            used: used,
            thermal: thermalStateString,
            pressure: pressure
        )

        DispatchQueue.main.async {
            self.readings.append(reading)
            if self.readings.count > self.maxReadings {
                self.readings.removeFirst(self.readings.count - self.maxReadings)
            }

            if pressure == "CRITICAL" || pressure == "SPIKE_DROP" {
                self.alertTriggered = true
                self.alertMessage = "Memory \(pressure): \(Int(available))MB available (dropped \(Int(dropFromPrevious))MB)"
                self.sendBeacon(urgent: true, event: pressure)
            }
        }

        previousAvailable = available
    }

    @objc private func didReceiveMemoryWarning() {
        let available = currentAvailableMB
        DispatchQueue.main.async {
            self.alertTriggered = true
            self.alertMessage = "SYSTEM MEMORY WARNING at \(Int(available))MB"
        }
        sendBeacon(urgent: true, event: "SYSTEM_MEMORY_WARNING")
    }

    @objc private func thermalStateChanged() {
        let state = thermalStateString
        if state == "serious" || state == "CRITICAL" {
            DispatchQueue.main.async {
                self.alertTriggered = true
                self.alertMessage = "Thermal state: \(state)"
            }
            sendBeacon(urgent: true, event: "THERMAL_\(state)")
        }
    }

    func sendBeacon(urgent: Bool = false, event: String = "heartbeat") {
        guard !webhookToken.isEmpty else { return }

        let available = currentAvailableMB
        let used = physicalMemoryMB - available

        let payload: [String: Any] = [
            "t": ISO8601DateFormatter().string(from: Date()),
            "e": event,
            "mem_avail_mb": Int(available),
            "mem_used_mb": Int(used),
            "mem_total_mb": Int(physicalMemoryMB),
            "thermal": thermalStateString,
            "baseline_mb": Int(baselineMemory),
            "drop_from_baseline_mb": Int(baselineMemory - available),
            "urgent": urgent,
            "uptime_s": Int(ProcessInfo.processInfo.systemUptime)
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string: "https://webhook.site/\(webhookToken)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("TCC-Monitor/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    self?.lastBeaconStatus = "OK (\(event)) \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))"
                } else {
                    self?.lastBeaconStatus = "FAIL: \(error?.localizedDescription ?? "unknown")"
                }
            }
        }.resume()
    }

    func exportLog() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(readings) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
