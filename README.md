# arm64-to-sim

A simple command-line tool for hacking native ARM64 binaries to run on the Apple Silicon iOS Simulator.

## Building

In order to build a universal `arm64-to-sim` executable, run:

```
swift build -c release --arch arm64 --arch x86_64
```

This will output the executable into the `.build/apple/Products/Release`
directory.
