import Foundation

struct LicenseStatus: Equatable {
    enum Kind: Equatable {
        case trial(daysRemaining: Int)
        case pro(holder: String, expiresAt: Date?)
        case expired
    }

    let kind: Kind

    var hasProAccess: Bool {
        switch kind {
        case .trial, .pro:
            true
        case .expired:
            false
        }
    }
}

enum LicenseError: LocalizedError {
    case configurationMissing
    case invalidLicense
    case activationLimitReached
    case licenseExpired
    case networkUnavailable
    case remoteMessage(String)
    case invalidResponse
    case noActiveLicense

    var errorDescription: String? {
        switch self {
        case .configurationMissing: "Lemon Squeezy has not been configured for this build."
        case .invalidLicense: "This license key is not valid."
        case .activationLimitReached: "This license key has reached its device activation limit."
        case .licenseExpired: "This license key has expired."
        case .networkUnavailable: "A network connection is required to verify this license key."
        case let .remoteMessage(message): message
        case .invalidResponse: "The licensing service returned an unexpected response."
        case .noActiveLicense: "There is no active license on this Mac."
        }
    }
}

/// These values are public identifiers, not Lemon Squeezy API credentials.
/// Set them in the target's Info settings before distributing a production build.
enum LemonSqueezyConfiguration {
    private static let storeIDKey = "LemonSqueezyStoreID"
    private static let productIDKey = "LemonSqueezyProductID"
    private static let variantIDKey = "LemonSqueezyVariantID"
    private static let checkoutURLKey = "LemonSqueezyCheckoutURL"

    static var storeID: Int? { integerValue(for: storeIDKey) }
    static var productID: Int? { integerValue(for: productIDKey) }
    static var variantID: Int? { integerValue(for: variantIDKey) }

    static var checkoutURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: checkoutURLKey) as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return URL(string: value)
    }

    static var isConfigured: Bool {
        storeID != nil && productID != nil && variantID != nil
    }

    private static func integerValue(for key: String) -> Int? {
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? Int, value > 0 {
            return value
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           let integer = Int(value), integer > 0 {
            return integer
        }
        return nil
    }
}

private struct StoredLemonLicense: Codable {
    let key: String
    let instanceID: String
    let holder: String
    let expiresAt: Date?
    let lastValidatedAt: Date
}

private struct LemonLicenseResponse: Decodable {
    let activated: Bool?
    let deactivated: Bool?
    let valid: Bool?
    let error: String?
    let licenseKey: LemonLicenseKey?
    let instance: LemonLicenseInstance?
    let meta: LemonLicenseMeta?

    enum CodingKeys: String, CodingKey {
        case activated, deactivated, valid, error, instance, meta
        case licenseKey = "license_key"
    }
}

private struct LemonLicenseKey: Decodable {
    let status: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case status
        case expiresAt = "expires_at"
    }
}

private struct LemonLicenseInstance: Decodable {
    let id: String?
}

private struct LemonLicenseMeta: Decodable {
    let storeID: Int?
    let productID: Int?
    let variantID: Int?
    let customerName: String?
    let customerEmail: String?

    enum CodingKeys: String, CodingKey {
        case storeID = "store_id"
        case productID = "product_id"
        case variantID = "variant_id"
        case customerName = "customer_name"
        case customerEmail = "customer_email"
    }
}

@MainActor
final class LicenseManager {
    private enum Keys {
        static let service = "dev.molecube.MoleCubeMac.license"
        static let lemonLicense = "lemon-license"
        static let trialStart = "trial-start"
        static let lastSeen = "last-seen"
        static let deviceID = "device-id"
    }

    private let trialDuration: TimeInterval = 14 * 24 * 60 * 60
    private let apiBaseURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses")!

    init() {
        _ = currentStatus()
    }

    var deviceID: String {
        if let stored = LicenseStore.string(for: Keys.deviceID, service: Keys.service), !stored.isEmpty {
            return stored
        }
        let identifier = "MoleCube-" + UUID().uuidString.uppercased()
        LicenseStore.store(identifier, for: Keys.deviceID, service: Keys.service)
        return identifier
    }

    var hasStoredLicense: Bool { storedLicense != nil }

    func currentStatus(now: Date = .now) -> LicenseStatus {
        if let license = storedLicense {
            if let expiresAt = license.expiresAt, expiresAt < now {
                return .init(kind: .expired)
            }
            return .init(kind: .pro(holder: license.holder, expiresAt: license.expiresAt))
        }

        let start = storedDate(for: Keys.trialStart) ?? {
            store(date: now, for: Keys.trialStart)
            return now
        }()
        let lastSeen = storedDate(for: Keys.lastSeen)
        if let lastSeen, now.addingTimeInterval(300) < lastSeen {
            return .init(kind: .expired)
        }
        if lastSeen == nil || now > lastSeen! {
            store(date: now, for: Keys.lastSeen)
        }

        let remaining = start.addingTimeInterval(trialDuration).timeIntervalSince(now)
        guard remaining > 0 else { return .init(kind: .expired) }
        return .init(kind: .trial(daysRemaining: max(1, Int(ceil(remaining / 86_400)))))
    }

    func activate(code: String) async throws -> LicenseStatus {
        guard LemonSqueezyConfiguration.isConfigured else { throw LicenseError.configurationMissing }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw LicenseError.invalidLicense }

        let response = try await request(path: "activate", parameters: [
            "license_key": normalized,
            "instance_name": deviceID
        ])
        guard response.activated == true else { throw responseError(from: response) }
        let license = try storedLicense(from: response, key: normalized)
        save(license)
        return currentStatus()
    }

    func validateStoredLicense() async throws -> LicenseStatus {
        guard let stored = storedLicense else { return currentStatus() }
        guard LemonSqueezyConfiguration.isConfigured else { throw LicenseError.configurationMissing }

        let response = try await request(path: "validate", parameters: [
            "license_key": stored.key,
            "instance_id": stored.instanceID
        ])
        guard response.valid == true else { throw responseError(from: response) }
        let refreshed = try storedLicense(from: response, key: stored.key, fallbackInstanceID: stored.instanceID)
        save(refreshed)
        return currentStatus()
    }

    func deactivate() async throws {
        guard let stored = storedLicense else { throw LicenseError.noActiveLicense }
        guard LemonSqueezyConfiguration.isConfigured else { throw LicenseError.configurationMissing }

        let response = try await request(path: "deactivate", parameters: [
            "license_key": stored.key,
            "instance_id": stored.instanceID
        ])
        guard response.deactivated == true else { throw responseError(from: response) }
        LicenseStore.remove(Keys.lemonLicense, service: Keys.service)
    }

    private func request(path: String, parameters: [String: String]) async throws -> LemonLicenseResponse {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        request.httpBody = formBody(parameters)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw LicenseError.invalidResponse }
            let decoded = try JSONDecoder().decode(LemonLicenseResponse.self, from: data)
            guard (200 ... 299).contains(httpResponse.statusCode) else { throw responseError(from: decoded) }
            return decoded
        } catch let error as LicenseError {
            throw error
        } catch is DecodingError {
            throw LicenseError.invalidResponse
        } catch {
            throw LicenseError.networkUnavailable
        }
    }

    private func storedLicense(
        from response: LemonLicenseResponse,
        key: String,
        fallbackInstanceID: String? = nil
    ) throws -> StoredLemonLicense {
        guard let meta = response.meta,
              meta.storeID == LemonSqueezyConfiguration.storeID,
              meta.productID == LemonSqueezyConfiguration.productID,
              meta.variantID == LemonSqueezyConfiguration.variantID else {
            throw LicenseError.invalidLicense
        }
        guard let instanceID = response.instance?.id ?? fallbackInstanceID, !instanceID.isEmpty else {
            throw LicenseError.invalidResponse
        }
        let expiresAt = parseLemonDate(response.licenseKey?.expiresAt)
        if let expiresAt, expiresAt < .now { throw LicenseError.licenseExpired }
        let holder = nonEmpty(meta.customerName) ?? nonEmpty(meta.customerEmail) ?? "MoleCube Pro"
        return StoredLemonLicense(
            key: key,
            instanceID: instanceID,
            holder: holder,
            expiresAt: expiresAt,
            lastValidatedAt: .now
        )
    }

    private func responseError(from response: LemonLicenseResponse) -> LicenseError {
        let message = response.error?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lowered = message.lowercased()
        if lowered.contains("activation") && (lowered.contains("limit") || lowered.contains("maximum")) {
            return .activationLimitReached
        }
        if lowered.contains("expired") { return .licenseExpired }
        if message.isEmpty { return .invalidLicense }
        return .remoteMessage(message)
    }

    private var storedLicense: StoredLemonLicense? {
        guard let value = LicenseStore.string(for: Keys.lemonLicense, service: Keys.service),
              let data = value.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StoredLemonLicense.self, from: data)
    }

    private func save(_ license: StoredLemonLicense) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(license), let value = String(data: data, encoding: .utf8) else { return }
        LicenseStore.store(value, for: Keys.lemonLicense, service: Keys.service)
    }

    private func formBody(_ parameters: [String: String]) -> Data? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._*"))
        let value = parameters
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        return Data(value.utf8)
    }

    private func parseLemonDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func nonEmpty(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private func storedDate(for key: String) -> Date? {
        guard let value = LicenseStore.string(for: key, service: Keys.service) else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private func store(date: Date, for key: String) {
        LicenseStore.store(ISO8601DateFormatter().string(from: date), for: key, service: Keys.service)
    }
}

/// License keys are customer-entered bearer keys, while Lemon Squeezy remains the source of truth.
/// Keep local state in the app preference domain so opening MoleCube never triggers a Keychain prompt.
@MainActor
private enum LicenseStore {
    private static let defaults = UserDefaults.standard

    static func string(for account: String, service: String) -> String? {
        defaults.string(forKey: "\(service).\(account)")
    }

    static func store(_ value: String, for account: String, service: String) {
        defaults.set(value, forKey: "\(service).\(account)")
    }

    static func remove(_ account: String, service: String) {
        defaults.removeObject(forKey: "\(service).\(account)")
    }
}
