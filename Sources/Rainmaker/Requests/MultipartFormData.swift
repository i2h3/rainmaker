// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// A `multipart/form-data` body with a single file field, written to a local file so that it can be sent through an upload task rather than held in memory.
///
/// This is what ``Server/addAttachment(_:toNote:fileName:)-(URL,Int,String?)`` and ``Server/addAttachment(_:toNote:fileName:)-(Data,Int,String)`` send, because the notes app only takes an attachment as the file of a form, as a browser would upload it. The body is staged in a file of its own and then sent by ``Requesting/upload(for:fromFile:delegate:)``, the same way ``Server/upload(_:to:force:chunkSize:)`` stages a chunk, so that neither the file nor its body has to fit into memory.
///
/// The caller removes the staged body once it has been sent, also when writing it failed halfway.
///
struct MultipartFormData {
    ///
    /// The line which delimits the parts of the body, unique per body so that it cannot occur within the file it carries.
    ///
    /// It is announced in ``contentType`` and therefore has to be sent along with the body.
    ///
    let boundary: String

    ///
    /// The value of the `Content-Type` header a request carrying this body has to send, which announces ``boundary``.
    ///
    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    ///
    /// Create a body with a boundary which differs from that of any other body.
    ///
    /// - Parameters:
    ///     - boundary: The line to delimit the parts of the body with. Defaults to one derived from a random UUID.
    ///
    init(boundary: String = "Rainmaker-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    ///
    /// Escape a name for a quoted parameter of the `Content-Disposition` header of a part, as browsers do.
    ///
    /// A double quote would end the quoted value early and a line break would end the header, so the former is replaced by `%22` and the latter are removed. Everything else, including characters beyond ASCII, is kept as UTF-8, which is what a server reading a form expects. The server does not decode `%22` again, so a file name with a double quote arrives with `%22` in its place.
    ///
    /// - Parameters:
    ///     - name: The name to escape.
    ///
    static func escapedParameterValue(_ name: String) -> String {
        name
            .replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    ///
    /// Write the body with the contents of a local file as its file field to the given location, copying through a buffer of the given size rather than reading the whole file into memory.
    ///
    /// - Parameters:
    ///     - source: The local file whose contents become the file field.
    ///     - fieldName: The name of the form field, which the server looks the file up by.
    ///     - fileName: The name of the file to announce, escaped through ``escapedParameterValue(_:)``.
    ///     - destination: The local location to write the body to, which is replaced when it exists.
    ///     - bufferSize: The number of bytes to copy at once, usually ``Server/stagingBufferSize``.
    ///
    func writeFile(from source: URL, fieldName: String, fileName: String, to destination: URL, bufferSize: Int) throws {
        let input = try FileHandle(forReadingFrom: source)

        defer {
            try? input.close()
        }

        try write(fieldName: fieldName, fileName: fileName, to: destination) { output in
            while let buffer = try input.read(upToCount: bufferSize), buffer.isEmpty == false {
                try output.write(contentsOf: buffer)
            }
        }
    }

    ///
    /// Write the body with the given bytes as its file field to the given location.
    ///
    /// This is the counterpart of ``writeFile(from:fieldName:fileName:to:bufferSize:)`` for bytes already in memory, which spares writing them to a file of their own first.
    ///
    /// - Parameters:
    ///     - data: The bytes which become the file field.
    ///     - fieldName: The name of the form field, which the server looks the file up by.
    ///     - fileName: The name of the file to announce, escaped through ``escapedParameterValue(_:)``.
    ///     - destination: The local location to write the body to, which is replaced when it exists.
    ///
    func write(_ data: Data, fieldName: String, fileName: String, to destination: URL) throws {
        try write(fieldName: fieldName, fileName: fileName, to: destination) { output in
            try output.write(contentsOf: data)
        }
    }

    ///
    /// Write the headers of the file part, then whatever the given closure writes as its contents, then the closing boundary.
    ///
    /// - Parameters:
    ///     - fieldName: The name of the form field.
    ///     - fileName: The name of the file to announce.
    ///     - destination: The local location to write the body to.
    ///     - writeContents: Writes the contents of the file to the given handle.
    ///
    private func write(fieldName: String, fileName: String, to destination: URL, writeContents: (FileHandle) throws -> Void) throws {
        try Data().write(to: destination)
        let output = try FileHandle(forWritingTo: destination)

        defer {
            try? output.close()
        }

        // The part's own type does not matter to the server, which only reads the name and the contents of an uploaded file, so the generic type for bytes is announced rather than a guess.
        let head = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(Self.escapedParameterValue(fieldName))\"; filename=\"\(Self.escapedParameterValue(fileName))\"\r\nContent-Type: application/octet-stream\r\n\r\n"

        try output.write(contentsOf: Data(head.utf8))
        try writeContents(output)
        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    }
}
