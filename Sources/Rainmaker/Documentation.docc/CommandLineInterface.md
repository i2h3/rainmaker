# Command Line Interface

Use the features of the library in a terminal through the executable this package also provides.

## Overview

The package provides the executable product `rainmaker-cli`, which offers the features of the library as subcommands.
Run it from the package root directory through the Swift Package Manager:

```bash
swift run rainmaker-cli <subcommand>
```

The command line interface describes itself, so ask it for help rather than relying on a copy of its help in this documentation.
The `--help` option lists the subcommands, and the `help` subcommand describes a single one, including the options it takes and how they are set:

```bash
swift run rainmaker-cli --help
swift run rainmaker-cli help <subcommand>
```
