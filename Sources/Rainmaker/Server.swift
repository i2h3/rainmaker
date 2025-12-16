import Foundation

///
/// Default implementation of ``Serving``.
/// 
public final class Server: Serving {
    static let resourceURL = Bundle.module.resourceURL!

    public let address: URL
    public let password: String
    let session: any Requesting

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

    public init(address: URL, password: String, user: String, session: any Requesting = URLSession(configuration: .ephemeral)) {
        self.address = address
        self.password = password
        self.session = session
        self.user = user
    }

    ///
    /// List the content of the remote directory.
    ///
    public func content(at path: String) async throws -> [Item] {
        let url = webDAVAddress.appending(path: path, directoryHint: .isDirectory)
        var request = makeWebDAVRequest(for: url, method: .propfind)
        request.httpBody = try? Data(contentsOf: Self.resourceURL.appending(component: "Bodies").appending(component: "Listing.xml"))

        let (data, _) = try await session.data(for: request)
        
        let items = try ResponseParser.items(from: data).filter {
            $0.href.path() != url.path()  // Filter out metadata about the listed directory itself.
        }

        return items
    }
}
