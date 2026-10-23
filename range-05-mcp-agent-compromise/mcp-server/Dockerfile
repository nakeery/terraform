# range-05-mcp-agent-compromise/mcp-server
#
# Build and push with:
#   az acr build --registry <terraform output -raw mcp_server_registry_name> \
#     --image mcp-server:latest .
#
# Then point the Container App at it (container_app.tf's var.mcp_server_image)
# and re-apply, or restart the revision to pick up a same-tag push.

FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server.py mock_data.py ./

ENV MCP_TRANSPORT=streamable-http
EXPOSE 8000

CMD ["python", "server.py"]
