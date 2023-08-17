# arm64-to-sim

A simple command-line tool for hacking native ARM64 binaries to run on the Apple Silicon iOS Simulator.

## Building

In order to build a universal `arm64-to-sim` executable, run:

```
swift build -c release --arch arm64 --arch x86_64
```

This will output the executable into the `.build/apple/Products/Release`
directory.


## Auto Script only framework
Download and run the "arm64_simulator.sh" script. 

And please put in the framework path that you want to modify. 

Then OO-simul.framework is automatically created in the path you put in. 

Please include the framework created in your project.

<img width="696" alt="스크린샷 2023-08-17 오후 3 45 31" src="https://github.com/bugkingK/arm64-to-sim/assets/33336869/d537c238-be9c-4847-b43d-03ec6f62dbc5">
