import Foundation

enum RequestBodyFactory {
    static func makeBaseDocument() -> XMLDocument {
        let document = XMLDocument()
        document.version = "1.0"
        document.characterEncoding = "UTF-8"

        return document
    }

    static func makeRequestBodyForDirectoryContentListing() -> XMLDocument {
        let displayname = XMLElement(name: "d:displayname")
        let resourcetype = XMLElement(name: "d:resourcetype")

        let prop = XMLElement(name: "d:prop")
        prop.addChild(displayname)
        prop.addChild(resourcetype)

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
