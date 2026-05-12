{% from "haproxy/map.jinja" import haproxy with context %}

haproxy-pkg:
  pkg.installed:
    - name: {{ haproxy.pkg }}
