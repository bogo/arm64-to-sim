# arm64-to-sim

A simple command-line tool for hacking native ARM64 binaries to run on the Apple Silicon iOS Simulator.

# Documentation
Read this two articles by the arm64-to-sim creator @bogo

* https://bogo.wtf/arm64-to-sim.html

* https://bogo.wtf/arm64-to-sim-dylibs.html

# How to create a .xcframework

Steps to create a xcframework including an arm64-simulator version from a arm64 framework already existent.

```$ mkdir -p GoogleInteractiveMediaAds.xcframework/ios-arm64_armv7
    $ mkdir -p GoogleInteractiveMediaAds.xcframework/ios-arm64_i386_x86_64-simulator
    $ touch GoogleInteractiveMediaAds.xcframework/Info.plist
```

Add next code to Info.plist
```<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AvailableLibraries</key>
    <array>
        <dict>
            <key>LibraryIdentifier</key>
            <string>ios-arm64_i386_x86_64-simulator</string>
            <key>LibraryPath</key>
            <string>GoogleInteractiveMediaAds.framework</string>
            <key>SupportedArchitectures</key>
            <array>
                <string>arm64</string>
                <string>i386</string>
                <string>x86_64</string>
            </array>
            <key>SupportedPlatform</key>
            <string>ios</string>
            <key>SupportedPlatformVariant</key>
            <string>simulator</string>
        </dict>
        <dict>
            <key>LibraryIdentifier</key>
            <string>ios-arm64_armv7</string>
            <key>LibraryPath</key>
            <string>GoogleInteractiveMediaAds.framework</string>
            <key>SupportedArchitectures</key>
            <array>
                <string>arm64</string>
                <string>armv7</string>
            </array>
            <key>SupportedPlatform</key>
            <string>ios</string>
        </dict>
    </array>
    <key>CFBundlePackageType</key>
    <string>XFWK</string>
    <key>XCFrameworkFormatVersion</key>
    <string>1.0</string>
</dict>
</plist>
```

Create device framework:
```
    $ cp -a GoogleInteractiveMediaAds.framework GoogleInteractiveMediaAds.xcframework/ios-arm64_armv7/
    $ lipo -thin arm64 GoogleInteractiveMediaAds.xcframework/ios-arm64_armv7/GoogleInteractiveMediaAds.framework/GoogleInteractiveMediaAds -output GoogleInteractiveMediaAds.xcframework/ios-arm64_armv7/GoogleInteractiveMediaAds.framework/GoogleInteractiveMediaAds.arm64
    $ lipo -thin armv7 GoogleInteractiveMediaAds.xcframework/ios-arm64_armv7/GoogleInteractiveMediaAds.framework/GoogleInteractiveMediaAds -output GoogleInteractiveMediaAds.xcframework/ios-arm64_armv7/GoogleInteractiveMediaAds.framework/GoogleInteractiveMediaAds.armv7
    $ lipo -create -output GoogleInteractiveMediaAds.xcframework/ios-arm64_armv7/GoogleInteractiveMediaAds GoogleInteractiveMediaAds.xcframework/ios-arm64_armv7/GoogleInteractiveMediaAds.arm64 GoogleInteractiveMediaAds.xcframework/ios-arm64_armv7/GoogleInteractiveMediaAds.armv7
```

Create simulator framework (multistep):
```
    $ cp -a GoogleInteractiveMediaAds.framework GoogleInteractiveMediaAds.xcframework/ios-arm64_i386_x86_64-simulator/
    $ lipo -thin arm64 GoogleInteractiveMediaAds.xcframework/ios-arm64_i386_x86_64-simulator/GoogleInteractiveMediaAds.framework/GoogleInteractiveMediaAds -output GoogleInteractiveMediaAds.xcframework/ios-arm64_i386_x86_64-simulator/GoogleInteractiveMediaAds.framework/GoogleInteractiveMediaAds.arm64
    $ lipo -thin i386 GoogleInteractiveMediaAds.xcframework/ios-arm64_i386_x86_64-simulator/GoogleInteractiveMediaAds.framework/GoogleInteractiveMediaAds -output GoogleInteractiveMediaAds.xcframework/ios-arm64_i386_x86_64-simulator/GoogleInteractiveMediaAds.framework/GoogleInteractiveMediaAds.i386
    $ lipo -thin x86_64 GoogleInteractiveMediaAds.xcframework/ios-arm64_i386_x86_64-simulator/GoogleInteractiveMediaAds.framework/GoogleInteractiveMediaAds -output GoogleInteractiveMediaAds.xcframework/ios-arm64_i386_x86_64-simulator/GoogleInteractiveMediaAds.framework/GoogleInteractiveMediaAds.x86_64
```
Hack arm64 framework from device to work on arm64 simulator:
```
    $ arm64-to-sim GoogleInteractiveMediaAds.xcframework/ios-arm64_i386_x86_64-simulator/GoogleInteractiveMediaAds.framework/GoogleInteractiveMediaAds.arm64
    $ lipo -create -output GoogleInteractiveMediaAds.xcframework/ios-arm64_i386_x86_64-simulator/GoogleInteractiveMediaAds GoogleInteractiveMediaAds.xcframework/ios-arm64_i386_x86_64-simulator/GoogleInteractiveMediaAds.arm64 GoogleInteractiveMediaAds.xcframework/ios-arm64_i386_x86_64-simulator/GoogleInteractiveMediaAds.i386 GoogleInteractiveMediaAds.xcframework/ios-arm64_i386_x86_64-simulator/GoogleInteractiveMediaAds.x86_64
```

Clean support files.
```
    $ rm GoogleInteractiveMediaAds.xcframework/ios-arm64_armv7/GoogleInteractiveMediaAds.*
    $ rm GoogleInteractiveMediaAds.xcframework/ios-arm64_i386_x86_64-simulator/GoogleInteractiveMediaAds.*
```

And sign the new simulator framework to avoid dyld loading errors.
```
    $ xcrun codesign --sign - GoogleInteractiveMediaAds.xcframework/ios-arm64_i386_x86_64-simulator/GoogleInteractiveMediaAds.framework
```
