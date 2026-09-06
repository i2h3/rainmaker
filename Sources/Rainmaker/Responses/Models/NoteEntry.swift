// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// One element of the JSON array as returned by the server for `GET /index.php/apps/notes/api/v1/notes` when a `pruneBefore` parameter narrows it down.
///
/// This is a data transfer object which exists because such a response mixes two shapes: a note modified since the requested moment arrives complete, while an older one is reduced to its identifier. Neither ``Server/notes(changedSince:)`` nor its ``NoteChanges`` result exposes this distinction as a type; it is partitioned away immediately after decoding.
///
enum NoteEntry: Decodable {
    ///
    /// A note which changed and therefore arrived complete.
    ///
    case changed(Note)

    ///
    /// The identifier of a note which did not change and was therefore reduced to it.
    ///
    case unchanged(id: Int)

    private enum CodingKeys: String, CodingKey {
        case id
        case title
    }

    ///
    /// Decode one element by telling the two shapes apart.
    ///
    /// The presence of `title` is what discriminates them, rather than attempting to decode a whole ``Note`` and treating a failure as a reduced entry: `title` is a field the API has carried since its very first version, so a genuinely malformed note stays a decoding error instead of being silently reported as unchanged.
    ///
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(Int.self, forKey: .id)

        guard container.contains(.title) else {
            self = .unchanged(id: id)
            return
        }

        self = try .changed(Note(from: decoder))
    }
}
