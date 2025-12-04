import Foundation

enum RequestBodyFactory {
    static func makeBaseDocument() -> XMLDocument {
        let document = XMLDocument()
        document.version = "1.0"
        document.characterEncoding = "UTF-8"

        return document
    }

    static func makeRequestBodyForDirectoryContentListing() -> XMLDocument {
        let prop = XMLElement(name: "d:prop")

        [
            "d:creationdate",
            "d:getlastmodified",
            "d:getetag",
            "d:getcontenttype",
            "oc:size",
            "d:displayname",
            "d:resourcetype",
            "oc:id",
            "oc:fileid",
            "oc:permissions",
            "nc:is-encrypted",
            "nc:is-mount-root",
            "oc:favorite",
            "oc:comments-href",
            "oc:comments-count",
            "oc:comments-unread",
            "oc:owner-id",
            "oc:owner-display-name",
            "nc:has-preview",
            "nc:hidden",
            "nc:upload_time",
            "nc:lock",
            "nc:lock-owner-type",
            "nc:lock-owner",
            "nc:lock-owner-displayname",
            "nc:lock-owner-editor",
            "nc:lock-time",
            "nc:lock-timeout",
            "nc:lock-token",
        ].forEach {
            prop.addChild(XMLElement(name: $0))
        }

        let root = XMLElement(name: "d:propfind")
        root.addNamespace(XMLNode.namespace(withName: "d", stringValue: "DAV:") as! XMLNode)
        root.addNamespace(XMLNode.namespace(withName: "oc", stringValue: "http://owncloud.org/ns") as! XMLNode)
        root.addNamespace(XMLNode.namespace(withName: "nc", stringValue: "http://nextcloud.org/ns") as! XMLNode)
        root.addChild(prop)

        let document = makeBaseDocument()
        document.setRootElement(root)

        return document
    }
}
