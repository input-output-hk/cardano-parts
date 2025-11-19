# To enable terraform and cloudFormation cluster secrets usage:
#   * update the following with the appropriate cluster secrets
#   * remove these comments
#   * encrypt this file with sops as a binary type using an age sre/admin secret key
#
# Expect this file to generate a pre-push error until it is either encrypted or deleted

# Set this to the finance billing code
tag_costCenter = "UPDATE_ME"
