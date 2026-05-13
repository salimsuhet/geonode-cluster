# libgdalalljni.so — GDAL Native Library para GeoServer

## Contexto

O plugin **ImageI/O-Ext GDAL Coverage Extension** (`gs-gdal`) do GeoServer requer a biblioteca
nativa `libgdalalljni.so` no `java.library.path` do Tomcat para habilitar suporte a formatos
raster proprietários como ECW, MrSID, HDF4/5, DTED e JPEG2000 via GDAL.

### Por que compilar manualmente?

O pacote `libgdal-java` foi **removido do Ubuntu 22.04 (Jammy)**. A imagem base do GeoServer
(`geonode/geoserver:2.27.4-latest`) é Ubuntu 22.04 e possui `libgdal30` (GDAL 3.4.1), mas sem
os bindings Java. As alternativas avaliadas foram:

| Fonte | Resultado |
|---|---|
| `apt install libgdal-java` (Ubuntu 22.04) | ❌ Pacote não existe |
| `apt install libgdal-java` (ubuntugis PPA) | ❌ Pacote não existe |
| Debian Bookworm `libgdal-java` (.deb) | ❌ Linka contra `libgdal.so.32` — incompatível com `libgdal.so.30` |
| Maven / imageio-ext bindings JAR | ❌ JAR não contém lib nativa para Linux |
| `gdal_wrap.cpp` no repositório Git do GDAL | ❌ Arquivo não commitado — gerado pelo SWIG |
| `gdal_wrap.cpp` no tarball de release OSGeo | ❌ Apenas wrappers Python e Perl incluídos |
| Compilar com SWIG a partir do fonte | ✅ Compatível — mesma versão GDAL do container |

---

## Arquivo pré-compilado

O arquivo `libgdalalljni.so` neste diretório foi compilado para:

- **OS:** Ubuntu 22.04 LTS (Jammy Jellyfish) — x86_64
- **GDAL:** 3.4.1 (`libgdal.so.30`) — mesmo que `geonode/geoserver:2.27.4-latest`
- **JDK:** OpenJDK 11 headless
- **SWIG:** 4.0.2

O Ansible distribui este arquivo para todos os hosts GeoServer via a task
`Copia libgdalalljni.so pré-compilada para o host` em `roles/geoserver/tasks/main.yml`.
Em runtime, o `copy-plugins.sh` (entrypoint wrapper do container) copia o arquivo de
`/opt/geoserver/gdal-native/` para `/usr/local/tomcat/native-jni-lib/`, que já está
no `java.library.path` do Tomcat.

---

## Como recompilar

Necessário quando a **versão do GDAL no container mudar** (ex: upgrade da imagem
`geonode/geoserver` que atualize `libgdal30` para uma versão maior).

### Pré-requisitos

- Docker Desktop instalado localmente
- Proxy configurado em **Docker Desktop → Settings → Resources → Proxies** (se necessário)

### Comando único

Execute a partir da **raiz do repositório**. O container compila e se auto-remove; o `.so`
é extraído via `docker cp` antes da remoção.

> Se o proxy corporativo interceptar HTTPS com certificado próprio, o script já inclui
> o workaround de verificação SSL do apt e o `-k` no curl.

```bash
docker run --name gdal-build ubuntu:22.04 bash -c '
  # Workaround proxy SSL corporativo
  echo "Acquire::https::Verify-Peer \"false\";" > /etc/apt/apt.conf.d/99no-verify &&
  echo "Acquire::https::Verify-Host \"false\";" >> /etc/apt/apt.conf.d/99no-verify &&
  echo "Acquire::AllowInsecureRepositories \"true\";" >> /etc/apt/apt.conf.d/99no-verify &&
  echo "Acquire::AllowDowngradeToInsecureRepositories \"true\";" >> /etc/apt/apt.conf.d/99no-verify &&

  # Dependências de build
  apt-get update &&
  apt-get install -y --no-install-recommends libgdal-dev g++ openjdk-11-jdk-headless swig curl &&

  # Versão GDAL instalada no container
  GDAL_VER=$(gdal-config --version) &&
  echo "Compilando para GDAL ${GDAL_VER}..." &&

  # Fonte GDAL (tarball OSGeo — único lugar com os arquivos .i para geração SWIG)
  curl -k -L "https://download.osgeo.org/gdal/${GDAL_VER}/gdal-${GDAL_VER}.tar.gz" \
       -o /tmp/gdal.tar.gz &&
  tar -xzf /tmp/gdal.tar.gz -C /tmp/ &&

  # Geração dos 5 wrappers SWIG (gdal, gdalconst, ogr, osr, gnm)
  cd /tmp/gdal-${GDAL_VER}/swig/java &&
  mkdir -p org/gdal/gdal org/gdal/gdalconst org/gdal/ogr org/gdal/osr org/gdal/gnm &&
  ARGS="-Wall -I../include -I../include/java -I../include/java/docs -I/tmp/gdal-${GDAL_VER}" &&

  swig ${ARGS} -c++ -java -outdir org/gdal/gdal      -package org.gdal.gdal      -o gdal_wrap.cpp    ../include/gdal.i &&
  swig ${ARGS}       -java -outdir org/gdal/gdalconst -package org.gdal.gdalconst -o gdalconst_wrap.c ../include/gdalconst.i &&
  swig ${ARGS} -c++ -java -outdir org/gdal/ogr       -package org.gdal.ogr       -o ogr_wrap.cpp     ../include/ogr.i &&
  swig ${ARGS} -c++ -java -outdir org/gdal/osr       -package org.gdal.osr       -o osr_wrap.cpp     ../include/osr.i &&
  swig ${ARGS} -c++ -java -outdir org/gdal/gnm       -package org.gdal.gnm       -o gnm_wrap.cpp     ../include/gnm.i &&

  # Compilação — gdalconst_wrap.c é C puro: usa gcc; demais são C++: usa g++
  JDK=/usr/lib/jvm/java-11-openjdk-amd64 &&
  CFLAGS="-fPIC -I${JDK}/include -I${JDK}/include/linux $(gdal-config --cflags)" &&

  gcc -c ${CFLAGS} -o gdalconst_wrap.o gdalconst_wrap.c &&
  g++ -c ${CFLAGS} -o gdal_wrap.o      gdal_wrap.cpp    &&
  g++ -c ${CFLAGS} -o ogr_wrap.o       ogr_wrap.cpp     &&
  g++ -c ${CFLAGS} -o osr_wrap.o       osr_wrap.cpp     &&
  g++ -c ${CFLAGS} -o gnm_wrap.o       gnm_wrap.cpp     &&

  g++ -shared -fPIC -o libgdalalljni.so \
      gdal_wrap.o gdalconst_wrap.o ogr_wrap.o osr_wrap.o gnm_wrap.o \
      $(gdal-config --libs) &&

  ls -lh libgdalalljni.so &&
  echo COMPILADO_OK
' && \
docker cp gdal-build:/tmp/gdal-3.4.1/swig/java/libgdalalljni.so \
    ansible/roles/geoserver/files/libgdalalljni.so && \
docker rm gdal-build && \
file ansible/roles/geoserver/files/libgdalalljni.so
```

### Commit

```bash
git add ansible/roles/geoserver/files/libgdalalljni.so \
        ansible/roles/geoserver/files/GDAL_NATIVE_LIB.md
git commit -m "chore: recompila libgdalalljni.so para GDAL 3.4.1 (Ubuntu 22.04 x86_64)"
```

Após o commit, rode `make ansible-tag TAG=geoserver` para distribuir aos hosts.

---

## Referências

- [GDAL source releases — download.osgeo.org](https://download.osgeo.org/gdal/)
- [GDAL SWIG Java bindings — swig/java/](https://github.com/OSGeo/gdal/tree/v3.4.1/swig/java)
- [imageio-ext GDAL Framework](https://github.com/geosolutions-it/imageio-ext)
- [GeoServer GDAL Extension](https://docs.geoserver.org/stable/en/user/data/raster/gdal.html)
- [GDAL Download — Linux](https://gdal.org/en/stable/download.html#linux)
- [OSGeo GDAL Docker images](https://github.com/OSGeo/gdal/pkgs/container/gdal)
