///
/// Semantic errors specific to this library.
///
enum RainmakerError: Error {
    ///
    /// The response most likely was not in the expected format or structure.
    ///
    case responseDecodingFailed
}
