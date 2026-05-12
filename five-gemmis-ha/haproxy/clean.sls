haproxy_clean_src_dir:
  cmd.run:
    - name: rm /usr/local/src -rf && mkdir -p /usr/local/src
