#gz_exists:
#  file.exists:
#    - name: '/var/log/haproxy_0.log.*.gz'

Delete *.gz log:
  cmd.run:
    - name: '(find /var/log -maxdepth 1 -name "haproxy_0.log.*.gz" | grep -q .) && (sudo rm /var/log/haproxy_0.log.*.gz) || echo -n "Compress log not exist" '
#############################################

Eliminate1 Rotate log:
  cmd.run:
    - name: 'sudo sh -c ''echo "clean log" > /var/log/haproxy_0.log && chown syslog:adm /var/log/haproxy_0.log && chmod 640 /var/log/haproxy_0.log'''

Eliminate2 Rotate log:
  cmd.run:
    - name: '(find /var/log -maxdepth 1 -name "haproxy_0.log.*"| grep -q .) && (a=$(find /var/log -maxdepth 1 -name "haproxy_0.log.*") ; echo "salt release usage"|sudo tee $a) || echo -n "rotate log not exist"'
##########################################
#handshake-fail-exists:
#  file.exists:
#    - name: "/var/log/frontend_ssl_handshake_failure.log"

Eliminate ssl-handshake-error log:
  cmd.run:
    - name: ' (test -e /var/log/frontend_ssl_handshake_failure.log) && (echo "salt release usage"|sudo tee /var/log/frontend_ssl_handshake_failure.log) || echo -n "No frontend failed log" '
############################################
Release Filebeat Service stucking space:
  cmd.run:
    - name: 'sudo systemctl restart filebeat.service || echo "No Filebeat service or failed"'
    - unless:
      - pkg.is_installed: filebeat
############################################
Show current usage:
  cmd.run:
    - name: "df -lh"
#
#test:
#  cmd.run:
#    - name: 'echo Its $(date)|tee /tmp/testt'
