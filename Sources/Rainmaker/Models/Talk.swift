// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// The server's Talk capability, advertised when the Talk app is installed and enabled.
///
/// On Nextcloud, conversations are provided by the "Talk" app which, unlike most of what this library covers, is not part of a Nextcloud installation and has to be installed separately. When that app is available the server advertises this object under the `spreed` key, which is why ``key`` is `"spreed"` — the app's own internal identifier, which predates the name it is presented under. Its mere presence is the signal a client needs before calling ``Server/conversations()``: check it with `try await capabilities().contains(Talk.self)`.
///
/// Unlike the ``Notes``, ``Notifications`` and ``Activity`` capabilities, this object is advertised to anonymous clients as well, so its presence says that the app is installed on the server rather than that the authenticated user may use it.
///
/// Talk versions its endpoints in their paths rather than advertising an API version, so there is nothing to check here the way ``Notes/isSupported`` checks the notes API. What a given server can do is described by named feature flags instead, which ``supports(_:)`` looks up.
/// The lists of features and the version are kept optional so that a server which omits one of them still decodes successfully, and ``storesAttachmentsPerConversation`` is `false` when the server omits it.
///
/// The app's configuration, which the server advertises under `config` and `config-local`, is deliberately not modelled beyond the single flag ``storesAttachmentsPerConversation`` reads: it is deeply nested, it is reshaped between Talk releases, and nothing else of it is needed to list conversations or to send to them. A downstream project which needs another part of it can declare its own ``Capability`` with the same ``key`` modelling just that subtree, which is exactly the extension point ``Capability`` offers.
///
public struct Talk: Capability {
    ///
    /// The name of the object the server advertises this capability under, which is the internal identifier of the Talk app rather than its presented name.
    ///
    public static let key = "spreed"

    ///
    /// The features the server supports, including those a conversation hosted on another server can offer, e.g. `["audio", "video", "chat-v2", "conversation-v4"]`.
    ///
    /// This corresponds to the server's `features` field. Look a flag up through ``supports(_:)`` rather than reaching in here, so that ``localFeatures`` is considered as well.
    ///
    public let features: [String]?

    ///
    /// The features which only conversations hosted by this server itself offer, e.g. `["favorites", "note-to-self"]`.
    ///
    /// This corresponds to the server's `features-local` field. A conversation reached through federation is hosted elsewhere and does not necessarily offer what this lists, which is why the server keeps the two apart.
    ///
    public let localFeatures: [String]?

    ///
    /// The version of the Talk app itself, e.g. `"24.0.4"`.
    ///
    /// This is the app's own version and unrelated to the server ``Version``, which is why it is kept as the plain string the server sends. Prefer ``supports(_:)`` over comparing versions: a feature flag says what a server can actually do, a version only implies it.
    ///
    public let version: String?

    ///
    /// Whether the server keeps the files sent into a conversation in a folder per conversation, which is what ``Server/sendFile(_:toConversation:caption:)`` requires.
    ///
    /// This corresponds to the server's `config` → `attachments` → `conversation-subfolders` field, which Talk 24 introduced together with the endpoints that sending a file is built on. It is `false` when the server does not advertise the field, as every older release does, and when an administrator turned the folders off, in both of which cases sending a file fails.
    /// The name mirrors ``Notes/storesAttachmentsPerNote``, and like that one it is a behaviour of the app which no feature flag in ``features`` announces.
    ///
    public let storesAttachmentsPerConversation: Bool

    ///
    /// Whether the server advertises the given Talk feature.
    ///
    /// The flag is looked up in ``features`` as well as in ``localFeatures``, which together describe everything a conversation on this server can do.
    ///
    /// - Parameters:
    ///     - feature: The feature flag to check for, e.g. `"conversation-v4"`.
    ///
    /// - Returns: `true` when either list contains the flag, otherwise `false`.
    ///
    public func supports(_ feature: String) -> Bool {
        features?.contains(feature) == true || localFeatures?.contains(feature) == true
    }

    ///
    /// The keys this capability is decoded from, which are the names the server sends.
    ///
    private enum CodingKeys: String, CodingKey {
        case features
        case localFeatures = "features-local"
        case version
        case configuration = "config"
    }

    ///
    /// The keys of the app's configuration below `config`, of which only the section ``storesAttachmentsPerConversation`` is read from is decoded.
    ///
    private enum ConfigurationKeys: String, CodingKey {
        case attachments
    }

    ///
    /// The keys of the `attachments` section of the app's configuration, of which only the flag behind ``storesAttachmentsPerConversation`` is decoded.
    ///
    private enum AttachmentsKeys: String, CodingKey {
        case conversationSubfolders = "conversation-subfolders"
    }

    // MARK: - Decodable

    ///
    /// Decode the capability from the object the server advertises under ``key``.
    ///
    /// The lists of features and the version are optional, so that a server which omits one of them still decodes, and ``storesAttachmentsPerConversation`` is read from two levels below `config` without modelling anything else there and is `false` when any level is missing.
    ///
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        features = try container.decodeIfPresent([String].self, forKey: .features)
        localFeatures = try container.decodeIfPresent([String].self, forKey: .localFeatures)
        version = try container.decodeIfPresent(String.self, forKey: .version)

        // A missing level anywhere on the way down means a release which predates the flag, so it decodes as `false` rather than failing the whole capability.
        let configuration = try? container.nestedContainer(keyedBy: ConfigurationKeys.self, forKey: .configuration)
        let attachments = try? configuration?.nestedContainer(keyedBy: AttachmentsKeys.self, forKey: .attachments)
        storesAttachmentsPerConversation = try attachments?.decodeIfPresent(Bool.self, forKey: .conversationSubfolders) ?? false
    }
}
