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
      fe_http_infra_in:
        name: fe_http_infra_in
        bind:
          - '*:80'
          - '*:443 ssl crt /etc/haproxy/ha_ssl alpn h2,http/1.1 strict-sni'
        maxconn: 200000
        stick_table: type ip size 999k expire 1m store gpc0,conn_rate(10s)
        options:
          - forwardfor
        captures:
          - declare capture request len 128 # id-0-host
          - declare capture request len 512 # id-1-User-Agent
          - declare capture request len 128 # id-2-Referer
          - declare capture request len 64  # id-3-Body
          - declare capture request len 16  # id-4-X-Forwarded-For
          - declare capture request len 16  # id-5-X-Client-IP
          - declare capture request len 16  # id-6-cf
          - declare capture request len 16  # id-7-byteplus          
          - declare capture request len 16  # id-8-5g-client-ip
          - declare capture request len 128  # id-9-5g-unique-id         
          - http-request capture req.hdr(Host) id 0             
          - http-request capture req.fhdr(User-Agent) id 1
          - http-request capture req.hdr(Referer) id 2
          - http-request capture req.body id 3          
          - http-request capture req.hdr(X-Client-IP) id 4
          - http-request capture req.hdr(X-Forwarded-For) id 5
          - http-request capture req.hdr(cf) id 6
          - http-request capture req.hdr(by) id 7
          - http-request capture req.hdr(5g-client-ip) id 8
          - http-request capture req.hdr(5g-unique-id) id 9   
        #errorfile_503:
         # - /etc/haproxy/html_static/error_503.html
        http_request:
          ###unique_id_check###
          - set-header 5g-unique-id %[unique-id] if ! { req.hdr(5g-unique-id) -m found }
          - set-var(txn.unique_id) req.hdr(5g-unique-id)
        ###Layer 7 header###                
          - set-header X-Forwarded-Host %[req.hdr(Host)] if !{ req.hdr(X-Forwarded-Host) -m found }
          - set-header X-Forwarded-Port %[dst_port]
          - set-header X-Real-IP %[src]
          - set-header X-Client-IP %[src]
          - set-header True-Client-IP %[src]
          - set-header X-Forwarded-For %[src]
          - set-header X-Forwarded-Proto https if { ssl_fc }
          - set-header X-Forwarded-Proto http if ! { ssl_fc }
        ###Consumers header###                 
          - set-header 5g-client-ip %[src]
          - set-header 5g-client-ip %[req.hdr(CF-Connecting-IP)] if { hdr(CF-Connecting-IP) -m found }
          - set-header 5g-client-ip %[req.hdr(BY-Connecting-IP)] if { hdr(BY-Connecting-IP) -m found }             
        ###add cdn header###                 
          - add-header cf %[req.hdr(CF-Connecting-IP)]
          - add-header by %[req.hdr(BY-Connecting-IP)]            
        ###CORS domain role###  
          - set-var(txn.origin) req.hdr(Origin) 
          - return status 204 hdr Access-Control-Allow-Origin "%[var(txn.origin)]" hdr Access-Control-Allow-Methods "PUT, PATCH, GET, POST, OPTIONS" hdr Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept, Authorization, sentry-trace, baggage accept-timezone" hdr Access-Control-Allow-Credentials "true" if { method OPTIONS }

        http_response:
          - del-header Server
          - del-header X-Powered-By

        default_backend:
          - no_acl_match

        acl:
          - source_is_serious_abuse src_conn_rate(fe_http_infra_in) gt 1000
          - conn_rate_abuse         sc1_conn_rate gt 30
          - mark_as_abuser          sc1_inc_gpc0  ge 0
          - source_is_abuser        src_get_gpc0(fe_http_infra_in) gt 50

        ## deny zone rule ##  
          - block-ip src -f /etc/haproxy/whitelist/blockip.list

        ## office rule ##     
          - 5g_offcie_ip src -f /etc/haproxy/whitelist/5g_offcie_ip.list

        ## monitor domain rule ##
          - monitor_domain hdr_dom(host) -i -f /etc/haproxy/whitelist/monitor_domain.list
          - internal_monitor_sub hdr_beg(host) -i -f /etc/haproxy/whitelist/internal_monitor_sub.list
          - internet_monitor_sub hdr_beg(host) -i -f /etc/haproxy/whitelist/internet_monitor_sub.list                       

        tcp_request:
          - inspect-delay 10s
          #- connection reject if block-ip

        use_backend:
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/monitor.map)]" if internal_monitor_sub monitor_domain 5g_offcie_ip || internet_monitor_sub monitor_domain'

      fe_tcp_memberdb_in:
        name: fe_tcp_memberdb_in
        bind:
          - '*:3306' #member_db_std
          - '*:3366' #member_db_prod
          - '*:3389' #win_test_eric
          - '*:9408' #warm_db_prod
          - '*:9406' #warm_db_std
          - '*:9509' #valkey-dev                             
          - '*:9510' #valkey-uat
          - '*:9511' #valkey-stage
          - '*:9512' #valkey-stage          

        mode: tcp
        log-formats: "%ci:%cp [%t] %ft %b/%s %Tw/%Tc/%Tt %B %ts %ac/%fc/%bc/%sc/%rc %sq/%bq"        
        maxconn: 500
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
          - 'member_db_std if { dst_port 3306 } 5g_offcie_ip'
          - 'member_db_prod if { dst_port 3366 } 5g_offcie_ip'
          - 'win_test_eric if { dst_port 3389 } 5g_offcie_ip'
          - 'warm_db_std if { dst_port 9406 } 5g_offcie_ip'
          - 'warm_db_prod if { dst_port 9408 } 5g_offcie_ip'
          - 'dev_valkey if { dst_port 9509 } 5g_offcie_ip'     
          - 'uat_valkey if { dst_port 9510 } 5g_offcie_ip'     
          - 'stage_valkey if { dst_port 9511 } 5g_offcie_ip'     
          - 'prod_valkey if { dst_port 9512 } 5g_offcie_ip'


    backends:
    #infra service#
     kafka_ui_elb:
       name: kafka_ui_elb
       options: 
         - "tcp-check"                   
       servers:
         - kafka_ui_elb_1 a5f71736ba4d945b69ac0cf8c84079e5-bfefc137668a4c18.elb.ap-southeast-1.amazonaws.com:80 check

     kafka_dal_uat_elb:
       name: kafka_dal_uat_elb
       options: 
         - "tcp-check"                   
       servers:
         - kafka_dal_uat_elb a1ddd20531d8e4fb69d34d263bbe9028-f2ae1a6e739467d4.elb.ap-southeast-1.amazonaws.com:8080 check

     kafka_dal_prod_elb:
       name: kafka_dal_prod_elb
       options: 
         - "tcp-check"                   
       servers:
         - kafka_dal_prod_elb a20383fb7594b49258852b60f8f54b31-f550bf4829519b5e.elb.ap-southeast-1.amazonaws.com:8080 check

     #openobserve
     openobserve_elb:
       name: openobserve_elb
       options: 
         - "tcp-check"                   
       servers:
         - openobserve_elb a5f71736ba4d945b69ac0cf8c84079e5-bfefc137668a4c18.elb.ap-southeast-1.amazonaws.com:80 check    

     #certmate#
     certmate_nlb:
       name: certmate_nlb
       options: 
         - "tcp-check"
       timeout_servers: 
         - 300
       servers:
         - certmate_nlb a5f71736ba4d945b69ac0cf8c84079e5-bfefc137668a4c18.elb.ap-southeast-1.amazonaws.com:80 check


     #grafana
     grafana_elb:
       name: grafana_elb
       options: 
         - "tcp-check"                   
       servers:
         - grafana_elb a5f71736ba4d945b69ac0cf8c84079e5-bfefc137668a4c18.elb.ap-southeast-1.amazonaws.com:80 check   

     #influxdb
     influxdb_elb:
       name: influxdb_elb
       options: 
         - "tcp-check"                   
       servers:
         - influxdb_elb a5f71736ba4d945b69ac0cf8c84079e5-bfefc137668a4c18.elb.ap-southeast-1.amazonaws.com:80 check 
     
     #rancher
     rancher_elb:
       name: rancher_elb
       options: 
         - "tcp-check"                   
       servers:
         - rancher_elb_1 a5f71736ba4d945b69ac0cf8c84079e5-bfefc137668a4c18.elb.ap-southeast-1.amazonaws.com:443 check ssl verify none        


     #VMSelect
     vmselect_elb:
       name: vmselect_elb
       options: 
         - "tcp-check"                   
       servers:
         - vmselect_elb a5f71736ba4d945b69ac0cf8c84079e5-bfefc137668a4c18.elb.ap-southeast-1.amazonaws.com:80 check

     #VMInsert
     vminsert_elb:
       name: vminsert_elb
       options: 
         - "tcp-check"                   
       servers:
         - vminsert_elb a5f71736ba4d945b69ac0cf8c84079e5-bfefc137668a4c18.elb.ap-southeast-1.amazonaws.com:80 check 

     member_db_std:
       name: member_db_std
       mode: tcp
       options: 
         - "tcp-check"                   
       servers:
         - member_db_std stdmysql.cluster-cdgm8426ylrz.ap-southeast-1.rds.amazonaws.com:3306 check        

     member_db_prod:
       name: member_db_prod
       mode: tcp
       options: 
         - "tcp-check"                   
       servers:
         - member_db_prod prodmysql-instance-1.cdgm8426ylrz.ap-southeast-1.rds.amazonaws.com:3306 check 

     warm_db_std:
       name: warm_db_std
       mode: tcp
       options: 
         - "tcp-check"
       tcp_checks:
         # MongoDB Wire Protocol - isMaster command
         - send-binary 3a000000   # Message Length (58 bytes)
         - send-binary EEEEEEEE   # Request ID (random)
         - send-binary 00000000   # Response To (nothing)
         - send-binary d4070000   # OpCode (OP_QUERY)
         - send-binary 00000000   # Query Flags
         - send-binary 61646d696e2e  # fullCollectionName: admin.
         - send-binary 24636d6400    # $cmd\0
         - send-binary 00000000   # NumToSkip
         - send-binary FFFFFFFF   # NumToReturn (-1)
         # BSON Document: { ismaster: 1 }
         - send-binary 13000000   # Document Length (19)
         - send-binary 10         # Type: Int32
         - send-binary 69736d617374657200  # "ismaster\0"
         - send-binary 01000000   # Value: 1
         - send-binary 00         # Document terminator
         # 只有 Primary 才會回傳 ismaster=true (0x01)
         - expect binary 69736d61737465720001                   
       servers:
         - warm_db_std_1 k8s-stdmongo-mongo0nl-0fe4befbc3-956ffdcd200e944d.elb.ap-southeast-1.amazonaws.com:27017 check    
         - warm_db_std_2 k8s-stdmongo-mongo1nl-ff3964ed12-45fe68d95bda32ad.elb.ap-southeast-1.amazonaws.com:27017 check    
         - warm_db_std_3 k8s-stdmongo-mongo2nl-051c390473-27e64a5a4a6fd818.elb.ap-southeast-1.amazonaws.com:27017 check    

     warm_db_prod:
       name: warm_db_prod
       mode: tcp
       options: 
         - "tcp-check"
       tcp_checks:
         # MongoDB Wire Protocol - isMaster command
         - send-binary 3a000000   # Message Length (58 bytes)
         - send-binary EEEEEEEE   # Request ID (random)
         - send-binary 00000000   # Response To (nothing)
         - send-binary d4070000   # OpCode (OP_QUERY)
         - send-binary 00000000   # Query Flags
         - send-binary 61646d696e2e  # fullCollectionName: admin.
         - send-binary 24636d6400    # $cmd\0
         - send-binary 00000000   # NumToSkip
         - send-binary FFFFFFFF   # NumToReturn (-1)
         # BSON Document: { ismaster: 1 }
         - send-binary 13000000   # Document Length (19)
         - send-binary 10         # Type: Int32
         - send-binary 69736d617374657200  # "ismaster\0"
         - send-binary 01000000   # Value: 1
         - send-binary 00         # Document terminator
         # 只有 Primary 才會回傳 ismaster=true (0x01)
         - expect binary 69736d61737465720001                   
       servers:
         - warm_db_prod_1 k8s-mongodbs-mongo0nl-45ad3a8300-62810babae1f4bbb.elb.ap-southeast-1.amazonaws.com:27017 check    
         - warm_db_prod_2 k8s-mongodbs-mongo1nl-f9f5879bcb-6365246bfb43b141.elb.ap-southeast-1.amazonaws.com:27017 check    
         - warm_db_prod_3 k8s-mongodbs-mongo2nl-a7e4f7100c-6e97de9d2ff672cd.elb.ap-southeast-1.amazonaws.com:27017 check  

     win_test_eric:
       name: win_test_eric
       mode: tcp
       options: 
         - "tcp-check"                   
       servers:
         - win_test_eric 10.29.15.79:3389 check 
    ###redis valkey###
     dev_valkey:
       name: dev_valkey
       mode: tcp
       options: 
         - "tcp-check"
       servers:
         - dev_valkey dev-kd3xbs.serverless.apse1.cache.amazonaws.com:6379 check

     uat_valkey:
       name: uat_valkey
       mode: tcp
       options: 
         - "tcp-check"
       servers:
         - uat_valkey redis-oss-uat-yoe3cu.serverless.ape1.cache.amazonaws.com:6379 check

     stage_valkey:
       name: stage_valkey
       mode: tcp
       options: 
         - "tcp-check"
       servers:
         - stage_valkey redis-oss-stage-yoe3cu.serverless.ape1.cache.amazonaws.com:6379 check

     prod_valkey:
       name: prod_valkey
       mode: tcp
       options: 
         - "tcp-check"
       servers:
         - prod_valkey redis-oss-prod-a01cf3.serverless.apse1.cache.amazonaws.com:6379 check
       
    ###singzo service### 
     singzo_ui_elb:
       name: singzo_ui_elb
       options: 
         - "tcp-check"                   
       servers:
         - singzo_ui_elb a65d5798cd527469cb9465c618c132ac-3f00a0216a64c583.elb.ap-southeast-1.amazonaws.com:8080 check

     ###jms service###
     jms_ec2:
       name: jms_ec2
       mode: http
       options: 
         - "httpchk"
       http_checks:
         - "send meth GET uri / ver HTTP/1.1 hdr Host 10.168.67.170"
         - "expect status 200"                  
       servers:
         - jms_ec2 10.168.67.170:80 check  


    ## no match any rule"
     no_acl_match:
       name: no_acl_match
       redirect: code 307 location http://localhost

