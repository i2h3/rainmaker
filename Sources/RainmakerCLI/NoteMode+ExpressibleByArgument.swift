// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import ArgumentParser
import Rainmaker

///
/// Makes the library's note mode directly usable as the value of the `--note-mode` option of the `notes-settings` command.
///
/// The conformance lives here rather than in the library so that `Rainmaker` itself stays free of a dependency on ArgumentParser, as with ``ActivitySort``. Because ``NoteMode`` is backed by the string the server uses, ArgumentParser's default implementation for `RawRepresentable` covers everything, including the list of `rich`, `edit` and `preview` it offers as completions, which is why the extension is empty.
///
extension NoteMode: ExpressibleByArgument {}
