# Future: ankitects/anki rslib via C FFI

Current backend is `LocalAnkiBackend` → `AnkiCollection` + `AnkiScheduler` (Anki SM-2 v2 semantics).

To replace with official Rust `rslib` (AGPL):

1. Install Rust + `aarch64-apple-ios` target
2. Vendor / submodule [ankitects/anki](https://github.com/ankitects/anki) and follow [amgi](https://github.com/antigluten/amgi) `build-xcframework.sh`
3. Implement `AnkiBackend` with the 4 C FFI entry points used by amgi
4. Keep UIKit UI and Mode A/B services unchanged

Why not linked on day one: this machine had no Rust toolchain; iPad Air 1 also needs a carefully pinned / memory-light build. The Swift scheduler reads/writes the same `collection.anki2` schema so `.apkg` progress round-trips with desktop Anki.
