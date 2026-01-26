# libLSDJ

Vendored copy of [libLSDJ](https://github.com/stijnfrishert/libLSDJ), a C library
for reading and writing Little Sound DJ `.sav` and `.lsdsng` files.

- Upstream commit: `6023c4e48ad8280abacfddba60f2689e2442d79c` (2024-05-02)
- License: MIT, copyright (c) 2018 Stijn Frishert. See `LICENSE`.

Only the public headers under `include/lsdj` and the library sources under
`src` are vendored. The command-line tools and tests from upstream are not
included. The sources are compiled with warnings disabled because they are
third-party code.
