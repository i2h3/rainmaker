// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Normalizes recorded HTTP responses so that fixtures stay stable and free of host-specific or volatile values across regenerations.
///
/// This is used by ``URLRecordingSession`` before a response is written to disk. It rewrites the ephemeral container origin to a canonical one and replaces values which change on every server deployment (entity tags, file identifiers, timestamps, login tokens, the login moments and quota of the account) with fixed placeholders. The replaced values are never asserted on by the tests and the chosen placeholders remain parseable by the production response parsing, which the replay-verify pass confirms.
///
struct FixtureCanonicalizer {
    ///
    /// The host-and-port authority of the live recording server, e.g. `"localhost:54540"`.
    ///
    /// Rewriting the authority rather than the full origin is deliberate: server responses serialize URLs with both plain (`http://`) and JSON-escaped (`http:\/\/`) slashes, and matching only the authority canonicalizes both forms.
    ///
    let liveAuthority: String

    ///
    /// The canonical host written into fixtures in place of ``liveAuthority``, without a port.
    ///
    let canonicalHost: String

    ///
    /// The response header fields preserved in the recorded `Headers.txt` of every response.
    ///
    /// Everything else (volatile headers such as `Date`, `ETag` or request identifiers) is dropped to keep fixtures minimal and stable, unless ``notesHeaderFields`` keeps it for a response of the notes app. The match is case-insensitive.
    ///
    /// `X-Notes-API-Versions` has to be kept because ``Server/notes()`` refuses a notes app older than ``Notes/minimumAPIVersion`` and reads that header to decide, so a replayed response without it would look unsupported. Its value tracks whichever app release the app store served at recording time and therefore changes when that does.
    ///
    /// The two activity headers carry the pagination cursors of ``ActivityPage``, which the client reads from the response rather than from its body, so a recording which dropped them would replay as a page without cursors. They hold plain identifiers and therefore cannot leak the recording host, unlike the `Link` header the same endpoint emits, which is deliberately not preserved.
    ///
    static let persistedHeaderFields = ["Content-Type", "X-Activity-First-Known", "X-Activity-Last-Given", "X-Notes-API-Versions"]

    ///
    /// The response header fields additionally preserved for a response of the notes app, which is one to a request whose path contains `/apps/notes/`, each paired with the canonical value written in place of the recorded one, or `nil` to keep the recorded value.
    ///
    /// These carry what ``NoteChanges`` reads from the headers rather than from the body, so a recording which dropped them would replay as a response without a moment to continue from, without an entity tag and, for a chunk, without a cursor.
    /// The `ETag` of a listing is a hash of its body, which contains entity tags and identifiers differing per deployment, and `Last-Modified` and the chunk cursor contain the moment the server started answering, so all three are replaced with fixed values which ``Server`` still reads as a quoted tag, an HTTP date and a cursor respectively.
    /// The number of pending notes is kept as recorded, because it only depends on the notes ``FixtureProvisioner`` seeds and on the requested chunk size.
    ///
    /// They are scoped to the notes app rather than added to ``persistedHeaderFields``, because WebDAV and other responses send an `ETag` and a `Last-Modified` header as well, whose churn would otherwise reach every fixture on every recording.
    ///
    static let notesHeaderFields: [(field: String, canonicalValue: String?)] = [
        ("ETag", "\"00000000000000000000000000000000\""),
        ("Last-Modified", "Sat, 01 Jan 2000 00:00:00 GMT"),
        ("X-Notes-Chunk-Cursor", "946684800-946684800-0"),
        ("X-Notes-Chunk-Pending", nil),
    ]

    ///
    /// Create a canonicalizer for a given live server address.
    ///
    /// - Parameters:
    ///     - liveServerAddress: The address the recording server is reachable at, e.g. `http://localhost:54540/`.
    ///     - canonicalHost: The host to rewrite the live authority to. Defaults to `"localhost"`, matching the address the tests construct in ``ServerTesting``.
    ///
    init(liveServerAddress: URL, canonicalHost: String = "localhost") {
        // URLComponents is used rather than URL.host()/URL.port so the authority can be extracted without the modern URL accessors that are unavailable on the older platforms the package supports.
        let components = URLComponents(url: liveServerAddress, resolvingAgainstBaseURL: false)
        let host = components?.host ?? canonicalHost

        if let port = components?.port {
            liveAuthority = "\(host):\(port)"
        } else {
            liveAuthority = host
        }

        self.canonicalHost = canonicalHost
    }

    // MARK: - Headers

    ///
    /// Serialize a response status and its headers into the plain-text format read back by ``HTTPURLResponse/init(from:for:)``.
    ///
    /// The first line carries the status, followed by one line per preserved header field. Header fields are emitted sorted by name so that the output is deterministic.
    ///
    /// The request URL decides which header fields are preserved, in the same way it decides which body replacements apply in ``canonicalizedBody(_:pathExtension:requestURL:)``: ``persistedHeaderFields`` for every response, and ``notesHeaderFields`` in addition for a response of the notes app.
    ///
    func headersText(statusCode: Int, headerFields: [AnyHashable: Any], requestURL: URL) -> Data {
        var lines = ["HTTP/1.1 \(statusCode) \(Self.reasonPhrase(forStatusCode: statusCode))"]

        let stringHeaders = headerFields.reduce(into: [String: String]()) { result, element in
            if let key = element.key as? String, let value = element.value as? String {
                result[key] = value
            }
        }

        var fields: [(field: String, canonicalValue: String?)] = Self.persistedHeaderFields.map { ($0, nil) }

        if Self.path(of: requestURL).contains("/apps/notes/") {
            fields += Self.notesHeaderFields
        }

        for (field, canonicalValue) in fields.sorted(by: { $0.field.lowercased() < $1.field.lowercased() }) {
            if let match = stringHeaders.first(where: { $0.key.caseInsensitiveCompare(field) == .orderedSame }) {
                lines.append("\(field): \(canonicalValue ?? match.value)")
            }
        }

        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    // MARK: - Body

    ///
    /// Canonicalize a response body for the given fixture file extension.
    ///
    /// Binary bodies (`bin`) are returned unchanged. Textual bodies have the live origin rewritten and volatile fields replaced with fixed placeholders. A body which is not valid UTF-8 is returned unchanged.
    ///
    /// The request URL decides which replacements apply. Beyond ``volatileReplacements``, which every body gets, there are rules whose field names are not unique across this server's APIs, and applying those everywhere rewrites values which happen to share a name with something volatile elsewhere. Scoping them to the API they describe is what keeps the login flow's single-use `token` from being confused with the token addressing a Talk conversation.
    ///
    func canonicalizedBody(_ data: Data, pathExtension: String, requestURL: URL) -> Data {
        guard pathExtension != "bin" else {
            return data
        }

        guard var text = String(data: data, encoding: .utf8) else {
            return data
        }

        text = text.replacingOccurrences(of: liveAuthority, with: canonicalHost)

        let path = Self.path(of: requestURL)
        var replacements = Self.volatileReplacements

        if path.contains("/login/v2") {
            replacements += Self.loginReplacements
        }

        if path.contains("/apps/spreed/") {
            replacements += Self.talkReplacements
        }

        if path.contains("/cloud/user") {
            replacements += Self.userReplacements
        }

        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }

        return Data(text.utf8)
    }

    // MARK: - Private

    ///
    /// The path of a request URL, which decides which of the scoped rules apply to its response.
    ///
    /// `URLComponents` is used rather than the modern `URL` path accessor for the same reason the initializer uses it: the accessor is unavailable on the older platforms the package supports.
    ///
    private static func path(of requestURL: URL) -> String {
        URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.path ?? ""
    }

    ///
    /// Regular-expression replacements applied to textual bodies, each pairing a pattern with its fixed replacement.
    ///
    /// The placeholders are chosen to remain parseable: the timestamp matches the date format the WebDAV parsing expects and the file identifier stays numeric.
    ///
    /// The JSON `"etag"` rule covers the notes the notes API reports, whose entity tags are content hashes differing per deployment. It also rewrites the one under `capabilities.files.directEditing` in the capabilities fixtures, the only other JSON fixture carrying that key, which is an entity tag as well and which no test asserts on.
    ///
    /// The `"hello-v2-token-key"` rule covers the public key the Talk app advertises under its capabilities, which is generated per installation. Its name is unique to that one field, which is why it belongs here rather than in a scoped set.
    ///
    /// Two neighbouring fields of a note are deliberately left alone. Its `"modified"` timestamp is reproducible rather than volatile, because ``FixtureProvisioner`` stamps the seeded note files with fixed modification dates which ``Server/upload(_:to:force:)`` preserves, and flattening it would remove the very difference the incremental retrieval tests rely on. Its numeric `"id"` is a database identifier which does differ per deployment, but collapsing every note's id to one placeholder would make them indistinguishable and contradict `Note` being `Identifiable`, so the tests look notes up by title instead.
    ///
    private static let volatileReplacements: [(pattern: String, replacement: String)] = [
        ("<d:getetag>[^<]*</d:getetag>", "<d:getetag>\"00000000000000000000000000000000\"</d:getetag>"),
        ("<d:getlastmodified>[^<]*</d:getlastmodified>", "<d:getlastmodified>Thu, 01 Jan 1970 00:00:00 GMT</d:getlastmodified>"),
        ("<oc:id>[^<]*</oc:id>", "<oc:id>00000000000000000000000000000000</oc:id>"),
        ("<oc:fileid>[^<]*</oc:fileid>", "<oc:fileid>0</oc:fileid>"),
        ("<oc:comments-href>[^<]*</oc:comments-href>", "<oc:comments-href>/remote.php/dav/comments/files/0</oc:comments-href>"),
        ("\"etag\"[ ]*:[ ]*\"[^\"]*\"", "\"etag\": \"00000000000000000000000000000000\""),
        ("\"hello-v2-token-key\"[ ]*:[ ]*\"[^\"]*\"", "\"hello-v2-token-key\": \"REDACTED\""),
    ]

    ///
    /// Replacements applied only to the bodies of the login flow, which is the one API whose `token` is a secret rather than an identifier.
    ///
    /// These used to be part of ``volatileReplacements`` and applied to every body, which was safe only while the login flow was the sole API sending a field named `token`. Talk sends one too, and its value addresses a conversation in every further request, so the two must not share a rule.
    ///
    private static let loginReplacements: [(pattern: String, replacement: String)] = [
        ("/login/v2/flow/[^\"<\\s]+", "/login/v2/flow/REDACTED"),
        ("\"token\"[ ]*:[ ]*\"[^\"]*\"", "\"token\": \"REDACTED\""),
        ("\"appPassword\"[ ]*:[ ]*\"[^\"]*\"", "\"appPassword\": \"REDACTED\""),
    ]

    ///
    /// Replacements applied only to the bodies of the Talk API, whose conversations carry timestamps and an avatar version differing per deployment.
    ///
    /// The token of a conversation is deliberately *not* replaced. It is not only asserted on, it is part of the path of every further request about that conversation, so the fixture directory of ``Server/conversationAvatar(_:darkTheme:)`` is named after it. Rewriting it in the listing while the recorded directory keeps the live value would send a replayed lookup to a directory which does not exist. Its churn across regenerations is therefore accepted.
    ///
    private static let talkReplacements: [(pattern: String, replacement: String)] = [
        ("\"lastActivity\"[ ]*:[ ]*[0-9]+", "\"lastActivity\": 1700000000"),
        ("\"timestamp\"[ ]*:[ ]*[0-9]+", "\"timestamp\": 1700000000"),
        ("\"avatarVersion\"[ ]*:[ ]*\"[^\"]*\"", "\"avatarVersion\": \"00000000\""),
    ]

    ///
    /// Replacements applied only to the bodies of the provisioning API's account details, which ``Server/currentUser()`` reads from `/cloud/user` and which `/cloud/users/<id>` sends in the same shape.
    ///
    /// The moments of the first and the last login change whenever the account logs in, which every recording does, and the numbers of the quota follow whatever the files of the account happen to occupy at the time of the recording.
    /// None of them is decoded by ``CurrentUserResponse``, so the fixed values only need to stay valid JSON numbers.
    /// The rules are scoped to these paths because the field names, `"used"` and `"total"` in particular, are too generic to rewrite in every body.
    ///
    private static let userReplacements: [(pattern: String, replacement: String)] = [
        ("\"firstLoginTimestamp\"[ ]*:[ ]*-?[0-9]+", "\"firstLoginTimestamp\": 946684800"),
        ("\"lastLoginTimestamp\"[ ]*:[ ]*-?[0-9]+", "\"lastLoginTimestamp\": 946684800"),
        ("\"lastLogin\"[ ]*:[ ]*-?[0-9]+", "\"lastLogin\": 946684800000"),
        ("\"free\"[ ]*:[ ]*-?[0-9.eE+]+", "\"free\": 0"),
        ("\"used\"[ ]*:[ ]*-?[0-9.eE+]+", "\"used\": 0"),
        ("\"total\"[ ]*:[ ]*-?[0-9.eE+]+", "\"total\": 0"),
        ("\"relative\"[ ]*:[ ]*-?[0-9.eE+]+", "\"relative\": 0"),
    ]

    ///
    /// Maps an HTTP status code to its reason phrase for the codes this client encounters, defaulting to an empty phrase.
    ///
    /// The reason phrase is informational only: ``HTTPURLResponse/init(from:for:)`` derives the status from the numeric code and ignores the phrase.
    ///
    private static func reasonPhrase(forStatusCode statusCode: Int) -> String {
        switch statusCode {
            case 200: "OK"
            case 201: "Created"
            case 204: "No Content"
            case 207: "Multi-Status"
            case 301: "Moved Permanently"
            case 302: "Found"
            case 304: "Not Modified"
            case 400: "Bad Request"
            case 401: "Unauthorized"
            case 403: "Forbidden"
            case 404: "Not Found"
            case 405: "Method Not Allowed"
            case 409: "Conflict"
            case 412: "Precondition Failed"
            case 423: "Locked"
            case 500: "Internal Server Error"
            case 507: "Insufficient Storage"
            default: ""
        }
    }
}
