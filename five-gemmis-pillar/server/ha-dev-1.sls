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

