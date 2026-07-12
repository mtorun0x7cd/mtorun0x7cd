# Security Policy

This repository holds the content of a public GitHub profile. It contains no
deployed software and processes no personal data.

## Reporting

Report any security concern — including issues affecting either published signing
credential (the S/MIME certificate or the SSH signing key) or the artifacts they
authenticate — to <info@mtorun0x7cd.com>. Sensitive reports may be encrypted to
the S/MIME certificate.

## Signed artifacts

Published artifacts are cryptographically signed by two separate mechanisms:
official PDF documents and e-mail with an S/MIME certificate, and every Git commit
and tag (hence every release) with an SSH key that GitHub renders as Verified. The
portal at <https://mtorun0x7cd.com/verify> verifies document and e-mail signatures
and publishes the SSH signing key; confirm both the S/MIME certificate and the SSH
key against the SHA-256 fingerprints in the profile README before trusting them.
