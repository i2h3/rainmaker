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
    ///
    /// The name of the object the server advertises this capability under, which is the identifier of the notes app.
    ///
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
    static let minimumMinorAPIVersion = 4

    ///
    /// The oldest version of the notes API this library works with, which is notes API version 1.4 as introduced by notes app 4.12.3 in 2025.
    ///
    /// Version 1.4 is the one which exposes the attachments of a note, below a path every release of the notes app advertising it serves, so requiring it is what lets the notes features rely on that path rather than probe for it.
    /// Everything older is unsupported: ``Note/entityTag`` and ``Note/isReadOnly`` arrived with API version 1.2 and are relied upon rather than treated as optional, custom file suffixes arrived with 1.3, and the attachment endpoints with 1.4.
    /// A server whose notes app is older makes ``Server/notes()``, ``Server/notes(changedSince:)``, ``Server/notes(changedSince:ifChangedFrom:)``, ``Server/notes(changedSince:chunkSize:continuingAfter:)``, ``Server/notes(changedSince:chunkSize:ifChangedFrom:)``, ``Server/noteChunks(changedSince:chunkSize:)``, ``Server/noteSummaries(changedSince:)``, ``Server/noteSummaries(changedSince:ifChangedFrom:)``, ``Server/noteSummaries(changedSince:chunkSize:continuingAfter:)``, ``Server/noteSummaries(changedSince:chunkSize:ifChangedFrom:)``, ``Server/noteSummaryChunks(changedSince:chunkSize:)``, ``Server/note(_:)``, ``Server/note(_:ifChangedFrom:)``, ``Server/createNote(title:category:content:modification:isFavorite:)``, ``Server/updateNote(_:title:category:content:modification:isFavorite:ifMatching:)``, ``Server/deleteNote(_:)``, ``Server/attachment(at:ofNote:)``, ``Server/downloadAttachment(at:ofNote:to:force:)``, ``Server/notesSettings()`` and ``Server/updateNotesSettings(notesPath:fileSuffix:noteMode:showsHiddenFiles:loadsRecentNoteOnStartUp:)`` throw ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)``.
    /// Adding and deleting attachments through ``Server/addAttachment(_:toNote:fileName:)-(URL,Int,String?)``, ``Server/addAttachment(_:toNote:fileName:)-(Data,Int,String)`` and ``Server/deleteAttachment(at:ofNote:)`` throws ``RainmakerError/methodNotAllowed`` on such a server instead, because an app which does not know the attachment routes routes no other method than `GET` below them, which the server refuses before the app is involved.
    ///
    public static var minimumAPIVersion: String {
        "\(minimumMajorAPIVersion).\(minimumMinorAPIVersion)"
    }

    ///
    /// Whether any of the given API versions satisfies ``minimumAPIVersion``.
    ///
    /// The strings are in the `"<major>.<minor>"` form the server uses, both in the ``apiVersion`` capability and in the `X-Notes-API-Versions` header every response the notes app sends itself carries, which `HTTPURLResponse.notesAPIVersions` reads. Any further components are tolerated and ignored, so a server which one day reports a patch component as well still reads as supported. An entry which does not parse at all is skipped rather than treated as a rejection, so a version scheme this library does not know about cannot make an otherwise supported server look unsupported.
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
    /// Every notes feature of ``Server`` requires at least ``minimumAPIVersion``, which ``isSupported`` checks for. A server advertising `"1.3"` as its newest version runs a notes app older than 4.12.3, which those features refuse.
    ///
    public let apiVersion: [String]?

    ///
    /// The version of the notes app itself, e.g. `"6.0.1"`.
    ///
    /// This is the app's own version and unrelated to the server ``Version``, which is why it is kept as the plain string the server sends.
    /// Behaviours the app does not announce through ``apiVersion`` can only be told apart by it, which is what ``isAppVersion(atLeast:)`` is for.
    ///
    public let version: String?

    ///
    /// The path of the folder the notes are stored in, relative to the account's files, e.g. `"Notes"`.
    ///
    /// The folder is what makes notes reachable over WebDAV as well, e.g. through ``Server/enumerate(at:recursively:)->[Item]``.
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

    ///
    /// The release of the notes app which started to keep the attachments uploaded through its API in a folder per note and to offer their deletion, which is `"6.1.0"`.
    ///
    /// Both behaviours are what ``storesAttachmentsPerNote`` and ``supportsAttachmentDeletion`` check for. Neither is announced through ``apiVersion``, which is `1.4` before and after this release, so the app's ``version`` is the only way to tell.
    ///
    public static let attachmentFoldersAppVersion = "6.1.0"

    ///
    /// Whether the installed notes app keeps the attachments uploaded through its API in a hidden `.attachments.<id>` folder next to the note they belong to.
    ///
    /// This is the case from ``attachmentFoldersAppVersion`` on. Older releases put an uploaded attachment straight into the folder of the note under a random name which only keeps the file extension, which is why a client wanting the attachments of a note to stay apart from its notes may want to check this first. See ``Note/path`` for where the folder is.
    /// It is `false` when ``version`` is absent or cannot be compared, see ``isAppVersion(atLeast:)``.
    ///
    public var storesAttachmentsPerNote: Bool {
        isAppVersion(atLeast: Self.attachmentFoldersAppVersion)
    }

    ///
    /// Whether the installed notes app can delete an attachment of a note through its API.
    ///
    /// This is the case from ``attachmentFoldersAppVersion`` on, because only attachments in the folder of a note, see ``storesAttachmentsPerNote``, can be told apart from other files and deleted. Older releases do not offer deletion at all and answer such a request with a status which maps to ``RainmakerError/methodNotAllowed``.
    /// It is `false` when ``version`` is absent or cannot be compared, see ``isAppVersion(atLeast:)``.
    ///
    public var supportsAttachmentDeletion: Bool {
        isAppVersion(atLeast: Self.attachmentFoldersAppVersion)
    }

    ///
    /// Whether the installed notes app is at least the given release, comparing it against ``version``.
    ///
    /// Versions are compared component by component as numbers, so `"6.10.0"` is newer than `"6.9.0"`, and missing components count as zero, so `"7"` equals `"7.0.0"`. A pre-release such as `"6.1.0-beta.3"` is older than the release it precedes, which errs on the side of not relying on a feature which may not have been part of the pre-release yet. Build metadata after a `+` is ignored.
    /// The answer is `false` rather than a guess when ``version`` is absent or either version cannot be read that way.
    ///
    /// This library itself only requires ``minimumAPIVersion``, so whether a feature tied to a release of the app, like ``supportsAttachmentDeletion``, is required is up to the client.
    ///
    /// - Parameter minimum: The oldest acceptable release of the notes app, e.g. `"6.1.0"`.
    /// - Returns: `true` if ``version`` is the same as or newer than `minimum`.
    ///
    public func isAppVersion(atLeast minimum: String) -> Bool {
        guard let version else {
            return false
        }

        guard let result = Self.compareAppVersions(version, minimum) else {
            return false
        }

        return result != .orderedAscending
    }

    ///
    /// Compare two releases of the notes app as ``isAppVersion(atLeast:)`` describes, or return `nil` when either of them cannot be read.
    ///
    /// The core of each version is what precedes the first `-` or `+`, split at `.` into numbers. On equal cores, a version with a pre-release suffix after `-` orders before one without, while two pre-releases of the same core count as equal because their suffixes are not compared.
    ///
    static func compareAppVersions(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        guard let left = parseAppVersion(lhs) else {
            return nil
        }

        guard let right = parseAppVersion(rhs) else {
            return nil
        }

        let count = max(left.core.count, right.core.count)

        for index in 0 ..< count {
            let leftComponent = index < left.core.count ? left.core[index] : 0
            let rightComponent = index < right.core.count ? right.core[index] : 0

            if leftComponent < rightComponent {
                return .orderedAscending
            }

            if leftComponent > rightComponent {
                return .orderedDescending
            }
        }

        switch (left.isPreRelease, right.isPreRelease) {
            case (true, false):
                return .orderedAscending
            case (false, true):
                return .orderedDescending
            default:
                return .orderedSame
        }
    }

    ///
    /// Split a release of the notes app into the numbers of its core and whether it is a pre-release, as ``compareAppVersions(_:_:)`` compares them, or return `nil` when the core is not made of numbers only.
    ///
    private static func parseAppVersion(_ version: String) -> (core: [Int], isPreRelease: Bool)? {
        let trimmed = version.trimmingCharacters(in: .whitespaces)
        let withoutBuild = trimmed.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let parts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let coreText = parts.first ?? ""
        let isPreRelease = parts.count > 1

        var core = [Int]()

        for component in coreText.split(separator: ".", omittingEmptySubsequences: false) {
            guard let number = Int(component), number >= 0 else {
                return nil
            }

            core.append(number)
        }

        guard core.isEmpty == false else {
            return nil
        }

        return (core, isPreRelease)
    }

    ///
    /// The keys this capability is decoded from, which are the names the server sends.
    ///
    private enum CodingKeys: String, CodingKey {
        case apiVersion = "api_version"
        case version
        case notesPath = "notes_path"
    }
}
