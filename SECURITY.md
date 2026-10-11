# Security Policy

## Scope

This repository holds the content of a public GitHub profile. It contains no deployed software and processes no personal data. The two signing credentials it publishes, the S/MIME certificate and the SSH signing key, are in scope, together with the artifacts they authenticate.

## What to report privately

- A secret, a credential or personal data committed to this repository by mistake, in a file or in the history.
- A problem with either published signing credential or with an artifact it authenticates, for example a fingerprint in the profile README that does not match the certificate or the key.
- A weakness of the workflows under `.github/` that could let someone change what the repository publishes.

## How to report

Use GitHub's private vulnerability reporting (the tab Security, then Report a vulnerability), or write to <info@mtorun0x7cd.com>, naming the file, the problem and how to see it. Sensitive reports may be encrypted to the S/MIME certificate, which is supplied on request to the same address; check it against the SHA-256 fingerprint in the profile README before use.

## What is not a vulnerability

Compiled binaries, installers and release archives carry no signature, as stated under Signed artifacts; their lack of one is not a vulnerability. Neither is an unsigned commit in a repository under another account, nor a signature that fails to verify because the document was changed after signing: that is the check doing its work.

## What to expect

Reports are read. A reply or a fix is not guaranteed.

## Signed artifacts

Two independent mechanisms are used. Commits and tags in the repositories under this account are signed with an SSH key, which GitHub renders as Verified. Documents issued by mtorun0x7cd and e-mail are signed with an S/MIME certificate. Compiled binaries, installers and release archives are not signed (this is not code signing), and commits in repositories under other accounts are not signed.

The SSH signing key is published at <https://api.github.com/users/mtorun0x7cd/ssh_signing_keys>; the S/MIME certificate is supplied on request (see How to report). Confirm both against the SHA-256 fingerprints in the profile README before trusting them. Document signatures are detached CMS (RFC 5652): the signature travels beside the document as `DOCUMENT.p7s`, never inside it, and is checked with `openssl cms -verify -binary -inform DER -content DOCUMENT -in DOCUMENT.p7s -purpose smimesign -CAfile chain.pem`. `chain.pem` is the issuer's chain in PEM, the root D-Trust SBR Root CA 1 2022 and the intermediate D-Trust SBR CA 1-22-1 2022; the profile README says how to obtain and check it, and how to check a signature after the certificate has expired.
