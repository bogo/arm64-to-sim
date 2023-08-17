#!/bin/sh

echo "Please add the framework you want to add arm64-simulator"
read FRAMEWORK_PATH
if [ ! -e $FRAMEWORK ]; then
    echo "The file does not exist. Please try again"
    exit
fi

FRAMEWORK_EXTENSION="${FRAMEWORK_PATH##*.}"
BASE_NAME=`basename $FRAMEWORK_PATH`
FRAMEWORK_NAME="${BASE_NAME%.*}"

if [ ! $FRAMEWORK_EXTENSION = "framework" ]; then
    echo "The file is not a framework. Please check again."
    exit
fi

# https://github.com/bogo/arm64-to-sim
if [ ! -d arm64-to-sim ]; then
    git clone https://github.com/bogo/arm64-to-sim
fi

cd arm64-to-sim
swift build -c release --arch arm64 --arch x86_64

cd .build/apple/Products/Release/

TOOL_PATH=$(pwd)/arm64-to-sim
cd ${FRAMEWORK_PATH}/..
mkdir ${FRAMEWORK_NAME}-reworked
REWORKED_PATH=$(pwd)/${FRAMEWORK_NAME}-reworked

echo "필요한 요소 출력"
echo "프레임워크 이름: ${FRAMEWORK_NAME}"
echo "프레임워크 위치: ${FRAMEWORK_PATH}"
echo "TOOOOOL 위치: ${TOOL_PATH}"
echo "REWORKED 위치: ${REWORKED_PATH}"

lipo -thin arm64 ${FRAMEWORK_PATH}/${FRAMEWORK_NAME} -output ${REWORKED_PATH}/${FRAMEWORK_NAME}.arm64

cd ${REWORKED_PATH}
ar x ${REWORKED_PATH}/${FRAMEWORK_NAME}.arm64

for file in *.o; do ${TOOL_PATH} $file; done;
ar crv ${FRAMEWORK_NAME}.arm64 *.o

mv ${FRAMEWORK_NAME}.arm64 ../${FRAMEWORK_NAME}.arm64
cd ..
rm -rf ${FRAMEWORK_NAME}-reworked

lipo -remove arm64 ${FRAMEWORK_PATH}/${FRAMEWORK_NAME} -o ${FRAMEWORK_NAME}-remove
lipo -create -output ${FRAMEWORK_NAME} ${FRAMEWORK_NAME}.arm64 ${FRAMEWORK_NAME}-remove
cp -R ${FRAMEWORK_NAME}.${FRAMEWORK_EXTENSION} ${FRAMEWORK_NAME}-simul.${FRAMEWORK_EXTENSION}

rm -rf ${FRAMEWORK_NAME}-simul.framework/${FRAMEWORK_NAME}
mv ${FRAMEWORK_NAME} ${FRAMEWORK_NAME}-simul.framework/${FRAMEWORK_NAME}

rm -rf ${FRAMEWORK_NAME}-remove
rm -rf ${FRAMEWORK_NAME}.arm64

file ${FRAMEWORK_NAME}-simul.${FRAMEWORK_EXTENSION}/${FRAMEWORK_NAME}
