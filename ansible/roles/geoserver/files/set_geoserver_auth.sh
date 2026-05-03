#!/bin/bash
# set_geoserver_auth.sh — versão corrigida
#
# Diferença em relação ao original da imagem:
#   REMOVIDA a linha `echo " " >> "$auth_conf_source"` que adicionava
#   uma linha em branco no final dos arquivos XML. Esse trailing whitespace
#   causava java.io.EOFException no XStream ao carregar as configurações
#   de segurança do GeoServer durante a autenticação OAuth2.
#
# Todos os demais comportamentos são idênticos ao original.

auth_conf_source="$1"
auth_conf_target="$2"
temp_file="xml.tmp"
touch $temp_file
source /root/.bashrc
source /root/.override_env
test -z "$auth_conf_source" && echo "You must specify a source file" && exit 1
test -z "$auth_conf_target" && echo "You must specify a target conf directory" && exit 1
test ! -f "$auth_conf_source" && echo "Source $auth_conf_source does not exist or is not a file" && exit 1
test ! -d "$auth_conf_target" && echo "Target directory $auth_conf_target does not exist or is not a directory" && exit 1

echo -e "OAUTH2_API_KEY=$OAUTH2_API_KEY\n"
echo -e "OAUTH2_CLIENT_ID=$OAUTH2_CLIENT_ID\n"
echo -e "OAUTH2_CLIENT_SECRET=$OAUTH2_CLIENT_SECRET\n"
echo -e "GEOSERVER_LOCATION=$GEOSERVER_LOCATION\n"
echo -e "GEONODE_LOCATION=$GEONODE_LOCATION\n"
echo -e "GEONODE_GEODATABASE=$GEONODE_GEODATABASE\n"
echo -e "GEONODE_GEODATABASE_USER=$GEONODE_GEODATABASE_USER\n"
echo -e "GEONODE_GEODATABASE_PASSWORD=$GEONODE_GEODATABASE_PASSWORD\n"
echo -e "auth_conf_source=$auth_conf_source\n"
echo -e "auth_conf_target=$auth_conf_target\n"

# LINHA REMOVIDA: echo " " >> "$auth_conf_source"
# O original adicionava uma linha em branco aqui para "ajudar" o sed
# a encontrar a última linha, mas causava EOF no XStream do GeoServer.

cat "$auth_conf_source"
tagname=( ${@:3:7} )

for i in "${tagname[@]}"
do
   echo "tagname=<$i>"
done
echo "DEBUG: Starting... [Ok]\n"

for i in "${tagname[@]}"
do
    echo "DEBUG: Working on '$auth_conf_source' for tagname <$i>"
    tagvalue=`grep "<$i>.*<.$i>" "$auth_conf_source" | sed -e "s/^.*<$i/<$i/" | cut -f2 -d">"| cut -f1 -d"<"`
    echo "DEBUG: Found the current value for the element <$i> - '$tagvalue'"
    case $i in
        authApiKey)
            echo "DEBUG: Editing '$auth_conf_source' for tagname <$i> and replacing its value with '$OAUTH2_API_KEY'"
            newvalue=`echo -ne "$tagvalue" | sed -re "s@.*@$OAUTH2_API_KEY@"`;;
        cliendId)
            echo "DEBUG: Editing '$auth_conf_source' for tagname <$i> and replacing its value with '$OAUTH2_CLIENT_ID'"
            newvalue=`echo -ne "$tagvalue" | sed -re "s@.*@$OAUTH2_CLIENT_ID@"`;;
        clientSecret)
            echo "DEBUG: Editing '$auth_conf_source' for tagname <$i> and replacing its value with '$OAUTH2_CLIENT_SECRET'"
            newvalue=`echo -ne "$tagvalue" | sed -re "s@.*@$OAUTH2_CLIENT_SECRET@"`;;
        proxyBaseUrl | redirectUri | userAuthorizationUri | logoutUri )
            echo "DEBUG: Editing '$auth_conf_source' for tagname <$i> and replacing its value with '$GEOSERVER_LOCATION'"
            newvalue=`echo -ne "$tagvalue" | sed -re "s@^(https?://[^/]+)@${GEOSERVER_LOCATION%/}@"`;;
        baseUrl | accessTokenUri | checkTokenEndpointUrl )
            echo "DEBUG: Editing '$auth_conf_source' for tagname <$i> and replacing its value with '$GEONODE_LOCATION'"
            newvalue=`echo -ne "$tagvalue" | sed -re "s@^(https?://[^/]+)@${GEONODE_LOCATION%/}@"`;;
        *) echo -n "an unknown variable has been found";;
    esac
    echo "DEBUG: Found the new value for the element <$i> - '$newvalue'"
    sed -e "s@<$i>$tagvalue<\/$i>@<$i>$newvalue<\/$i>@g" "$auth_conf_source" > "$temp_file"
    cp "$temp_file" "$auth_conf_source"
done

echo "DEBUG: Finished... [Ok] --- Final xml file is \n"
cat "$auth_conf_source"
