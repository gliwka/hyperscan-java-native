#!/bin/bash

# Ensure to exit on all kinds of errors
set -xeu
set -o pipefail

VERSION="5.4.11"
SHA256="905f76ad1fa9e4ae0eb28232cac98afdb96c479666202c5a4c27871fb30a2711"

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

curl -L -o vectorscan-$VERSION.tar.gz https://github.com/VectorCamp/vectorscan/archive/refs/tags/vectorscan/5.4.11.tar.gz
cross_platform_check_sha \
  $SHA256 \
  vectorscan-$VERSION.tar.gz
tar -xvf vectorscan-$VERSION.tar.gz
mv vectorscan-vectorscan-$VERSION vectorscan

curl -L -o boost_1_74_0.tar.gz https://archives.boost.io/release/1.74.0/source/boost_1_74_0.tar.gz
cross_platform_check_sha \
  afff36d392885120bcac079148c177d1f6f7730ec3d47233aa51b0afa4db94a5 \
  boost_1_74_0.tar.gz
tar -zxf boost_1_74_0.tar.gz
mv boost_1_74_0/boost vectorscan/include/boost

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

# Patch correctness regression
patch -p1 < ../../patches/upstream-x86-correctness-regression.patch

# Disable flakey sqlite detection - only needed to build auxillary tools anyways.
> cmake/sqlite3.cmake

case $DETECTED_PLATFORM in
linux-x86_64)
  cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(pwd)/.." -DCMAKE_INSTALL_LIBDIR="lib" -DPCRE_SOURCE="." -DFAT_RUNTIME=on -DBUILD_SHARED_LIBS=on -DBUILD_AVX2=yes -DBUILD_AVX512=yes -DBUILD_AVX512VBMI=yes .
  make -j $THREADS
  make install/strip
  ;;
linux-arm64)
  CC="clang" CXX="clang++" cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(pwd)/.." -DCMAKE_INSTALL_LIBDIR="lib" -DPCRE_SOURCE="." -DFAT_RUNTIME=on -DBUILD_SHARED_LIBS=on .
  make -j $THREADS
  make install/strip
  ;;
macosx-x86_64|macosx-arm64)
  export MACOSX_DEPLOYMENT_TARGET=12
  cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(pwd)/.." -DCMAKE_INSTALL_LIBDIR="lib" -DARCH_OPT_FLAGS='-Wno-error' -DPCRE_SOURCE="." -DBUILD_SHARED_LIBS=on .
  make -j $THREADS
  make install/strip
  ;;
*)
  echo "Error: Arch \"$DETECTED_PLATFORM\" is not supported"
  ;;
esac

cd ../..

# only deploy with deploy command line param
if [ $# -gt 0 ] && [ $1 = "deploy" ]
then
  mvn -B -Dorg.bytedeco.javacpp.platform=$DETECTED_PLATFORM --settings mvnsettings.xml deploy
else
  mvn -B -Dorg.bytedeco.javacpp.platform=$DETECTED_PLATFORM install
fi

