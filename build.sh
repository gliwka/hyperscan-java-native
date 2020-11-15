#!/bin/bash

# Ensure to exit on all kinds of errors
set -xeu
set -o pipefail

THREADS=$(nproc --all)

mkdir -p target/lib
mkdir -p target/include/hs
cd target

git clone -b v5.3.0 --depth 1 https://github.com/intel/hyperscan.git

curl -LOJ https://dl.bintray.com/boostorg/release/1.65.1/source/boost_1_65_1.tar.gz
tar -zxf boost_1_65_1.tar.gz
mv boost_1_65_1/boost hyperscan/include/boost

curl -LOJ https://www.colm.net/files/ragel/ragel-6.10.tar.gz
tar -zxf ragel-6.10.tar.gz
cd ragel-6.10
./configure
make -j $THREADS
make install
cd ..

cd hyperscan

case $OS_ARCH in
linux-x86_64)
  CFLAGS='-O -fPIC' CC="gcc" CXX="g++ -std=c++11 -m64 -fPIC" cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(pwd)/.." -DCMAKE_INSTALL_LIBDIR="lib" .
  make -j $THREADS
  make install/strip
  ;;
macosx-x86_64)
  cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(pwd)/.." -DCMAKE_INSTALL_LIBDIR="lib" -DARCH_OPT_FLAGS='-Wno-error' .
  make -j $THREADS
  make install/strip
  ;;
windows-x86_64)
  unset TEMP TMP # temp is defined in uppercase by bash and lowercase by windows, which causes problems with cmake + msbuild
  CXXFLAGS="/Wv:17" cmake -G "Visual Studio 16 2019" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(pwd)/.." -DCMAKE_INSTALL_LIBDIR="lib" -DARCH_OPT_FLAGS='' .
  MSBuild.exe hyperscan.sln //p:Configuration=Release //p:Platform=x64
  cp -r src/* ../include/hs/
  cp lib/*.lib ../lib
  ;;
*)
  echo "Error: Arch \"$OS_ARCH\" is not supported"
  ;;
esac
