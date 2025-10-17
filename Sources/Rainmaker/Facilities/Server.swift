import Foundation

final class Server: Serving {
    let address: URL
    let password: String
    let session: URLSession

    ///
    /// WebDAV root address for the account on the server.
    ///
    var webDAVAddress: URL {
        address.appending(components: "remote.php", "dav", "files", user)
    }

    let user: String

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

    init(address: URL, password: String, user: String) {
        self.address = address
        self.password = password
        self.session = URLSession(configuration: .ephemeral)
        self.user = user
    }

    ///
    /// List the content of the remote directory.
    ///
    func content(at path: String) async throws -> [Item] {
        let url = webDAVAddress.appending(path: path)
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
