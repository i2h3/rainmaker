import ArgumentParser

///
/// The output format the CLI should render content as.
///
enum OutputFormat: String, ExpressibleByArgument {
    ///
    /// JSON
    ///
    case json

    ///
    /// Plain Text
    ///
    case plain
}
