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
          - set-header X-Forwarded-Host %[req.hdr(Host)] if !{ req.hdr(X-Forwarded-Host) -m found }
          - set-header X-Forwarded-Port %[dst_port]
          - set-header X-Real-IP %[src]
          - set-header X-Client-IP %[src]
          - set-header True-Client-IP %[src]
          - set-header X-Forwarded-For %[src]
          - set-header X-Forwarded-Proto https if { ssl_fc }
          - set-header X-Forwarded-Proto http if ! { ssl_fc }       
          - add-header cf %[req.hdr(CF-Connecting-IP)]
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

    backends:
    #infra service#
     kafka_ui_elb:
       name: kafka_ui_elb
       options: 
         - "tcp-check"                   
       servers:
         - kafka_ui_elb_1 ae9e38330b71a4e559eda0c9477636b7-76478760af7236c4.elb.ap-southeast-1.amazonaws.com:80 check    
     #openobserve
     openobserve_elb:
       name: openobserve_elb
       options: 
         - "tcp-check"                   
       servers:
         - openobserve_elb a62b17fae956349e59c35aba177dfce5-c087f3f4263d17dd.elb.ap-southeast-1.amazonaws.com:5080 check    


     member_db_std:
       name: member_db_std
       mode: tcp
       options: 
         - "tcp-check"                   
       servers:
         - member_db_std stdmysql-instance-1.cdgm8426ylrz.ap-southeast-1.rds.amazonaws.com:3306 check        

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
         - dev_valkey redis-oss-dev-yoe3cu.serverless.ape1.cache.amazonaws.com:6379 check 



    ## no match any rule"
     no_acl_match:
       name: no_acl_match
       redirect: code 307 location http://localhost

