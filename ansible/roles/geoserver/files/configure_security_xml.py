#!/usr/bin/env python3
"""
configure_security_xml.py — Ajusta o security/config.xml do GeoServer para OAuth2.

Saída: "changed" | "ok"

Alterações mínimas (alinhadas com o comportamento da imagem de referência):
  1. webLogin: adiciona geonode-oauth2 (para o botão de login iniciar o fluxo)
  2. webLogin: allowSessionCreation=true (para salvar token na sessão após login)
  3. webLogin: exceptionTranslationName=exception (para UserRedirectRequiredException
     ser tratada e redirecionar para o GeoNode corretamente)
  4. webLogout: adiciona geonode-oauth2
"""

import sys
import re


def has_filter_in_chain(content, chain_name, filter_name):
    pattern = r'name="{}"[^>]*>(.*?)</filters>'.format(chain_name)
    match = re.search(pattern, content, re.DOTALL)
    if match:
        return '<filter>{}</filter>'.format(filter_name) in match.group(1)
    return False


def insert_filter_in_chain(content, chain_name, filter_name):
    pattern = r'(name="{}"[^>]*>)'.format(chain_name)
    replacement = r'\1\n      <filter>{}</filter>'.format(filter_name)
    return re.sub(pattern, replacement, content, count=1)


def main():
    path = sys.argv[1]
    with open(path, 'r') as f:
        original = f.read()

    content = original

    # 1. webLogin: geonode-oauth2
    if not has_filter_in_chain(content, 'webLogin', 'geonode-oauth2'):
        content = insert_filter_in_chain(content, 'webLogin', 'geonode-oauth2')

    # 2. webLogin: allowSessionCreation=true
    content = re.sub(
        r'(name="webLogin"[^>]*allowSessionCreation=")false(")',
        r'\1true\2',
        content
    )

    # 3. webLogin: exceptionTranslationName=exception
    def add_exception_translation(m):
        tag = m.group(0)
        if 'exceptionTranslationName' not in tag:
            tag = tag.rstrip('>')
            tag += ' exceptionTranslationName="exception">'
        return tag

    content = re.sub(
        r'<filters name="webLogin"[^>]*>',
        add_exception_translation,
        content
    )

    # 4. webLogout: geonode-oauth2
    if not has_filter_in_chain(content, 'webLogout', 'geonode-oauth2'):
        content = insert_filter_in_chain(content, 'webLogout', 'geonode-oauth2')

    if content != original:
        with open(path, 'w') as f:
            f.write(content)
        print("changed")
    else:
        print("ok")


if __name__ == '__main__':
    main()
