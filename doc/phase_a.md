sequenceDiagram
  autonumber
  actor Admin as Admin / Developer
  participant SecretsFile as Secrets (secrets.md)
  participant ProvisionScript as Provisioning (provision.ps1)
  participant RagUploadScript as RAG Uploader (rag-upload.ps1)
  participant PollScript as RAG Poller (poll.ps1)
  participant GCSBucket as GCS Storage (gs://ssa-safety-docs)
  participant DiscoveryEngine as Vertex AI Search (DataStore / Engine)

  rect rgb(230, 242, 255)
      note over Admin, DiscoveryEngine: PHASE A: Infrastructure Provisioning & RAG Data Ingestion

      Admin->>SecretsFile: Load process env vars (load-secrets.ps1)
      SecretsFile-->>Admin: Process env loaded (GCP__ProjectId, DB_PASSWORD, etc.)

      Admin->>ProvisionScript: Execute .\provision.ps1 -Up
      ProvisionScript->>ProvisionScript: Set active project (ssa-gcp-515109)
      ProvisionScript->>ProvisionScript: Enable GCP APIs (compute, run, sqladmin, storage, cloudbuild, discoveryengine, firebase)
      ProvisionScript->>ProvisionScript: Ensure Artifact Registry (ssa-gcp-docker-repo) & Cloud SQL (ssa-sql-instance)
      ProvisionScript->>GCSBucket: Ensure GCS Bucket (gs://ssa-safety-docs)
      ProvisionScript->>GCSBucket: Grant storage.objectViewer IAM to allUsers & Discovery Engine Agent
      ProvisionScript-->>Admin: Provisioning UP complete! (Prompt to run .\rag-upload.ps1)

      Admin->>RagUploadScript: Execute .\rag-upload.ps1
      RagUploadScript->>RagUploadScript: Parse active PDF URLs from ragdocs.md
      RagUploadScript->>RagUploadScript: Download missing local PDFs into gcp/ragdocs/
      RagUploadScript->>RagUploadScript: Generate metadata.jsonl (UTF-8 without BOM)
      RagUploadScript->>GCSBucket: Upload active PDFs + metadata.jsonl to gs://ssa-safety-docs/
      RagUploadScript->>DiscoveryEngine: Provision DataStore (ssa-ds-*) with contentConfig = "NO_CONTENT"
      RagUploadScript->>DiscoveryEngine: Provision Search Engine (ssa-eng-*) with SEARCH_TIER_ENTERPRISE & SEARCH_ADD_ON_LLM
      RagUploadScript->>DiscoveryEngine: Issue POST /branches/0/documents:import (metadata.jsonl)
      DiscoveryEngine-->>RagUploadScript: Import operation initiated (LRO)
      RagUploadScript-->>Admin: Ingestion initiated! (Prompt to run .\poll.ps1)

      Admin->>PollScript: Execute .\poll.ps1
      loop Every 130 seconds
          PollScript->>DiscoveryEngine: Query GET /dataStores & GET /engines (find latest by createTime)
          PollScript->>DiscoveryEngine: Query GET /branches/0/documents (count indexed PDFs)
          PollScript->>DiscoveryEngine: Query GET /operations/{opName} (check LRO done status)
          PollScript->>DiscoveryEngine: Query POST /servingConfigs/default_search:search (test summary)
          DiscoveryEngine-->>PollScript: Return LRO status, doc count, and summaryText
          PollScript->>PollScript: Print progress row to console table
      end
      PollScript-->>Admin: SUCCESS: All PDFs indexed & Gemini grounding READY!
  end