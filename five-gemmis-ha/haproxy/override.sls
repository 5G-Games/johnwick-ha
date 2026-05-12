haproxy-systemd-dropin-dir:
  file.directory:
    - name: /etc/systemd/system/haproxy.service.d
    - user: root
    - group: root
    - mode: 755

haproxy-systemd-override:
  file.managed:
    - name: /etc/systemd/system/haproxy.service.d/override.conf
    - source: salt://haproxy/files/haproxy.service.override.conf
    - user: root
    - group: root
    - mode: 644
    - require:
      - file: haproxy-systemd-dropin-dir
    - watch_in:
      - cmd: haproxy-daemon-reload
      - service: haproxy-service-restart

haproxy-sysctl-config:
  file.managed:
    - name: /etc/sysctl.d/99-haproxy.conf
    - source: salt://haproxy/files/99-haproxy.conf
    - user: root
    - group: root
    - mode: 644

haproxy-sysctl-apply:
  cmd.run:
    - name: sysctl --system
    - onchanges:
      - file: haproxy-sysctl-config

haproxy-daemon-reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: haproxy-systemd-override

haproxy-service-restart:
  service.running:
    - name: haproxy
    - enable: True
    - reload: True
    - watch:
      - file: haproxy-systemd-override
      - cmd: haproxy-daemon-reload
