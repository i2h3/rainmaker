// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

///
/// Default implementation of ``Serving``.
///
public final class Server: Serving {
    static let resourceURL = Bundle.module.resourceURL!

    let logger = Logger(category: "Server")
    let session: any Requesting

    public let address: URL
    public let password: String
    public let user: String

    ///
    /// The path prefix appended to the base address before the actual remote subject path on every WebDAV request, including the user's name.
    ///
    /// Looks like `"/remote.php/dav/files/<user>"`.
    ///
    public let webDAVPathPrefix: String

    ///
    /// WebDAV root address for the account on the server.
    ///
    public let webDAVAddress: URL

    // MARK: - Private

    ///
    /// Set up a URL request specifically for WebDAV interaction.
    ///
    private func makeWebDAVRequest(for url: URL, method: Method) -> URLRequest {
        let encodedCredentials = Data("\(user):\(password)".utf8).base64EncodedString()

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(encodedCredentials)", forHTTPHeaderField: "Authorization")

        return request
    }

    ///
    /// List the content of the remote directory.
    ///
    private func content(at path: String) async throws -> [Item] {
        let url = webDAVAddress.appending(path: path, directoryHint: .isDirectory)
        var request = makeWebDAVRequest(for: url, method: .propfind)
        request.httpBody = try? Data(contentsOf: Self.resourceURL.appending(component: "Bodies").appending(component: "Listing.xml"))

        let (data, _) = try await session.data(for: request)

        // Filter out metadata about the listed directory itself.
        let items = try ResponseParser.items(from: data, webDAVPathPrefix: webDAVPathPrefix).filter { item in
            if path == item.path {
                return false
            }

            return true
        }

        return items
    }

    // MARK: - Public

    public init(address: URL, password: String, user: String, session: any Requesting = URLSession(configuration: .ephemeral)) {
        self.address = address
        self.password = password
        self.session = session
        self.user = user
        webDAVAddress = address.appending(path: "/remote.php/dav/files/\(user)", directoryHint: .isDirectory)
        webDAVPathPrefix = "/remote.php/dav/files/\(user)"
    }

    public func enumerate(at path: String, recursively: Bool) async throws -> AsyncThrowingStream<Item, Error> {
        logger.debug("Enumerating items\(recursively ? " recursively" : "") at path: \(path)")

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let items = try await content(at: path)

                    for item in items {
                        continuation.yield(item)

                        guard recursively, item.isDirectory else {
                            continue
                        }

                        logger.debug("Entering subdirectory: \(item.path)")
                        let nestedItems: AsyncThrowingStream<Item, Error> = try await enumerate(at: item.path, recursively: true)

                        for try await nestedItem in nestedItems {
                            continuation.yield(nestedItem)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
