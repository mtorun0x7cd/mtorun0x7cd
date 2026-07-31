# Security Policy

This repository holds the content of a public GitHub profile. It contains no
deployed software and processes no personal data.

## Reporting

Report any security concern — including issues affecting either published signing
credential (the S/MIME certificate or the SSH signing key) or the artifacts they
authenticate — to <info@mtorun0x7cd.com>. Sensitive reports may be encrypted to
the S/MIME certificate.

## Signed artifacts

Two independent mechanisms are used. Commits and tags in the repositories under this account are signed with an SSH key, which GitHub renders as Verified. Documents issued by mtorun0x7cd and e-mail are signed with an S/MIME certificate. Compiled binaries, installers and release archives are not signed — this is not code signing — and commits in repositories under other accounts are not signed.

The portal at <https://mtorun0x7cd.com/verify> verifies document and e-mail signatures
and publishes the SSH signing key; confirm both the S/MIME certificate and the SSH
key against the SHA-256 fingerprints in the profile README before trusting them.
