server:
  roles:
    - ha-dev
  haproxy:
    ssl: True
    whitelist: True
    role: ha-dev
    cfg_dir: ha-dev
    version: '3.2.4'
    patch: False
    host_map: True
    quictls: False
    openssl: True
    dataplaneapi: False
    html_static: False
    install_from_source: true
    promexporter: True        
    node_exporter: True
    include:
      - haproxy.override
    frontends:
      fe_http_gs_in:
        name: fe_http_gs_in
        bind:
          - '*:80'
          - '*:443 ssl crt /etc/haproxy/ha_ssl alpn h2,http/1.1 strict-sni'
        maxconn: 200000
        stick_table: type ip size 999k expire 1m store gpc0,conn_rate(10s)
        options:
          - forwardfor
        captures:
          - declare capture request len 128
          - http-request capture req.hdr(Host) id 0
          - declare capture request len 512
          - http-request capture req.fhdr(User-Agent) id 1
          - declare capture request len 128
          - http-request capture req.hdr(Referer) id 2
          - declare capture request len 64
          - http-request capture req.hdr(X-Client-IP) id 3
          - declare capture request len 15
          - http-request capture req.hdr(X-Forwarded-For) id 4
          - declare capture request len 2048
          - http-request capture req.body id 5
          - declare capture request len 15
          - http-request capture req.hdr(cf) id 6


        #errorfile_503:
         # - /etc/haproxy/html_static/error_503.html
        http_request:
          - set-header X-Real-IP %[src]
          - set-header X-Client-IP %[src]
          - set-header True-Client-IP %[src]
          - set-header X-Forwarded-Proto https if { ssl_fc }
          - set-header X-Forwarded-Proto http if ! { ssl_fc }
          - add-header cf %[req.hdr(CF-Connecting-IP)]


        http_response:
          - del-header Server
          - del-header X-Powered-By

        default_backend:
          - no_acl_match

        acl:
          - source_is_serious_abuse src_conn_rate(fe_http_gs_in) gt 1000
          - conn_rate_abuse         sc1_conn_rate gt 30
          - mark_as_abuser          sc1_inc_gpc0  ge 0
          - source_is_abuser        src_get_gpc0(fe_http_gs_in) gt 50

        ## deny zone rule ##  
          - block-ip src -f /etc/haproxy/whitelist/blockip.list

        ## office rule ##     
          - 5g_offcie_ip src -f /etc/haproxy/whitelist/5g_offcie_ip.list

        ## game rule ##
          - gs_domain hdr_dom(host) -i -f /etc/haproxy/whitelist/gs_domain.list
          - gs_sub hdr_beg(host) -i -f /etc/haproxy/whitelist/gs_sub.list

        ## api domain rule ##
          - api_domain hdr_dom(host) -i -f /etc/haproxy/whitelist/api_domain.list
          - api_sub hdr_beg(host) -i -f /etc/haproxy/whitelist/api_sub.list
        ## monitor domain rule ##
          - monitor_domain hdr_dom(host) -i -f /etc/haproxy/whitelist/monitor_domain.list
          - internal_monitor_sub hdr_beg(host) -i -f /etc/haproxy/whitelist/internal_monitor_sub.list
          - internet_monitor_sub hdr_beg(host) -i -f /etc/haproxy/whitelist/internet_monitor_sub.list          
        ## ecv std domain rule ##
          - std_domain hdr_dom(host) -i -f /etc/haproxy/whitelist/std_domain.list
          - dev_sub hdr_beg(host) -i -f /etc/haproxy/whitelist/dev_sub.list
          - uat_sub hdr_beg(host) -i -f /etc/haproxy/whitelist/uat_sub.list
          - stage_sub hdr_beg(host) -i -f /etc/haproxy/whitelist/stage_sub.list                    

        tcp_request:
          - inspect-delay 10s
          #- connection reject if block-ip

        use_backend:
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/game.map)]" if gs_sub gs_domain'
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/api.map)]" if api_sub api_domain'
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/monitor.map)]" if internal_monitor_sub monitor_domain 5g_offcie_ip || internet_monitor_sub monitor_domain'
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/dev.map)]" if dev_sub std_domain 5g_offcie_ip'
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/uat.map)]" if uat_sub std_domain 5g_offcie_ip'
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/stage.map)]" if stage_sub std_domain'

      frontend mysql_front
        bind 
          - '*:3306'
        mode tcp
        option tcplog
        acl allowed_ip src 10.168.0.16
        tcp-request connection reject if !allowed_ip
        default_backend mysql_back

      fe_http_das_in:
        name: fe_http_das_in
        bind:
          - '*:6980'
          - '*:6981'
          - '*:6982'
          - '*:6983'                                
          - '*:6943 ssl crt /etc/haproxy/ha_ssl alpn h2,http/1.1 strict-sni'
          - '*:6944 ssl crt /etc/haproxy/ha_ssl alpn h2,http/1.1 strict-sni'
          - '*:6945 ssl crt /etc/haproxy/ha_ssl alpn h2,http/1.1 strict-sni'
          - '*:6946 ssl crt /etc/haproxy/ha_ssl alpn h2,http/1.1 strict-sni'
        mode: tcp
        maxconn: 200000
        options:
          - tcplog

        default_backend:
          - no_acl_match
        acl:
        ## deny zone rule ##  
          - block-ip src -f /etc/haproxy/whitelist/blockip.list

        ## office rule ##     
          - 5g_offcie_ip src -f /etc/haproxy/whitelist/5g_offcie_ip.list

        tcp_request:
          - inspect-delay 10s
          #- connection reject if block-ip

        use_backend:
          - 'dal_dev_elb if { dst_port 6980 } 5g_offcie_ip || { dst_port 6943 } 5g_offcie_ip'
          - 'dal_uat_elb if { dst_port 6981 } 5g_offcie_ip || { dst_port 6944 } 5g_offcie_ip'
          - 'dal_stage_elb if { dst_port 6982 } 5g_offcie_ip || { dst_port 6945 } 5g_offcie_ip'          
          - 'dal_prod_elb if { dst_port 6983 } 5g_offcie_ip || { dst_port 6946 } 5g_offcie_ip'          



    backends:
     influxdb_elb:
       name: influxdb_elb
       options: 
         - "tcp-check"                   
       servers:
         - influxdb_elb_1 a0e78a798a6c048b9b167e1f50797864-437797f47aa7fb2c.elb.ap-southeast-1.amazonaws.com:8086 check        

     grafana_elb:
       name: grafana_elb
       options: 
         - "tcp-check"                   
       servers:
         - grafana_elb_1 a0e78a798a6c048b9b167e1f50797864-437797f47aa7fb2c.elb.ap-southeast-1.amazonaws.com:3000 check        

     rancher_elb:
       name: rancher_elb
       options: 
         - "tcp-check"                   
       servers:
         - rancher_elb_1 a0e78a798a6c048b9b167e1f50797864-437797f47aa7fb2c.elb.ap-southeast-1.amazonaws.com:443 check ssl verify none        

     kafka_ui_elb:
       name: kafka_ui_elb
       options: 
         - "tcp-check"                   
       servers:
         - kafka_ui_elb_1 a0e78a798a6c048b9b167e1f50797864-437797f47aa7fb2c.elb.ap-southeast-1.amazonaws.com:8080 check

     kafka_dal_uat_elb:
       name: kafka_dal_uat_elb
       options: 
         - "tcp-check"                   
       servers:
         - kafka_dal_uat_elb_1 a1ddd20531d8e4fb69d34d263bbe9028-f2ae1a6e739467d4.elb.ap-southeast-1.amazonaws.com:8080 check

     kafka_dal_prod_elb:
       name: kafka_dal_prod_elb
       options: 
         - "tcp-check"                   
       servers:
         - kafka_dal_prod_elb a20383fb7594b49258852b60f8f54b31-f550bf4829519b5e.elb.ap-southeast-1.amazonaws.com:8080 check

     victoriametrics_elb:
       name: victoriametrics_elb
       options: 
         - "tcp-check"                   
       servers:
         - victoriametrics_elb a0e78a798a6c048b9b167e1f50797864-437797f47aa7fb2c.elb.ap-southeast-1.amazonaws.com:8480 check

     prometheus_elb:
       name: prometheus_elb
       options: 
         - "tcp-check"                   
       servers:
         - prometheus_elb a0e78a798a6c048b9b167e1f50797864-437797f47aa7fb2c.elb.ap-southeast-1.amazonaws.com:8480 check

     qa_cheat_elb:
       name: qa_cheat_elb
       options: 
         - "tcp-check"                   
       servers:
         - qa_cheat_elb a0e78a798a6c048b9b167e1f50797864-437797f47aa7fb2c.elb.ap-southeast-1.amazonaws.com:6363 check

     singzo_ui_elb:
       name: singzo_ui_elb
       options: 
         - "tcp-check"                   
       servers:
         - singzo_ui_elb a0e78a798a6c048b9b167e1f50797864-437797f47aa7fb2c.elb.ap-southeast-1.amazonaws.com:8088 check

     singzo_api_elb:
       name: singzo_api_elb
       options: 
         - "tcp-check"                   
       servers:
         - singzo_api_elb a0e78a798a6c048b9b167e1f50797864-437797f47aa7fb2c.elb.ap-southeast-1.amazonaws.com:4318 check

     certmate_nlb:
       name: certmate_nlb
       options: 
         - "tcp-check"                   
       servers:
         - certmate_nlb a0e78a798a6c048b9b167e1f50797864-437797f47aa7fb2c.elb.ap-southeast-1.amazonaws.com:8089 check


     openobserv_elb:
       name: openobserv_elb
       mode: http
       options: 
         - "httpchk GET /"                 
       servers:
         - openobserv_elb a61bfc0990d2d4954bf4eb86591d47d4-a0d0f11857a65487.elb.ap-southeast-1.amazonaws.com:5080 check

     jms_ec2:
       name: jms_ec2
       mode: http
       options: 
         - "httpchk"
       http_checks:
         - "send meth GET uri / ver HTTP/1.1 hdr Host 10.58.68.170"
         - "expect status 200"                  
       servers:
         - jms_ec2 10.58.68.170:80 check  

     ##hk-dev-game-server
     dev_gs_alb:
       name: dev_gs_alb
       mode: http
       options: 
         - "httpchk GET /alive"                   
       servers:
         - dev_gs_alb internal-ALB-GameServer-HaProxy-2426960.ap-east-1.elb.amazonaws.com:80 check  
     ###dal service### 
     dal_dev_elb:
       name: dal_dev_elb
       mode: tcp
       options: 
         - "tcp-check"                    
       servers:
         - dal_dev_elb dal-dev.5gfafa.com:6969 check port 9696    

     dal_uat_elb:
       name: dal_uat_elb
       mode: tcp
       options: 
         - "tcp-check"                   
       servers:
         - dal_uat_elb dal-uat.5gfafa.com:6969 check port 9696    

     dal_stage_elb:
       name: dal_stage_elb
       mode: tcp
       options: 
         - "tcp-check"                  
       servers:
         - dal_stage_elb dal-stage.5gfafa.com:6969 check port 9696 

     dal_prod_elb:
       name: dal_prod_elb
       mode: tcp
       options: 
         - "tcp-check"                  
       servers:
         - dal_prod_elb dal-prod.5gfafa.com:6969 check port 9696

backend mysql_back
    mode tcp
    option tcp-check
    timeout connect 5s
    timeout server 30s
    server mysql-rds stdmysql-instance-1.cdgm8426ylrz.ap-southeast-1.rds.amazonaws.com:3306 check

    ## no match any rule"
     no_acl_match:
       name: no_acl_match
       redirect: code 307 location http://localhost

