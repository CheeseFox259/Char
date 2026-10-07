# Char 0.3.1 — theme icon consistency

Fixes a final v2 theme check finding: changing themes now refreshes the menu bar icon together with the application and installation icons, including switching back to the original theme.

Includes all v0.3.0 appearance capabilities and v0.2.2 edge host fixes. Native regression checks compare the actual menu bar image before, during and after theme switching.

Public macOS binaries remain Universal arm64/x86_64 and ad hoc signed. Installing a new release or synchronizing a custom installation icon may require re-adding Char Accessibility permission.

Adds an optional bilingual Performance panel in Settings: Char host, selected appearance script and enabled integration adapters; current/average/peak CPU and RSS, valid samples and reset. One native sample per second while enabled; no background sampling by default. Host rendering remains shared and is not falsely attributed to one package. Monitoring statistics stay in memory for the current run.
