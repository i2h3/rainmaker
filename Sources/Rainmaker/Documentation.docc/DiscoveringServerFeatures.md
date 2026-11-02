# Capabilities and Navigation

Find out what a server offers before relying on it, and which apps it advertises to the authenticated user.

## Overview

``Server/capabilities()`` returns what the server and its apps advertise, from which a client looks up the ``Capability`` it is interested in, such as ``Notes`` before using the notes features or ``Talk`` before sending into a conversation.
A downstream project can declare a ``Capability`` of its own for anything this library does not model.

``Server/navigation()`` lists the server apps, such as Files, Photos and Activity, which the server advertises to the authenticated user so that a client can surface them in its own navigation.
It is also how a client finds out whether an app without a capability of its own, such as Collectives, is available.

## Topics

### Capabilities

- ``Server/capabilities()``
- ``CapabilitySet``
- ``Capability``
- ``Activity``
- ``ChunkedUpload``
- ``Notes``
- ``Notifications``
- ``PushNotifications``
- ``Talk``
- ``Theming``
- ``Trashing``
- ``Version``

### Navigation

- ``Server/navigation()``
- ``NavigationItem``
