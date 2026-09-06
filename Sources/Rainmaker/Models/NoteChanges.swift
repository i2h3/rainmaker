// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The notes which changed since a given moment, together with the identifiers of those which did not.
///
/// This is what ``Server/notes(changedSince:)`` returns. The server answers such a request with the full content of every note it recorded a change for since the given moment and reduces every other note to its identifier alone, which is why the two arrive separately here. Both together are the complete set of notes the account has, so a note whose identifier appears in neither was deleted on the server:
///
/// ```swift
/// let changes = try await server.notes(changedSince: lastSynchronization)
///
/// for note in changes.changed {
///     store.upsert(note)
/// }
///
/// store.deleteAll(exceptFor: changes.changed.map(\.id) + changes.unchanged)
/// ```
///
/// Which moment to pass on the next call is left to the caller, which usually remembers when its previous synchronization started. There is deliberately no cursor in here, because the server communicates it as a response header this library does not surface. It has to come from a clock comparable to the server's rather than from a note's ``Note/modification`` date, because the server prunes by when it noticed a change: a note may be from 2020, but when the server only found it today it is not pruned. See ``Server/notes(changedSince:)``.
///
public struct NoteChanges: Model {
    ///
    /// The notes the server recorded a change for at or after the requested moment, in the order returned by the server.
    ///
    /// Empty whenever nothing changed, which is the common case for a client polling frequently.
    ///
    public let changed: [Note]

    ///
    /// The identifiers of the notes the server recorded no change for and therefore reduced to just those identifiers.
    ///
    /// These carry no content on purpose: a client already has it and only needs to know the note still exists.
    ///
    public let unchanged: [Int]
}
