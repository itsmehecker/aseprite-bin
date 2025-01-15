#!/bin/bash

set -e

# Check if git is installed
if ! command -v git &> /dev/null; then
  echo "ERROR: git not found"
  exit 1
fi

# Check if 7-Zip is installed
if command -v 7z &> /dev/null; then
  SZIP=7z
else
  echo "ERROR: 7-Zip not found"
  exit 1
fi

# Check if ninja is installed
if ! command -v ninja &> /dev/null; then
  curl -LO https://github.com/ninja-build/ninja/releases/download/v1.11.0/ninja-linux.zip
  $SZIP x ninja-linux.zip -o/usr/local/bin
  chmod +x /usr/local/bin/ninja
  rm ninja-linux.zip
fi

# Fetch latest release version
if [ -z "$ASEPRITE_VERSION" ]; then
  ASEPRITE_VERSION=$(curl -sL https://api.github.com/repos/aseprite/aseprite/releases/latest | jq -r .tag_name)
fi
echo "Building $ASEPRITE_VERSION"

if [[ "$ASEPRITE_VERSION" == *beta* ]]; then
  SKIA_VERSION=m124-08a5439a6b
else
  SKIA_VERSION=m102-861e4743af
fi

# Clone aseprite repo
if [ -d "aseprite" ]; then
  pushd aseprite
  git clean -fdx
  git submodule foreach --recursive git clean -xfd
  git fetch --depth=1 --no-tags origin $ASEPRITE_VERSION:refs/remotes/origin/$ASEPRITE_VERSION || {
    echo "Failed to fetch latest version"
    exit 1
  }
  git reset --hard origin/$ASEPRITE_VERSION || {
    echo "Failed to update to latest version"
    exit 1
  }
  git submodule update --init --recursive || {
    echo "Failed to update submodules"
    exit 1
  }
  popd
else
  git clone --quiet --no-tags --recursive --depth=1 -b "$ASEPRITE_VERSION" https://github.com/aseprite/aseprite.git || {
    echo "Failed to clone repo"
    exit 1
  }
fi

python3 -c "v = open('aseprite/src/ver/CMakeLists.txt').read(); open('aseprite/src/ver/CMakeLists.txt', 'w').write(v.replace('1.x-dev', '${ASEPRITE_VERSION:1}'))"

# Download skia
if [ ! -d "skia-$SKIA_VERSION" ]; then
  mkdir skia-$SKIA_VERSION
  pushd skia-$SKIA_VERSION
  curl -LO https://github.com/aseprite/skia/releases/download/$SKIA_VERSION/Skia-Linux-Release-x64.zip || {
    echo "Failed to download skia"
    exit 1
  }
  $SZIP x Skia-Linux-Release-x64.zip
  popd
fi

# Build aseprite
if [ -d "build" ]; then
  rm -rf build
fi

cmake -G Ninja -S aseprite -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_DEFAULT_CMP0074=NEW \
  -DCMAKE_POLICY_DEFAULT_CMP0091=NEW \
  -DCMAKE_POLICY_DEFAULT_CMP0092=NEW \
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded \
  -DENABLE_CCACHE=OFF \
  -DOPENSSL_USE_STATIC_LIBS=TRUE \
  -DLAF_BACKEND=skia \
  -DSKIA_DIR=$(pwd)/skia-$SKIA_VERSION \
  -DSKIA_LIBRARY_DIR=$(pwd)/skia-$SKIA_VERSION/out/Release-x64 \
  -DSKIA_OPENGL_LIBRARY= || {
    echo "Failed to configure build"
    exit 1
  }

ninja -C build || {
  echo "Build failed"
  exit 1
}

# Create output folder
mkdir aseprite-$ASEPRITE_VERSION
echo "# This file is here so Aseprite behaves as a portable program" > aseprite-$ASEPRITE_VERSION/aseprite.ini
cp -r aseprite/docs aseprite-$ASEPRITE_VERSION/docs
cp build/bin/aseprite aseprite-$ASEPRITE_VERSION/
cp -r build/bin/data aseprite-$ASEPRITE_VERSION/data

if [ -n "$GITHUB_WORKFLOW" ]; then
  mkdir github
  mv aseprite-$ASEPRITE_VERSION github/
  echo "ASEPRITE_VERSION=$ASEPRITE_VERSION" >> $GITHUB_OUTPUT
fi