base:
  'salt-master':
    - server.{{ grains['id'] }}
  'ha-std-*':
    - server.{{ grains['id'] }}
  'ha-dev-*':
    - server.{{ grains['id'] }}
