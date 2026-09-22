output "attacker_access_key_id" {
  description = "Attacker AWS access key ID - starting credentials for the scenario"
  value       = aws_iam_access_key.attacker.id
  sensitive   = false
}

output "attacker_secret_access_key" {
  description = "Attacker AWS secret access key"
  value       = aws_iam_access_key.attacker.secret
  sensitive   = true
}

output "knowledge_base_bucket" {
  description = "Name of the misconfigured knowledge base S3 bucket"
  value       = aws_s3_bucket.knowledge_base.bucket
}

output "sensitive_data_bucket" {
  description = "Name of the sensitive data bucket (pivot target)"
  value       = aws_s3_bucket.sensitive_data.bucket
}

output "harness_arn" {
  description = "AgentCore harness ARN - needed to invoke the assistant (InvokeHarness)"
  value       = aws_bedrockagentcore_harness.assistant.arn
}

output "harness_id" {
  description = "AgentCore harness ID"
  value       = aws_bedrockagentcore_harness.assistant.harness_id
}

output "gateway_id" {
  description = "AgentCore gateway ID backing the assistant's MCP tools"
  value       = aws_bedrockagentcore_gateway.tools.gateway_id
}

output "gateway_url" {
  description = "AgentCore gateway MCP endpoint URL"
  value       = aws_bedrockagentcore_gateway.tools.gateway_url
}

output "knowledge_base_id" {
  description = "Bedrock knowledge base ID"
  value       = aws_bedrockagent_knowledge_base.main.id
}

output "data_source_id" {
  description = "Bedrock knowledge base data source ID - needed to start ingestion"
  value       = aws_bedrockagent_data_source.s3_docs.data_source_id
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret (pivot target)"
  value       = aws_secretsmanager_secret.internal_api_key.arn
}

output "scenario_summary" {
  description = "Quick reference for the scenario"
  value       = <<-EOT
    =============================================
    range-04 - Bedrock RAG Injection Range
    =============================================
    Starting credentials have been provisioned.
    Run: terraform output -raw attacker_secret_access_key

    Your goal: pivot from the knowledge base bucket
    into sensitive AWS resources using indirect
    prompt injection against the AgentCore assistant.

    Hint: What happens when the assistant retrieves
    a document that contains instructions?
    =============================================
  EOT
}

output "warning" {
  description = "Reminder that everything in this scenario is intentionally insecure"
  value       = "INTENTIONALLY VULNERABLE. This stack builds an over-privileged, prompt-injectable AI assistant for training only. Deploy in an isolated sandbox account, walk the chain, then 'terraform destroy'. Never point real workloads at it."
}
