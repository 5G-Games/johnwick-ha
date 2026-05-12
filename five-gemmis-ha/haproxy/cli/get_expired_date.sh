#for pem in config/*/ssl/* ; do
#    NEW_EPOCH=`date +%s`
#    EXPIRY_DATE=`openssl x509 -noout -enddate -in "$pem"| cut -d"=" -f 2`
#    EXPIRY_EPOCH=`date -d "$EXPIRY_DATE" +%s`
#    EXPIRY_DAYS="$(( ( $EXPIRY_EPOCH - $NEW_EPOCH ) / (3600 * 24) ))"
#    EXP=`(( $EXPIRY_DAYS >= 0 )) && echo "" || echo Expired`
#    PEM_CN=`openssl x509 -noout -subject -in "$pem"| cut -d "=" -f 3`
#    printf '%-60s %-45s %20s %10s %s\n' "$pem" "$PEM_CN" "$EXPIRY_DATE" "$EXPIRY_DAYS days" "$EXP"
#done | sort -k4 -n

#COLOR TAG
RED='\033[0;31m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

for pem in  config/*/ssl/* ; do
    ISSUER=$(openssl x509 -in $pem -issuer  -noout | awk -F ', ' '{print $2}' | awk -F '= ' '{print $2}')
    NEW_EPOCH=`date +%s`
    EXPIRY_DATE=`openssl x509 -noout -enddate -in "$pem"| cut -d"=" -f 2`
    EXPIRY_EPOCH=`date -d "$EXPIRY_DATE" +%s`
    EXPIRY_DAYS="$(( ( $EXPIRY_EPOCH - $NEW_EPOCH ) / (3600 * 24) ))"
    #EXP=`(( $EXPIRY_DAYS >= 0 )) && echo "" || echo Expired`
    EXP=`
    if (( $EXPIRY_DAYS < 0 ))
    then
          printf "$RED Expired $NC"
    elif (( $EXPIRY_DAYS <= 7 ))
    then
          printf "$ORANGE Warning $NC"
    else
         echo "       "
    fi`
    PEM_CN=`openssl x509 -noout -subject -in "$pem"| cut -d "=" -f 3`
    arr=$(openssl x509 -noout -ext subjectAltName -in $pem | grep DNS | sed -e 's/^[ \t]*//' | sed 's/, /\n/g')
    printf '%-20s %-55s %-28s %20s %10s %9s %-45s\n' "$ISSUER" "$pem" "$PEM_CN" "$EXPIRY_DATE" "$EXPIRY_DAYS days" "$EXP" "${arr[@]}"
done | sed -e 's/^DNS:/                                                                                                                                                        DNS:/g'
