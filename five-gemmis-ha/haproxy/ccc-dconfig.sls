{%- set role = salt['pillar.get']('server:roles', 'webdev') %}
{%- set cfg_dir = salt['pillar.get']('server:haproxy:cfg_dir', 'webdev') %}
{%- set distro = grains.lsb_distrib_codename %}
{%- set os_version = grains.osrelease %}
{%- set state_dir = '/etc/haproxy/state' %}

pkg-init:
  pkg.installed:
    - names:
      - logrotate
      
{{ state_dir }}:
  file:
    - user: haproxy
    - group: haproxy
    - mode: 644
    - directory
    - makedirs: True

rsyslog-config:
  file:
    - managed
    - name: /etc/rsyslog.d/49-haproxy.conf
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - source: salt://haproxy/files/rsyslog.d-haproxy

/etc/rsyslog.d/50-default.conf:
  file:
    - replace
    - pattern: 'authpriv.none'
    - repl: 'authpriv,local0,local1.none'
    - ignore_if_missing: True

create-haproxy-log-files:
  file.managed:
    - names:
      - /var/log/haproxy_0.log
      - /var/log/haproxy_allbutinfo.log
      - /var/log/frontend_ssl_handshake_failure.log
    - user: syslog
    - group: adm
    - mode: 640
    - replace: False
    - require_in:
      - service: rsyslog

rsyslog:
  service.running:
    - watch:
      - file: /etc/rsyslog.d/49-haproxy.conf
      - file: /etc/rsyslog.d/50-default.conf

logrotate-config:
  file:
    - managed
    - name: /etc/logrotate.d/haproxy
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - source: salt://haproxy/files/logrotate.d-haproxy
    - require:
      - pkg: logrotate

haproxy-service:
  file:
    - managed
    - name: /lib/systemd/system/haproxy.service
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - source: salt://haproxy/templates/haproxy.service.jinja

haproxy-deploy-config:
  file:
    - managed
    - name: /etc/haproxy/haproxy.cfg
    - template: jinja
    - user: haproxy
    - group: haproxy
    - mode: 644
{% if salt['pillar.get']('server:haproxy:role') == 'ha-gs' %}
    - source: salt://haproxy/config/{{ cfg_dir }}/haproxy.gs.jinja
{% elif salt['pillar.get']('server:haproxy:role') == 'ha-dev' %}
    - source: salt://haproxy/config/{{ cfg_dir }}/haproxy.dev.jinja
{% elif salt['pillar.get']('server:haproxy:role') == 'ha-std' %}
    - source: salt://haproxy/config/{{ cfg_dir }}/haproxy.std.jinja         
{% endif %}
    - makedirs: True

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

{% if salt['pillar.get']('server:haproxy:whitelist', False ) %}
haproxy-deploy-whitelist-ips:
  file:
    - managed
    - name: /etc/haproxy/whitelist-ips
    - template: jinja
    - user: haproxy
    - group: haproxy
    - mode: 644
    - source: salt://haproxy/config/{{ cfg_dir }}/whitelist-ips
    - makedirs: True

/etc/haproxy/whitelist:
  file.recurse:
    - source: salt://haproxy/config/{{ cfg_dir }}/whitelist
    - user: root
    - group: root
    - file_mode: 644
    - dir_mode: 755
    - include_pat: 'E@.(list|jpeg|jpg|png|gif|ico)$'
    - makedirs: True
{% endif %}

{% if salt['pillar.get']('server:haproxy:host_map', False ) %}
/etc/haproxy/hosts.map:
  file.managed:
    - template: jinja
    - user: haproxy
    - group: haproxy
    - mode: 644
    - source: salt://haproxy/config/{{ cfg_dir }}/hosts.map
    - makedirs: True

/etc/haproxy/hostmap:
  file.recurse:
    - source: salt://haproxy/config/{{ cfg_dir }}/hostmap
    - user: haproxy
    - group: haproxy
    - include_empty: True
    - file_mode: 644
    - dir_mode: 755
    - clean: True
    - include_pat: E@.map$
    - makedirs: True
{% endif %}

{% if salt['pillar.get']('server:haproxy:html_static', False ) %}
/etc/haproxy/html_static:
  file.recurse:
    - source: salt://haproxy/config/{{ cfg_dir }}/html_static
    - user: haproxy
    - group: haproxy
    - include_empty: True
    - file_mode: 644
    - dir_mode: 755
    - clean: True
    - include_pat: E@.html$
    - makedirs: True
{% endif %}

haproxy_validate_config:
  cmd.run:
    - name: /usr/local/sbin/haproxy -c -f /etc/haproxy/haproxy.cfg
    - onchanges:
      - file: haproxy-deploy-config
{% if salt['pillar.get']('server:haproxy:whitelist', False ) %}
      - file: /etc/haproxy/whitelist
{% endif %}
{% if salt['pillar.get']('server:haproxy:host_map', False ) %}
      - file: /etc/haproxy/hosts.map
      - file: /etc/haproxy/hostmap
{% endif %}
{% if salt['pillar.get']('server:haproxy:ssl', False ) %}
      - file: /etc/haproxy/ha_ssl
{% endif %}

haproxy_validate_hostmap_backends:
  cmd.run:
    - name: |
        set -eu
        backend_targets_file="$(mktemp)"
        missing_lines_file="$(mktemp)"
        trap 'rm -f "$backend_targets_file" "$missing_lines_file"' EXIT
        awk '$1 == "backend" {print $2}' /etc/haproxy/haproxy.cfg | sort -u > "$backend_targets_file"
        : > "$missing_lines_file"
        for map_file in /etc/haproxy/hostmap/*.map; do
          [ -e "$map_file" ] || continue
          awk -v backend_file="$backend_targets_file" '
            BEGIN {
              while ((getline line < backend_file) > 0) {
                valid[line] = 1
              }
              close(backend_file)
            }
            NF >= 2 && $1 !~ /^#/ {
              target = $2
              if (!(target in valid)) {
                print FILENAME ":" FNR " -> " target
              }
            }
          ' "$map_file" >> "$missing_lines_file"
        done
        if [ -s "$missing_lines_file" ]; then
          echo "ERROR: hostmap contains undefined backends at:"
          cat "$missing_lines_file"
          exit 1
        fi
    - require:
      - cmd: haproxy_validate_config
    - onchanges:
      - file: haproxy-deploy-config
{% if salt['pillar.get']('server:haproxy:host_map', False ) %}
      - file: /etc/haproxy/hosts.map
      - file: /etc/haproxy/hostmap
{% endif %}

haproxy:
  service.running:
    - enable: True
    - reload: True
    - require:
      - file: haproxy-deploy-config
      - cmd: haproxy_validate_config
      - cmd: haproxy_validate_hostmap_backends
    - watch:
      - file: haproxy-deploy-config
{% if salt['pillar.get']('server:haproxy:whitelist', False ) %}
      - file: /etc/haproxy/whitelist
{% endif %}
{% if salt['pillar.get']('server:haproxy:host_map', False ) %}
      - file: /etc/haproxy/hosts.map
{% endif %}
{% if salt['pillar.get']('server:haproxy:host_map', False ) %}
      - file: /etc/haproxy/hostmap
{% endif %}
{% if salt['pillar.get']('server:haproxy:ssl', False ) %}
      - file: /etc/haproxy/ha_ssl
{% endif %}
