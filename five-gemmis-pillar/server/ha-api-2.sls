{% import_yaml "server/ha-api-1.sls" as std1 %}

server:
  roles:
    - ha-api
  haproxy: {{ std1.get('server', {}).get('haproxy', {}) }}