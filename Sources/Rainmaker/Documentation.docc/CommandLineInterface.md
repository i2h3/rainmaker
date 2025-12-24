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
