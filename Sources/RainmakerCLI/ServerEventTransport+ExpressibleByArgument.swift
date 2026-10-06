// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Rainmaker

///
/// Makes the library's event transport directly usable as the value of the `watch` command's `--transport` option.
///
/// The conformance lives here rather than in the library so that `Rainmaker` itself stays free of a dependency on ArgumentParser, as with ``Rainmaker/ActivitySort``. Because ``Rainmaker/ServerEventTransport`` is backed by a string and lists its cases, ArgumentParser's default implementations cover everything, including the possible values shown in the help, which is why the extension is empty.
///
extension ServerEventTransport: ExpressibleByArgument {}
