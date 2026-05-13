#!/bin/bash
# copy-plugins.sh — entrypoint wrapper do container GeoServer
#
# Copia os JARs de plugins para WEB-INF/lib antes de iniciar o Tomcat.
# Usa `find` recursivo para capturar JARs em qualquer subdiretório de
# ADDITIONAL_PLUGINS_DIR (community modules e geofence extraem com subpastas).
#
# O path de WEB-INF/lib e o script de startup são auto-descobertos,
# eliminando a dependência de `command:` no docker-compose e de
# CATALINA_HOME estar corretamente definido.
#
# Uso no docker-compose — basta sobrescrever o entrypoint:
#   entrypoint: ["/bin/bash", "/usr/local/bin/copy-plugins.sh"]
#   (NÃO é necessário definir command:)
#
# Variáveis de ambiente opcionais:
#   ADDITIONAL_PLUGINS_DIR — origem dos JARs    (default: /opt/additional_plugins)
#   CATALINA_HOME          — home do Tomcat      (default: auto-descoberto)

SRC_DIR="${ADDITIONAL_PLUGINS_DIR:-/opt/additional_plugins}"

# ----------------------------------------------------------------
# 1. Auto-descobre WEB-INF/lib
# ----------------------------------------------------------------
WEBINF_LIB=""
for CANDIDATE in \
    "${CATALINA_HOME:-__unset__}/webapps/geoserver/WEB-INF/lib" \
    "/usr/local/tomcat/webapps/geoserver/WEB-INF/lib" \
    "/opt/geoserver/webapps/geoserver/WEB-INF/lib" \
    "/opt/tomcat/webapps/geoserver/WEB-INF/lib"; do
    if [ -d "${CANDIDATE}" ]; then
        WEBINF_LIB="${CANDIDATE}"
        break
    fi
done

# ----------------------------------------------------------------
# 2. Copia JARs (recursivo — captura subdiretórios do unarchive)
# ----------------------------------------------------------------
if [ -z "${WEBINF_LIB}" ]; then
    echo "[geoserver-plugins] AVISO: WEB-INF/lib não encontrado — plugins não instalados."
else
    JARS=$(find "${SRC_DIR}" -name "*.jar" 2>/dev/null || true)
    if [ -n "${JARS}" ]; then
        COUNT=$(echo "${JARS}" | wc -l)
        echo "[geoserver-plugins] Instalando ${COUNT} JAR(s) em ${WEBINF_LIB}..."
        echo "${JARS}" | while IFS= read -r jar; do
            cp "${jar}" "${WEBINF_LIB}/" \
                && echo "[geoserver-plugins]   + $(basename "${jar}")" \
                || echo "[geoserver-plugins]   ! falha: $(basename "${jar}")"
        done
    else
        echo "[geoserver-plugins] Nenhum JAR em ${SRC_DIR} — iniciando sem plugins extras."
    fi
fi

# ----------------------------------------------------------------
# 3. GDAL native lib
#
# libgdalalljni.so é necessária para o plugin gs-gdal (ImageI/O-Ext).
# O Ansible distribui o .so pré-compilado para /opt/geoserver/gdal-native/
# (montado em /opt/gdal-native/ no container). Aqui apenas copiamos para
# native-jni-lib, que já está no java.library.path do Tomcat.
# ----------------------------------------------------------------
NATIVE_LIB_DIR="${CATALINA_HOME:-/usr/local/tomcat}/native-jni-lib"
GDAL_SRC="/opt/gdal-native/libgdalalljni.so"
HAS_GDAL_PLUGIN=$(find "${SRC_DIR}" -name "gs-gdal-*.jar" 2>/dev/null | head -1)

if [ -n "${HAS_GDAL_PLUGIN}" ] && [ -d "${NATIVE_LIB_DIR}" ]; then
    if [ -f "${GDAL_SRC}" ]; then
        cp "${GDAL_SRC}" "${NATIVE_LIB_DIR}/libgdalalljni.so" \
            && echo "[geoserver-plugins] GDAL native lib instalada." \
            || echo "[geoserver-plugins] AVISO: falha ao copiar GDAL native lib."
    else
        echo "[geoserver-plugins] AVISO: ${GDAL_SRC} não encontrado — GDAL indisponível."
    fi
fi

# ----------------------------------------------------------------
# 4. Startup: usa $@ se fornecido (override via command:),
#    senão auto-descobre o script de inicialização da imagem.
# ----------------------------------------------------------------
if [ $# -gt 0 ]; then
    exec "$@"
fi

for STARTUP in \
    "/usr/local/bin/startup.sh" \
    "/scripts/start.sh" \
    "/usr/local/bin/start.sh"; do
    if [ -x "${STARTUP}" ]; then
        echo "[geoserver-plugins] Iniciando via ${STARTUP}..."
        exec "${STARTUP}"
    fi
done

# Fallback: catalina.sh run (startup canônico do Tomcat)
CATALINA_SH="${CATALINA_HOME:-/usr/local/tomcat}/bin/catalina.sh"
if [ -x "${CATALINA_SH}" ]; then
    echo "[geoserver-plugins] Iniciando via catalina.sh run..."
    exec "${CATALINA_SH}" run
fi

echo "[geoserver-plugins] ERRO: nenhum script de startup encontrado. Verifique a imagem."
exit 1
