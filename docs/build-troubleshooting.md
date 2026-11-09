# SwiftUI build troubleshooting

## `SwiftUIMacros.StateMacro` not found

Newer Apple SDKs expose `@State` as a macro (see Apple's
[State documentation](https://developer.apple.com/documentation/swiftui/state)).
A direct `swiftc` build can fail if the platform plugin search path is missing,
if the compiler and SDK come from incompatible installations, or if the developer
tools do not include the required plugin. Downloading an unrelated Swift package
named SwiftUIMacros will not provide Apple's implementation.

The settings view uses an `ObservableObject` held by `@StateObject`, rather than
`@State`, so its three transient fields do not require `StateMacro`. The lifetime
is still owned by SwiftUI; preferences continue to live separately in `Settings`.
No third-party Swift dependency is needed for this fix.

## Automatic checks

```sh
make doctor
make build
```

`scripts/swift_toolchain.sh` resolves the compiler and macOS SDK from one developer
installation, adds available platform/toolchain plugin directories using that
compiler's plugin server, and typechecks a small SwiftUI view with observable
state, mutations and projected bindings. It never uses an unrelated `swiftc`
found earlier in PATH. Build caches are isolated by compiler/SDK identity.

If the selected default tools fail, the script tries installed Xcode apps under
`/Applications` and `~/Applications`. It does not change the system-wide
`xcode-select` setting. If `DEVELOPER_DIR` is explicitly set, only that installation
is used. Failed attempts and compiler diagnostics are saved to
`build/swift-toolchain.log`. This preflight also runs during `make install`, before
the normal dependency/model setup in a serial make invocation.

## When developer tools are incomplete

Try updating Command Line Tools through Software Update. If they are missing:

```sh
xcode-select --install
```

If a required Apple SDK plugin is unavailable in Command Line Tools, install full
Xcode from the Mac App Store and open it once to complete initial setup. Select
it for a single command without sudo or a system-wide configuration change:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make doctor
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make app
```

Apple's proprietary SDK/plugin components are distributed with developer tools;
the build does not download arbitrary plugin binaries. Model and Python dependency
installation remains handled by `make install`.

For stale environment overrides, retry without them:

```sh
unset SDKROOT TOOLCHAINS
make doctor
```

When reporting a failure, include `make doctor` output and
`build/swift-toolchain.log`. A successful probe checks the real selected compiler;
mock toolchain regression tests exercise discovery/fallback separately and do not
replace testing on the affected Mac.
