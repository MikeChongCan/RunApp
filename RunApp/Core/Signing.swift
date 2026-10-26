import Foundation
import Security

/// A development team with a usable signing identity in the keychain.
struct SigningTeam: Hashable, Sendable, Codable, Identifiable {
    /// Team ID, from the certificate's OU (not the ID in the common name's parentheses).
    let id: String
    /// Organization, e.g. "RockieStar Inc.".
    let name: String
}

/// How RunApp overrides the project's code signing for a run. Passed to xcodebuild through
/// `sweetpad run … -- KEY=VALUE`, so the project file is never edited.
enum SigningOverride: Hashable, Sendable, Codable {
    /// Use the project's own settings.
    case project
    /// Ad-hoc "Sign to Run Locally". Works for the Mac and simulators, not physical devices.
    case local
    /// Automatic signing with one of this Mac's teams.
    case team(SigningTeam)

    var title: String {
        switch self {
        case .project: "Project Settings"
        case .local: "Sign to Run Locally"
        case let .team(team): "\(team.name) (\(team.id))"
        }
    }

    /// Extra xcodebuild arguments; empty for `.project`.
    var xcodebuildArguments: [String] {
        switch self {
        case .project:
            []
        case .local:
            [
                "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM=",
                "PROVISIONING_PROFILE_SPECIFIER=", "PROVISIONING_PROFILE=", "OTHER_CODE_SIGN_FLAGS=",
            ]
        case let .team(team):
            [
                "-allowProvisioningUpdates", "CODE_SIGN_STYLE=Automatic", "DEVELOPMENT_TEAM=\(team.id)",
                "CODE_SIGN_IDENTITY=Apple Development", "PROVISIONING_PROFILE_SPECIFIER=", "PROVISIONING_PROFILE=",
            ]
        }
    }

    func isUsable(on destination: Destination?) -> Bool {
        guard case .local = self, let destination else { return true }
        return destination.kind == .mac || destination.kind == .simulator
    }

    /// Remembered per project in UserDefaults.
    static func remembered(for project: LocatedProject, defaults: UserDefaults = .standard) -> SigningOverride {
        guard let data = defaults.data(forKey: key(project)),
              let value = try? JSONDecoder().decode(SigningOverride.self, from: data)
        else { return .project }
        return value
    }

    func remember(for project: LocatedProject, defaults: UserDefaults = .standard) {
        if self == .project {
            defaults.removeObject(forKey: Self.key(project))
        } else if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key(project))
        }
    }

    private static func key(_ project: LocatedProject) -> String {
        "signing:\(project.url.path)"
    }

    /// Whether a build error is a signing problem that a different override could fix.
    static func isSigningFailure(_ text: String) -> Bool {
        let needles = [
            "signing certificate", "requires a development team", "No profiles for", "provisioning profile",
            "Signing for", "No Account for Team", "doesn't match the entitlements", "code signing",
        ]
        return needles.contains { text.localizedCaseInsensitiveContains($0) }
    }
}

enum SigningTeams {
    /// Teams that have an "Apple Development" identity (certificate plus private key) in the keychain.
    static func load() -> [SigningTeam] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let identities = result as? [SecIdentity]
        else { return [] }

        var teams: [String: SigningTeam] = [:]
        for identity in identities {
            var certificate: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { continue }
            var commonName: CFString?
            SecCertificateCopyCommonName(certificate, &commonName)
            guard let commonName = commonName as String?, commonName.hasPrefix("Apple Development") else { continue }
            let subject = subjectFields(certificate)
            guard let teamID = subject["2.5.4.11"] else { continue }
            teams[teamID] = SigningTeam(id: teamID, name: subject["2.5.4.10"] ?? teamID)
        }
        return teams.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Subject name fields by OID, e.g. `2.5.4.11` (OU) and `2.5.4.10` (O).
    private static func subjectFields(_ certificate: SecCertificate) -> [String: String] {
        let keys = [kSecOIDX509V1SubjectName] as CFArray
        guard let values = SecCertificateCopyValues(certificate, keys, nil) as? [String: Any],
              let subject = values[kSecOIDX509V1SubjectName as String] as? [String: Any],
              let entries = subject[kSecPropertyKeyValue as String] as? [[String: Any]]
        else { return [:] }
        var fields: [String: String] = [:]
        for entry in entries {
            if let label = entry[kSecPropertyKeyLabel as String] as? String,
               let value = entry[kSecPropertyKeyValue as String] as? String {
                fields[label] = value
            }
        }
        return fields
    }
}
