#!/bin/zsh
#
# SPDX-FileCopyrightText: 2025 Iva Horn
# SPDX-License-Identifier: MIT

set -e

# MARK: - Script Arguments

if [[ -z "${NEXTCLOUD_SERVER_PORT+x}" ]]; then
    NEXTCLOUD_SERVER_PORT=8421
fi

if [[ -z "${1:-}" ]]; then
    echo "Usage: ${0##*/} <nextcloud-version>" >&2
    exit 1
fi

NEXTCLOUD_SERVER_VERSION="$1"
NEXTCLOUD_SERVER_HOST="http://localhost:${NEXTCLOUD_SERVER_PORT}"

# MARK: - Generic Fetch Implementations

fetch_response() {
    curl -o "$2.txt" --no-progress-meter \
         -X "PROPFIND" "${NEXTCLOUD_SERVER_HOST}/remote.php/dav/files/admin/$1" \
         -H 'Accept: application/xml' \
         -H 'Content-Type: application/xml' \
         -u 'admin:admin' \
         -d "$3"

    xmllint --format "$2.txt" > "$2.xml"
    rm "$2.txt"

    echo "Updated: $2.xml"
}

# MARK: - Specific Fetch Definitions

fetch_response_ListingTests_listRootFolderContent() {
    echo "Fetching response for ListingTests.listRootFolderContent..."
    TARGET_FILE="Tests/RainmakerTests/Responses/${NEXTCLOUD_SERVER_VERSION}/ListingTests/listRootFolderContent/1"
    REMOTE_PATH=""
    REQUEST_BODY='<?xml version="1.0" encoding="UTF-8"?>
    <d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns" xmlns:nc="http://nextcloud.org/ns">
        <d:prop>
            <d:creationdate />
            <d:getlastmodified />
            <d:getetag />
            <d:getcontenttype />
            <oc:size />
            <d:displayname />
            <d:resourcetype />
            <oc:id />
            <oc:fileid />
            <oc:permissions />
            <nc:is-encrypted />
            <nc:is-mount-root />
            <oc:tags />
            <oc:favorite />
            <oc:comments-href />
            <oc:comments-count />
            <oc:comments-unread />
            <oc:owner-id />
            <oc:owner-display-name />
            <oc:checksums />
            <nc:has-preview />
            <nc:hidden />
            <nc:upload_time />
            <nc:group-folder-id />
            <nc:lock />
            <nc:lock-owner-type />
            <nc:lock-owner />
            <nc:lock-owner-displayname />
            <nc:lock-owner-editor />
            <nc:lock-time />
            <nc:lock-timeout />
            <nc:lock-token />
            <nc:version-label />
            <nc:version-author />
        </d:prop>
    </d:propfind>'

    fetch_response "$REMOTE_PATH" "$TARGET_FILE" "$REQUEST_BODY"
}

fetch_response_ListingTests_listDocumentsFolderContent() {
    echo "Fetching response for ListingTests.listDocumentsFolderContent..."
    TARGET_FILE="Tests/RainmakerTests/Responses/${NEXTCLOUD_SERVER_VERSION}/ListingTests/listDocumentsFolderContent/1"
    REMOTE_PATH="Documents/"
    REQUEST_BODY='<?xml version="1.0" encoding="UTF-8"?>
    <d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns" xmlns:nc="http://nextcloud.org/ns">
        <d:prop>
            <d:creationdate />
            <d:getlastmodified />
            <d:getetag />
            <d:getcontenttype />
            <oc:size />
            <d:displayname />
            <d:resourcetype />
            <oc:id />
            <oc:fileid />
            <oc:permissions />
            <nc:is-encrypted />
            <nc:is-mount-root />
            <oc:tags />
            <oc:favorite />
            <oc:comments-href />
            <oc:comments-count />
            <oc:comments-unread />
            <oc:owner-id />
            <oc:owner-display-name />
            <oc:checksums />
            <nc:has-preview />
            <nc:hidden />
            <nc:upload_time />
            <nc:group-folder-id />
            <nc:lock />
            <nc:lock-owner-type />
            <nc:lock-owner />
            <nc:lock-owner-displayname />
            <nc:lock-owner-editor />
            <nc:lock-time />
            <nc:lock-timeout />
            <nc:lock-token />
            <nc:version-label />
            <nc:version-author />
        </d:prop>
    </d:propfind>'

    fetch_response "$REMOTE_PATH" "$TARGET_FILE" "$REQUEST_BODY"
}

# MARK: - Deploy Docker Container

echo "Deploying Nextcloud container to fetch test responses from..."

docker run \
    --name 'rainmaker-test-responses' \
    --detach \
    --publish "${NEXTCLOUD_SERVER_PORT}:80" \
    --env SQLITE_DATABASE=nextcloud.sqlite \
    --env NEXTCLOUD_ADMIN_PASSWORD=admin \
    --env NEXTCLOUD_ADMIN_USER=admin \
    "nextcloud:${NEXTCLOUD_SERVER_VERSION}"

# MARK: - Await Availability

echo "Waiting for Nextcloud to become ready..."

for attempt in {1..30}; do
    if curl --silent --fail "${NEXTCLOUD_SERVER_HOST}/status.php" | grep -q '"installed":true'; then
        echo "Nextcloud is ready (attempt ${attempt})."
        break
    fi

    echo "Attempt ${attempt}/30: Nextcloud not ready yet, retrying..."
    sleep 2

    if [[ ${attempt} -eq 30 ]]; then
        echo "Nextcloud did not become ready in time." >&2
        exit 1
    fi
done

# MARK: - Create Destination Folders

mkdir -p "Tests/RainmakerTests/Responses/${NEXTCLOUD_SERVER_VERSION}/ListingTests/listRootFolderContent"
mkdir -p "Tests/RainmakerTests/Responses/${NEXTCLOUD_SERVER_VERSION}/ListingTests/listDocumentsFolderContent"

# MARK: - Actual Fetches

fetch_response_ListingTests_listRootFolderContent
fetch_response_ListingTests_listDocumentsFolderContent

# MARK: - Delete Docker Container

echo "Removing Nextcloud container again..."
docker rm --force 'rainmaker-test-responses'
