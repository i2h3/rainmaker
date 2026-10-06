// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

public extension Server {
    ///
    /// List all notes of the authenticated user.
    ///
    /// Notes are provided by the server's notes app which, unlike most of what this library covers, is not part of a Nextcloud installation and has to be installed separately. Whether it is available can be checked in advance via the ``Notes`` capability, e.g. `try await capabilities().contains(Notes.self)`. When the app is unavailable the underlying endpoint does not exist and this call throws ``RainmakerError/appUnavailable(app:)`` for `"notes"`.
    ///
    /// The very same error is what a server causes whose `index.php` routing is disabled or whose reverse proxy swallows the route, so those causes cannot be told apart from the response alone. It is deliberately not ``RainmakerError/notFound``, which the notes features reserve for a note that does not exist, so that a client keeping its own copy never takes a missing app for an account without notes.
    ///
    /// An app which is installed but older than ``Notes/minimumAPIVersion`` is reported separately, as ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)``. That requirement is checked on every response, because the notes API advertises the versions it serves in a header of its own, and it can be checked in advance through ``Notes/isSupported``.
    ///
    /// The whole collection is retrieved in a single request, because the endpoint returns everything at once unless a chunk size is requested, which this deliberately does not do. Use ``notes(changedSince:)`` to retrieve only what changed since an earlier call.
    ///
    /// > Warning: Every note including its full content is fetched and held in memory at once, so what this costs grows with the size of the account's notes.
    ///
    /// A note the server could not read is listed like any other and does not fail the call. It carries ``Note/hasError`` and its ``Note/content`` is a message about the failure rather than the note's text, so anything which stores what it retrieves has to check that first.
    ///
    /// Credentials are required: notes are user-scoped and the underlying endpoint rejects unauthenticated requests.
    ///
    /// - Returns: The notes in the order returned by the server.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/appUnavailable(app:)`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry a list of notes.
    ///     - Any other error that might occur during retrieval.
    ///
    func notes() async throws -> [Note] {
        try requireCredentials()
        logger.debug("Fetching notes...")

        let request = try makeNotesAPIRequest(for: "notes", method: .get)
        let (data, _) = try await notesAPIResponse(for: request)

        return try decodeNotesAPIPayload([Note].self, from: data, describing: "the notes")
    }

    ///
    /// List the notes of the authenticated user which changed since a given moment, together with the identifiers of those which did not.
    ///
    /// This is the incremental counterpart of ``notes()`` for a client keeping its own copy of the notes: the server returns every note it recorded a change for at or after `changedSince` in full, and reduces every note it did not to its identifier alone. Both together are the complete set of notes the account has, which is what makes deletions detectable. See ``NoteChanges`` for how the two halves are meant to be applied.
    ///
    /// The moment is sent to the server as its `pruneBefore` parameter, converted to whole seconds since the Unix epoch. A moment at or before the epoch prunes nothing and therefore behaves like ``notes()``.
    ///
    /// > Warning: The server compares this moment against its own record of when it last noticed each note change, which is not the same as that note's ``Note/modification`` date. A note may be from 2020, but when the server only found it today it is not pruned from the response. Never pass a note's ``Note/modification`` back in as this moment; pass one measured on the same clock the server runs on instead, such as when the previous retrieval was made. The API defines the exact value to reuse as the `Last-Modified` header of the previous response, which is the server's own request time and which this library does not surface.
    ///
    /// Everything else, including how an unavailable app surfaces and how a note the server could not read is reported, matches ``notes()``.
    ///
    /// - Parameters:
    ///     - changedSince: The moment to retrieve changes since, measured against the server's own record of when it last saw a note change rather than against ``Note/modification``.
    ///
    /// - Returns: The changed notes and the identifiers of the unchanged ones.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/appUnavailable(app:)`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry a list of notes.
    ///     - Any other error that might occur during retrieval.
    ///
    func notes(changedSince: Date) async throws -> NoteChanges {
        try requireCredentials()
        logger.debug("Fetching notes changed since \(changedSince)...")

        // A moment at or before the Unix epoch has no positive number of seconds to express it, and pruning before it would exclude nothing anyway, so the server is asked not to prune at all.
        let pruneBefore = changedSince.wholeSecondsSince1970 ?? 0
        let request = try makeNotesAPIRequest(for: "notes", method: .get, queryItems: [URLQueryItem(name: "pruneBefore", value: String(pruneBefore))])
        let (data, _) = try await notesAPIResponse(for: request)
        let entries = try decodeNotesAPIPayload([NoteEntry].self, from: data, describing: "the notes")

        var changed = [Note]()
        var unchanged = [Int]()

        for entry in entries {
            switch entry {
                case let .changed(note): changed.append(note)
                case let .unchanged(id): unchanged.append(id)
            }
        }

        return NoteChanges(changed: changed, unchanged: unchanged)
    }

    ///
    /// Look up the settings the notes app keeps for the authenticated user.
    ///
    /// These say where the app stores notes and which extension it gives a new one, which matters because notes are ordinary files: the folder is not a fixed name but a value derived from the account's locale by default, so anything which wants to reach notes over WebDAV rather than through ``notes()`` has to ask for it rather than assume it. See ``NotesSettings``.
    ///
    /// The same requirement and the same failure modes as ``notes()`` apply, since this is the same app's API.
    ///
    /// - Returns: The notes app's settings for the authenticated user.
    ///
    /// - Throws:
    ///     - ``RainmakerError/credentialsRequired`` when no credentials are set.
    ///     - ``RainmakerError/appUnavailable(app:)`` when the notes app is not available on the server.
    ///     - ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` when it is available but older than ``Notes/minimumAPIVersion``.
    ///     - ``RainmakerError/responseDecodingFailed(reason:)`` when a success response does not carry the settings.
    ///     - Any other error that might occur during retrieval.
    ///
    func notesSettings() async throws -> NotesSettings {
        try requireCredentials()
        logger.debug("Fetching note settings...")

        let request = try makeNotesAPIRequest(for: "settings", method: .get)
        let (data, _) = try await notesAPIResponse(for: request)

        return try decodeNotesAPIPayload(NotesSettings.self, from: data, describing: "the note settings")
    }
}

// MARK: - Notes API Helpers

extension Server {
    ///
    /// Build a request for an endpoint of the notes app's REST API, which every notes feature of ``Server`` sends through ``notesAPIResponse(for:uploadingFrom:allowsNotModified:)``.
    ///
    /// The request is built by ``makeAppRequest(for:method:queryItems:)`` and therefore carries the credentials when there are any, so callers check for them with ``requireCredentials()`` first.
    /// Its cache policy is `reloadIgnoringLocalCacheData`, so a response is never answered from a `URLCache`, which could otherwise hide the server's real answer to a conditional request from the caller or serve bytes cached for another account sharing the same session.
    /// A JSON body is sent with the matching content type, and the given header fields are applied last so a caller can set conditional headers such as `If-Match` or `If-None-Match`.
    ///
    /// - Parameters:
    ///     - path: The path relative to `root`, e.g. `"notes"` or `"settings"`.
    ///     - method: The HTTP method to use.
    ///     - root: The root of the API the path is relative to, which is ``notesAPIRoot`` for everything but attachments and ``notesAttachmentAPIRoot`` for them.
    ///     - queryItems: The query parameters to append, in the order they should appear.
    ///     - headerFields: Additional header fields to set, which override those set before.
    ///     - jsonBody: The JSON body to send, usually written by ``encodeNotesAPIBody(_:)``, or `nil` for none.
    ///
    private func makeNotesAPIRequest(for path: String, method: Method, root: String = Server.notesAPIRoot, queryItems: [URLQueryItem] = [], headerFields: [String: String] = [:], jsonBody: Data? = nil) throws -> URLRequest {
        var request = try makeAppRequest(for: root + path, method: method, queryItems: queryItems)

        // A cached response would hide what the server answers now. For a conditional request that is the not modified status the caller asked about, and a session shared between accounts could even be answered with another account's notes.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonBody
        }

        for (field, value) in headerFields {
            request.setValue(value, forHTTPHeaderField: field)
        }

        return request
    }

    ///
    /// Perform a request built by ``makeNotesAPIRequest(for:method:root:queryItems:headerFields:jsonBody:)`` and map the status of its response onto ``RainmakerError``.
    ///
    /// This is what every notes feature shares: the mapping of the statuses the notes app answers with onto errors a caller can act upon, and the enforcement of ``Notes/minimumAPIVersion``.
    ///
    /// The notes app adds its `X-Notes-API-Versions` header to every response it sends itself, see `HTTPURLResponse.notesAPIVersions`, while a response the server or a proxy sends on its behalf lacks it. A status therefore only carries the notes app's meaning when the header is present, and it is checked before the version requirement so that an error the app reports is not mistaken for an outdated app:
    ///
    /// - `200` is a success, provided the header advertises a supported API version, and ``RainmakerError/unsupportedAPIVersion(app:required:advertised:)`` otherwise.
    /// - `304` is returned as it is when `allowsNotModified` is set, for a conditional request, and ``RainmakerError/unexpectedStatus(code:)`` otherwise.
    /// - `403` with the header is ``RainmakerError/readOnly``.
    /// - `404` with the header is ``RainmakerError/notFound``, because the app reports a note or an attachment which does not exist, while `404` without it is ``RainmakerError/appUnavailable(app:)``, because the route itself does not exist.
    /// - `405` is ``RainmakerError/methodNotAllowed``, which the server answers before the app is involved, for a method an older release of the app does not route.
    /// - `412` with the header and a note as its body is ``RainmakerError/noteConflict(current:)``.
    /// - `423` with the header is ``RainmakerError/locked``.
    /// - `507` with the header is ``RainmakerError/insufficientStorage``.
    /// - Everything else, including `401`, is ``RainmakerError/unexpectedStatus(code:)``, which is what the event stream relies on to recognize rejected credentials.
    ///
    /// - Parameters:
    ///     - request: The request to perform.
    ///     - fileURL: The location of a local file to upload as the request body through an upload task, or `nil` to perform a data task.
    ///     - allowsNotModified: Whether a `304` response is an expected answer to a conditional request rather than an error.
    ///
    /// - Returns: The response body and the response itself, whose status is either `200` or, when allowed, `304`.
    ///
    private func notesAPIResponse(for request: URLRequest, uploadingFrom fileURL: URL? = nil, allowsNotModified: Bool = false) async throws -> (data: Data, response: HTTPURLResponse) {
        let data: Data
        let urlResponse: URLResponse

        if let fileURL {
            (data, urlResponse) = try await session.upload(for: request, fromFile: fileURL, delegate: nil)
        } else {
            (data, urlResponse) = try await session.data(for: request)
        }

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        let advertisedAPIVersions = response.notesAPIVersions
        let isFromNotesApp = advertisedAPIVersions.isEmpty == false

        switch response.status {
            case .ok:
                // Every response of the notes app advertises which versions of its API it can serve, so the requirement is enforced from the response already in hand rather than by asking for the server's capabilities first.
                guard Notes.supports(apiVersions: advertisedAPIVersions) else {
                    throw RainmakerError.unsupportedAPIVersion(app: Notes.key, required: Notes.minimumAPIVersion, advertised: advertisedAPIVersions)
                }

                return (data, response)

            case .notModified where allowsNotModified:
                return (data, response)

            case .forbidden where isFromNotesApp:
                throw RainmakerError.readOnly

            case .notFound where isFromNotesApp:
                throw RainmakerError.notFound

            case .notFound:
                // The route only exists while the notes app is installed and enabled, so a not found status the app did not send means the app is not there. Reporting it as such rather than as a missing note keeps a client from deleting its local notes because the app went away.
                throw RainmakerError.appUnavailable(app: Notes.key)

            case .methodNotAllowed:
                throw RainmakerError.methodNotAllowed

            case .preconditionFailed where isFromNotesApp:
                // The notes app sends the note as it currently is along with the conflict, so the caller can resolve it without another request. A body which is not a note leaves nothing to resolve with, so it is reported as the bare status instead.
                guard let current = try? jsonDecoder.decode(Note.self, from: data) else {
                    throw RainmakerError.unexpectedStatus(code: response.statusCode)
                }

                throw RainmakerError.noteConflict(current: current)

            case .locked where isFromNotesApp:
                throw RainmakerError.locked

            case .insufficientStorage where isFromNotesApp:
                throw RainmakerError.insufficientStorage

            default:
                throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }
    }

    ///
    /// Decode the body of a successful response from ``notesAPIResponse(for:uploadingFrom:allowsNotModified:)`` with ``jsonDecoder``.
    ///
    /// None of the notes app's endpoints answers with an OCS envelope, so unlike every other JSON endpoint in this library there is no `meta` status vouching for a payload. A success response carrying something else entirely, for example an HTML login or maintenance page served by a proxy, therefore has to surface as ``RainmakerError/responseDecodingFailed(reason:)`` rather than as an opaque Foundation error. The payload is left out of that message so that note contents cannot leak into logs.
    ///
    /// - Parameters:
    ///     - type: The type to decode.
    ///     - data: The response body.
    ///     - subject: What is being decoded, for the error message, e.g. `"the notes"`.
    ///
    private func decodeNotesAPIPayload<Value: Decodable>(_ type: Value.Type, from data: Data, describing subject: String) throws -> Value {
        do {
            return try jsonDecoder.decode(type, from: data)
        } catch {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to decode \(subject): \(error)")
        }
    }

    ///
    /// Encode a request body for the notes app's REST API with ``jsonEncoder``, to be passed as the JSON body to ``makeNotesAPIRequest(for:method:root:queryItems:headerFields:jsonBody:)``.
    ///
    /// - Parameters:
    ///     - value: The value to encode, usually a data transfer object shaped as the notes app expects it.
    ///
    private func encodeNotesAPIBody(_ value: some Encodable) throws -> Data {
        try jsonEncoder.encode(value)
    }
}
