#!/bin/bash

# Ensure to exit on all kinds of errors
set -xeu
set -o pipefail

VERSION="5.4.12"
SHA256="1ac4f3c038ac163973f107ac4423a6b246b181ffd97fdd371696b2517ec9b3ed"

detect_platform() {
  # use os-maven-plugin to detect platform
  local platform=$(mvn help:evaluate -Dexpression=os.detected.classifier -q -DforceStdout)
  # fix value for macosx: plugin outputs osx, but JavaCPP needs it to be macosx
  local fixOsName=${platform/osx/macosx}
  # fix value for arm64: plugin outputs aarch64, but JavaCPP needs it to be arm64
  echo ${fixOsName/aarch_64/arm64}
}

export DETECTED_PLATFORM=${DETECTED_PLATFORM:-$(detect_platform)}

cross_platform_nproc() {
  case $DETECTED_PLATFORM in
    macosx-x86_64|macosx-arm64) echo $(sysctl -n hw.logicalcpu) ;;
    linux-x86_64|linux-arm64) echo $(nproc --all) ;;
    *) echo Unsupported Platform: $DETECTED_PLATFORM >&2 ; exit -1 ;;
  esac
}

cross_platform_check_sha() {
  local sha=$1
  local file=$2
  case $DETECTED_PLATFORM in
    macosx-x86_64|macosx-arm64) echo "$sha  $file" | shasum -a 256 -c ;;
    linux-x86_64|linux-arm64) echo "$sha  $file" | sha256sum -c ;;
    *) echo Unsupported Platform: $DETECTED_PLATFORM >&2 ; exit -1 ;;
  esac
}

THREADS=$(cross_platform_nproc)

mkdir -p cppbuild/lib
mkdir -p cppbuild/bin
mkdir -p cppbuild/include/hs
cd cppbuild

curl -L -o vectorscan-$VERSION.tar.gz https://github.com/VectorCamp/vectorscan/archive/refs/tags/vectorscan/$VERSION.tar.gz
cross_platform_check_sha \
  $SHA256 \
  vectorscan-$VERSION.tar.gz
tar -xvf vectorscan-$VERSION.tar.gz
mv vectorscan-vectorscan-$VERSION vectorscan

curl -L -o boost_1_89_0.tar.gz https://archives.boost.io/release/1.89.0/source/boost_1_89_0.tar.gz
cross_platform_check_sha \
  9de758db755e8330a01d995b0a24d09798048400ac25c03fc5ea9be364b13c93 \
  boost_1_89_0.tar.gz
tar -zxf boost_1_89_0.tar.gz
mv boost_1_89_0/boost vectorscan/include/boost

curl -L -o ragel-6.10.tar.gz https://www.colm.net/files/ragel/ragel-6.10.tar.gz
cross_platform_check_sha \
  5f156edb65d20b856d638dd9ee2dfb43285914d9aa2b6ec779dac0270cd56c3f \
  ragel-6.10.tar.gz

tar -zxf ragel-6.10.tar.gz
cd ragel-6.10
./configure --prefix="$(pwd)/.."
make -j $THREADS
make install
cd ..

cd vectorscan

# Disable flakey sqlite detection - only needed to build auxillary tools anyways.
> cmake/sqlite3.cmake

case $DETECTED_PLATFORM in
linux-x86_64)
  cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(pwd)/.." -DCMAKE_INSTALL_LIBDIR="lib" -DPCRE_SOURCE="." -DFAT_RUNTIME=on -DBUILD_SHARED_LIBS=on -DBUILD_AVX2=yes -DBUILD_AVX512=yes -DBUILD_AVX512VBMI=yes .
  make -j $THREADS all unit install/strip

  ;;
linux-arm64)
  CC="clang" CXX="clang++" cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(pwd)/.." -DCMAKE_INSTALL_LIBDIR="lib" -DPCRE_SOURCE="." -DFAT_RUNTIME=on -DBUILD_SHARED_LIBS=on -DBUILD_SVE=on -DBUILD_SVE2=on .
  make -j $THREADS all unit install/strip
  ;;
macosx-x86_64|macosx-arm64)
  export MACOSX_DEPLOYMENT_TARGET=12
  cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(pwd)/.." -DCMAKE_INSTALL_LIBDIR="lib" -DARCH_OPT_FLAGS='-Wno-error' -DPCRE_SOURCE="." -DBUILD_SHARED_LIBS=on . -DFAT_RUNTIME=off -DBUILD_BENCHMARKS=false
  make -j $THREADS all unit install/strip
  ;;
*)
  echo "Error: Arch \"$DETECTED_PLATFORM\" is not supported"
  ;;
esac

cd ../..

mvn -B -Dorg.bytedeco.javacpp.platform=$DETECTED_PLATFORM