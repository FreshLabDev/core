# Shared local Telegram Bot API

This manifest is deployed as the independent WS04 stack
`/opt/stacks/telegram-bot-api`. It serves Vido and Searchy over the external
Docker network `telegram_bot_api_net`; port 8081 is intentionally not published
on the host.

The runtime `data/` directory is populated from the existing Vido Bot API
volume before the first start. `/opt/stacks/shared-media-cache` is mounted
read-only at the same path used by both bots.

Create the external network once:

```sh
docker network create telegram_bot_api_net
```

The image digest is the currently deployed and verified `7.11` image. Updating
the Bot API server is a separate change from the Vido/Searchy bridge rollout.
