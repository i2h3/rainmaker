<div align="center">
    <img src="Rainmaker.png" alt="Logo of Rainmaker" width="256" height="256" />
</div>

# Rainmaker

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fi2h3%2Frainmaker%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/i2h3/rainmaker)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fi2h3%2Frainmaker%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/i2h3/rainmaker)
[![Tests](https://github.com/i2h3/rainmaker/actions/workflows/test.yml/badge.svg)](https://github.com/i2h3/rainmaker/actions/workflows/test.yml)
[![REUSE](https://api.reuse.software/badge/github.com/i2h3/rainmaker)](https://api.reuse.software/info/github.com/i2h3/rainmaker)

A simple Swift library and CLI to access [Nextcloud](https://www.nextcloud.com) files programmatically.
For further information, see [the documentation which is built from the source code and deployed to GitHub pages](https://i2h3.github.io/rainmaker/). 

## License

See [LICENSE](LICENSE).

## Contributing

[SwiftFormat](https://github.com/nicklockwood/SwiftFormat) was introduced into this project.
Before submitting a pull request, please ensure that your code changes comply with the currently configured code style.
You can run the following command in the root of the package repository clone:

```bash
swift package plugin --allow-writing-to-package-directory swiftformat --verbose --cache ignore
```

Also, there is a GitHub action run automatically which lints code changes in pull requests.
