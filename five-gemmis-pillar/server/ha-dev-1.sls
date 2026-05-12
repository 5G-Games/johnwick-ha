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
      fe_tcp_memberdb_in:
        name: fe_tcp_memberdb_in
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

    ## no match any rule"
     no_acl_match:
       name: no_acl_match
       redirect: code 307 location http://localhost

