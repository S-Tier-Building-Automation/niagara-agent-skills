# Limitations

These need the station's own API or Workbench; the platform tools cannot do them:

- Creating station users, resetting passwords, roles and categories.
- Structural changes inside a running station (components, links, wiresheets, PX views).
- Acquiring or binding licences (the platform can *place* a licence file; `place-license` is planned).
- Generating certificates or key pairs (`import-trust-cert` only imports existing PEM certificates).
- Commissioning wizards, TCP/IP configuration through `plat ipconfig` is intentionally not wrapped.
- Reading a station's console live before it stops: use `watch-station` (console.txt is flushed on stop).
- Editing `config.bog` offline (`edit-station-config`) is planned for a later release; the `bog` tier is reserved for it.
