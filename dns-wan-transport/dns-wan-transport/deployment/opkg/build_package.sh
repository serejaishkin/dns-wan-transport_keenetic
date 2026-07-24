#!/bin/sh
set -e

# Настройки путей
PROJECT_ROOT=$(pwd)
BUILD_DIR="${PROJECT_ROOT}/build"
STAGE_DIR="${BUILD_DIR}/ipk_staging"
IPK_NAME="dns-wan-transport_1.0.0-1_mipselsf.ipk"

echo "=== Starting OPKG build process ==="

# 1. Проверяем наличие скомпилированного бинарника
if [ ! -f "${BUILD_DIR}/dns-wan-transport_mipsle" ]; then
    echo "Error: mipsle binary not found! Running 'make mipsle' first..."
    make mipsle
fi

# 2. Очищаем прошлую сборку
rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}/control"
mkdir -p "${STAGE_DIR}/data/opt/bin"
mkdir -p "${STAGE_DIR}/data/opt/etc/dns-wan-transport"
mkdir -p "${STAGE_DIR}/data/opt/etc/init.d"

echo "-> Preparing staging directory..."

# 3. Копируем файлы в структуру данных пакета (data)
cp "${BUILD_DIR}/dns-wan-transport_mipsle" "${STAGE_DIR}/data/opt/bin/dns-wan-transport"
cp "${PROJECT_ROOT}/configs/config.json" "${STAGE_DIR}/data/opt/etc/dns-wan-transport/config.json"
cp "${PROJECT_ROOT}/deployment/init.d/S99dns-wan-transport" "${STAGE_DIR}/data/opt/etc/init.d/S99dns-wan-transport"

# 4. Копируем файлы управления (control)
cp "${PROJECT_ROOT}/deployment/opkg/control" "${STAGE_DIR}/control/control"
cp "${PROJECT_ROOT}/deployment/opkg/postinst" "${STAGE_DIR}/control/postinst"
chmod +x "${STAGE_DIR}/control/postinst"

# 5. Создаем пост-скрипт удаления (postrm) — очистка при деинсталляции
cat << 'POSTRM' > "${STAGE_DIR}/control/postrm"
#!/bin/sh
echo "Removing dns-wan-transport configuration from KeeneticOS..."
if [ -x /opt/bin/ndmc ]; then
    /opt/bin/ndmc -c "interface Proxy0 down" 2>/dev/null || true
    /opt/bin/ndmc -c "no interface Proxy0" 2>/dev/null || true
    /opt/bin/ndmc -c "system configuration save" 2>/dev/null || true
fi
exit 0
POSTRM
chmod +x "${STAGE_DIR}/control/postrm"

# 6. Создаем файл conffiles, чтобы opkg не затирал конфиг при обновлении
echo "/opt/etc/dns-wan-transport/config.json" > "${STAGE_DIR}/control/conffiles"

# 7. Архивация контента
echo "-> Packing control.tar.gz..."
cd "${STAGE_DIR}/control"
tar -czf "${STAGE_DIR}/control.tar.gz" ./*

echo "-> Packing data.tar.gz..."
cd "${STAGE_DIR}/data"
tar -czf "${STAGE_DIR}/data.tar.gz" ./*

# 8. Финальная сборка .ipk (формат ar/tar)
echo "-> Structuring final .ipk file..."
cd "${STAGE_DIR}"
echo "2.0" > debian-binary
tar -czf "${BUILD_DIR}/${IPK_NAME}" ./debian-binary ./control.tar.gz ./data.tar.gz

# Очистка за собой
rm -rf "${STAGE_DIR}"

echo "=== SUCCESS ==="
echo "Package built at: build/${IPK_NAME}"
