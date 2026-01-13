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
  list                    List the content of a directory on the server by the given path.
  login                   Fetch the login flow information from a server.
  poll                    Poll the status of a previously initiated login flow.

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
