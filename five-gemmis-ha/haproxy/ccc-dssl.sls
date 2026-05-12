{%- set role = salt['pillar.get']('server:roles', 'pushnode-haproxy') %}
{%- set cfg_dir = salt['pillar.get']('server:haproxy:cfg_dir', 'template') %}
{%- set distro = grains.lsb_distrib_codename %}
{%- set os_version = grains.osrelease %}
{%- set state_dir = '/etc/haproxy/state' %}

{% if salt['pillar.get']('server:haproxy:ssl', False ) %}
/etc/haproxy/ha_ssl:
  file.recurse:
    - source: salt://haproxy/config/{{ cfg_dir }}/ssl
    - user: root
    - group: root
    - include_empty: True
    - file_mode: 644
    - dir_mode: 755
    - include_pat: E@.pem$
    - clean: True
    - makedirs: True
{% endif %}

haproxy_debug:
  cmd.run:
    - name: haproxy -f "/etc/haproxy/haproxy.cfg" -c -dr


haproxy:
  service.running:
    - enable: True
    - reload: True
    - watch:
      - file: /etc/haproxy/ha_ssl*
    - require:
      - cmd: haproxy_debug




