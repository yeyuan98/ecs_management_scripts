#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Postfix Aliyun SMTPDM Auto Setup Script ===${NC}"

# Auto-detect system settings
AUTO_HOSTNAME=$(hostname -f 2>/dev/null || hostname)
AUTO_LOCAL_HOSTNAME=$(hostname)
DEFAULT_RELAY_HOST="smtpdm.aliyun.com"
DEFAULT_RELAY_PORT="465"

# Prompt for user input with sensible defaults
read -p "Enter your fully qualified domain name (FQDN) [$AUTO_HOSTNAME]: " MY_HOSTNAME
MY_HOSTNAME=${MY_HOSTNAME:-$AUTO_HOSTNAME}

read -p "Enter your authenticated email address: " SENDER_EMAIL
while [[ -z "$SENDER_EMAIL" ]]; do
    echo -e "${RED}Please enter your verified Aliyun sender email address${NC}"
    read -p "Authenticated email address: " SENDER_EMAIL
done

read -sp "Enter your Aliyun SMTP Authorization Code: " SMTP_PASSWORD
echo ""

read -p "SMTP relay host [$DEFAULT_RELAY_HOST]: " RELAY_HOST
RELAY_HOST=${RELAY_HOST:-$DEFAULT_RELAY_HOST}

read -p "SMTP relay port [$DEFAULT_RELAY_PORT]: " RELAY_PORT
RELAY_PORT=${RELAY_PORT:-$DEFAULT_RELAY_PORT}

# Step1: Cleanup existing broken Postfix installation
echo -e "${YELLOW}1. Cleaning up existing installation...${NC}"
systemctl stop postfix || true
apt purge --yes postfix > /dev/null 2>&1
rm -rf /etc/postfix /etc/systemd/system/postfix.service /var/spool/postfix/pid/*

# Step2: Install fresh Postfix
echo -e "${YELLOW}2. Installing fresh Postfix...${NC}"
debconf-set-selections <<< "postfix postfix/main_mailer_type select Internet Site"
debconf-set-selections <<< "postfix postfix/mailname string $MY_HOSTNAME"
apt install --yes postfix > /dev/null 2>&1

# Step3: Configure main.cf dynamically (fixed macro processing error)
echo -e "${YELLOW}3. Configuring Postfix main.cf...${NC}"
TLS_WRAPPER_MODE="no"
if [[ "$RELAY_PORT" == "465" ]]; then
    TLS_WRAPPER_MODE="yes"
fi

# Fixed mydomain calculation using bash instead of postfix macro
MYDOMAIN=$(echo "$MY_HOSTNAME" | cut -d'.' -f2-)

cat <<EOF > /etc/postfix/main.cf
smtpd_banner = \$myhostname ESMTP \$mail_name (Ubuntu)
biff = no
append_dot_mydomain = no
readme_directory = no
compatibility_level = 3.6

# Inbound TLS settings
smtpd_tls_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
smtpd_tls_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
smtpd_tls_security_level=may

# Outbound TLS settings
smtp_tls_CApath=/etc/ssl/certs
smtp_tls_security_level=encrypt
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache
smtp_tls_wrappermode = $TLS_WRAPPER_MODE
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt

# Relay configuration
myhostname = $MY_HOSTNAME
mydomain = $MYDOMAIN
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
myorigin = $MY_HOSTNAME
mydestination = localhost.localdomain, localhost
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = loopback-only
inet_protocols = all

relayhost = [$RELAY_HOST]:$RELAY_PORT
smtp_sasl_auth_enable = yes
smtp_sasl_security_options = noanonymous
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtpd_sender_restrictions = permit_mynetworks, reject_unknown_sender_domain
smtputf8_enable = no
sender_canonical_maps = hash:/etc/postfix/sender_canonical
sender_canonical_classes = envelope_sender
masquerade_domains = $MY_HOSTNAME
masquerade_exceptions = root
smtp_discard_ehlo_keywords = 8BITMIME
smtp_always_send_ehlo = yes
EOF

# Step4: Configure SASL Password
echo -e "${YELLOW}4. Configuring SASL authentication...${NC}"
cat <<EOF > /etc/postfix/sasl_passwd
[$RELAY_HOST]:$RELAY_PORT    $SENDER_EMAIL:$SMTP_PASSWORD
EOF
chown root:root /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd

# Step5: Configure Sender Canonical
echo -e "${YELLOW}5. Configuring sender canonical mapping...${NC}"
cat <<EOF > /etc/postfix/sender_canonical
root@$AUTO_LOCAL_HOSTNAME $SENDER_EMAIL
@$AUTO_LOCAL_HOSTNAME $SENDER_EMAIL
* $SENDER_EMAIL
EOF
postmap /etc/postfix/sender_canonical

# Step6: Start Postfix
echo -e "${YELLOW}6. Starting Postfix service...${NC}"
systemctl daemon-reload
systemctl enable --now postfix > /dev/null 2>&1

# Step7: Verify setup
echo -e "${YELLOW}7. Verifying setup...${NC}"
sleep 2
if systemctl is-active --quiet postfix; then
    echo -e "${GREEN}✅ Postfix service is running successfully${NC}"
else
    echo -e "${RED}❌ Postfix failed to start${NC}"
    echo -e "${YELLOW}Check logs with: journalctl -u postfix${NC}"
    exit 1
fi

# Step8: Test email option
read -p "Would you like to send a test email? (y/n): " SEND_TEST
if [[ "$SEND_TEST" =~ ^[Yy]$ ]]; then
    read -p "Enter test email address: " TEST_EMAIL
    echo "Test email from Postfix Aliyun SMTPDM setup" | mail -s "Postfix Setup Successful" "$TEST_EMAIL"
    echo -e "${GREEN}✅ Test email sent to $TEST_EMAIL${NC}"
    echo -e "${YELLOW}Check delivery status in /var/log/mail.log${NC}"
fi

echo -e "${GREEN}=== Setup completed successfully! ===${NC}"
echo -e "${YELLOW}Your Postfix is now configured to relay through $RELAY_HOST:$RELAY_PORT${NC}"
echo -e "${BLUE}All system settings auto-detected successfully!${NC}"
