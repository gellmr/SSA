sequenceDiagram
  autonumber
  actor Admin as Admin / Developer
  participant ProvisionScript as Provisioning (provision.ps1)
  participant DiscoveryEngine as Vertex AI Search (DataStore / Engine)
  participant GCSBucket as GCS Storage (gs://ssa-safety-docs)
  participant CloudRun as Cloud Run (ssa-app)

  rect rgb(255, 235, 235)
      note over Admin, CloudRun: PHASE D: Teardown & Zero-Cost State

      Admin->>ProvisionScript: Execute .\provision.ps1 -Down (or -Downx)
      ProvisionScript->>DiscoveryEngine: Call Teardown-VertexRag: DELETE /engines/ssa-eng-* & DELETE /dataStores/ssa-ds-*
      DiscoveryEngine-->>ProvisionScript: RAG Engine & DataStore deleted (Stop query/indexing fees)
      ProvisionScript->>GCSBucket: Execute gcloud storage rm --recursive gs://ssa-safety-docs
      GCSBucket-->>ProvisionScript: Bucket & all PDFs deleted (Stop GCS storage fees)
      ProvisionScript->>CloudRun: Execute gcloud run services delete ssa-app
      CloudRun-->>ProvisionScript: Cloud Run service deleted
      ProvisionScript->>ProvisionScript: Execute gcloud artifacts repositories delete ssa-gcp-docker-repo
      opt If -Down (Full Teardown)
          ProvisionScript->>ProvisionScript: Execute gcloud sql instances delete ssa-sql-instance
      end
      ProvisionScript-->>Admin: Teardown complete! Environment returned to $0 idle cost state.
  end