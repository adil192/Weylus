#!/usr/bin/env sh

function die {
    # cleanup to ensure restarting this script doesn't fail because
    # of ports that are still in use
    kill $(jobs -p) > /dev/null 2>&1
    rm -f index_tls.html
    exit $1
}

# generate certificate if it doesn't exist yet
if [ ! -e weylus.pem ]
then
    openssl req -batch -newkey rsa:4096 -sha256 -keyout weylus.key -nodes -x509 -days 365 \
        -subj="/CN=Weylus" -out weylus.crt

    # combine into a pem file as this is everything hitch needs
    cat weylus.key weylus.crt > weylus.pem
    rm weylus.key weylus.crt
fi

# WEYLUS can be used to determine which version of Weylus to run
# If unset, try ./weylus and then weylus from path. If both fail,
# read the path to Weylus from stdin.
if [ -z "$WEYLUS" ]
then
    if [ -e weylus ]
    then
        WEYLUS=./weylus
    else
        if which weylus > /dev/null 2>&1
        then
            WEYLUS=weylus
        else
            echo "Please specify path to weylus."
            echo -n "> "
            read -r WEYLUS
        fi
    fi
fi

if [ -z "$ACCESS_CODE" ]
then
    # generate access code if none is given
    ACCESS_CODE="$(openssl rand -base64 12)"
    echo "Autogenerated access code: $ACCESS_CODE"
fi

# cleanup on CTRL+C
trap die SIGINT

# The TLS proxy will be set up as follows:
# Proxy all incoming traffic from ports 1701 and 9001 to 1702 and
# 9002 on which the actual instance of Weylus is running.
#
# This means the websocket port that Weylus encodes into the
# index.html is the unencrypted port 9002 which is changed to the
# encrypted version on port 9001 by specifiying a custom index html.
$WEYLUS --print-index-html | sed 's/{{websocket_port}}/9001/' > index_tls.html

# start Weylus listening only on the local interface
$WEYLUS --custom-index-html index_tls.html \
    --bind-address 127.0.0.1 \
    --web-port 1702 \
    --websocket-port 9002 \
    --access-code "$ACCESS_CODE" \
    --no-gui &

# start the proxy
hitch --frontend=[0.0.0.0]:1701 --backend=[127.0.0.1]:1702 \
    --daemon=off --tls-protos="TLSv1.2 TLSv1.3" weylus.pem &

hitch --frontend=[0.0.0.0]:9001 --backend=[127.0.0.1]:9002 \
    --daemon=off --tls-protos="TLSv1.2 TLSv1.3" weylus.pem &

wait
