///
/// Errors specific to the mock implementation of `Requesting`.
///
enum URLTestSessionError: Error {
    ///
    /// The test module bundle apparently does not have any resources.
    ///
    case resourcesNotFound

    ///
    /// The tests require a server version for which there are no resources in the bundle.
    ///
    case serverVersionNotFound

    ///
    /// The dedicated folder for the test suite was not found.
    ///
    case suiteNotFound

    ///
    /// There is no resource folder for the specific test being run.
    ///
    case testNotFound
}
