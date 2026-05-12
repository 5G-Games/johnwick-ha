{% if salt['pillar.get']('server:haproxy:node_exporter', False) %}
{% set version = '1.10.2' %}
{% set node_exporter_src = 'node_exporter-' ~ version ~ '.linux-amd64' %}

node-exporter-tarball:
  file.managed:
    - name: /usr/local/src/{{ node_exporter_src }}.tar.gz
    - source: salt://haproxy/packages/{{ node_exporter_src }}.tar.gz
    - user: root
    - group: root
    - mode: "0644"

node-exporter-extract-and-install:
  cmd.run:
    - name: |
        cd /usr/local/src && tar xvf {{ node_exporter_src }}.tar.gz
        mv {{ node_exporter_src }}/node_exporter /usr/local/bin/
    - onchanges:
      - file: node-exporter-tarball

node-exporter-service-file:
  file.managed:
    - name: /etc/systemd/system/node_exporter.service
    - source: salt://haproxy/files/node_exporter.service.jinja
    - user: root
    - group: root
    - mode: "0644"

node-exporter-systemd-reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: node-exporter-service-file

node-exporter-service:
  service.running:
    - name: node_exporter
    - enable: True
    - watch:
      - file: node-exporter-service-file
    - require:
      - cmd: node-exporter-extract-and-install
{% endif %}
