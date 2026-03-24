#!/usr/bin/env bash
set -o errexit -o pipefail -o nounset

echo "Checking health of milters"
# postgrey times out with any request, so we cannot check it
miltertest -s /scripts/dkim_milter_test_spec.lua
miltertest -s /scripts/dmarc_milter_test_spec.lua
miltertest -s /scripts/spamass_milter_test_spec.lua
