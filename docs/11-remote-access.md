# Remote Access

Status date: 2026-07-25

## Trust Boundary

Remote administration is limited to the trusted LAN:

- SSH is key-based in both directions.
- macOS Screen Sharing uses the Mac's local account at connection time.
- Ubuntu exposes an existing live-desktop RDP bridge on a non-default LAN port.
- publication CDP and noVNC endpoints remain bound to `127.0.0.1`.

Never expose account-bearing browser profiles, CDP, noVNC, VNC, or RDP directly
to the public internet. Use an SSH tunnel or a separately managed VPN when
working away from the LAN.

## Mac to Ubuntu

The Mac SSH config defines a stable host alias and a dedicated Ed25519 key.
Windows App has a local `.rdp` file that:

- points at the Ubuntu live-desktop bridge;
- stores the username but no password;
- prompts for credentials;
- enables clipboard and dynamic resolution;
- disables audio playback for a quieter operator session.

The Ubuntu RDP certificate fingerprint must be checked again if the host is
reinstalled or its remote-desktop identity is regenerated.

## Ubuntu to Mac

Ubuntu has:

- a working SSH host alias for the Mac;
- a Remmina VNC profile for macOS Screen Sharing;
- no saved VNC password.

The Mac's standard Screen Sharing port was reachable from Ubuntu at the
verified checkpoint. Legacy single-password VNC mode was deliberately not
enabled because local-account authentication is the stronger boundary.

## Publication Browser

The Mac publication Chrome uses:

- a dedicated profile outside all Git repositories;
- remote debugging bound to loopback;
- a pinned loopback CDP port;
- human entry for passwords and 2FA.

Short-lived SSH control tunnels may forward that loopback endpoint to another
trusted host. Close the control tunnel after use. Never copy the browser
profile or cookie database into a handoff repository.
