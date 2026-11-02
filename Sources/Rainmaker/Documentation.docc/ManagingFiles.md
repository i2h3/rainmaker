# Files

Browse, download, upload and reorganize the files of an account over WebDAV, and restore them from its trash bin.

## Overview

A file larger than the chunk size is uploaded in chunks the server assembles, which keeps large uploads within the request limits of the server and any reverse proxy in front of it.
The ``ChunkedUpload`` capability advertises the limits a server suggests for that.

Deleted items are kept in a per-account trash bin, from which they can be listed, restored and permanently removed.
Whether the server offers one is advertised through the ``Trashing`` capability.

## Topics

### Browsing

- ``Server/enumerate(at:recursively:)->AsyncThrowingStream<Item,Error>``
- ``Server/enumerate(at:recursively:)->[Item]``
- ``Server/info(_:)``

### Transferring

- ``Server/download(_:to:force:)``
- ``Server/upload(_:to:force:chunkSize:)``

### Reorganizing

- ``Server/createDirectory(_:)``
- ``Server/delete(_:)``
- ``Server/move(_:to:overwrite:)``

### Trash Bin

- ``Server/trash()``
- ``Server/restore(_:)-(String)``
- ``Server/restore(_:)-(TrashItem)``
- ``Server/emptyTrash()``

### Data Models

- ``Item``
- ``Lock``
- ``Permission``
- ``Quota``
- ``AvailableQuota``
- ``TrashItem``
