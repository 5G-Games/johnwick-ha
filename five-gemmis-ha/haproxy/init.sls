{% from "haproxy/map.jinja" import haproxy with context %}

include:
  {% if haproxy.is_source_install %}
  - haproxy.clean
  - haproxy.source
  {% else %}
  - haproxy.install
  {% endif %}
  - haproxy.ccc-dconfig
  - haproxy.disable-auto-upgrades
  {% if salt['pillar.get']('server:haproxy:node_exporter', False) %}
  - haproxy.node_exporter
  {% endif %}
