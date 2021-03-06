#!/bin/bash
set -e

function init_pgp(){
    echo "####################################"
    echo "PGP Key exists and copy it to MISP webroot"
    echo "####################################"

    # Copy public key to the right place
    sudo -u www-data sh -c "cp /var/www/MISP/.gnupg/public.key /var/www/MISP/app/webroot/gpg.asc"
    ### IS DONE VIA ANSIBLE: # And export the public key to the webroot
    ### IS DONE VIA ANSIBLE: #sudo -u www-data sh -c "gpg --homedir /var/www/MISP/.gnupg --export --armor $SENDER_ADDRESS > /var/www/MISP/app/webroot/gpg.asc"
}

function init_smime(){
    echo "####################################"
    echo "S/MIME Cert exists and copy it to MISP webroot"
    echo "####################################"
    ### Set permissions
    chown www-data:www-data /var/www/MISP/.smime
    chmod 500 /var/www/MISP/.smime
    ## Export the public certificate (for Encipherment) to the webroot
    sudo -u www-data sh -c "cp /var/www/MISP/.smime/cert.pem /var/www/MISP/app/webroot/public_certificate.pem"
    #Due to this action, the MISP users will be able to download your public certificate (for Encipherment) by clicking on the footer
    ### Set permissions
    #chown www-data:www-data /var/www/MISP/app/webroot/public_certificate.pem
    sudo -u www-data sh -c "chmod 440 /var/www/MISP/app/webroot/public_certificate.pem"
}

function start_workers(){
    # start Workers for MISP
    su -s /bin/bash -c "/var/www/MISP/app/Console/worker/start.sh" www-data
}

function init_apache() {
    echo "####################################  started Apache2 with cmd: '$CMD_APACHE' ####################################"
    # Apache gets grumpy about PID files pre-existing
    rm -f /run/apache2/apache2.pid
    #exec apache2 -DFOREGROUND
    # start workers
    start_workers
    /usr/sbin/apache2ctl -DFOREGROUND $1
}

function add_analyze_column(){
    ORIG_FILE="/var/www/MISP/app/View/Elements/Events/eventIndexTable.ctp"
    PATCH_FILE="/eventIndexTable.patch"

    # Backup Orig File
    cp $ORIG_FILE ${ORIG_FILE}.bak
    # Patch file
    patch $ORIG_FILE < $PATCH_FILE
}

function change_php_vars(){
    [ -z ${PHP_MEMORY} ] && PHP_MEMORY=512
    for FILE in $(ls /etc/php/*/apache2/php.ini)
    do
        sed -i "s/memory_limit = .*/memory_limit = ${PHP_MEMORY}M/" $FILE
        sed -i "s/max_execution_time = .*/max_execution_time = 300/" $FILE
        sed -i "s/upload_max_filesize = .*/upload_max_filesize = 50M/" $FILE
        sed -i "s/post_max_size = .*/post_max_size = 50M/" $FILE
    done
}

function setup_via_cake_cli(){
    PATH_TO_MISP="/var/www/MISP"
    CAKE="$PATH_TO_MISP/app/Console/cake"
    # Initialize user and fetch Auth Key
    #sudo -E $CAKE userInit -q
    export AUTH_KEY=$(mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE -e "SELECT authkey FROM users;" | tail -1)
    # Setup some more MISP default via cake CLI
    # Tune global time outs
    sudo $CAKE Admin setSetting "Session.autoRegenerate" 0
    sudo $CAKE Admin setSetting "Session.timeout" 600
    sudo $CAKE Admin setSetting "Session.cookie_timeout" 3600
    # Enable GnuPG
    sudo $CAKE Admin setSetting "GnuPG.email" "$SENDER_ADDRESS"
    sudo $CAKE Admin setSetting "GnuPG.homedir" "$PATH_TO_MISP/.gnupg"
    #sudo $CAKE Admin setSetting "GnuPG.password" ""
    # Enable Enrichment set better timeouts
    sudo $CAKE Admin setSetting "Plugin.Enrichment_services_enable" true
    sudo $CAKE Admin setSetting "Plugin.Enrichment_hover_enable" true
    sudo $CAKE Admin setSetting "Plugin.Enrichment_timeout" 300
    sudo $CAKE Admin setSetting "Plugin.Enrichment_hover_timeout" 150
    sudo $CAKE Admin setSetting "Plugin.Enrichment_cve_enabled" true
    sudo $CAKE Admin setSetting "Plugin.Enrichment_dns_enabled" true
    sudo $CAKE Admin setSetting "Plugin.Enrichment_services_url" "http://misp-modules"
    sudo $CAKE Admin setSetting "Plugin.Enrichment_services_port" 6666
    # Enable Import modules set better timout
    sudo $CAKE Admin setSetting "Plugin.Import_services_enable" true
    sudo $CAKE Admin setSetting "Plugin.Import_services_url" "http://misp-modules"
    sudo $CAKE Admin setSetting "Plugin.Import_services_port" 6666
    sudo $CAKE Admin setSetting "Plugin.Import_timeout" 300
    sudo $CAKE Admin setSetting "Plugin.Import_ocr_enabled" true
    sudo $CAKE Admin setSetting "Plugin.Import_csvimport_enabled" true
    # Enable Export modules set better timout
    sudo $CAKE Admin setSetting "Plugin.Export_services_enable" true
    sudo $CAKE Admin setSetting "Plugin.Export_services_url" "http://misp-modules"
    sudo $CAKE Admin setSetting "Plugin.Export_services_port" 6666
    sudo $CAKE Admin setSetting "Plugin.Export_timeout" 300
    sudo $CAKE Admin setSetting "Plugin.Export_pdfexport_enabled" true
    # Enable installer org and tune some configurables
    sudo $CAKE Admin setSetting "MISP.host_org_id" 1
    sudo $CAKE Admin setSetting "MISP.email" "$SENDER_ADDRESS"
    sudo $CAKE Admin setSetting "MISP.disable_emailing" true
    sudo $CAKE Admin setSetting "MISP.contact" "$SENDER_ADDRESS"
    # sudo $CAKE Admin setSetting "MISP.disablerestalert" true
    # sudo $CAKE Admin setSetting "MISP.showCorrelationsOnIndex" true
    # Provisional Cortex tunes
    # sudo $CAKE Admin setSetting "Plugin.Cortex_services_enable" false
    # sudo $CAKE Admin setSetting "Plugin.Cortex_services_url" "http://127.0.0.1"
    # sudo $CAKE Admin setSetting "Plugin.Cortex_services_port" 9000
    # sudo $CAKE Admin setSetting "Plugin.Cortex_timeout" 120
    # sudo $CAKE Admin setSetting "Plugin.Cortex_services_url" "http://127.0.0.1"
    # sudo $CAKE Admin setSetting "Plugin.Cortex_services_port" 9000
    # sudo $CAKE Admin setSetting "Plugin.Cortex_services_timeout" 120
    # sudo $CAKE Admin setSetting "Plugin.Cortex_services_authkey" ""
    # sudo $CAKE Admin setSetting "Plugin.Cortex_ssl_verify_peer" false
    # sudo $CAKE Admin setSetting "Plugin.Cortex_ssl_verify_host" false
    # sudo $CAKE Admin setSetting "Plugin.Cortex_ssl_allow_self_signed" true
    # Various plugin sightings settings
    # sudo $CAKE Admin setSetting "Plugin.Sightings_policy" 0
    # sudo $CAKE Admin setSetting "Plugin.Sightings_anonymise" false
    # sudo $CAKE Admin setSetting "Plugin.Sightings_range" 365
    # Plugin CustomAuth tuneable
    # sudo $CAKE Admin setSetting "Plugin.CustomAuth_disable_logout" false
    # RPZ Plugin settings
    # sudo $CAKE Admin setSetting "Plugin.RPZ_policy" "DROP"
    # sudo $CAKE Admin setSetting "Plugin.RPZ_walled_garden" "127.0.0.1"
    # sudo $CAKE Admin setSetting "Plugin.RPZ_serial" "\$date00"
    # sudo $CAKE Admin setSetting "Plugin.RPZ_refresh" "2h"
    # sudo $CAKE Admin setSetting "Plugin.RPZ_retry" "30m"
    # sudo $CAKE Admin setSetting "Plugin.RPZ_expiry" "30d"
    # sudo $CAKE Admin setSetting "Plugin.RPZ_minimum_ttl" "1h"
    # sudo $CAKE Admin setSetting "Plugin.RPZ_ttl" "1w"
    # sudo $CAKE Admin setSetting "Plugin.RPZ_ns" "localhost."
    # sudo $CAKE Admin setSetting "Plugin.RPZ_ns_alt" ""
    # sudo $CAKE Admin setSetting "Plugin.RPZ_email" "$SENDER_ADDRESS"
    # Force defaults to make MISP Server Settings less RED
    sudo $CAKE Admin setSetting "MISP.language" "eng"
    #sudo $CAKE Admin setSetting "MISP.proposals_block_attributes" false
    # Redis block
    sudo $CAKE Admin setSetting "MISP.redis_host" "127.0.0.1"
    sudo $CAKE Admin setSetting "MISP.redis_port" 6379
    sudo $CAKE Admin setSetting "MISP.redis_database" 13
    sudo $CAKE Admin setSetting "MISP.redis_password" ""
    # Force defaults to make MISP Server Settings less YELLOW
    # sudo $CAKE Admin setSetting "MISP.ssdeep_correlation_threshold" 40
    # sudo $CAKE Admin setSetting "MISP.extended_alert_subject" false
    # sudo $CAKE Admin setSetting "MISP.default_event_threat_level" 4
    # sudo $CAKE Admin setSetting "MISP.newUserText" "Dear new MISP user,\\n\\nWe would hereby like to welcome you to the \$org MISP community.\\n\\n Use the credentials below to log into MISP at \$misp, where you will be prompted to manually change your password to something of your own choice.\\n\\nUsername: \$username\\nPassword: \$password\\n\\nIf you have any questions, don't hesitate to contact us at: \$contact.\\n\\nBest regards,\\nYour \$org MISP support team"
    # sudo $CAKE Admin setSetting "MISP.passwordResetText" "Dear MISP user,\\n\\nA password reset has been triggered for your account. Use the below provided temporary password to log into MISP at \$misp, where you will be prompted to manually change your password to something of your own choice.\\n\\nUsername: \$username\\nYour temporary password: \$password\\n\\nIf you have any questions, don't hesitate to contact us at: \$contact.\\n\\nBest regards,\\nYour \$org MISP support team"
    # sudo $CAKE Admin setSetting "MISP.enableEventBlacklisting" true
    # sudo $CAKE Admin setSetting "MISP.enableOrgBlacklisting" true
    # sudo $CAKE Admin setSetting "MISP.log_client_ip" false
    # sudo $CAKE Admin setSetting "MISP.log_auth" false
    # sudo $CAKE Admin setSetting "MISP.disableUserSelfManagement" false
    # sudo $CAKE Admin setSetting "MISP.block_event_alert" false
    # sudo $CAKE Admin setSetting "MISP.block_event_alert_tag" "no-alerts=\"true\""
    # sudo $CAKE Admin setSetting "MISP.block_old_event_alert" false
    # sudo $CAKE Admin setSetting "MISP.block_old_event_alert_age" ""
    # sudo $CAKE Admin setSetting "MISP.incoming_tags_disabled_by_default" false
    # sudo $CAKE Admin setSetting "MISP.footermidleft" "This is an initial install"
    # sudo $CAKE Admin setSetting "MISP.footermidright" "Please configure and harden accordingly"
    # sudo $CAKE Admin setSetting "MISP.welcome_text_top" "Initial Install, please configure"
    # sudo $CAKE Admin setSetting "MISP.welcome_text_bottom" "Welcome to MISP, change this message in MISP Settings"
    
    # Force defaults to make MISP Server Settings less GREEN
    # sudo $CAKE Admin setSetting "Security.password_policy_length" 16
    # sudo $CAKE Admin setSetting "Security.password_policy_complexity" '/^((?=.*\d)|(?=.*\W+))(?![\n])(?=.*[A-Z])(?=.*[a-z]).*$|.{16,}/'
    # Tune global time outs
    sudo $CAKE Admin setSetting "Session.autoRegenerate" 0
    sudo $CAKE Admin setSetting "Session.timeout" 600
    sudo $CAKE Admin setSetting "Session.cookie_timeout" 3600
    # Set MISP Live
    # sudo $CAKE Live 1
    # Update the galaxies…
    # sudo $CAKE Admin updateGalaxies
    # Updating the taxonomies…
    # sudo $CAKE Admin updateTaxonomies
    # Updating the warning lists…
    # sudo $CAKE Admin updateWarningLists
    # Updating the notice lists…
    # sudo $CAKE Admin updateNoticeLists
    #curl --header "Authorization: $AUTH_KEY" --header "Accept: application/json" --header "Content-Type: application/json" -k -X POST https://127.0.0.1/noticelists/update
    
    # Updating the object templates…
    # sudo $CAKE Admin updateObjectTemplates
    #curl --header "Authorization: $AUTH_KEY" --header "Accept: application/json" --header "Content-Type: application/json" -k -X POST https://127.0.0.1/objectTemplates/update

    # Delete the initial decision file:
    rm "/var/www/MISP/app/Config/NOT_CONFIGURED"
}

function upgrade(){
    # OLDEST SUPPORTED VERSION TAG 0.2.0
    
    
    # LIST of VOLUMES:
    # - misp-vol-server-apache2-config-sites-enabled:/etc/apache2/sites-enabled:ro
    # - misp-vol-ssl:/etc/apache2/ssl:ro
    # - misp-vol-pgp:/var/www/MISP/.gnupg
    # - misp-vol-smime:/var/www/MISP/.smime
    # - misp-vol-server-MISP-app-Config:/var/www/MISP/app/Config
    # - misp-vol-server-MISP-cakeresque-config:/var/www/MISP/app/Plugin/CakeResque/Config
    VOLUMES="/etc/apache2/sites-enabled \
            /etc/apache2/ssl \
            /var/www/MISP/.gnupg \
            /var/www/MISP/.smime \
            /var/www/MISP/app/Config \
            /var/www/MISP/app/Plugin/CakeResque/Config \
            "
    for v in $VOLUMES
    do
        # if no Version Tag exists in VOLUME create one with the current version
        [ -f $v/$NAME ] || echo "$VERSION" >> $v/$NAME

        case $(echo $v/$NAME) in
        2.4.92)
            # Tasks todo in 2.4.92
            echo "#### Upgrade Volumes from 2.4.92    ####"
            ;;
        *)
            echo "Unknown Version, upgrade not possible."
            exit
            ;;
        esac



    done

}

# if secring.pgp exists execute init_pgp
[ -f "/var/www/MISP/.gnupgp/public.key" ] && init_pgp
# If certificate exists execute init_smime
[ -f "/var/www/MISP/.smime/cert.pem" ] && init_smime

# If a customer needs a analze column in misp
[ "$ADD_ANALYZE_COLUMN" == "yes" ] && add_analyze_column

# Change PHP VARS
change_php_vars

# check if setup is new: - in the dockerfile i create on this path a empty file to decide is the configuration completely new or not
[ -f "/var/www/MISP/app/Config/NOT_CONFIGURED" -a -f "/var/www/MISP/app/Config/database.php"  ] && setup_via_cake_cli

# execute apache
[ "$CMD_APACHE" != "none" ] && init_apache $CMD_APACHE
[ "$CMD_APACHE" == "none" ] && init_apache
