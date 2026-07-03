server:
  roles:
    - ha-std
  haproxy:
    ssl: True
    whitelist: True
    role: ha-std
    cfg_dir: ha-std
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
          - return status 204 hdr Access-Control-Allow-Origin "%[var(txn.origin)]" hdr Access-Control-Allow-Methods "PUT, PATCH, GET, POST, OPTIONS" hdr Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept, Authorization, sentry-trace, baggage accept-timezone" hdr Access-Control-Allow-Credentials "true" if { method OPTIONS }
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
        ## ecv std domain rule ##
          - std_domain hdr_dom(host) -i -f /etc/haproxy/whitelist/std_domain.list
          - dev_sub hdr_beg(host) -i -f /etc/haproxy/whitelist/dev_sub.list
          - uat_sub hdr_beg(host) -i -f /etc/haproxy/whitelist/uat_sub.list
          - stage_sub hdr_beg(host) -i -f /etc/haproxy/whitelist/stage_sub.list                    

        tcp_request:
          - inspect-delay 10s

        use_backend:
          - header_print if header_print 5g_offcie_ip
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/dev.map)]" if dev_sub std_domain'          
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/uat.map)]" if uat_sub std_domain'
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/stage.map)]" if stage_sub std_domain'                  
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/game.map)]" if gs_sub gs_domain'        
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/api.map)]" if api_sub api_domain'         

      fe_http_dal_in:
        name: fe_http_dal_in
        bind:
          - '*:6980'                                  
          - '*:6943 ssl crt /etc/haproxy/ha_ssl alpn h2,http/1.1 strict-sni'
          - '*:6944 ssl crt /etc/haproxy/ha_ssl alpn h2,http/1.1 strict-sni'
          - '*:6944 ssl crt /etc/haproxy/ha_ssl alpn h2,http/1.1 strict-sni'
          - '*:6945 ssl crt /etc/haproxy/ha_ssl alpn h2,http/1.1 strict-sni'
          - '*:6946 ssl crt /etc/haproxy/ha_ssl alpn h2,http/1.1 strict-sni'
          - '*:6947 ssl crt /etc/haproxy/ha_ssl alpn h2,http/1.1 strict-sni'
          - '*:6948 ssl crt /etc/haproxy/ha_ssl alpn h2,http/1.1 strict-sni'

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
          - 'dal_dev_elb_8080 if { dst_port 6980 } 5g_offcie_ip'
          - 'dal_dev_elb if { dst_port 6943 } 5g_offcie_ip'
          - 'dal_uat_elb if { dst_port 6944 } 5g_offcie_ip'
          - 'dal_stage_elb if { dst_port 6945 } 5g_offcie_ip'          
          - 'dal_prod_elb if { dst_port 6946 } 5g_offcie_ip'          
          - 'platfrom_dal_uat_elb if { dst_port 6947 } 5g_offcie_ip'   
          - 'backstage_dal_uat_elb if { dst_port 6948 } 5g_offcie_ip'

    backends:
    ###demo service###
     demoapi_dev:
       name: demoapi_dev
       mode: http
       options: 
         - "httpchk GET /alive"
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions                  
       servers:
         - demoapi_dev internal-ALB-DemoApi-Dev-990969710.ap-southeast-1.elb.amazonaws.com:8080 check 
    ###api service###
     api_dev:
       name: api_dev
       mode: http
       options: 
         - "httpchk GET /alive"
         - forwardfor
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions                  
       servers:
         - api_dev internal-ALB-PlatformApi-Dev-671097587.ap-southeast-1.elb.amazonaws.com:8080 check

     api_uat:
       name: api_uat
       mode: http
       options: 
         - "httpchk GET /alive"
         - forwardfor
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions                  
       servers:
         - api_uat internal-ALB-PlatformApi-Uat-57992648.ap-southeast-1.elb.amazonaws.com:8080 check

     api_stage:
       name: api_stage
       mode: http
       options: 
         - "httpchk GET /alive"
         - forwardfor
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions                  
       servers:
         - api_stage internal-ALB-PlatformApi-Stage-1312367995.ap-southeast-1.elb.amazonaws.com:8080 check

     api_dev_5gg_io:
       name: api_dev_5gg_io
       mode: http
       options: 
         - "httpchk GET /alive"
         - forwardfor
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions                  
       servers:
         - api_dev_5gg_io internal-ALB-OfficialWebApi-Dev-522703919.ap-southeast-1.elb.amazonaws.com:8080 check

     api_refactor_dev:
       name: api_refactor_dev
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - api_refactor_dev internal-ALB-PlatformApi-Refactor-1867007938.ap-southeast-1.elb.amazonaws.com:8080 check 

     ###backstage service###
     backstage_api_dev:
       name: backstage_api_dev
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - backstage_api_dev internal-ALB-BackstageApi-Dev-2107151475.ap-southeast-1.elb.amazonaws.com:8080 check          

     backstage_api_uat:
       name: backstage_api_uat
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - backstage_api_uat internal-ALB-BackstageApi-Uat-720955944.ap-southeast-1.elb.amazonaws.com:8080 check  

     backstage_api_stage:
       name: backstage_api_stage
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - backstage_api_stage internal-ALB-BackstageApi-Stage-55134287.ap-southeast-1.elb.amazonaws.com:8080 check  

     backstage_agent_api_dev:
       name: backstage_agent_api_dev
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - backstage_agent_api_dev internal-ALB-BackstageAgentApi-Dev-1567630179.ap-southeast-1.elb.amazonaws.com:8080 check 

     backstage_agent_api_uat:
       name: backstage_agent_api_uat
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - backstage_agent_api_uat internal-ALB-BackstageAgentApi-Uat-889927419.ap-southeast-1.elb.amazonaws.com:8080 check   

     backstage_agent_api_stage:
       name: backstage_agent_api_stage
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - backstage_agent_api_stage internal-ALB-BackstageAgentApi-Stage-230462263.ap-southeast-1.elb.amazonaws.com:8080 check 

     backstage_api_refactor_dev:
       name: backstage_api_refactor_dev
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - backstage_api_refactor_dev internal-ALB-BackstageApi-Refactor-654211116.ap-southeast-1.elb.amazonaws.com:8080 check 

     backstage_agent_api_refactor_dev:
       name: backstage_agent_api_refactor_dev
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - backstage_agent_api_refactor_dev internal-ALB-BackstageAgentApi-Refactor-532391851.ap-southeast-1.elb.amazonaws.com:8080 check 

    ###message_center###
     message_center_dev:
       name: message_center_dev
       mode: http            
       options: 
         - "httpchk GET /health" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - message_center_dev mc-dev.5gservice.com:8080 check

     message_center_uat:
       name: message_center_uat
       mode: http            
       options: 
         - "httpchk GET /health" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - message_center_uat mc-uat.5gservice.com:8080 check

     message_center_stage:
       name: message_center_stage
       mode: http            
       options: 
         - "httpchk GET /health" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - message_center_stage mc-stage.5gservice.com:8080 check 

     message_center_refactor:
       name: message_center_refactor
       mode: http            
       options: 
         - "httpchk GET /health" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - message_center_refactor mc-refactor.5gservice.com:8080 check

    ###tournament###
     tournament_dev:
       name: tournament_dev
       mode: http            
       options: 
         - "httpchk GET /health" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - tournament_dev tournament-dev.5gservice.com:8080 check

     tournament_uat:
       name: tournament_uat
       mode: http            
       options: 
         - "httpchk GET /health" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - tournament_uat internal-ALB-Tournament-Uat-709669374.ap-southeast-1.elb.amazonaws.com:8080 check

     tournament_refactor:
       name: tournament_refactor
       mode: http            
       options: 
         - "httpchk GET /health" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - tournament_refactor tournament-refactor.5gservice.com:8080 check

    ###bridge###
     bridge_dev:
       name: bridge_dev
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - bridge_dev bridge-dev.5gservice.com:8080 check

     bridge_uat:
       name: bridge_uat
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - bridge_uat internal-ALB-BridgeApi-Uat-1287411251.ap-southeast-1.elb.amazonaws.com:8080 check

    ###campaign###
     campaign_dev:
       name: campaign_dev
       mode: http            
       options: 
         - "httpchk GET /health" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - campaign_dev campaign-dev.5gservice.com:8080 check

     campaign_uat:
       name: campaign_uat
       mode: http            
       options: 
         - "httpchk GET /health" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - campaign_uat internal-ALB-FrbCampaign-Uat-1338635269.ap-southeast-1.elb.amazonaws.com:8080 check

     campaign_refactor:
       name: campaign_refactor
       mode: http            
       options: 
         - "httpchk GET /health" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - campaign_refactor campaign-refactor.5gservice.com:8080 check

    ###game service###
     game_server_dev:
       name: game_server_dev
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - game_server_dev internal-ALB-GameServer-Dev-1498468321.ap-southeast-1.elb.amazonaws.com:8080 check 

     game_server_uat:
       name: game_server_uat
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - game_server_uat internal-ALB-GameServer-Uat-2116443273.ap-southeast-1.elb.amazonaws.com:8080 check

     game_server_stage:
       name: game_server_stage
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - game_server_stage internal-ALB-GameServer-Stage-1007126180.ap-southeast-1.elb.amazonaws.com:8080 check           

     gs_refactor_dev:
       name: gs_refactor_dev
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - gs_refactor_dev internal-ALB-GameServer-Refactor-754804591.ap-southeast-1.elb.amazonaws.com:8080 check 

     tushar_gs_dev:
       name: tushar_gs_dev
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - tushar_gs_dev internal-ALB-GameServer-Optimized-827801056.ap-southeast-1.elb.amazonaws.com:8080 check 

     game_engin_dev:
       name: game_engin_dev
       mode: http
       options: 
         - "httpchk"
       http_check:
         - "connect port 443 ssl alpn h2 sni str(ge-dev.5gstatic.com)"
         - "send meth POST uri /grpc.health.v1.Health/Check ver HTTP/2 hdr host ge-dev.5gstatic.com hdr content-type application/grpc"
         - "expect status 200"
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions       
       servers:
         - game_engin_dev internal-ALB-GameEngine-Dev-494097733.ap-southeast-1.elb.amazonaws.com:443 ssl verify none check check-ssl alpn h2

     ###dal service### 
     dal_dev_elb:
       name: dal_dev_elb
       mode: tcp       
       options: 
         - "tcp-check"               
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions            
       servers:
         - dal_dev_elb dal-dev.5gfafa.com:6969 check port 9696

     dal_dev_elb_8080:
       name: dal_dev_elb_8080
       mode: tcp       
       options: 
         - "tcp-check"               
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions            
       servers:
         - dal_dev_elb_8080 dal-dev.5gfafa.com:8080 check port 9696

     dal_uat_elb:
       name: dal_uat_elb
       mode: tcp
       options: 
         - "tcp-check"
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions            
       servers:
         - dal_uat_elb dal-uat.5gfafa.com:6969 check port 9696

     platfrom_dal_uat_elb:
       name: platfrom_dal_uat_elb
       mode: tcp
       options: 
         - "tcp-check"
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions            
       servers:
         - platfrom_dal_uat_elb platform-dal-uat.5gfafa.com:6969 check port 9696

     backstage_dal_uat_elb:
       name: backstage_dal_uat_elb
       mode: tcp
       options: 
         - "tcp-check"
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions            
       servers:
         - backstage_dal_uat_elb backstage-dal-uat.5gfafa.com:6969 check port 9696               

     dal_stage_elb:
       name: dal_stage_elb
       mode: tcp
       options: 
         - "tcp-check"
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions            
       servers:
         - dal_stage_elb dal-stage.5gfafa.com:6969 check port 9696 

     dal_prod_elb:
       name: dal_prod_elb
       mode: tcp
       options: 
         - "tcp-check"                  
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none on-marked-down shutdown-sessions                     
       servers:
         - dal_prod_elb dal-prod.5gfafa.com:6969 check port 9696

     #qa_chat#
     qa_cheat_elb:
       name: qa_cheat_elb
       options: 
         - "tcp-check"                   
       servers:
         - qa_cheat_elb a5f71736ba4d945b69ac0cf8c84079e5-bfefc137668a4c18.elb.ap-southeast-1.amazonaws.com:80 check

     #funnel#
     funnel_dev:
       name: funnel_dev
       options: 
         - "tcp-check"                   
       servers:
         - funnel_dev a5f71736ba4d945b69ac0cf8c84079e5-bfefc137668a4c18.elb.ap-southeast-1.amazonaws.com:8601 check

     #dataaggregator_dev
     #dataaggregator_dev:
       #name: dataaggregator_dev
       #options: 
         #- "tcp-check"                   
       #servers:
         #- dataaggregator_dev a8801acc85b4b4985abbd9e756b2305f-5ca8652a72afd3ca.elb.ap-southeast-1.amazonaws.com:8089 check

     ####infra service####
     header_print:
       name: header_print
       options: 
         - "tcp-check"                
       servers:
         - header_print 10.29.8.218:8080 check


    ## no match any rule"
     no_acl_match:
       name: no_acl_match
       redirect: code 307 location http://localhost

