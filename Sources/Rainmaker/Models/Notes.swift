// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The server's notes capability, advertised when the notes app is installed and enabled.
///
/// On Nextcloud, notes are provided by the "Notes" app (`notes`), which unlike most of what this library covers is not part of a Nextcloud installation and has to be installed separately. When that app is available the server advertises this object under the `notes` key, which is why ``key`` is `"notes"`. Its mere presence is the signal a client needs before calling ``Server/notes()`` or ``Server/notes(changedSince:)``: check it with `try await capabilities().contains(Notes.self)`.
///
/// The object is only advertised to authenticated clients; an anonymous capabilities request does not contain it.
/// All fields are kept optional so that a server which omits one of them still decodes successfully.
///
public struct Notes: Capability {
    public static let key = "notes"

    ///
    /// The major component of ``minimumAPIVersion``.
    ///
    /// Only this exact major version satisfies the requirement. A future major version would be a different API with its own base path, so it must not silently pass a check meant for this one.
    ///
    static let minimumMajorAPIVersion = 1

    ///
    /// The minor component of ``minimumAPIVersion``.
    ///
    static let minimumMinorAPIVersion = 3

    ///
    /// The oldest version of the notes API this library works with, which notes app 4.5 introduced in 2022.
    ///
    /// Everything older is unsupported: ``Note/entityTag`` and ``Note/isReadOnly`` arrived with API version 1.2 and are relied upon rather than treated as optional, and custom file suffixes arrived with 1.3. A server whose notes app is older makes ``Server/notes()`` and ``Server/notes(changedSince:)`` throw ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)``.
    ///
    public static var minimumAPIVersion: String {
        "\(minimumMajorAPIVersion).\(minimumMinorAPIVersion)"
    }

    ///
    /// Whether any of the given API versions satisfies ``minimumAPIVersion``.
    ///
    /// The strings are in the `"<major>.<minor>"` form the server uses, both in the ``apiVersion`` capability and in the `X-Notes-API-Versions` header every response of the notes API carries. Any further components are tolerated and ignored, so a server which one day reports a patch component as well still reads as supported. An entry which does not parse at all is skipped rather than treated as a rejection, so a version scheme this library does not know about cannot make an otherwise supported server look unsupported.
    ///
    static func supports(apiVersions: [String]) -> Bool {
        apiVersions.contains { version in
            let components = version.split(separator: ".").compactMap { Int($0) }

            guard components.count >= 2 else {
                return false
            }

            return components[0] == minimumMajorAPIVersion && components[1] >= minimumMinorAPIVersion
        }
    }

    ///
    /// The versions of the REST API the server supports, e.g. `["0.2", "1.3", "1.4"]`.
    ///
    /// Both retrieval methods require at least ``minimumAPIVersion``, which ``isSupported`` checks for.
    ///
    public let apiVersion: [String]?

    ///
    /// The version of the notes app itself, e.g. `"6.0.1"`.
    ///
    /// This is the app's own version and unrelated to the server ``Version``, which is why it is kept as the plain string the server sends.
    ///
    public let version: String?

    ///
    /// The path of the folder the notes are stored in, relative to the account's files, e.g. `"Notes"`.
    ///
    /// The folder is what makes notes reachable over WebDAV as well, e.g. through ``Server/enumerate(at:recursively:)``.
    /// It tracks the user's setting rather than reporting a fixed default, so it is the same value ``NotesSettings/notesPath`` reports and spares a client which fetched the capabilities anyway a second request.
    ///
    public let notesPath: String?

    ///
    /// Whether the installed app is new enough for this library to work with it.
    ///
    /// This is the cheap way to find out before calling ``Server/notes()``, which enforces the same requirement on every response and throws ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is not met. It is `false` when the server advertises no API version at all.
    ///
    public var isSupported: Bool {
        Self.supports(apiVersions: apiVersion ?? [])
    }

    private enum CodingKeys: String, CodingKey {
        case apiVersion = "api_version"
        case version
        case notesPath = "notes_path"
    }
}
