// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

///
/// The rules by which the notes app resolves the path of an attachment, which is relative to the folder of a note's category, to the file it names, for a client which wants to know which file ``Server/attachment(at:ofNote:)`` would return without asking the server.
///
/// This is useful for a client keeping attachments in a store of its own, which can key them by the resolved path so that two notes referencing the same file share one entry, and for one which reaches the files over WebDAV, see ``Server/download(_:to:force:)``, below the folder ``NotesSettings/notesPath`` names.
/// ``resolve(_:relativeTo:)`` is pure, so it needs neither a ``Server`` nor a connection, and it can run on any thread, but it cannot tell whether a file exists at the path.
///
public enum NoteAttachmentPath {
    ///
    /// Resolve the path of an attachment, as ``Server/addAttachment(_:toNote:fileName:)-(URL,Int,String?)`` returns it or as ``NoteAttachmentReference/decode(_:)`` reads it from a note's content, to a path relative to the notes folder.
    ///
    /// The path is read relative to the folder of the note's category, starting from the components of the category:
    ///
    /// - Every `\` in the path counts as `/`, while one in the category does not.
    /// - Empty components, such as those of a leading, a trailing or a doubled `/`, are skipped.
    /// - A `..` takes the component before it back, but never steps above the notes folder, so `../../x` of a note in the category `Work` resolves to `x`.
    /// - A `.` is dropped from the result, but only after the path was resolved, because it counts as a component a following `..` takes back, so `Work` and `a/./../b` resolve to `Work/a/b`.
    /// - Any other component is appended as it is, without changing its percent-encoding or its Unicode normalization form.
    ///
    /// - Parameters:
    ///     - path: The path of the attachment relative to the folder of the note's category, which must not be percent-encoded anymore.
    ///     - category: The ``Note/category`` of the note, or an empty string for a note under no category.
    ///
    /// - Returns: The path of the attachment relative to the notes folder, with `/` delimiting its components, or `nil` when it resolves to the notes folder itself, which never is an attachment.
    ///
    public static func resolve(_ path: String, relativeTo category: String) -> String? {
        var components = category.unicodeScalars.split(separator: "/", omittingEmptySubsequences: true).map { String(String.UnicodeScalarView($0)) }
        let normalizedPath: [Unicode.Scalar] = path.unicodeScalars.map { $0 == "\\" ? "/" : $0 }

        for component in normalizedPath.split(separator: "/", omittingEmptySubsequences: true) {
            if component.elementsEqual([".", "."]) {
                _ = components.popLast()
            } else {
                components.append(String(String.UnicodeScalarView(component)))
            }
        }

        let resolved = components.filter { $0.unicodeScalars.elementsEqual(["."]) == false }

        guard resolved.isEmpty == false else {
            return nil
        }

        return resolved.joined(separator: "/")
    }
}
