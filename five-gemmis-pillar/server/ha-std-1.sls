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
          - set-header X-Real-IP %[src]
          - set-header X-Client-IP %[src]
          - set-header True-Client-IP %[src]
          - set-header X-Forwarded-For %[src]
          - set-header X-Forwarded-Proto https if { ssl_fc }
          - set-header X-Forwarded-Proto http if ! { ssl_fc }       
          - add-header cf %[req.hdr(CF-Connecting-IP)]
        ###CORS domain role###  
          - set-var(txn.origin) req.hdr(Origin) 
          - return status 204 hdr Access-Control-Allow-Origin "%[var(txn.origin)]" hdr Access-Control-Allow-Methods "PUT, GET, POST, OPTIONS" hdr Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept, Authorization, sentry-trace, baggage" hdr Access-Control-Allow-Credentials "true" if { method OPTIONS }
        http_response:
          - del-header Server
          - del-header X-Powered-By
        ###CORS domain role###           
        http_after_response:
          - set-header Access-Control-Allow-Origin "%[var(txn.origin)]"
          - set-header Access-Control-Allow-Credentials "true"

        default_backend:
          - no_acl_match

        acl:
          - source_is_serious_abuse src_conn_rate(fe_http_gs_in) gt 1000
          - conn_rate_abuse         sc1_conn_rate gt 30
          - mark_as_abuser          sc1_inc_gpc0  ge 0
          - source_is_abuser        src_get_gpc0(fe_http_gs_in) gt 50

        ##infra rule##
          - hd_check_server path_reg -i ^/6969

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
          #- header_print if hd_check_server 5g_offcie_ip
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/game.map)]" if gs_sub gs_domain'
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/stage.map)]" if stage_sub std_domain'          
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/api.map)]" if api_sub api_domain 5g_offcie_ip'
          - '"%[req.hdr(host),lower,map_sub(/etc/haproxy/hostmap/dev.map)]" if dev_sub std_domain 5g_offcie_ip'
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
         - demoapi_dev internal-ALB-DemoApi-Dev-877871421.ap-southeast-1.elb.amazonaws.com:8080 check 

    ###game service###
     game_dev:
       name: game_dev
       mode: http            
       options: 
         - "httpchk GET /alive" 
       default-servers:
         - resolvers awsdns resolve-prefer ipv4 init-addr none         
       servers:
         - game_dev NLB-GameServer-Dev-83fa74183f53a6da.elb.ap-southeast-1.amazonaws.com:8080 check 



     ####infra service#ß##
     #header_print:
     #  name: header_print
     #  options: 
     #    - "tcp-check"                
     #  servers:
     #    - header_print internal-ALB-MessageCenterApi-Dev-1727792962.ap-east-1.elb.amazonaws.com:80 check


    ## no match any rule"
     no_acl_match:
       name: no_acl_match
       redirect: code 307 location http://localhost

