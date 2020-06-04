#!/bin/bash

# Pulse Connect Secure (PCS) Hostname - <<SERVER HOST>> (eg vpn.pulsesecure.net)
# Pulse Connect Secure URL Path - <<SERVER URL PATH>>. (eg /division/)
# Pulse Connect Secure sign-in URL - <<SERVER URL>> (https://<<SERVER HOST>><<SERVER URL PATH>>) (eg https://vpn.pulsesecure.net/division/)
# VPN username - <<VPN USER>>
# VPN password - <<VPN PWD>>
# RSA SecureID PIN (static part) - <<RSA PIN>>
# RSA SecureID Token (dynamic part) - <<RSA TOKEN>>
# VPN secondary password (RSA SecureID PIN + Token) - <<RSA PIN>><<RSA TOKEN>> (<<VPN PWD2>>)
# Pulse Secure authentication realm - <<AUTH REALM>>

debug=

function getcookies
{
    local logindata="$1"
    local cookies2=
    { cookies2=$( sed -n '
        /Set-Cookie/ {
            s/Set-Cookie:[[:space:]]*//;
            s/;.*//;
            /=.\+/p
        }' |
        while read c; do
            echo -n "$c; ";
        done |
        sed 's/; $/\n/'
    ); } < <(echo "$logindata")
    echo "$cookies2"
}

function gettextarea
{
    local logindata="$1"
    local areaname="$2"

    local textarea=
    {
        # search for textarea tag with specified "name" parameter
        # remove open and close tags
        textarea=$(sed -n '
            /<textarea[^>]*name=["'\'']'$areaname'["'\''][^>]*>/,\,</textarea>, {
                s/^.*<textarea[^>]*>//;
                s,</textarea>.*$,,;
                p
        }' 
    ); } < <(echo "$logindata")
    echo "$textarea"
}


function getformdata
{
    local htmlline="$1"

    local formdata=$( echo "$htmlline" |
        # get only parameter-value pairs from inside of "input" tag
        sed -n '/^<\(input\|textarea\)/ {
            s/<\(input\|textarea\)[[:space:]]*//;
            s,[[:space:]]*[/]\?>,,g;
            s/\([^[:space:]]*\)="\([^"]*\)"[[:space:],]*/\1=\2:/g;
            p }' |
        # get parameters "name" and "value" and concatenate them to pair
        awk -F: '{
            value = "";
            for ( i = 1; i <= NF; i++ ) {
                if ( $i ~ /^name/ ) {
                    k = index($i, "=");
                    name = substr($i, k + 1)
                } else if ( $i ~ /^value/ ) {
                    k = index($i, "=");
                    value = substr($i, k+1)
                }
            };
            printf "%s=%s\n", name, value }'
    )
    echo "$formdata"
}

function usage
{
    cat << EOF
Usage: $0 -c [OPTIONS]
       $0 -g [OPTIONS]
       $0 -k

    -c              print only cookie to STDOUT
    -g              run Network Connect in GUI mod (Java required)
    -k              stop Network Connect daemon
    -u              username to use for VPN connection

EOF
}

# Alexander Ursu - 2015-06-22 !!! UPDATED
# Script for automatic Juniper VPN connection
# Requirements:
# 1) network connect software should be installed:
#    a) create folder:
#        mkdir -p ~/.juniper_networks/network_connect
#        mkdir -p /usr/local/nc
#    b) login to <<SERVER URL>>
#    c) download archive: https://<<SERVER HOST>>/dana-cached/nc/ncLinuxApp.jar
#       to ~/.juniper_networks folder
# UNDER root USER:
#    d) unpack it:
#        unzip ~/.juniper_networks/ncLinuxApp.jar -d /usr/local/nc
#    e) install next tools/libraries: glibc.i686, zlib.i686, libgcc.i686, gcc
#       glibc-devel.i686
#       on Ubuntu/Debian possible required: gcc-multilib
#    f) compile ncui console client:
#        cd /usr/local/nc
#        gcc -m32 -Wl,-rpath,/usr/local/nc -o ncui libncui.so
#    g) fix permissions:
#        chown -R 0:0 /usr/local/nc
#        chmod 755 /usr/local/nc 
#        chmod 6711 /usr/local/nc/ncsvc
# 2) curl should be installed (i.e. yum install curl) 
# 3) Packages: glibc.i686, zlib.i686, libgcc.i686 
#    Only for GUI:
#              libXrender.i686
#              libXtst.i686
# 4) Setup properly credentials below
# 5) Run this script under regular user (not root) (-h option for help)
# 6) to check if VPN is running use route -n (you should see different routing table than your default)
# 7) Only for GUI: Oracle JAVA i386 should be installed

JAVAi386=/usr/java/latest.i586/bin/java

UNAME=<<VPN USER>>
# LDAP password
PWD='<<VPN PWD>>'
# Secure PIN
PIN='<<RSA PIN>>'

HOST=<<SERVER HOST>>
ORIGIN="https://$HOST"
URLPATH="<<SERVER URL PATH>>"
IVEURL="${ORIGIN}$URLPATH"
# you can get from HTML source of login form
REALM="<<AUTH REALM>>"
LOGINP=login.cgi
logouturl="${ORIGIN}/dana-na/auth/logout.cgi"
JNCHOME=~/.juniper_networks/network_connect
CERTSTORE=$JNCHOME
JNCROOT=/usr/local/nc

UA="Mozilla/5.0 (X11; Linux i686 (x86_64)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/33.0.1750.152 Safari/537.36"

# Cookies JAR
CJAR=/tmp/cookies.jar
if [ -f $CJAR ]; then
    cp -a $CJAR{,.save}
fi
:> $CJAR

lastsess=
if [ -f "${CJAR}.save" ]; then
    laststmp=$(cat "${CJAR}.save" | awk '/DSFirstAccess/{print $NF}')
    if [ -n "$laststmp" ]; then
        lastsess=$(TZ="America/Toronto" date --date=@$laststmp +%m\/%d\/%Y\ %T)
    fi
fi

onlycookies=no
gui=no
dostop=no
while getopts ":cghku:" o; do
    case $o in
        h) 
            usage >&2 && exit 0
        ;;
        k)
            dostop=yes
        ;;
        c)
            onlycookies=yes
        ;;
        g)
            gui=yes
        ;;
        u)
            UNAME="$OPTARG"
        ;;
        \?)
            echo "ERROR: -$OPTARG not implemented." >&2
            usage >&2 && exit -1
        ;;
        :)
            echo "ERROR: -$OPTARG requires argument." >&2
            usage >&2 && exit -1
        ;;
    esac
done        

if [ "$dostop" == "yes" ]; then
    if [ ! -x $JNCROOT/ncsvc ]; then
        echo "ERROR: ncsvc daemon not compiled/installed properly" >&2
        exit -1
    fi

    echo "INFO: stop Network Connect daemon" >&2
    $JNCROOT/ncsvc -K
    
    exit 0
fi

# get own IP address
dnsc=$(which dig 2>/dev/null)
myip=
if [ -n "$dnsc" ]; then
#    myip=$(dig txt o-o.myaddr.l.google.com @ns1.google.com +short)
    myip=$(dig myip.opendns.com @resolver1.opendns.com +short)
fi

if [ -n "$myip" ]; then
    echo "INFO: my IP address: $myip" >&2
fi

if [ -n "$lastsess" ]; then
    echo "INFO: last session login time: $lastsess"
fi

# follow to Signin URL
# to get login page address (Location response header)
# and initial cookies

echo "INFO: go to access point $IVEURL" >&2

greetings=$( curl -k $IVEURL -i -A "$UA" -c $CJAR 2>/dev/null |
    sed -n '
        /[Ll]ocation/ { s/[Ll]ocation:[[:space:]]*//;
                        s/\r//p
        };
        /Set-Cookie/  {
                       s/Set-Cookie:[[:space:]]*//;
                       s/;.*//;
                       /=.\+/p
        }'
)

location=
cookies=
{   read location;
    cookies=$( while read c; do
            echo -n "$c; ";
        done |
        sed 's/; $/\n/'
    )
} < <(echo "$greetings")

# Login URL
loginurl="${location%/*}/$LOGINP"
# if returned relative URL 
if [ -z "${location%%/*}" ]; then
   loginurl="${ORIGIN}${loginurl}" 
fi

echo "INFO: login url $loginurl" >&2

securekey=
if [ -n "$loginurl" ]; then
    echo "INFO: Username: $UNAME" >&2
    if [ -z "$PWD" -o -z "$PIN" ]; then
        read -s -p 'Enter SecureKey: ' securekey
        echo >&2
        read -s -p 'Password: ' PWD
        echo >&2
    else
        # read RSA Token
        read -p 'RSA SecurID: ' securid
        securekey="${PIN}$securid"
    fi
else
    echo "Try again!" >&2
    exit -1
fi

echo "INFO: send login data to $loginurl" >&2

# send Login POST request
if [ -n "$debug" ]; then
    echo "DEBUG: curl -k $loginurl -i -c $CJAR -A \"$UA\" -e \"$location\" -H \"Origin: $ORIGIN\" --data-urlencode 'tz_offset=120' --data-urlencode \"username=$UNAME\" --data-urlencode \"password=$PWD\" --data-urlencode \"realm=$REALM\" --data-urlencode \"password#2=$securekey\" 2>/dev/null"
    echo
fi

logindata=$(curl -k $loginurl -i -c $CJAR -A "$UA" -e "$location" \
    -H "Origin: $ORIGIN"  \
    --data-urlencode 'tz_offset=120' \
    --data-urlencode "username=$UNAME" \
    --data-urlencode "password=$PWD" \
    --data-urlencode "realm=$REALM" \
    --data-urlencode "password#2=$securekey" 2>/dev/null
)

# check "New PIN Required"
if echo "$logindata" | grep -q "New PIN Required\|Sign-In NewPin\|NewPinMode"; then
    echo "ALERT: You must create a new Personal Identification Number (PIN) before you can sign in. Please login into $IVEURL manually and proceed required actions" >&2
    exit -1
fi

cookies2=$(getcookies "$logindata")

# check if POST request sent OK (Set-Cookie response headers exist)
if [ -z "$cookies2" ]; then

    echo "INFO: not logged in, loop through possible issues" >&2

    while [ -z "$cookies2" ]; do {

        echo "INFO: cookies are not set (some troubles?)" >&2

        sessp=$( sed -n '/[Ll]ocation/ { s/[Ll]ocation:[[:space:]]*//; s/\r//p }' )
        [ -n "$sessp" ] && {
            if [ -z "${sessp%%/*}" ]; then
                sessp="${ORIGIN}${sessp}"
            fi

            echo "INFO: redirect exists to $sessp" >&2

            # receive page content with session list and management form
            postauth=$(curl -k "$sessp" -c $CJAR -A "$UA" 2>/dev/null)

            # convert HTML page to single string and move "input" and "textarea" tags to separate lines
            htmlline=$( echo "$postauth" |
                sed ':a;
                     N;
                     $! ba;
                     s/\n//g;
                     s/\(<input[^>]*>\)/\n\1\n/g;
                     s/\(<textarea[^>]*>\)/\n\1\n/g;
                     s,\(</textarea>\),\n\1\n,g'
            )

            lastsesshtml=
            if [ -n "$lastsess" ]; then
                 lastsesshtml=$(echo "$htmlline" | grep -B 1 "$lastsess")
            fi

            lastsessid=
            if [ -n "$lastsess" -a -n "$lastsesshtml" ]; then
                lastsessid=$(getformdata "$lastsesshtml")
            fi

            # get all "input" and "textarea" elements' data in form key=value list
            formdata=$(getformdata "$htmlline") 

            # Check if this is URL to "PCS Access Service - Confirmation Open Sessions" page
            if echo "$sessp" | grep -q "p=user-confirm"; then

                echo "INFO: received Confirmation Open Sessions page" >&2

                # generate POST parameters based on parsed data
                postdata=$( echo "$formdata" |
                    # remove "Cancel" button action
                    grep -v ^btnCancel |
                    # create POST data in form of curl option list
                    {
                        d="";
                        while read p; do
                            k=${p%%=*}
                            v=${p#*=}
                            if [ -z "$lastsessid" -o "${lastsessid/$k/}" == "$lastsessid" -o "${lastsessid/$v/}" != "$lastsessid" ]; then
                                d="$d --data-urlencode '$k=$v'";
                            fi
                        done;
                        echo "$d";
                    }
                )
                if echo "$postdata" | grep -q FormDataStr; then
                    cmd="curl $postdata -k -i -c $CJAR -A '$UA' -e '$sessp' $loginurl"

                    echo "INFO: form submitted to release all sessions and relogin" >&2

                    data=$(eval $cmd 2>/dev/null)

                    cookies2=$(getcookies "$data")
                    logindata="$data"
                else
                    echo "ERROR: Error occured during open sessions management. Please use this URL: $sessp
to resolve the issue" >&2
                    exit -1
                fi
            # Check if this is URL to "PCS Access Service - Sign-In Notification" page
            elif echo "$sessp" | grep -q "p=sn-postauth-show"; then

                echo "INFO: received Sign-In Notification page" >&2

                # proceed with agreement confirmation
                # generate POST parameters based on parsed data
                postdata=$(
                    # create POST data in form of curl option list
                    {
                        d="";
                        while read p; do
                            name=${p%%=*}
                            value=${p#*=}
                            # if value is empty - try to get it from textarea field with "name" field matched
                            if [ -z "$value" ]; then
                                value=$(gettextarea "$postauth" "$name")
                            fi
                            # send to server only if value is set
                            if [ -n "$value" ]; then 
                                d="$d --data-urlencode '$name=$value'"
                            fi
                        done;
                        echo "$d";
                    } < <( echo "$formdata" | 
                            # remove "Decline" button action
                            grep -v ^sn-postauth-decline )
                )

                if echo "$postdata" | grep -q sn-postauth-text; then
                    cmd="curl $postdata -k -i -c $CJAR -A '$UA' -e '$sessp' $loginurl"

                    echo "INFO: form submitted to confirm user agreement" >&2

                    data=$(eval $cmd 2>/dev/null)

                    cookies2=$(getcookies "$data")
                    logindata="$data"
                else
                    echo "ERROR: Error occured during open sign-in notification. Please use this URL: $sessp
to resolve the issue" >&2
                    exit -1
                fi
            else
                echo "ERROR: Please use this URL: $sessp 
to resolve the issue" >&2
                exit -1
            fi;
        } || break
    } < <(echo "$logindata"); done
fi

# We need DSID= cookie value only
DSID="DSID="
if [ -n "$cookies2" ]; then
    DSID=$(echo $cookies2 | sed 's/.*\(DSID=\)/\1/; s/;.*//' )
fi

# prepare cookies for NC java applet use
STAMP=$(date +%s)
cookies="$cookies; $cookies2; DSLastAccess=$STAMP; path=/; secure"

# create certificate store dir
mkdir -p $CERTSTORE

echo "INFO: get $HOST SSL certificate" >&2

# get PCS host certificate
pemcert=$(echo |
    openssl s_client -connect $HOST:443 2>/dev/null |
    sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p')

if [ -n "$pemcert" ]; then
    echo "$pemcert" > $CERTSTORE/${HOST}.pem
    echo "$pemcert" | openssl x509 -outform DER -out $CERTSTORE/${HOST}.crt
else
    echo "ERROR: Can not get certificate from $HOST" >&2
    exit -1
fi

# get PCS host certificate's md5 fingerprint
fingerp=$(echo "$pemcert" |
    openssl x509 -noout -fingerprint -md5 |
    sed 's/MD5 Fingerprint=//g; s/://g' |
    tr 'A-Z' 'a-z'
)

if [ "$onlycookies" == "yes" ]; then
    echo $DSID
    exit 0
fi

echo "INFO: run Network Connect software" >&2

if [ "$(uname -m)" == "aarch64" ]; then
    openconnect --background --juniper -C "$DSID" $HOST
    exit 0
fi

if [ "$gui" == "yes" ]; then
    if [ ! -f $JNCROOT/NC.jar ]; then
        echo "ERROR: Network Connect not installed properly" >&2
        echo "ERROR: You can download it here (after login):
https://$HOST/dana-cached/nc/ncLinuxApp.jar" >&2
        exit -1
    fi

    if [ ! -x $JAVAi386 ]; then
        echo "ERROR: Java JRE should be availble here: $JAVAi386" >&2
        echo "ERROR: Does not exist!" >&2
        exit -1
    fi 

    # run Networ Connector java applet with proper parameters
    echo "cookie
$cookies
ivehost
$HOST
cert_md5
$fingerp
action
install" |  $JAVAi386 \
    -classpath $JNCROOT/NC.jar NC -h $HOST \
    -n -t -x -l 5 -L 5 1>/dev/null 2>/dev/null &
else
    if [ ! -f $JNCROOT/ncui ]; then
        echo "ERROR: ncui client not compiled/installed properly" >&2
        exit -1
    fi   
    #echo "DEBUG: echo $PWD | $JNCROOT/ncui -h $HOST -c $DSID -f $CERTSTORE/${HOST}.crt -U \"$IVEURL\" 1>/dev/null 2>/dev/null" >&2
    echo $PWD | $JNCROOT/ncui -h $HOST -c $DSID -f $CERTSTORE/${HOST}.crt -U "$IVEURL" &

fi
