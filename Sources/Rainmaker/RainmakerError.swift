// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Semantic errors specific to this library.
///
public enum RainmakerError: Error, Equatable, CustomStringConvertible {
    ///
    /// A server app the intended action depends on is not available on the server, for example because it is not installed or disabled.
    ///
    /// Carries the identifier of the app, e.g. `"notes"` for the features built on ``Notes``.
    /// The notes features report this when an endpoint of the notes app answers with a not found status the app itself did not send, which is what the server does for the routes of an app it does not serve. It is kept apart from ``notFound``, which those features reserve for a note or an attachment that does not exist, so that a client keeping its own copy of notes never takes a missing app for notes which were deleted. The exception is the retrieval of an attachment through ``Server/attachment(at:ofNote:)`` and ``Server/downloadAttachment(at:ofNote:to:force:)``, which reports an absent app as ``notFound`` as well, because the notes app answers every failure of that request with the same bare not found status; the ``Notes`` capability tells the cases apart.
    /// A server whose `index.php` routing is broken or whose reverse proxy swallows the route answers the same way, so those causes cannot be told apart from the response alone.
    ///
    case appUnavailable(app: String)

    ///
    /// The intended action requires credentials like user name and password but they were not given.
    ///
    case credentialsRequired

    ///
    /// A move was attempted but the destination already exists and overwriting was not requested.
    ///
    case destinationExists(URL)

    ///
    /// The destination location is not an empty directory.
    ///
    case directoryNotEmpty

    ///
    /// During a local directory enumeration, the given error occurred for the item at the provided location.
    ///
    case enumeration(URL, String)

    ///
    /// A file transfer was attempted but the destination already exists and was not requested to be overwritten.
    ///
    case fileAlreadyExists(URL)

    ///
    /// The server does not have enough storage left for the account to save what was sent.
    ///
    /// The notes features report this when the notes app answers with the status `507` itself, for example when a note or an attachment would exceed the account's quota.
    ///
    case insufficientStorage

    ///
    /// The server could not perform the intended action because the file it concerns is locked, for example while another client is writing it.
    ///
    /// The notes features report this when the notes app answers with the status `423` itself, which it only does after it has already retried for several seconds, so a client should back off rather than retry right away.
    ///
    case locked

    ///
    /// The server does not support the HTTP method of the request on the requested endpoint.
    ///
    /// The notes features report this for an endpoint which an older release of the notes app does not offer for that method, which the server answers with the status `405` before the app is even involved.
    ///
    case methodNotAllowed

    ///
    /// A note was not changed because it changed on the server since the entity tag the change was based on.
    ///
    /// ``Server/updateNote(_:title:category:content:modification:isFavorite:ifMatching:)`` reports this when it was given an entity tag which no longer matches the note, in which case nothing was changed.
    /// Carries the note as it currently is on the server, which the notes app sends along with the status `412`, so a client can resolve the conflict without a further request.
    /// Its ``Note/entityTag`` is what a retried change has to be based on.
    ///
    case noteConflict(current: Note)

    ///
    /// Whatever you were looking for is not there.
    ///
    /// The notes features report this when the notes app itself answers that a note or an attachment does not exist, and ``appUnavailable(app:)`` when the app is not there at all, except for ``Server/attachment(at:ofNote:)`` and ``Server/downloadAttachment(at:ofNote:to:force:)``, which report every failure including an absent app as this case, see there.
    ///
    case notFound

    ///
    /// The intended change was refused because the subject is read-only for the authenticated user.
    ///
    /// The notes features report this when the notes app answers with the status `403` itself, for example for a note shared without write access, see ``Note/isReadOnly``.
    ///
    case readOnly

    ///
    /// The response most likely was not in the expected format or structure.
    ///
    /// - Parameters:
    ///     - reason: A human readable explanation why it failed.
    ///
    case responseDecodingFailed(reason: String)

    ///
    /// A local file changed while it was being uploaded in chunks, so the upload was abandoned rather than having the server assemble a file from chunks of two different versions.
    ///
    /// Carries the location of the local file. Uploading it again sends the current version.
    ///
    case sourceChanged(URL)

    ///
    /// The HTTP response was delivered with the given status code which was unexpected in the throwing code.
    ///
    case unexpectedStatus(code: Int)

    ///
    /// A server app is installed but too old to serve the version of its API this library requires.
    ///
    /// Carries the app identifier, the API version required, and the versions the app advertises.
    ///
    case unsupportedAPIVersion(app: String, required: String, advertised: [String])

    ///
    /// For conformance to `CustomStringConvertible` to render an error as a human readable error description.
    ///
    public var description: String {
        switch self {
            case let .appUnavailable(app: app):
                "The \"\(app)\" app is not available on the server."
            case .credentialsRequired:
                "Credentials required"
            case let .destinationExists(url):
                "A remote item already exists at: \(url.compatibilityPath())"
            case .directoryNotEmpty:
                "The destination location is not an empty directory."
            case let .enumeration(url, error):
                "The item at \(url.compatibilityPath()) could not be enumerated: \(error)"
            case let .fileAlreadyExists(url):
                "A file already exists at: \(url.compatibilityPath())"
            case .insufficientStorage:
                "There is not enough storage left on the server."
            case .locked:
                "The subject is locked on the server."
            case .methodNotAllowed:
                "The server does not allow this method on the endpoint."
            case let .noteConflict(current: note):
                "The note \(note.id) changed on the server in the meantime."
            case .notFound:
                "Not found."
            case .readOnly:
                "The subject is read-only."
            case let .responseDecodingFailed(reason: reason):
                reason
            case let .sourceChanged(url):
                "The file at \(url.compatibilityPath()) changed while it was being uploaded."
            case let .unsupportedAPIVersion(app: app, required: required, advertised: advertised):
                "The \"\(app)\" app on the server does not support API version \(required) or newer, which is required. It advertises \(advertised.isEmpty ? "no version at all" : advertised.joined(separator: ", ")). Update the app on the server."
            case let .unexpectedStatus(code: code):
                "Unexpected status: \(code) \(HTTPStatus(rawValue: code)?.description ?? "")"
        }
    }
}
