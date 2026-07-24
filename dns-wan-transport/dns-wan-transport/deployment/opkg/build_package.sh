#!/bin/sh
set -e

PROJECT_ROOT=$(pwd)
BUILD_DIR="${PROJECT_ROOT}/build"
STAGE_DIR="${BUILD_DIR}/ipk_staging"
IPK_NAME="dns-wan-transport_1.0.4_all.ipk"

echo "=== Starting OPKG build process ==="

if [ ! -f "${BUILD_DIR}/dns-wan-transport_mipsle" ]; then
    echo "-> Running 'make mipsle'..."
    make mipsle
fi

rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}/control"
mkdir -p "${STAGE_DIR}/data/opt/bin"
mkdir -p "${STAGE_DIR}/data/opt/etc/dns-wan-transport"
mkdir -p "${STAGE_DIR}/data/opt/etc/init.d"

cp "${BUILD_DIR}/dns-wan-transport_mipsle" "${STAGE_DIR}/data/opt/bin/dns-wan-transport"
cp "${PROJECT_ROOT}/configs/config.json" "${STAGE_DIR}/data/opt/etc/dns-wan-transport/config.json"
cp "${PROJECT_ROOT}/deployment/init.d/S99dns-wan-transport" "${STAGE_DIR}/data/opt/etc/init.d/S99dns-wan-transport"

cp "${PROJECT_ROOT}/deployment/opkg/control" "${STAGE_DIR}/control/control"
cp "${PROJECT_ROOT}/deployment/opkg/postinst" "${STAGE_DIR}/control/postinst"
cp "${PROJECT_ROOT}/deployment/opkg/postrm" "${STAGE_DIR}/control/postrm"

chmod +x "${STAGE_DIR}/control/postinst"
chmod +x "${STAGE_DIR}/control/postrm"

echo "/opt/etc/dns-wan-transport/config.json" > "${STAGE_DIR}/control/conffiles"

echo "-> Packing control.tar.gz..."
cd "${STAGE_DIR}/control"
tar -czf "${STAGE_DIR}/control.tar.gz" ./*

echo "-> Packing data.tar.gz..."
cd "${STAGE_DIR}/data"
tar -czf "${STAGE_DIR}/data.tar.gz" ./*

echo "-> Structuring final .ipk file..."
cd "${STAGE_DIR}"
echo "2.0" > debian-binary
tar -czf "${BUILD_DIR}/${IPK_NAME}" ./debian-binary ./control.tar.gz ./data.tar.gz

rm -rf "${STAGE_DIR}"

echo "=== SUCCESS ==="
echo "Package built at: build/${IPK_NAME}"
