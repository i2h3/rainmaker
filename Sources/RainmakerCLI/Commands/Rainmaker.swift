import ArgumentParser
import Foundation

///
/// Main command of this application.
///
@main
struct Rainmaker: AsyncParsableCommand {
    static let configuration = CommandConfiguration(subcommands: [List.self])
}
