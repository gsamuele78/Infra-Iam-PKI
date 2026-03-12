#!/bin/bash
set -euo pipefail

# End-to-End SSO Test for Infra-Iam-PKI Sandbox
# This script simulates a non-optimistic authentication flow directly from the host.
# It proves that OOD properly delegates to Keycloak, and that Keycloak successfully
# authenticates a user and returns valid OIDC tokens/cookies to OOD.

OOD_IP="192.168.56.30"
IAM_IP="192.168.56.20"

echo "=================================================="
echo "    System Engineer E2E Trust Verification"
echo "=================================================="

# ---------------------------------------------------------
# Step 1: Ensure Keycloak 'ondemand' Client has Correct URI
# ---------------------------------------------------------
echo "[1/4] Ensuring Keycloak OIDC Client is configured for $OOD_IP..."
vagrant ssh iam-host -c "sudo docker exec iam-keycloak /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password sandbox_admin_password" > /dev/null 2>&1
CLIENT_ID=$(vagrant ssh iam-host -c "sudo docker exec iam-keycloak /opt/keycloak/bin/kcadm.sh get clients -r master -q clientId=ondemand --fields id" | grep -o '"id" : "[^"]*"' | head -n1 | cut -d'"' -f4 || echo "")

if [ -z "$CLIENT_ID" ]; then
    echo "  -> 'ondemand' OIDC client not found. Creating it..."
    vagrant ssh iam-host -c "sudo docker exec iam-keycloak /opt/keycloak/bin/kcadm.sh create clients -r master -s clientId=ondemand -s enabled=true -s publicClient=false -s secret=sandbox_ood_secret -s standardFlowEnabled=true -s implicitFlowEnabled=false -s directAccessGrantsEnabled=false -s \"redirectUris=[\\\"http://$OOD_IP/oidc\\\", \\\"http://localhost/oidc\\\"]\"" > /dev/null
    echo "  -> 'ondemand' client created."
else
    echo "  -> Updating 'ondemand' client with valid redirectURIs and secret..."
    vagrant ssh iam-host -c "sudo docker exec iam-keycloak /opt/keycloak/bin/kcadm.sh update clients/$CLIENT_ID -r master -s secret=sandbox_ood_secret -s \"redirectUris=[\\\"http://$OOD_IP/oidc\\\", \\\"http://localhost/oidc\\\"]\"" > /dev/null
fi

TEST_USER="ood-tester"
USER_ID=$(vagrant ssh iam-host -c "sudo docker exec iam-keycloak /opt/keycloak/bin/kcadm.sh get users -r master -q username=$TEST_USER --fields id" | grep -o '"id" : "[^"]*"' | head -n1 | cut -d'"' -f4 || echo "")
if [ -z "$USER_ID" ]; then
    echo "  -> Creating test user '$TEST_USER'..."
    vagrant ssh iam-host -c "sudo docker exec iam-keycloak /opt/keycloak/bin/kcadm.sh create users -r master -s username=$TEST_USER -s enabled=true -s email=tester@local.dev" > /dev/null
    vagrant ssh iam-host -c "sudo docker exec iam-keycloak /opt/keycloak/bin/kcadm.sh set-password -r master --username $TEST_USER --new-password testerpass" > /dev/null
fi

echo "  -> Ensuring POSIX user '$TEST_USER' exists in ood-portal container..."
vagrant ssh ood-host -c "sudo docker exec ood-portal id -u $TEST_USER &>/dev/null || sudo docker exec ood-portal useradd -m -s /bin/bash $TEST_USER" > /dev/null

COOKIE_JAR=$(mktemp)

# ---------------------------------------------------------
# Step 2: Access OOD and get the Keycloak Login Redirect
# ---------------------------------------------------------
echo "[2/4] Accessing OOD Portal (should redirect to Keycloak)..."
OOD_RESP=$(curl -c "$COOKIE_JAR" -i -s http://$OOD_IP/pun/sys/dashboard 2>&1)
LOGIN_URL=$(echo "$OOD_RESP" | grep -i "Location:" | awk '{print $2}' | tr -d '\r')

OIDC_COOKIE=$(echo "$OOD_RESP" | grep -i "Set-Cookie: mod_auth_openidc_state" | cut -d':' -f2 | cut -d';' -f1 | tr -d ' ' | tr -d '\r')
if [ -n "$OIDC_COOKIE" ]; then
    echo "  -> Captured OIDC State Cookie: ${OIDC_COOKIE%%=*}..."
else
    echo "❌ ERROR: No mod_auth_openidc Set-Cookie header found in OOD response."
    exit 1
fi

if [[ "$LOGIN_URL" != *"192.168.56.20/realms/master/protocol/openid-connect/auth"* ]]; then
    echo "❌ ERROR: Expected redirect to Keycloak auth, got: $LOGIN_URL"
    exit 1
fi
echo "  -> Redirect OK: $LOGIN_URL"

echo "$LOGIN_URL" | sed 's/ /%w/g' > /tmp/login_url.txt
AUTH_PAGE=$(curl -c "$COOKIE_JAR" -s -L "$(cat /tmp/login_url.txt)")

FORM_ACTION=$(echo "$AUTH_PAGE" | grep 'action="' | sed -n 's/.*action="\([^"]*\)".*/\1/p' | sed 's/&amp;/\&/g')

if [ -z "$FORM_ACTION" ]; then
    echo "❌ ERROR: Could not extract login form action URL from Keycloak."
    exit 1
fi
echo "  -> Keycloak form action Extracted OK."

# ---------------------------------------------------------
# Step 3: Authenticate to Keycloak
# ---------------------------------------------------------
echo "[3/4] Authenticating to Keycloak..."

LOGIN_RES=$(curl -s -i -b "$COOKIE_JAR" -c "$COOKIE_JAR" -d "username=$TEST_USER" -d "password=testerpass" -d "credentialId=" "$FORM_ACTION")

OOD_CALLBACK=$(echo "$LOGIN_RES" | grep -i "Location:" | awk '{print $2}' | tr -d '\r')

if [[ "$OOD_CALLBACK" != *"192.168.56.30/oidc"* ]]; then
    echo "❌ ERROR: Login failed or did not redirect back to OOD. Redirect URL: $OOD_CALLBACK"
    exit 1
fi
echo "  -> Keycloak Authentication OK. Redirecting to: $OOD_CALLBACK"

# ---------------------------------------------------------
# Step 4: OOD Verification
# ---------------------------------------------------------
echo "[4/4] Sending Auth Code to OOD and verifying Dashboard access..."

OOD_AUTH_RES=$(curl -s -i -H "Cookie: $OIDC_COOKIE" -b "$COOKIE_JAR" -c "$COOKIE_JAR" "$OOD_CALLBACK")

SESSION_COOKIE=$(grep "mod_auth_openidc_session" "$COOKIE_JAR" || echo "")
if [ -z "$SESSION_COOKIE" ]; then
    echo "  -> Note: mod_auth_openidc session cookie not generated directly, following final redirect..."
    FINAL_URL=$(echo "$OOD_AUTH_RES" | grep -i "Location:" | awk '{print $2}' | tr -d '\r')
    if [ -n "$FINAL_URL" ]; then
        curl -s -i -H "Cookie: $OIDC_COOKIE" -b "$COOKIE_JAR" -c "$COOKIE_JAR" "$FINAL_URL" > /dev/null
    fi
fi

DASHBOARD_RES=$(curl -s -i -b "$COOKIE_JAR" "http://$OOD_IP/pun/sys/dashboard")
HTTP_CODE=$(echo "$DASHBOARD_RES" | head -n1 | awk '{print $2}')

if [ "$HTTP_CODE" == "200" ]; then
    echo "=================================================="
    echo " ✅ SUCCESS: E2E Authentication Flow is Working!"
    echo " Data path: Request (Unauth) -> HTTP 302 -> Keycloak -> HTTP 200 (Form) -> POST (Auth) -> HTTP 302 (Code) -> OOD -> HTTP 302 (Accept) -> Dashboard (HTTP 200)"
    echo "=================================================="
else
    echo "❌ ERROR: Expected HTTP 200 on Dashboard, got $HTTP_CODE"
    exit 1
fi

rm -f "$COOKIE_JAR" /tmp/login_url.txt
