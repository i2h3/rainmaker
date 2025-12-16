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

PROPFIND_REQUEST_BODY='<?xml version="1.0" encoding="UTF-8"?>
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

fetch_response() {
    WEBDAV_PATH_PREFIX="remote.php/dav/files"
    USER_PATH_PREFIX="${WEBDAV_PATH_PREFIX}/admin"
    RESOURCE_PATH="${USER_PATH_PREFIX}/$2"
    FILE_PATH_PREFIX="Tests/RainmakerTests/Responses/${NEXTCLOUD_SERVER_VERSION}/$1/PROPFIND/${RESOURCE_PATH}"

    mkdir -p "${FILE_PATH_PREFIX}"

    curl -o "${FILE_PATH_PREFIX}/Response.txt" --no-progress-meter \
         -X "PROPFIND" "${NEXTCLOUD_SERVER_HOST}/${RESOURCE_PATH}" \
         -H 'Accept: application/xml' \
         -H 'Content-Type: application/xml' \
         -u 'admin:admin' \
         -d "$PROPFIND_REQUEST_BODY"

    xmllint --format "${FILE_PATH_PREFIX}/Response.txt" > "${FILE_PATH_PREFIX}/Response.xml"
    rm "${FILE_PATH_PREFIX}/Response.txt"

    echo "Updated: ${FILE_PATH_PREFIX}/Response.xml"
}

# MARK: - Specific Fetch Definitions

fetch_response_ListingTests_listRootFolderContent() {
    fetch_response "ListingTests/listRootFolderContent" ""
}

fetch_response_ListingTests_listDocumentsFolderContent() {
    fetch_response "ListingTests/listDocumentsFolderContent" "Documents"
}

fetch_response_ListingTests_listAllContentRecursivelyAndAsynchronously() {
    fetch_response "ListingTests/listAllContentRecursivelyAndAsynchronously" ""
    fetch_response "ListingTests/listAllContentRecursivelyAndAsynchronously" "Documents"
    fetch_response "ListingTests/listAllContentRecursivelyAndAsynchronously" "Photos"
    fetch_response "ListingTests/listAllContentRecursivelyAndAsynchronously" "Templates"
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

# MARK: - Actual Fetches

fetch_response_ListingTests_listAllContentRecursivelyAndAsynchronously
fetch_response_ListingTests_listDocumentsFolderContent
fetch_response_ListingTests_listRootFolderContent

# MARK: - Delete Docker Container

echo "Removing Nextcloud container again..."
docker rm --force 'rainmaker-test-responses'
