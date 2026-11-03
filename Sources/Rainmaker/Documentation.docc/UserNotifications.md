# Notifications

List what the server currently has queued for the authenticated user.

## Overview

These are what is worth retrieving again in response to ``ServerEvent/notifications``.
Whether and how many notifications are pending follows from the returned array, and whether the app providing them is installed at all is advertised through the ``Notifications`` capability.

## Topics

### Retrieving Notifications

- ``Server/notifications()``
- ``NotificationItem``
