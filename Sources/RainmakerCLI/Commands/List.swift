import ArgumentParser
import Foundation
import Rainmaker

///
/// Remote content listing command.
///
struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the content of a directory on the server by the given path.")

    @OptionGroup
    var arguments: SharedArguments

    @Option(help: "Path to list the content of as in the account.")
    var path: String = "/"

    func run() async throws {
        guard let address = URL(string: arguments.address) else {
            throw RainmakerCommandError.invalidAddress
        }

        let server = Server(address: address, password: arguments.password, user: arguments.user)
        let items = try await server.content(at: "/")

        switch arguments.outputFormat {
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

                let data = try encoder.encode(items)

                guard let json = String(data: data, encoding: .utf8) else {
                    throw RainmakerCommandError.encodingError
                }

                print(json)
            case .plain:
                for item in items {
                    print(item.name)
                }
        }
    }
}
