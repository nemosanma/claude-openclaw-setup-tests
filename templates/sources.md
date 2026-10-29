# Sources — Claude Code + OpenClaw setup guide

Collected 2026-10-29 (Asia/Taipei, UTC+8). Every URL below was fetched or status-checked on that date.
Versions tested on the box: Claude Code 2.1.312 (native + npm), OpenClaw 2026.10.8 (npm + official installer), Node 24.22.1, npm 11.21.1.

## Claude Code (Anthropic) — official docs
- Advanced setup / install methods / uninstall: https://code.claude.com/docs/en/setup
- Quickstart: https://code.claude.com/docs/en/quickstart
- Authentication: https://code.claude.com/docs/en/authentication
- Settings (files, precedence, `$schema`): https://code.claude.com/docs/en/settings
- Settings JSON schema (SchemaStore): https://json.schemastore.org/claude-code-settings.json
- Permissions (rule syntax, compound commands, path anchors, modes): https://code.claude.com/docs/en/permissions
- Hooks reference (events, exit codes, JSON output): https://code.claude.com/docs/en/hooks
- Hooks guide: https://code.claude.com/docs/en/hooks-guide
- MCP: https://code.claude.com/docs/en/mcp
- Subagents: https://code.claude.com/docs/en/sub-agents
- Skills (custom commands merged into skills): https://code.claude.com/docs/en/skills
- Memory / CLAUDE.md / CLAUDE.local.md / @imports: https://code.claude.com/docs/en/memory
- Costs (`/usage`, reducing tokens): https://code.claude.com/docs/en/costs
- Status line (cost + context fields): https://code.claude.com/docs/en/statusline
- CLI reference (`--max-budget-usd`, `--max-turns`, `claude doctor`, `claude auth status`): https://code.claude.com/docs/en/cli-reference
- Commands: https://code.claude.com/docs/en/commands
- Security: https://code.claude.com/docs/en/security
- Sandboxing: https://code.claude.com/docs/en/sandboxing
- Troubleshooting: https://code.claude.com/docs/en/troubleshooting
- Model configuration: https://code.claude.com/docs/en/model-config
- Legal and compliance (OAuth vs API key use): https://code.claude.com/docs/en/legal-and-compliance
- Docs index used for discovery: https://code.claude.com/docs/llms.txt

## Anthropic — billing, terms, policy
- Log in to your Claude account (subscriptions vs third-party tools): https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account
- API rate limits & spend limits: https://platform.claude.com/docs/en/api/rate-limits
- Usage Policy (AUP): https://www.anthropic.com/legal/aup
- Consumer Terms: https://www.anthropic.com/legal/consumer-terms
- Commercial Terms: https://www.anthropic.com/legal/commercial-terms
- TechCrunch, 2026-04-04 — subscription limits no longer cover third-party harnesses incl. OpenClaw: https://techcrunch.com/2026/04/04/anthropic-says-claude-code-subscribers-will-need-to-pay-extra-for-openclaw-support/
- The Verge, 2026-04-03 — same change: https://www.theverge.com/ai-artificial-intelligence/907074/anthropic-openclaw-claude-subscription-ban

## OpenClaw — official docs (docs.openclaw.ai; every page is also available as `.md`)
- Install: https://docs.openclaw.ai/install
- Getting started: https://docs.openclaw.ai/start/getting-started
- Onboard CLI (non-interactive flags): https://docs.openclaw.ai/cli/onboard
- Doctor: https://docs.openclaw.ai/cli/doctor/running
- Status: https://docs.openclaw.ai/cli/status
- Gateway query (`usage-cost`): https://docs.openclaw.ai/cli/gateway/query
- Config CLI (`validate`, `patch`, `schema`): https://docs.openclaw.ai/cli/config
- Configuration overview / examples / env vars: https://docs.openclaw.ai/gateway/configuration , https://docs.openclaw.ai/gateway/configuration-examples , https://docs.openclaw.ai/gateway/configuration/environment-variables
- Security overview: https://docs.openclaw.ai/gateway/security
- Hardened baselines: https://docs.openclaw.ai/gateway/security/hardened-baseline
- Network exposure: https://docs.openclaw.ai/gateway/security/network-exposure
- Exposure runbook: https://docs.openclaw.ai/gateway/security/exposure-runbook
- Running the security audit: https://docs.openclaw.ai/gateway/security/running-the-audit
- Security CLI: https://docs.openclaw.ai/cli/security
- Security & access-control FAQ: https://docs.openclaw.ai/help/faq/security-and-access-control
- Skills: https://docs.openclaw.ai/tools/skills ; Creating skills: https://docs.openclaw.ai/tools/creating-skills ; Skills CLI: https://docs.openclaw.ai/cli/skills
- ClawHub security audits: https://docs.openclaw.ai/clawhub/security-audits
- Heartbeat (scheduled checks / cost): https://docs.openclaw.ai/gateway/heartbeat
- Models: https://docs.openclaw.ai/concepts/models ; Anthropic provider: https://docs.openclaw.ai/providers/anthropic
- Telegram setup: https://docs.openclaw.ai/channels/telegram/setup ; WhatsApp: https://docs.openclaw.ai/channels/whatsapp ; Discord: https://docs.openclaw.ai/channels/discord
- Docs index: https://docs.openclaw.ai/llms.txt
- Source repo (MIT license per npm metadata `license: MIT`): https://github.com/openclaw/openclaw

## OpenClaw security incidents (for the hardening chapter)
- GHSA-g8p2-7wf7-98mq / CVE-2026-25253 — 1-click RCE via gatewayUrl token exfiltration (fixed; upgrade): https://github.com/openclaw/openclaw/security/advisories/GHSA-g8p2-7wf7-98mq ; https://osv.dev/vulnerability/GHSA-g8p2-7wf7-98mq
- OpenClaw issue #8490 — malware campaign targeting ClawHub skills (base64 droppers, fake prerequisites): https://github.com/openclaw/openclaw/issues/8490
- OpenSourceMalware — malicious ClawHub skills: https://opensourcemalware.com/blog/malicious-clawhub-skills-target-openclaw-users
- Palo Alto Networks Unit 42 — OpenClaw skill marketplace supply-chain risk (Feb–May 2026 findings, VirusTotal/ClawScan/NVIDIA screening): https://unit42.paloaltonetworks.com/openclaw-ai-supply-chain-risk/

## Gumroad (selling rules)
- Prohibited products (AI-services clause: selling access to AI tools/subscriptions fulfilled outside Gumroad is prohibited; also crypto, investments, consulting firms, financial-advice predictions): https://gumroad.com/prohibited
- Adding a product: https://gumroad.com/help/article/149-adding-a-product

## Market comparables (from prior research, /workspace/ai_agent_money/sources.md)
- Austen Allred OpenClaw handbook — $5, 3,868 sales (Gumroad listing, seller-reported counter).
- AI Breakfast setup guide — $19, 204 sales (Gumroad listing counter).

## Third-party packages referenced (not redistributed)
- `@anthropic-ai/claude-code` (Anthropic license, "SEE LICENSE IN README.md") — installed by the buyer from npm/official installer.
- `openclaw` (MIT) — installed by the buyer.
- `@modelcontextprotocol/server-filesystem` — referenced in an example `.mcp.json`; installed by the buyer via npx.
- Build-time only (not shipped): pandoc-free pipeline using Python-Markdown (BSD), WeasyPrint (BSD), Pillow (MIT-CMU), Pygments (BSD).

## Notes on link checks
- https://nvd.nist.gov/vuln/detail/CVE-2026-25253 returned HTTP 403 to curl (NVD blocks scripted clients); cited via the GitHub advisory and OSV instead.
- No trademark-policy page found at openclaw.ai/trademark or docs.openclaw.ai/trademark (404). The guide uses names nominatively with a non-affiliation disclaimer.
