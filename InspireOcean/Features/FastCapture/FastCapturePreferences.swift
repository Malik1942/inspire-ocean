import Foundation

enum FastCaptureTrigger: String, CaseIterable, Identifiable {
    case actionButton
    case cameraControl

    var id: String { rawValue }

    var label: String {
        switch self {
        case .actionButton: return "Action Button"
        case .cameraControl: return "Camera Control"
        }
    }

    var symbol: String {
        switch self {
        case .actionButton: return "button.programmable"
        case .cameraControl: return "camera.viewfinder"
        }
    }

    var setupSteps: [String] {
        switch self {
        case .actionButton:
            return [
                "Settings",
                "Action Button",
                "Shortcut",
                "Start Fast Capture"
            ]
        case .cameraControl:
            return [
                "Shortcuts",
                "Take Screenshot",
                "Start Context Capture",
                "Assign where available"
            ]
        }
    }
}

enum FastCaptureInputPreference: String, CaseIterable, Identifiable {
    case voiceFirst
    case typingFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .voiceFirst: return "Voice First"
        case .typingFirst: return "Typing First"
        }
    }

    var symbol: String {
        switch self {
        case .voiceFirst: return "waveform"
        case .typingFirst: return "text.cursor"
        }
    }
}

enum FastCaptureLaunchSource: String, Codable {
    case actionButton
    case cameraControl
    case shortcut
    case onboarding
    case inApp

    var label: String {
        switch self {
        case .actionButton: return "Action Button"
        case .cameraControl: return "Camera Control"
        case .shortcut: return "Shortcut"
        case .onboarding: return "First capture"
        case .inApp: return "Fast Capture"
        }
    }
}

struct FastCaptureRequest: Identifiable {
    let id: UUID
    var source: FastCaptureLaunchSource
    var inputPreference: FastCaptureInputPreference
    var imageData: Data?
    var seedText: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        source: FastCaptureLaunchSource,
        inputPreference: FastCaptureInputPreference,
        imageData: Data? = nil,
        seedText: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.source = source
        self.inputPreference = inputPreference
        self.imageData = imageData
        self.seedText = seedText
        self.createdAt = createdAt
    }
}

enum FastCapturePreferenceKeys {
    static let trigger = "fastCapture.trigger"
    static let inputPreference = "fastCapture.inputPreference"
    static let autoScreenshot = "fastCapture.autoScreenshot"
    static let onboardingCompleted = "fastCapture.onboardingCompleted"
}

enum FastCapturePreferences {
    static let defaults: UserDefaults = UserDefaults(suiteName: Persistence.appGroupID) ?? .standard

    static var trigger: FastCaptureTrigger {
        get {
            let raw = defaults.string(forKey: FastCapturePreferenceKeys.trigger)
            return raw.flatMap(FastCaptureTrigger.init(rawValue:)) ?? .actionButton
        }
        set { defaults.set(newValue.rawValue, forKey: FastCapturePreferenceKeys.trigger) }
    }

    static var inputPreference: FastCaptureInputPreference {
        get {
            let raw = defaults.string(forKey: FastCapturePreferenceKeys.inputPreference)
            return raw.flatMap(FastCaptureInputPreference.init(rawValue:)) ?? .voiceFirst
        }
        set { defaults.set(newValue.rawValue, forKey: FastCapturePreferenceKeys.inputPreference) }
    }

    static var autoScreenshotEnabled: Bool {
        get {
            guard defaults.object(forKey: FastCapturePreferenceKeys.autoScreenshot) != nil else { return true }
            return defaults.bool(forKey: FastCapturePreferenceKeys.autoScreenshot)
        }
        set { defaults.set(newValue, forKey: FastCapturePreferenceKeys.autoScreenshot) }
    }
}

private struct StoredFastCaptureRequest: Codable {
    var id: UUID
    var source: FastCaptureLaunchSource
    var inputPreferenceRaw: String
    var imageFileName: String?
    var seedText: String
    var createdAt: Date
}

enum FastCaptureLaunchStore {
    private static let pendingRequestKey = "fastCapture.pendingRequest"

    static func stagePendingRequest(
        source: FastCaptureLaunchSource,
        imageData: Data? = nil,
        seedText: String = ""
    ) {
        let imageFileName = writePendingImage(imageData)
        let stored = StoredFastCaptureRequest(
            id: UUID(),
            source: source,
            inputPreferenceRaw: FastCapturePreferences.inputPreference.rawValue,
            imageFileName: imageFileName,
            seedText: seedText.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: .now
        )

        guard let data = try? JSONEncoder().encode(stored) else { return }
        FastCapturePreferences.defaults.set(data, forKey: pendingRequestKey)
    }

    static func consumePendingRequest() -> FastCaptureRequest? {
        guard let data = FastCapturePreferences.defaults.data(forKey: pendingRequestKey),
              let stored = try? JSONDecoder().decode(StoredFastCaptureRequest.self, from: data)
        else { return nil }

        FastCapturePreferences.defaults.removeObject(forKey: pendingRequestKey)
        let imageData = stored.imageFileName.flatMap { readPendingImage(named: $0) }
        let inputPreference = FastCaptureInputPreference(rawValue: stored.inputPreferenceRaw) ?? .voiceFirst

        return FastCaptureRequest(
            id: stored.id,
            source: stored.source,
            inputPreference: inputPreference,
            imageData: imageData,
            seedText: stored.seedText,
            createdAt: stored.createdAt
        )
    }

    private static var directory: URL {
        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Persistence.appGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("FastCapture", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func writePendingImage(_ imageData: Data?) -> String? {
        guard let imageData else { return nil }
        let fileName = "context-\(UUID().uuidString).image"
        let url = directory.appendingPathComponent(fileName)
        do {
            try imageData.write(to: url, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    private static func readPendingImage(named fileName: String) -> Data? {
        let url = directory.appendingPathComponent(fileName)
        defer { try? FileManager.default.removeItem(at: url) }
        return try? Data(contentsOf: url)
    }
}
