// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The server's chunked upload capability, advertising the limits the server suggests for uploading a large file in pieces.
///
/// Nextcloud accepts a large file as a sequence of chunks which the server assembles once the last one has arrived, which is what ``Server/upload(_:to:force:chunkSize:)`` does for every file larger than its chunk size. The server advertises the related limits inside the `files` capability object, which is why ``key`` is `"files"`, next to the flags ``Trashing`` reads from the same object.
///
/// The limits are advisory: the server does not enforce them itself, but a reverse proxy in front of it commonly caps the size of a single request body, which is what ``maxSize`` accounts for. A chunk size passed to ``Server/upload(_:to:force:chunkSize:)`` should therefore not exceed it.
///
/// The object is only advertised to authenticated clients; an anonymous capabilities request does not contain it.
/// All fields are kept optional so that a server which omits one of them still decodes successfully.
///
public struct ChunkedUpload: Capability {
    ///
    /// The name of the object the server advertises this capability under, which is the shared `files` object rather than one of its own.
    ///
    public static let key = "files"

    ///
    /// Whether the server supports uploading a file in chunks at all.
    ///
    /// This corresponds to the Nextcloud `files.bigfilechunking` capability, which every server release this library supports advertises as `true`.
    ///
    public let isSupported: Bool?

    ///
    /// The largest chunk size in bytes the server suggests, e.g. `104857600` for the default of 100 MiB.
    ///
    /// This corresponds to the Nextcloud `files.chunked_upload.max_size` capability, which an administrator lowers when a reverse proxy caps the size of request bodies.
    ///
    public let maxSize: Int?

    ///
    /// How many chunks the server suggests uploading concurrently at most, e.g. `5`.
    ///
    /// This corresponds to the Nextcloud `files.chunked_upload.max_parallel_count` capability. ``Server/upload(_:to:force:chunkSize:)`` sends its chunks one after another and therefore never exceeds it.
    ///
    public let maxParallelCount: Int?

    ///
    /// The keys this capability is decoded from, which are the names the server sends.
    ///
    /// The two limits are nested in a `chunked_upload` object on the server, which is flattened into this type because it carries nothing else.
    ///
    private enum CodingKeys: String, CodingKey {
        case isSupported = "bigfilechunking"
        case limits = "chunked_upload"
    }

    ///
    /// The keys of the nested `chunked_upload` object, which are the names the server sends.
    ///
    private enum LimitKeys: String, CodingKey {
        case maxSize = "max_size"
        case maxParallelCount = "max_parallel_count"
    }

    ///
    /// Decode the capability, flattening the nested limits object into ``maxSize`` and ``maxParallelCount``.
    ///
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isSupported = try container.decodeIfPresent(Bool.self, forKey: .isSupported)

        guard container.contains(.limits) else {
            maxSize = nil
            maxParallelCount = nil
            return
        }

        let limits = try container.nestedContainer(keyedBy: LimitKeys.self, forKey: .limits)
        maxSize = try limits.decodeIfPresent(Int.self, forKey: .maxSize)
        maxParallelCount = try limits.decodeIfPresent(Int.self, forKey: .maxParallelCount)
    }
}
