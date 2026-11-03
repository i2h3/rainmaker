# Collectives

Retrieve the collectives of an account and the pages within one of them.

## Overview

The Collectives app is not part of a Nextcloud installation, and unlike every other app covered here it advertises no capability at all, so whether it is available is answered by looking for the entry with the identifier `collectives` in ``Server/navigation()`` rather than through ``Server/capabilities()``.
Pages are returned flat and in the server's order; their hierarchy is reconstructed from ``CollectivePage/parentId``.

## Topics

### Retrieving Collectives

- ``Server/collectives()``
- ``Server/pages(inCollective:)``
- ``Collective``
- ``CollectivePage``
- ``MembershipLevel``
