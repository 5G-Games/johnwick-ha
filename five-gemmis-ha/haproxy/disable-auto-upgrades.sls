{% if grains.get('os') == 'Ubuntu' and grains.get('osrelease') == '24.04' %}

disable_apt_daily_timer:
  service.dead:
    - name: apt-daily.timer
    - enable: False

disable_apt_daily_upgrade_timer:
  service.dead:
    - name: apt-daily-upgrade.timer
    - enable: False

disable_apt_daily_service:
  service.dead:
    - name: apt-daily.service
    - enable: False

disable_apt_daily_upgrade_service:
  service.dead:
    - name: apt-daily-upgrade.service
    - enable: False

disable_unattended_upgrades_config:
  file.managed:
    - name: /etc/apt/apt.conf.d/20auto-upgrades
    - contents: |
        APT::Periodic::Update-Package-Lists "0";
        APT::Periodic::Download-Upgradeable-Packages "0";
        APT::Periodic::AutocleanInterval "0";
        APT::Periodic::Unattended-Upgrade "0";
    - user: root
    - group: root
    - mode: "0644"

remove_unattended_upgrades_pkg:
  pkg.removed:
    - name: unattended-upgrades

verify_auto_upgrades_disabled:
  cmd.run:
    - name: |
        set -e
        echo "Verifying automatic updates are disabled..."
        if systemctl is-active --quiet apt-daily.timer; then echo "apt-daily.timer is still active" && exit 1; fi
        if systemctl is-active --quiet apt-daily-upgrade.timer; then echo "apt-daily-upgrade.timer is still active" && exit 1; fi
        if dpkg-query -W -f='${Status}' unattended-upgrades 2>/dev/null | grep -q "install ok installed"; then echo "unattended-upgrades package is still installed" && exit 1; fi
        grep -q 'APT::Periodic::Unattended-Upgrade "0";' /etc/apt/apt.conf.d/20auto-upgrades || (echo "Config not updated" && exit 1)
        echo "Automatic updates disabled successfully"
    - require:
      - service: disable_apt_daily_timer
      - service: disable_apt_daily_upgrade_timer
      - file: disable_unattended_upgrades_config
      - pkg: remove_unattended_upgrades_pkg

{% endif %}
