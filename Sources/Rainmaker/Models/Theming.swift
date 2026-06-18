// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The server's theming capability, exposing the instance branding.
///
/// This is a built-in example of a ``Capability``.
/// Use it as a template for your own capability types.
///
/// ``url`` and ``background`` are kept as strings on purpose: depending on server configuration they may be empty or, in the case of ``background``, hold a color value rather than a link.
///
public struct Theming: Capability {
    public static let key = "theming"

    ///
    /// The human readable name of the instance, e.g. `"Nextcloud"`.
    ///
    public let name: String

    ///
    /// The product name of the instance, e.g. `"Nextcloud"`.
    ///
    public let productName: String

    ///
    /// The URL the instance links to, e.g. `"https://nextcloud.com"`.
    ///
    public let url: String

    ///
    /// The slogan of the instance.
    ///
    public let slogan: String

    ///
    /// The primary brand color, e.g. `"#00679e"`.
    ///
    public let color: String

    ///
    /// The text color to use on top of the primary ``color``.
    ///
    public let colorText: String

    ///
    /// The brand color used for interface elements.
    ///
    public let colorElement: String

    ///
    /// A brighter variant of ``colorElement`` for sufficient contrast on dark backgrounds.
    ///
    public let colorElementBright: String

    ///
    /// A darker variant of ``colorElement`` for sufficient contrast on bright backgrounds.
    ///
    public let colorElementDark: String

    ///
    /// The URL of the instance logo.
    ///
    public let logo: URL

    ///
    /// The background, either a URL to an image or a color value.
    ///
    public let background: String

    ///
    /// The text color to use on top of the ``background``.
    ///
    public let backgroundText: String

    ///
    /// Whether the background is a plain color rather than an image.
    ///
    public let backgroundPlain: Bool

    ///
    /// Whether the default background is in use.
    ///
    public let backgroundDefault: Bool

    ///
    /// The URL of the logo shown in the header.
    ///
    public let logoHeader: URL

    ///
    /// The URL of the instance favicon.
    ///
    public let favicon: URL

    private enum CodingKeys: String, CodingKey {
        case name
        case productName
        case url
        case slogan
        case color
        case colorText = "color-text"
        case colorElement = "color-element"
        case colorElementBright = "color-element-bright"
        case colorElementDark = "color-element-dark"
        case logo
        case background
        case backgroundText = "background-text"
        case backgroundPlain = "background-plain"
        case backgroundDefault = "background-default"
        case logoHeader = "logoheader"
        case favicon
    }
}
