// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Rainmaker

///
/// Makes the library's sort order directly usable as a command line option value.
///
/// The conformance lives here rather than in the library so that `Rainmaker` itself stays free of a dependency on ArgumentParser. Because ``Rainmaker/ActivitySort`` is backed by a string, ArgumentParser's default implementation for `RawRepresentable` covers everything, which is why the extension is empty.
///
extension ActivitySort: ExpressibleByArgument {}
