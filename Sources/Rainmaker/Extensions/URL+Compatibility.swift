// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

extension URL {
    ///
    /// Directory disposition for the path appending compatibility helpers.
    ///
    /// This mirrors the cases of `URL.DirectoryHint`, which is only available since macOS 13, iOS 16, tvOS 16 and watchOS 9, so that the disposition can be expressed in code which still has to compile for macOS 12, iOS 15, tvOS 15 and watchOS 8.
    ///
    enum CompatibilityDirectoryHint {
        ///
        /// The appended path or component is known to refer to a directory.
        ///
        case isDirectory

        ///
        /// The appended path or component is known not to refer to a directory.
        ///
        case notDirectory

        ///
        /// The directory disposition is inferred from a trailing slash on the appended string.
        ///
        case inferFromPath
    }

    ///
    /// The file system path of this URL, optionally percent-encoded.
    ///
    /// This is a behavior-preserving replacement for `path(percentEncoded:)`, which is only available since macOS 13, iOS 16, tvOS 16 and watchOS 9, so that ``Server`` and the response parsing can support macOS 12, iOS 15, tvOS 15 and watchOS 8.
    ///
    func compatibilityPath(percentEncoded: Bool = true) -> String {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            return path(percentEncoded: percentEncoded)
        } else {
            // Unlike the legacy `path` property, the modern `path(percentEncoded:)` preserves a trailing slash, which `URLComponents` reproduces.
            let components = URLComponents(url: self, resolvingAgainstBaseURL: false)
            return percentEncoded ? (components?.percentEncodedPath ?? path) : (components?.path ?? path)
        }
    }

    ///
    /// Returns a URL by appending a path, which may consist of multiple components, to this URL.
    ///
    /// This is a behavior-preserving replacement for `appending(path:directoryHint:)`, which is only available since macOS 13, iOS 16, tvOS 16 and watchOS 9. On those systems the original implementation is used so that behavior is identical, while earlier systems fall back to `appendingPathComponent(_:isDirectory:)` with the equivalent directory disposition so that ``Server`` can support macOS 12, iOS 15, tvOS 15 and watchOS 8.
    ///
    func appendingCompatibility(path: some StringProtocol, directoryHint: CompatibilityDirectoryHint = .inferFromPath) -> URL {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            return appending(path: path, directoryHint: directoryHint.native)
        } else {
            // `appending(path:)` interprets its argument as relative and therefore drops a single leading slash, whereas `appendingPathComponent(_:)` would keep it.
            let relativePath = path.hasPrefix("/") ? String(path.dropFirst()) : String(path)

            switch directoryHint {
                case .isDirectory:
                    return appendingPathComponent(relativePath, isDirectory: true)
                case .notDirectory:
                    return appendingPathComponent(relativePath, isDirectory: false)
                case .inferFromPath:
                    return appendingPathComponent(relativePath, isDirectory: relativePath.hasSuffix("/"))
            }
        }
    }

    ///
    /// Returns a URL by appending a single path component to this URL.
    ///
    /// This is a behavior-preserving replacement for `appending(component:directoryHint:)`, which is only available since macOS 13, iOS 16, tvOS 16 and watchOS 9. On those systems the original implementation is used so that behavior is identical, while earlier systems fall back to `appendingPathComponent(_:isDirectory:)` with the equivalent directory disposition so that ``Server`` can support macOS 12, iOS 15, tvOS 15 and watchOS 8.
    ///
    func appendingCompatibility(component: some StringProtocol, directoryHint: CompatibilityDirectoryHint = .inferFromPath) -> URL {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            return appending(component: component, directoryHint: directoryHint.native)
        } else {
            let component = String(component)

            switch directoryHint {
                case .isDirectory:
                    return appendingPathComponent(component, isDirectory: true)
                case .notDirectory:
                    return appendingPathComponent(component, isDirectory: false)
                case .inferFromPath:
                    return appendingPathComponent(component, isDirectory: component.hasSuffix("/"))
            }
        }
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
private extension URL.CompatibilityDirectoryHint {
    ///
    /// The matching `URL.DirectoryHint` for this compatibility disposition, used on systems where the modern URL appending API is available.
    ///
    var native: URL.DirectoryHint {
        switch self {
            case .isDirectory: .isDirectory
            case .notDirectory: .notDirectory
            case .inferFromPath: .inferFromPath
        }
    }
}
