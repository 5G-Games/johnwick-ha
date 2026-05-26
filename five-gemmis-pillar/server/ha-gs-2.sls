{% import_yaml "server/ha-std-1.sls" as std1 %}

server:
  roles:
    - ha-std
  haproxy: {{ std1.get('server', {}).get('haproxy', {}) }}