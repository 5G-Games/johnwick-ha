server:
  roles:
    - ha-gs
  haproxy:
    ssl: True
    whitelist: True
    role: ha-gs
    cfg_dir: ha-gs
    version: '3.2.4'
    patch: False
    host_map: True
    quictls: False
    openssl: True
    dataplaneapi: False
    html_static: True
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

        errorfile_503:
          - /etc/haproxy/html_static/error_503.html
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
          - return status 204 hdr Access-Control-Allow-Origin "%[var(txn.origin)]" hdr Access-Control-Allow-Methods "PUT, GET, POST, OPTIONS" hdr Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept, Authorization, sentry-trace, baggage accept-timezone" hdr Access-Control-Allow-Credentials "true" if { method OPTIONS }
        http_response:
          - del-header Server
          - del-header X-Powered-By
        ###CORS domain role###           
        http_after_response:
          - set-header Access-Control-Allow-Origin "%[var(txn.origin)]"
          - set-header Access-Control-Allow-Credentials "true"
          - set-header Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept, Authorization, sentry-trace, baggage, accept-timezone"
        default_backend:
          - no_acl_match

        acl:
          - source_is_serious_abuse src_conn_rate(fe_http_gs_in) gt 1000
          - conn_rate_abuse         sc1_conn_rate gt 30
          - mark_as_abuser          sc1_inc_gpc0  ge 0
          - source_is_abuser        src_get_gpc0(fe_http_gs_in) gt 50

        ##infra rule##
          - header_print path_reg -i ^/6969$

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
                

        tcp_request:
          - inspect-delay 10s

        use_backend:
          #- header_print if header_print 5g_offcie_ip
          - '"%[req.hdr(host),lower,map_beg(/etc/haproxy/hostmap/game.map)]" if gs_sub gs_domain'        
          - '"%[req.hdr(host),lower,map_beg(/etc/haproxy/hostmap/api.map)]" if api_sub api_domain'

    backends:
    ###message_center###
     message_center_prod:
       name: message_center_prod
       mode: http            
       options: 
         - "httpchk GET /health" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - message_center_prod mc.5gservice.com:80 check

    ###funnel service###
     funnel_prod:
       name: funnel_prod
       options: 
         - "tcp-check"                   
       servers:
         - funnel_prod a5f71736ba4d945b69ac0cf8c84079e5-bfefc137668a4c18.elb.ap-southeast-1.amazonaws.com:8602 check

    ###singzno service###
     singzo_api_elb:
       name: singzo_api_elb
       options: 
         - "tcp-check"                   
       servers:
         - singzo_api_elb a34b88004054c4b02a2efb394a2179de-7e40569043206b87.elb.ap-southeast-1.amazonaws.com:4318 check

    ###game server sevice###
     game_server_elb:
       name: game_server_elb
       options: 
         - "tcp-check"
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions                                
       servers:
         - game_server_elb internal-ALB-GameServer-Prod-657632584.ap-southeast-1.elb.amazonaws.com:8080 check maxconn 50000

     game_canary_server_elb:
       name: game_canary_server_elb
       options: 
         - "tcp-check"
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions                            
       servers:
         - game_canary_server_elb internal-ALB-GameServer-Canary-52864939.ap-southeast-1.elb.amazonaws.com:8080 check


    ## no match any rule"
     no_acl_match:
       name: no_acl_match
       redirect: code 307 location http://localhost

