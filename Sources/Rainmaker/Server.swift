// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

///
/// Main type to interact with an account on a Nextcloud server.
///
public final class Server {
    static let resourceURL = Bundle.module.resourceURL!

    let logger = Logger(category: "Server")
    let jsonDecoder: JSONDecoder
    let session: any Requesting

    ///
    /// HTTP address of the Nextcloud host.
    ///
    public let address: URL

    ///
    /// In most cases, this is the app password and not the account password.
    ///
    public let password: String?

    ///
    /// The Nextcloud user name used to identify as.
    ///
    public let user: String?

    ///
    /// The user agent to report as in HTTP request headers.
    ///
    public let userAgent: String

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

    private func requireCredentials() throws {
        guard user != nil, password != nil else {
            throw RainmakerError.credentialsRequired
        }
    }

    ///
    /// Create a new URL request object with some basics configured consistently.
    ///
    private func makeRequest(for url: URL, method: Method) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        return request
    }

    ///
    /// Set up a URL request specifically for WebDAV interaction.
    ///
    private func makeWebDAVRequest(for url: URL, method: Method) throws -> URLRequest {
        guard let user, let password else {
            throw RainmakerError.credentialsRequired
        }

        let encodedCredentials = Data("\(user):\(password)".utf8).base64EncodedString()

        var request = makeRequest(for: url, method: method)
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
        var request = try makeWebDAVRequest(for: url, method: .propfind)
        request.httpBody = try? Data(contentsOf: Self.resourceURL.appending(component: "Bodies").appending(component: "Listing.xml"))

        let (data, urlResponse) = try await session.data(for: request)

        guard let response = urlResponse as? HTTPURLResponse else {
            throw RainmakerError.responseDecodingFailed(reason: "Failed to cast URLResponse to HTTPURLResponse.")
        }

        guard response.status == .multiStatus else {
            throw RainmakerError.unexpectedStatus(code: response.statusCode)
        }

        // Filter out metadata about the listed directory itself.
        let items = try ResponseParser.items(from: data, webDAVPathPrefix: webDAVPathPrefix).filter { item in
            if path == item.path {
                return false
            }

            return true
        }

        return items
    }

    ///
    /// Create a new server object.
    ///
    /// - Parameters:
    ///     - address: HTTP address of the Nextcloud host.
    ///     - password: In most cases, this is the app password and not the account password.
    ///     - user: The Nextcloud user name used to identify as.
    ///     - userAgent: The user agent to report as in HTTP request headers.
    ///
    public convenience init(address: URL, password: String? = nil, user: String? = nil, userAgent: String = "Rainmaker") {
        let session = URLSession(configuration: .ephemeral)
        self.init(address: address, password: password, user: user, session: session, userAgent: userAgent)
    }

    init(address: URL, password: String? = nil, user: String? = nil, session: any Requesting, userAgent: String) {
        self.address = address
        jsonDecoder = JSONDecoder()
        self.password = password
        self.session = session
        self.user = user
        self.userAgent = userAgent
        webDAVAddress = address.appending(path: "/remote.php/dav/files/\(user ?? "")", directoryHint: .isDirectory)
        webDAVPathPrefix = "/remote.php/dav/files/\(user ?? "")"
    }
}

// MARK: - Serving

extension Server: Serving {
    public func enumerate(at path: String, recursively: Bool) async throws -> AsyncThrowingStream<Item, Error> {
        try requireCredentials()

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

    public func login() async throws -> LoginFlow {
        logger.debug("Fetching login information...")

        let url = address.appending(path: "index.php/login/v2", directoryHint: .notDirectory)
        let request = makeRequest(for: url, method: .post)
        let (data, _) = try await session.data(for: request)
        let dataTransferObject = try jsonDecoder.decode(LoginFlowResponse.self, from: data)
        return LoginFlow(endpoint: dataTransferObject.poll.endpoint, entry: dataTransferObject.login, token: dataTransferObject.poll.token)
    }

    public func poll(_ endpoint: URL, token: String) async throws -> LoginResult {
        logger.debug("Polling \(endpoint.absoluteString)")

        var request = makeRequest(for: endpoint, method: .post)
        request.httpBody = "token=\(token)".data(using: .utf8)
        let (data, _) = try await session.data(for: request)
        let stringRepresentation = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard stringRepresentation != "[]" else {
            throw RainmakerError.responseDecodingFailed(reason: "The server returned no login flow result on polling.")
        }

        let dataTransferObject = try jsonDecoder.decode(LoginResultResponse.self, from: data)
        return LoginResult(name: dataTransferObject.loginName, password: dataTransferObject.appPassword, server: dataTransferObject.server)
    }
}
