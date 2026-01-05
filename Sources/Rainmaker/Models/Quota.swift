// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Storage restrictions and usage information per directory.
///
public struct Quota: Model {
    ///
    /// Available bytes in the directory.
    ///
    public let available: AvailableQuota

    ///
    /// Amount of bytes used in the directory.
    ///
    public let used: Int64
}
