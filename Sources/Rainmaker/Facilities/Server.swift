import Foundation

public final class Server: Serving {
    public let address: URL
    public let password: String
    let session: URLSession

    ///
    /// WebDAV root address for the account on the server.
    ///
    var webDAVAddress: URL {
        address.appending(components: "remote.php", "dav", "files", user, directoryHint: .isDirectory)
    }

    public let user: String

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

    // MARK: - Public

    public init(address: URL, password: String, user: String) {
        self.address = address
        self.password = password
        self.session = URLSession(configuration: .ephemeral)
        self.user = user
    }

    ///
    /// List the content of the remote directory.
    ///
    public func content(at path: String) async throws -> [Item] {
        let url = webDAVAddress.appending(path: path, directoryHint: .isDirectory)
        let requestDocument = RequestBodyFactory.makeRequestBodyForDirectoryContentListing()

        var request = makeWebDAVRequest(for: url, method: .propfind)
        request.httpBody = requestDocument.xmlData

        let (data, _) = try await session.data(for: request)

        let responseDocument = try XMLDocument(data: data)

        guard let root = responseDocument.rootElement() else {
            throw RainmakerError.responseDecodingFailed
        }

        let responses = root.elements(forName: "d:response")

        let items = responses.compactMap { response -> Item? in
            guard let href = response.elements(forName: "d:href").first?.stringValue else {
                return nil
            }

            guard href != url.path() else {
                return nil // Filter out metadata about the listed directory itself.
            }

            guard let propstat = response.elements(forName: "d:propstat").first else {
                return nil
            }

            guard let prop = propstat.elements(forName: "d:prop").first else {
                return nil
            }

            guard let displayName = prop.elements(forName: "d:displayname").first?.stringValue else {
                return nil
            }

            let isDirectory = prop.elements(forName: "d:resourcetype").first?.elements(forName: "d:collection").isEmpty == false

            return Item(isDirectory: isDirectory, name: displayName)
        }

        return items
    }
}
