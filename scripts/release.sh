#!/bin/env bash

# Set the DEBUG envar to not clean up resources for debugging

temp=$(mktemp -d)

echo $temp

release_notes="$temp/release.md"
towncrier build --draft > $release_notes

towncrier build 
cp CHANGELOG.md $temp/
cp README.md $temp/

small_build_base="git-grab_fast_linux_amd64"
fast_build_base="git-grab_small_linux_amd64"

small_build="$temp/$small_build_base"
fast_build="$temp/$fast_build_base"

mkdir -p $small_build
mkdir -p $fast_build

zig build --release=fast
cp zig-out/bin/grab "$fast_build/"
cp "$temp/CHANGELOG.md" "$fast_build/"
cp "$temp/README.md" "$fast_build/"
tar -czf "$fast_build.tar.gz" -C "$temp" "$fast_build_base"

zig build --release=small
cp zig-out/bin/grab "$small_build/"
cp "$temp/CHANGELOG.md" "$small_build/"
cp "$temp/README.md" "$small_build/"
tar -czf "$small_build.tar.gz" -C "$temp" "$small_build_base"

if [ -z "$DEBUG" ]; then
    rm -rf $temp
fi
