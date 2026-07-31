# Security Policy

This repository holds the content of a public GitHub profile. It contains no deployed software and processes no personal data.

## Reporting

Report any security concern — including issues affecting either published signing credential (the S/MIME certificate or the SSH signing key) or the artifacts they authenticate — to <info@mtorun0x7cd.com>. Sensitive reports may be encrypted to the S/MIME certificate, which is supplied on request to the same address; check it against the SHA-256 fingerprint in the profile README before use.

## Signed artifacts

Two independent mechanisms are used. Commits and tags in the repositories under this account are signed with an SSH key, which GitHub renders as Verified. Documents issued by mtorun0x7cd and e-mail are signed with an S/MIME certificate. Compiled binaries, installers and release archives are not signed — this is not code signing — and commits in repositories under other accounts are not signed.

The SSH signing key is published at <https://api.github.com/users/mtorun0x7cd/ssh_signing_keys>; the S/MIME certificate is supplied on request (see Reporting). Confirm both against the SHA-256 fingerprints in the profile README before trusting them. Document signatures are detached CMS (RFC 5652): the signature travels beside the document as `DOCUMENT.p7s`, never inside it, and is checked with `openssl cms -verify -binary -content DOCUMENT -in DOCUMENT.p7s -purpose smimesign -CAfile chain.pem`.
