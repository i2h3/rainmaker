# Command Line Interface

This package also provides a convenient executable to leverage the features of the library in a terminal environment.

## Overview

You can get an overview by running the command line interface itself or any subcommand with the `--help` option in the package root directory like this, shown here and below without the line wrapping a terminal applies:

```plaintext
$ swift run rainmaker-cli --help
USAGE: rainmaker <subcommand>

OPTIONS:
  -h, --help              Show help information.

SUBCOMMANDS:
  activities              List one page of the activity stream of the authenticated user. Requires authentication and the server's activity app.
  activity-filters        List the filters the server offers to narrow the activity stream down with. Requires authentication and the server's activity app.
  capabilities            Fetch the capabilities advertised by a server. Authentication is optional.
  collectives             List the collectives of the authenticated user and their pages. Requires authentication and the server's collectives app.
  conversations           List the Talk conversations of the authenticated user and retrieve their images. Requires authentication and the server's Talk app.
  create-directory        Create a directory on the server.
  current-user            Show the identifier and the display name of the authenticated account. Requires authentication.
  delete                  Delete a file or directory from the server.
  delete-app-password     Delete the app password currently used to authenticate, ending the session on the server side.
  download                Download a file or directory from the server.
  info                    Show information about a remote file or directory.
  list                    List the content of a directory on the server by the given path.
  login                   Fetch the login flow information from a server.
  move                    Move or rename a remote file or directory on the server.
  navigation              List the apps navigation entries advertised by a server. Requires authentication.
  notes                   List, retrieve, create, change and delete the notes of the authenticated user and their attachments. Requires authentication and the server's notes app.
  notes-settings          Show or change where and how the notes app stores the notes of the authenticated user. Requires authentication and the server's notes app.
  notifications           List the notifications queued for the authenticated user. Requires authentication and the server's notifications app.
  poll                    Poll the status of a previously initiated login flow.
  trash                   Manage the server trash bin.
  upload                  Upload a file or directory to a folder on the server.
  watch                   Observe server-side changes over notify_push (or polling when unavailable or asked to) and print each event. Runs until interrupted.
  record-fixtures         Record test fixtures by deploying Nextcloud containers and running the test suite against them.

  See 'rainmaker help <subcommand>' for detailed help.
```

## Notes

The `notes` command is a group of subcommands, of which `list` is the default, so `notes --changed-since` keeps working as before.
Attachments are managed by the nested `notes attachment` group, and the settings of the notes app by the separate `notes-settings` command.

```plaintext
$ swift run rainmaker-cli notes --help
OVERVIEW: List, retrieve, create, change and delete the notes of the authenticated user and their attachments. Requires authentication and the server's notes app.

USAGE: rainmaker notes <subcommand>

OPTIONS:
  -h, --help              Show help information.

SUBCOMMANDS:
  list (default)          List the notes of the authenticated user, all of them, those changed since a moment, or one chunk of those.
  get                     Retrieve a single note of the authenticated user by its identifier.
  create                  Create a note for the authenticated user and print its identifier, entity tag and title.
  update                  Change a note of the authenticated user and print its identifier, entity tag and title.
  delete                  Delete a note of the authenticated user.
  attachment              Retrieve, add and delete the files attached to a note of the authenticated user.

  See 'rainmaker help notes <subcommand>' for detailed help.
```

```plaintext
$ swift run rainmaker-cli notes attachment --help
OVERVIEW: Retrieve, add and delete the files attached to a note of the authenticated user.

USAGE: rainmaker notes attachment <subcommand>

OPTIONS:
  -h, --help              Show help information.

SUBCOMMANDS:
  get                     Retrieve a file attached to a note of the authenticated user.
  add                     Attach a local file to a note of the authenticated user and print the path the server stored it at.
  delete                  Delete a file attached to a note of the authenticated user. Requires the notes app 6.1.0 or newer.

  See 'rainmaker help notes attachment <subcommand>' for detailed help.
```

```plaintext
$ swift run rainmaker-cli notes-settings --help
OVERVIEW: Show or change where and how the notes app stores the notes of the authenticated user. Requires authentication and the server's notes app.

USAGE: rainmaker notes-settings [--user <user>] [--password <password>] [--output-format <output-format>] [--host <host>] [--notes-path <notes-path>] [--file-suffix <file-suffix>] [--note-mode <note-mode>] [--show-hidden-files <show-hidden-files>] [--load-recent-note-on-start-up <load-recent-note-on-start-up>]

OPTIONS:
  -u, --user <user>       The user account name to authenticate with. Can also be set via RAINMAKER_USER environment variable.
  -p, --password <password>
                          The password to authenticate with. Can also be set via RAINMAKER_PASSWORD environment variable.
  --output-format <output-format>
                          In what form to render the output. (default: plain)
  -h, --host <host>       The Nextcloud instance to connect to. Can also be set via RAINMAKER_HOST environment variable.
  --notes-path <notes-path>
                          Store the notes in this folder, relative to the account's files, with an empty string for the root folder. Existing notes are not moved.
  --file-suffix <file-suffix>
                          Give the notes created from now on this file extension, such as '.md' or '.txt'.
  --note-mode <note-mode> Open notes in the web interface in this mode. (values: rich, edit, preview)
  --show-hidden-files <show-hidden-files>
                          Whether files and folders whose names start with a dot are listed as notes and categories, 'true' or 'false'. Requires notes app 6.1.0 or newer.
  --load-recent-note-on-start-up <load-recent-note-on-start-up>
                          Whether the web interface opens the most recently edited note when it starts, 'true' or 'false'. Requires notes app 6.1.0 or newer.
  -h, --help              Show help information.
```

## Current User

```plaintext
$ swift run rainmaker-cli current-user --help
OVERVIEW: Show the identifier and the display name of the authenticated account. Requires authentication.

USAGE: rainmaker current-user [--user <user>] [--password <password>] [--output-format <output-format>] [--host <host>]

OPTIONS:
  -u, --user <user>       The user account name to authenticate with. Can also be set via RAINMAKER_USER environment variable.
  -p, --password <password>
                          The password to authenticate with. Can also be set via RAINMAKER_PASSWORD environment variable.
  --output-format <output-format>
                          In what form to render the output. (default: plain)
  -h, --host <host>       The Nextcloud instance to connect to. Can also be set via RAINMAKER_HOST environment variable.
  -h, --help              Show help information.
```

## Login

`login` starts a login flow and prints the login page to open in a browser together with the poll address and the poll token, which `poll` takes to wait for the app password.
While the flow is pending, `poll` tries again every second, and any real failure, such as an unreachable server or an address which is not a login flow endpoint, ends it with that error.

```plaintext
$ swift run rainmaker-cli poll --help
OVERVIEW: Poll the status of a previously initiated login flow.

USAGE: rainmaker poll [--output-format <output-format>] <endpoint> <token> [--tries <tries>]

ARGUMENTS:
  <endpoint>              The address which to poll for login flow status.
  <token>                 The token to identify the login flow.

OPTIONS:
  --output-format <output-format>
                          In what form to render the output. (default: plain)
  --tries <tries>         How many times the endpoint should be polled before failing. (default: 300)
  -h, --help              Show help information.
```

## Observing Changes

```plaintext
$ swift run rainmaker-cli watch --help
OVERVIEW: Observe server-side changes over notify_push (or polling when unavailable or asked to) and print each event. Runs until interrupted.

USAGE: rainmaker watch [--user <user>] [--password <password>] [--host <host>] [--poll-interval <poll-interval>] [--transport <transport>] [--listen-file-ids]

OPTIONS:
  -u, --user <user>       The user account name to authenticate with. Can also be set via RAINMAKER_USER environment variable.
  -p, --password <password>
                          The password to authenticate with. Can also be set via RAINMAKER_PASSWORD environment variable.
  -h, --host <host>       The Nextcloud instance to connect to. Can also be set via RAINMAKER_HOST environment variable.
  --poll-interval <poll-interval>
                          The polling interval in seconds used when notify_push is unavailable or not used. (default: 30.0)
  --transport <transport> How to learn about changes: 'automatic' prefers notify_push and polls when it is unavailable, 'polling' only polls. (values: automatic, polling; default: automatic)
  --listen-file-ids       Request per-file identifiers via notify_file_id.
  -h, --help              Show help information.
```

## Authentication

You can provide credentials directly as command-line options:

```bash
$ swift run rainmaker-cli list --host "http://localhost:8080" --user "myuser" --password "mypassword"
```

To avoid password leakage and enable a default account pattern, you can also set credentials via environment variables:

```bash
export RAINMAKER_HOST="http://localhost:8080"
export RAINMAKER_USER="myuser"
export RAINMAKER_PASSWORD="mypassword"

$ swift run rainmaker-cli list
```

Environment variables can be mixed with command-line options. Command-line options take precedence over environment variables.
