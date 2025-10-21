///
/// Errors specific to the Rainmaker CLI.
///
enum RainmakerCommandError: Error {
    ///
    /// The data to output could not be encoded.
    ///
    case encodingError

    ///
    /// The provided server address could not be parsed.
    ///
    case invalidAddress
}
