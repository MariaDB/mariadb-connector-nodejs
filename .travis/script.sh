#!/bin/bash

set -x
set -e

###################################################################################################################
# test different type of configuration
###################################################################################################################
if [ -n "$SKYSQL" ] || [ -n "$SKYSQL_HA" ]; then
  if [ -n "$SKYSQL" ] ; then
    if [ -z "$SKYSQL_HOST" ] ; then
      echo "No SkySQL configuration found !"
      exit 0
    else
      export TEST_USER=$SKYSQL_USER
      export TEST_HOST=$SKYSQL_HOST
      export TEST_PASSWORD=$SKYSQL_PASSWORD
      export TEST_PORT=$SKYSQL_PORT
      export TEST_SSL_CA=$SKYSQL_SSL_CA
    fi
  else
    if [ -z "$SKYSQL_HA_HOST" ] ; then
      echo "No SkySQL configuration found !"
      exit 0
    else
      export TEST_USER=$SKYSQL_HA_USER
      export TEST_HOST=$SKYSQL_HA_HOST
      export TEST_PASSWORD=$SKYSQL_HA_PASSWORD
      export TEST_PORT=$SKYSQL_HA_PORT
      export TEST_SSL_CA=$SKYSQL_HA_SSL_CA
    fi
  fi

else
  export TEST_USER=bob
  export TEST_HOST=mariadb.example.com
  export COMPOSE_FILE=.travis/docker-compose.yml
  export ENTRYPOINT=$PROJ_PATH/.travis/sql
  export ENTRYPOINT_PAM=$PROJ_PATH/.travis/pam

  if [[ "$DB" == build* ]] ; then
    .travis/build/build.sh
    docker build -t build:10.6 --label build .travis/build/
  fi

  if [ -n "$MAXSCALE_VERSION" ] ; then
    ###################################################################################################################
    # launch Maxscale with one server
    ###################################################################################################################
    export COMPOSE_FILE=.travis/maxscale-compose.yml

    docker-compose -f ${COMPOSE_FILE} build
    export TEST_PORT=4006
    export TEST_SSL_PORT=4009
    export TEST_USER=boby
    export TEST_PASSWORD=heyPassw0@rd
  fi

  docker-compose -f ${COMPOSE_FILE} up -d

  if [ -z "$SKIP_LEAK" ] ; then npm install node-memwatch; fi

  node .travis/wait-for-docker-up.js
  docker-compose -f ${COMPOSE_FILE} logs
  if [ -n "$MAXSCALE_VERSION" ] ; then
      docker-compose -f ${COMPOSE_FILE} exec maxscale tail -n 500 /var/log/maxscale/maxscale.log
  fi


  if [[ "$DB" != mysql* ]] ; then
    ###################################################################################################################
    # execute pam
    ###################################################################################################################
    docker-compose -f ${COMPOSE_FILE} exec -u root db bash /pam/pam.sh
    sleep 1
    docker-compose -f ${COMPOSE_FILE} restart db
    sleep 5

    ###################################################################################################################
    # wait for restart
    ###################################################################################################################
    node .travis/wait-for-docker-up.js
    docker-compose -f ${COMPOSE_FILE} logs
    if [ -n "$MAXSCALE_VERSION" ] ; then
        docker-compose -f ${COMPOSE_FILE} exec maxscale tail -n 500 /var/log/maxscale/maxscale.log
    fi
  fi
fi

if [ -n "$LINT" ] ; then npm run test:lint; fi
if [ -z "$BENCH$LINT" ] ; then npm run coverage:test; fi
if [ -n "$BENCH" ] ; then
  npm install promise-mysql mysql2
  npm install microtime
  npm run benchmark
fi
