#!/bin/bash

# Ensure to exit on all kinds of errors
set -xeu
set -o pipefail

HYPERSCAN=5.4.0

detect_platform() {
  # use os-maven-plugin to detect platform
  local platform=$(mvn help:evaluate -Dexpression=os.detected.classifier -q -DforceStdout)
  # fix value for macos: plugin outputs osx, but JavaCPP needs it to be macosx
  if [[ $platform == osx-* ]]
  then
    echo mac$platform
  else
    echo $platform
  fi
}

export DETECTED_PLATFORM=$(detect_platform)

THREADS=$(nproc --all)

mkdir -p cppbuild/lib
mkdir -p cppbuild/include/hs
cd cppbuild

# -OJ doesn't work on old centos, so we have to be verbose
curl -L -o hyperscan-$HYPERSCAN.tar.gz https://github.com/intel/hyperscan/archive/v$HYPERSCAN.tar.gz
echo "e51aba39af47e3901062852e5004d127fa7763b5dbbc16bcca4265243ffa106f  hyperscan-$HYPERSCAN.tar.gz" | sha256sum -c
tar -zxf hyperscan-$HYPERSCAN.tar.gz

curl -L -o boost_1_74_0.tar.gz https://dl.bintray.com/boostorg/release/1.74.0/source/boost_1_74_0.tar.gz
echo "afff36d392885120bcac079148c177d1f6f7730ec3d47233aa51b0afa4db94a5  boost_1_74_0.tar.gz" | sha256sum -c
tar -zxf boost_1_74_0.tar.gz
mv boost_1_74_0/boost hyperscan-$HYPERSCAN/include/boost

curl -L -o ragel-6.10.tar.gz https://www.colm.net/files/ragel/ragel-6.10.tar.gz
echo "5f156edb65d20b856d638dd9ee2dfb43285914d9aa2b6ec779dac0270cd56c3f  ragel-6.10.tar.gz" | sha256sum -c

tar -zxf ragel-6.10.tar.gz
cd ragel-6.10
./configure
make -j $THREADS
make install
cd ..

cd hyperscan-$HYPERSCAN

case $OS_ARCH in
ubuntu-latest-x86_64)
  CFLAGS='-O -fPIC' CC="gcc" CXX="g++ -std=c++11 -m64 -fPIC" cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(pwd)/.." -DCMAKE_INSTALL_LIBDIR="lib" .
  make -j $THREADS
  make install/strip
  ;;
macos-latest-x86_64)
  cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(pwd)/.." -DCMAKE_INSTALL_LIBDIR="lib" -DARCH_OPT_FLAGS='-Wno-error' .
  make -j $THREADS
  make install/strip
  ;;
windows-latest-x86_64)
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

cd ../..

mvn -B --settings mvnsettings.xml deploy
