{% if grains.get('os') == 'Ubuntu' and grains.get('osrelease') == '24.04' %}

# 1. & 2. 停止、禁用並 Mask systemd 自動更新與韌體更新相關服務
disable_and_mask_auto_upgrade_services:
  cmd.run:
    - name: |
        SERVICES="apt-daily.service apt-daily.timer apt-daily-upgrade.service apt-daily-upgrade.timer packagekit.service firmware-notifier.service fwupd.service"
        for svc in $SERVICES; do
          systemctl stop "$svc" 2>/dev/null || true
          systemctl disable "$svc" 2>/dev/null || true
          systemctl mask "$svc" 2>/dev/null || true
        done
        systemctl daemon-reload
    - unless: |
        test "$(systemctl is-enabled apt-daily.timer 2>/dev/null)" = "masked"

# 3. 移除 unattended-upgrades 套件（從根源拔除自動升級套件）
remove_unattended_upgrades_pkg:
  pkg.purged:
    - name: unattended-upgrades

# 4. 強制寫入 apt 設定檔，全面關閉所有背景週期任務
disable_unattended_upgrades_config_20:
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

# 5. 確保 unattended-upgrades 的配置也被覆蓋為停用
disable_unattended_upgrades_config_10:
  file.managed:
    - name: /etc/apt/apt.conf.d/10periodic
    - contents: |
        APT::Periodic::Update-Package-Lists "0";
        APT::Periodic::Download-Upgradeable-Packages "0";
        APT::Periodic::AutocleanInterval "0";
        APT::Periodic::Unattended-Upgrade "0";
    - user: root
    - group: root
    - mode: "0644"

{% endif %}
