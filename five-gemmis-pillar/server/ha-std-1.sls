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
          - declare capture request len 16
          - http-request capture req.body id 5
          - declare capture request len 16
          - http-request capture req.hdr(cf) id 6

        errorfile_503:
          - /etc/haproxy/html_static/error_503.html
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
        ## ecv std domain rule ##
          - std_domain hdr_dom(host) -i -f /etc/haproxy/whitelist/std_domain.list
          - dev_sub hdr_beg(host) -i -f /etc/haproxy/whitelist/dev_sub.list
          - uat_sub hdr_beg(host) -i -f /etc/haproxy/whitelist/uat_sub.list
          - stage_sub hdr_beg(host) -i -f /etc/haproxy/whitelist/stage_sub.list                    

        tcp_request:
          - inspect-delay 10s

        use_backend:
          - header_print if header_print 5g_offcie_ip
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/game.map)]" if gs_sub gs_domain'        
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/api.map)]" if api_sub api_domain'
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/stage.map)]" if stage_sub std_domain'            
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/dev.map)]" if dev_sub std_domain'
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/uat.map)]" if uat_sub std_domain 5g_offcie_ip'

    backends:
    ###demo service###
     demoapi_dev:
       name: demoapi_dev
       mode: http
       options: 
         - "httpchk GET /alive"
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none                    
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
         - resolvers awsdns resolve-prefer ipv4 init-addr none                    
       servers:
         - api_dev internal-ALB-PlatformApi-Dev-671097587.ap-southeast-1.elb.amazonaws.com:8080 check 
     ###backstage service###
     backstage_api_dev:
       name: backstage_api_dev
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none         
       servers:
         - backstage_api_dev internal-ALB-BackstageApi-Dev-2107151475.ap-southeast-1.elb.amazonaws.com:8080 check          

     backstage_agent_api_dev:
       name: backstage_agent_api_dev
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none         
       servers:
         - backstage_agent_api_dev internal-ALB-BackstageAgentApi-Dev-1567630179.ap-southeast-1.elb.amazonaws.com:8080 check 

    ###message_center###
     message_center_dev:
       name: message_center_dev
       mode: http            
       options: 
         - "httpchk GET /health" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none         
       servers:
         - message_center_dev mc-dev.5gservice.com:8080 check

     message_center_uat:
       name: message_center_uat
       mode: http            
       options: 
         - "httpchk GET /health" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none         
       servers:
         - message_center_uat mc-uat.5gservice.com:80 check

     message_center_stage:
       name: message_center_stage
       mode: http            
       options: 
         - "httpchk GET /health" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none         
       servers:
         - message_center_stage mc-stage.5gservice.com:80 check 

    ###tournament###
     tournament_dev:
       name: tournament_dev
       mode: http            
       options: 
         - "httpchk GET /health" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none         
       servers:
         - tournament_dev tournament-dev.5gservice.com:8080 check

    ###bridge###
     bridge_dev:
       name: bridge_dev
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none         
       servers:
         - bridge_dev bridge-dev.5gservice.com:8080 check

    ###campaign###
     campaign_dev:
       name: campaign_dev
       mode: http            
       options: 
         - "httpchk GET /health" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none         
       servers:
         - campaign_dev campaign-dev.5gservice.com:8080 check

    ###game service###
     game_server_dev:
       name: game_server_dev
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none         
       servers:
         - game_server_dev internal-ALB-GameServer-Dev-1498468321.ap-southeast-1.elb.amazonaws.com:8080 check 

     tushar_gs_dev:
       name: tushar_gs_dev
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none         
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
         - resolvers awsdns resolve-prefer ipv4 init-addr none         
       servers:
         - game_engin_dev internal-ALB-GameEngine-Dev-494097733.ap-southeast-1.elb.amazonaws.com:443 ssl verify none check check-ssl alpn h2

     ###dal service### 
     dal_dev_elb:
       name: dal_dev_elb
       options: 
         - "tcp-check"               
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none              
       servers:
         - dal_dev_elb dal-dev.5gfafa.com:6969 check port 9696

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

