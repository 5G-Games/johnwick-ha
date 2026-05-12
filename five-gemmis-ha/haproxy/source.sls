{% from "haproxy/map.jinja" import haproxy with context %}

{% set version = haproxy.get('version', '3.2.4') %}
{% set source_dir = '/usr/local/src' %}
{% set install_dir = '/usr/local' %}
{% set haproxy_src = 'haproxy-' ~ version %}

haproxy-source-deps:
  pkg.installed:
    - pkgs: {{ haproxy.source_deps }}

haproxy-user-group:
  group.present:
    - name: {{ haproxy.group }}
    - system: True
  user.present:
    - name: {{ haproxy.user }}
    - gid: {{ haproxy.group }}
    - system: True
    - shell: /usr/sbin/nologin
    - home: /var/lib/haproxy

haproxy-download:
  file.managed:
    - name: {{ source_dir }}/{{ haproxy_src }}.tar.gz
    - source: salt://haproxy/packages/{{ haproxy_src }}.tar.gz
    - user: root
    - group: root
    - mode: "0644"
    - makedirs: True

haproxy-extract:
  cmd.run:
    - name: tar zxf {{ haproxy_src }}.tar.gz
    - cwd: {{ source_dir }}
    - creates: {{ source_dir }}/{{ haproxy_src }}
    - require:
      - file: haproxy-download

haproxy-build-install:
  cmd.run:
    - name: |
        make -j$(nproc) TARGET=linux-glibc \
             USE_PCRE2=1 USE_PCRE2_JIT=1 \
             USE_OPENSSL=1 USE_ZLIB=1 USE_LUA=1 \
            {%- if salt['pillar.get']('server:haproxy:promexporter', False ) == True %}
                USE_PROMEX=1 \
            {%- endif %}
             {{ haproxy.get('extra_build_args', '') }}
        make install
    - cwd: {{ source_dir }}/{{ haproxy_src }}
    - onchanges:
      - cmd: haproxy-extract
    - require:
      - pkg: haproxy-source-deps

# Ensure the binary is in a standard path if needed
haproxy-symlink:
  file.symlink:
    - name: /usr/sbin/haproxy
    - target: {{ install_dir }}/sbin/haproxy
    - force: True
    - require:
      - cmd: haproxy-build-install

# Create config directory
haproxy-config-dir:
  file.directory:
    - name: {{ haproxy.config_dir }}
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
