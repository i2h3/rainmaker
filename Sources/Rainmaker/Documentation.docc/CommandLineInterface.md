# Command Line Interface

This package also provides a convenient executable to leverage the features of the library in a terminal environment.

## Overview

You can get an overview by running the command line interface itself or any subcommand with the `--help` option in the package root directory like this:

```plaintext
$ swift run rainmaker-cli --help
USAGE: rainmaker <subcommand>

OPTIONS:
  -h, --help              Show help information.

SUBCOMMANDS:
  activities              List one page of the activity stream of the authenticated user. Requires authentication and the server's activity app.
  activity-filters        List the filters the server offers to narrow the activity stream down with. Requires authentication and the server's activity app.
  capabilities            Fetch the capabilities advertised by a server. Authentication is optional.
  create-directory        Create a directory on the server.
  delete                  Delete a file or directory from the server.
  delete-app-password     Delete the app password currently used to authenticate, ending the session on the server side.
  download                Download a file or directory from the server.
  info                    Show information about a remote file or directory.
  list                    List the content of a directory on the server by the given path.
  login                   Fetch the login flow information from a server.
  move                    Move or rename a remote file or directory on the server.
  navigation              List the apps navigation entries advertised by a server. Requires authentication.
  notifications           List the notifications queued for the authenticated user. Requires authentication and the server's notifications app.
  poll                    Poll the status of a previously initiated login flow.
  upload                  Upload a file or directory to a folder on the server.
  watch                   Observe server-side changes over notify_push (or polling when unavailable) and print each event. Runs until interrupted.

  See 'rainmaker help <subcommand>' for detailed help.
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
