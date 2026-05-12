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
      fe_http_memberdb_in:
        name: fe_http_memberdb_in
        bind:
          - '*:3306' #member_db_std
          - '*:3366' #member_db_prod
        mode: tcp
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
         
    backends:
     backend member_db_std
       mode tcp
       option tcp-check
       timeout connect 5s
       timeout server 30s
       server member_db_std stdmysql-instance-1.cdgm8426ylrz.ap-southeast-1.rds.amazonaws.com:3306 check

     backend member_db_prod
       mode tcp
       option tcp-check
       timeout connect 5s
       timeout server 30s
       server member_db_prod stdmysql-instance-1.cdgm8426ylrz.ap-southeast-1.rds.amazonaws.com:3306 check       

    ## no match any rule"
     no_acl_match:
       name: no_acl_match
       redirect: code 307 location http://localhost

