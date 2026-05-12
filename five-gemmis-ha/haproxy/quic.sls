{% set source = '/usr/local/src' -%}

#openssl-quic-install:
#  cmd.run:
#    - name: |
#           source /root/.bashrc
#           cd {{ source }}
#           git config --global user.email "cook@eth2.com"
#           git config --global user.name "cook"
#           git config --global https.proxy http.proxy http://proxy.jumbo98.com:3128
#           git clone https://github.com/quictls/openssl.git
#           cd openssl
#           ./config --libdir=lib --prefix=/opt/quictls
#           make
#           make install

openssl-quic-install:
  file.managed:
    - name: {{ source }}/openssl-3.0.3+quic.zip
    - source: salt://haproxy/files/openssl-3.0.3+quic.zip
    - user: root
    - group: root
    - mode: 755
  cmd.run:
    - name: |
            cd {{ source }} && rm -rf openssl-openssl-3.0.3-quic && unzip openssl-3.0.3+quic.zip
            cd openssl-openssl-3.0.3-quic 
            ./Configure enable-tls1_3 --libdir=lib --prefix=/opt/quictls \
            -g -O2 -fstack-protector-strong -Wformat -Werror=format-security \
            -DOPENSSL_TLS_SECURITY_LEVEL=2 -DOPENSSL_USE_NODELETE -DL_ENDIAN \
            -DOPENSSL_PIC -DOPENSSL_CPUID_OBJ -DOPENSSL_IA32_SSE2 \
            -DOPENSSL_BN_ASM_MONT -DOPENSSL_BN_ASM_MONT5 -DOPENSSL_BN_ASM_GF2m \
            -DSHA1_ASM -DSHA256_ASM -DSHA512_ASM -DKECCAK1600_ASM -DMD5_ASM \
            -DAESNI_ASM -DVPAES_ASM -DGHASH_ASM -DECP_NISTZ256_ASM -DX25519_ASM \
            -DX448_ASM -DPOLY1305_ASM -DNDEBUG -Wdate-time -D_FORTIFY_SOURCE=2 \
            make
            make install
            cp /opt/quictls/lib/libcrypto.so /usr/lib/
            cp /opt/quictls/lib/libssl.so /usr/lib/
            ldconfig
            /opt/quictls/bin/openssl version -a
    - require:
      - file: openssl-quic-install
    - watch:
      - file: openssl-quic-install
