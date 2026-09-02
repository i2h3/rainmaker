// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The interpolatable variant of an activity's subject or message, pairing a template with the objects its placeholders refer to.
///
/// Every ``ActivityItem`` carries both a flat, already rendered sentence (``ActivityItem/subject`` and ``ActivityItem/message``) and this richer counterpart (``ActivityItem/subjectRich`` and ``ActivityItem/messageRich``). The flat variant is enough to display an activity as plain text, while this one lets a client render the referenced files, users and tags as interactive elements instead of as words.
///
/// The ``template`` contains placeholders in braces, e.g. `"You changed {file}"`, and ``parameters`` maps each placeholder name to the ``ActivityRichObject`` it stands for. Flattening the two back into plain text is ``resolved()``, which reproduces what the server put into ``ActivityItem/subject``.
///
/// The server advertises whether it supports this at all under the ``Activity`` capability's `"rich-strings"` entry.
///
public struct ActivityRichText: Model, Decodable, CustomStringConvertible, CustomDebugStringConvertible {
    ///
    /// The sentence with a placeholder in braces for every referenced object, e.g. `"You changed {file}"`.
    ///
    /// Empty when the activity carries no rich variant of this text, which is the common case for ``ActivityItem/messageRich``.
    ///
    public let template: String

    ///
    /// The objects the placeholders in ``template`` refer to, keyed by placeholder name without the braces.
    ///
    /// Every placeholder occurring in ``template`` has an entry here because the server validates that, but the reverse does not hold: a parameter may be present without being referenced.
    ///
    public let parameters: [String: ActivityRichObject]

    ///
    /// Flatten this into plain text by replacing every placeholder with the name of the object it refers to.
    ///
    /// This mirrors what the server itself does when it derives ``ActivityItem/subject`` from ``ActivityItem/subjectRich``, so the result of calling this on ``ActivityItem/subjectRich`` equals ``ActivityItem/subject``. It is useful for clients which want to render the rich variant selectively and fall back to text elsewhere.
    ///
    /// The template is scanned exactly once and substituted text is never revisited, so a name which happens to look like a placeholder itself is inserted literally instead of being expanded again. Object names are chosen by whoever created the file, the calendar or the tag an activity is about, which makes that reachable rather than theoretical. A placeholder without a matching parameter is left in place verbatim.
    ///
    /// - Returns: The template with all of its placeholders substituted.
    ///
    public func resolved() -> String {
        guard parameters.isEmpty == false else {
            return template
        }

        var result = ""
        var remainder = Substring(template)

        while let opening = remainder.firstIndex(of: "{") {
            result.append(contentsOf: remainder[remainder.startIndex ..< opening])

            let afterOpening = remainder.index(after: opening)

            guard let closing = remainder[afterOpening...].firstIndex(of: "}") else {
                // An unterminated brace is not a placeholder, so the rest of the template is taken as it is.
                return result + remainder[opening...]
            }

            if let parameter = parameters[String(remainder[afterOpening ..< closing])] {
                result.append(parameter.name)
            } else {
                result.append(contentsOf: remainder[opening ... closing])
            }

            remainder = remainder[remainder.index(after: closing)...]
        }

        return result + remainder
    }

    // MARK: - Decodable

    ///
    /// Decode a rich text from the two-element array the server serializes it as, the template first and its parameters second.
    ///
    /// Both elements are tolerated to be missing or of an unexpected shape, because the server serializes an empty parameter dictionary as an empty array rather than as an empty object, and omits the rich variant entirely for some activities.
    ///
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()

        template = (try? container.decode(String.self)) ?? ""
        parameters = (try? container.decode([String: ActivityRichObject].self)) ?? [:]
    }

    // MARK: - CustomStringConvertible

    ///
    /// Implementation for `CustomStringConvertible` conformance to have a concise and human-readable textual representation of a rich text.
    ///
    public var description: String {
        resolved()
    }

    // MARK: - CustomDebugStringConvertible

    ///
    /// Implementation for `CustomDebugStringConvertible` conformance to have a concise and human-readable textual representation of a rich text.
    ///
    public var debugDescription: String {
        "\(template) \(parameters)"
    }
}
