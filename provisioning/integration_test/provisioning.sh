#!/bin/bash

SHARD=${SHARD:-"noProvision"}
NUM_USERS=${NUM_USERS:-2}
DOMAIN="example.com"

# Wait for a mailbox to be available before importing EMLs
function wait_for_mailbox() {
  local email="$1"
  local folder="$2"
  local retries=10
  local count=0

  while [ $count -lt $retries ]; do
    if james-cli ListUserMailboxes "$email" | grep -q "$folder"; then
      echo "Mailbox '$folder' for '$email' is ready."
      return 0
    fi
    echo "Waiting for mailbox '$folder' to be created..."
    sleep 2
    ((count++))
  done

  echo "Error: Mailbox '$folder' for '$email' was not created in time."
  return 1
}

case "$SHARD" in
  noProvision)
    for i in $(seq -f "%03g" 0 $((NUM_USERS-1))); do
      james-cli AddUser "np_${i}@${DOMAIN}" "np_${i}"
    done
    ;;

  searchEmails)
    for i in $(seq -f "%03g" 0 $((NUM_USERS-1))); do
      james-cli AddUser "se_${i}@${DOMAIN}" "se_${i}"
      james-cli CreateMailbox \#private "se_${i}@${DOMAIN}" "Search Emails"
      wait_for_mailbox "se_${i}@${DOMAIN}" "Search Emails" || exit 1
      for eml in 0 1 2 3 4; do
        echo "Importing $eml.eml into 'Search Emails' for se_${i}"
        james-cli ImportEml \#private "se_${i}@${DOMAIN}" "Search Emails" \
          "/root/conf/integration_test/eml/search_email_with_sort_order/${eml}.eml"
      done
    done
    ;;

  preloadedEmails)
    for i in $(seq -f "%03g" 0 $((NUM_USERS-1))); do
      james-cli AddUser "pe_${i}@${DOMAIN}" "pe_${i}"

      james-cli CreateMailbox \#private "pe_${i}@${DOMAIN}" "Forward Emails"
      james-cli CreateMailbox \#private "pe_${i}@${DOMAIN}" "Reply Emails"
      james-cli CreateMailbox \#private "pe_${i}@${DOMAIN}" "Calendar"
      james-cli CreateMailbox \#private "pe_${i}@${DOMAIN}" "Disposition"
      james-cli CreateMailbox \#private "pe_${i}@${DOMAIN}" "MailBase64"

      for folder in "Forward Emails" "Reply Emails" "Calendar" "Disposition" "MailBase64"; do
        wait_for_mailbox "pe_${i}@${DOMAIN}" "$folder" || exit 1
      done

      echo "Importing forward.eml for pe_${i}"
      james-cli ImportEml \#private "pe_${i}@${DOMAIN}" "Forward Emails" \
        "/root/conf/integration_test/eml/forward_email/forward.eml"

      for eml in reply-all reply-to-list with-reply-to without-reply-to reply-thread; do
        echo "Importing ${eml}.eml for pe_${i}"
        james-cli ImportEml \#private "pe_${i}@${DOMAIN}" "Reply Emails" \
          "/root/conf/integration_test/eml/reply_email/${eml}.eml"
      done

      echo "Importing calendar_counter.eml for pe_${i}"
      james-cli ImportEml \#private "pe_${i}@${DOMAIN}" "Calendar" \
        "/root/conf/integration_test/eml/calendar/calendar_counter.eml"

      echo "Importing no_disposition_inline.eml for pe_${i}"
      james-cli ImportEml \#private "pe_${i}@${DOMAIN}" "Disposition" \
        "/root/conf/integration_test/eml/no_disposition_inline/no_disposition_inline.eml"

      echo "Importing 0.eml (base64) for pe_${i}"
      james-cli ImportEml \#private "pe_${i}@${DOMAIN}" "MailBase64" \
        "/root/conf/integration_test/eml/reply_email_with_image_base64/0.eml"
    done
    ;;

  infra)
    for i in $(seq -f "%03g" 0 $((NUM_USERS-1))); do
      james-cli AddUser "si_${i}@${DOMAIN}" "si_${i}"

      echo "Creating team mailbox si_${i}-guests"
      curl -XPUT "http://172.18.0.2:8000/domains/${DOMAIN}/team-mailboxes/si_${i}-guests"
      curl -XPUT "http://172.18.0.2:8000/domains/${DOMAIN}/team-mailboxes/si_${i}-guests/members/si_${i}@${DOMAIN}?role=member"

      echo "Setting quota for si_${i}"
      curl -X PUT "http://172.18.0.2:8000/quota/users/si_${i}@${DOMAIN}" \
        -d '{"count":200,"size":50000000}' -H "Content-Type: application/json"
    done
    ;;

  *)
    echo "Unknown shard: $SHARD. Valid values: noProvision, searchEmails, preloadedEmails, infra"
    exit 1
    ;;
esac

echo "Provisioning complete for shard=$SHARD NUM_USERS=$NUM_USERS"
