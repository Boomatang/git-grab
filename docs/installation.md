# Installation

`git` must be installed before using `git-grab`.

## Prebuilt binary
1. Download the latest release archive for your OS/arch.
2. Extract it and move the `grab` binary somewhere on your `PATH`.
3. Verify:
```
grab --version
```

## Build from source (Zig)
1. Install Zig (matching the version supported by this repo).
2. From the repository root, build the binary:
```
zig build -Doptimize=ReleaseSafe
```
3. The binary is created at:
```
zig-out/bin/grab
```
4. Optional: run it directly via Zig:
```
zig build run -- <args>
```
