{% import_yaml "server/ha-gs-1.sls" as std1 %}

server:
  roles:
    - ha-gs
  haproxy: {{ gs1.get('server', {}).get('haproxy', {}) }}