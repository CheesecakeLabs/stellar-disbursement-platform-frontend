#!/bin/sh
if [ -n "$WINDOW_ENV_VAR_BASE64" ]; then
  echo "Decoding WINDOW_ENV_VAR_BASE64 environment variable..."
  echo "$WINDOW_ENV_VAR_BASE64" | base64 -d > /usr/share/nginx/html/settings/env-config.js
  echo "env-config.js file created successfully!"
else
  echo "WARNING: WINDOW_ENV_VAR_BASE64 not defined. Creating default file..."
  echo "window._env_ = {};" > /usr/share/nginx/html/settings/env-config.js
fi
