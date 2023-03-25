#!/bin/bash

# Ensure to exit on all kinds of errors
set -xeu
set -o pipefail

VECTORSCAN=5.4.9

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
    linux-x86_64|windows-x86_64) echo $(nproc --all) ;;
    *) echo Unsupported Platform: $DETECTED_PLATFORM >&2 ; exit -1 ;;
  esac
}

cross_platform_check_sha() {
  local sha=$1
  local file=$2
  case $DETECTED_PLATFORM in
    macosx-x86_64|macosx-arm64) echo "$sha  $file" | shasum -a 256 -c ;;
    linux-x86_64|windows-x86_64) echo "$sha  $file" | sha256sum -c ;;
    *) echo Unsupported Platform: $DETECTED_PLATFORM >&2 ; exit -1 ;;
  esac
}

THREADS=$(cross_platform_nproc)

mkdir -p cppbuild/lib
mkdir -p cppbuild/bin
mkdir -p cppbuild/include/hs
cd cppbuild

curl -L -o vectorscan-$VECTORSCAN.tar.gz https://github.com/VectorCamp/vectorscan/archive/refs/tags/vectorscan/$VECTORSCAN.tar.gz
cross_platform_check_sha \
  e61c78f26a9d04ccffab0df1159885c4503fc501172402c57f7357a2126ea3c6 \
  vectorscan-$VECTORSCAN.tar.gz
tar -zxf vectorscan-$VECTORSCAN.tar.gz

curl -L -o boost_1_74_0.tar.gz https://boostorg.jfrog.io/artifactory/main/release/1.74.0/source/boost_1_74_0.tar.gz
cross_platform_check_sha \
  afff36d392885120bcac079148c177d1f6f7730ec3d47233aa51b0afa4db94a5 \
  boost_1_74_0.tar.gz
tar -zxf boost_1_74_0.tar.gz
mv boost_1_74_0/boost vectorscan-vectorscan-$VECTORSCAN/include/boost

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

cd vectorscan-vectorscan-$VECTORSCAN

case $DETECTED_PLATFORM in
linux-x86_64)
  CFLAGS='-O -fPIC' CC="gcc" CXX="g++ -std=c++11 -m64 -fPIC" cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(pwd)/.." -DCMAKE_INSTALL_LIBDIR="lib" -DPCRE_SOURCE="." .
  make -j $THREADS hs hs_runtime hs_compile
  make install/strip
  ;;
macosx-x86_64)
  cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(pwd)/.." -DCMAKE_INSTALL_LIBDIR="lib" -DARCH_OPT_FLAGS='-Wno-error' -DPCRE_SOURCE="." .
  make -j $THREADS hs hs_runtime hs_compile
  make install/strip
  ;;
macosx-arm64)
  CFLAGS="-target arm64-apple-macos11" CXXFLAGS="-target arm64-apple-macos11" cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(pwd)/.." -DCMAKE_INSTALL_LIBDIR="lib" -DARCH_OPT_FLAGS='-Wno-error' -DPCRE_SOURCE="." .
  make -j $THREADS hs hs_runtime hs_compile
  make install/strip
  ;;
windows-x86_64)
  unset TEMP TMP # temp is defined in uppercase by bash and lowercase by windows, which causes problems with cmake + msbuild
  CXXFLAGS="/Wv:17" cmake -G "Visual Studio 16 2019" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(pwd)/.." -DCMAKE_INSTALL_LIBDIR="lib" -DARCH_OPT_FLAGS='' -DPCRE_SOURCE="." .
  MSBuild.exe hyperscan.sln //p:Configuration=Release //p:Platform=x64
  cp -r src/* ../include/hs/
  cp lib/*.lib ../lib
  ;;
*)
  echo "Error: Arch \"$DETECTED_PLATFORM\" is not supported"
  ;;
esac

cd ../..

# only deploy with deploy command line param on master with clean working area
if [ $# -gt 0 ] && [ $1 = "deploy" ] && [ "$(git symbolic-ref HEAD)" = "refs/heads/main" ] && [ -z "$(git status --porcelain)" ]
then
  mvn -B -Dorg.bytedeco.javacpp.platform=$DETECTED_PLATFORM --settings mvnsettings.xml deploy
else
  mvn -B -Dorg.bytedeco.javacpp.platform=$DETECTED_PLATFORM install
fi