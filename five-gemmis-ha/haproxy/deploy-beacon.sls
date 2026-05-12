## Create by Leo
## haprxy beacon config
##### 1.detect haproxy server disk usage.

{%- set hostname = grains.host %}

copy-haproxy-beacon-config:
  file.managed:
    - name: /etc/salt/minion.d/beacon.conf
    - template: jinja
    - user: root
    - group: root
    - mode: "0775"
    - makedirs: True
    - source: salt://haproxy/templates/default-beacon.conf
    - tgt: {{ hostname }}
    - tgt_type: compound

#restart-minion:
#  cmd.run:
#    - name: 'salt-call service.restart salt-minion'
#    - bg: True
#    - onchanges:
#      - file: copy-haproxy-beacon-config

#restart-minion:
#  cmd.wait:
#    - name: 'sleep 1 && salt-call --local service.restart salt-minion'
##    - name: 'sudo systemctl restart salt-minion'
#    - bg: True
##    - order: last
#    - watch:
#      - file: copy-haproxy-beacon-config
#    - onchanges:
#      - file: copy-haproxy-beacon-config
#    - tgt: {{ hostname }}
#    - tgt_type: compound
#    - kwarg:
#        bg: True
#

restart-salt-minion:
  cmd.run:
    - name: 'salt-call service.restart salt-minion'
    - bg: True
    - onchanges:
      - file: copy-haproxy-beacon-config

#wait-for-minion-restart:
#  salt.wait_for_event:
#    - timeout: 200
#    - order: last
#    - name: salt/minion/*/start
#    - id_list: {{ hostname }}
##    - require:
##      - cmd: restart-minion
