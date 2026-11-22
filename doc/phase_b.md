sequenceDiagram
    autonumber
    actor Admin as Admin / Developer
    participant SecretsFile as Secrets (secrets.md)
    participant RedeployScript as Deployer (redeploy.ps1)
    participant Dockerfile as Docker Context
    participant CloudBuild as GCP Cloud Build
    participant CloudRun as Cloud Run (ssa-app)
    participant FirebaseProxy as Firebase Hosting

    rect rgb(235, 250, 235)
        note over Admin, FirebaseProxy: PHASE B: Multi-Stage Container Build & Cloud Deployment

        Admin->>RedeployScript: Execute .\redeploy.ps1
        RedeployScript->>SecretsFile: Read secrets from C:\sensitive\ssa-gcp\secrets.md
        RedeployScript->>CloudBuild: gcloud builds submit (tarball context excluding .dockerignore)

        CloudBuild->>Dockerfile: Stage 1 (build-client): node:20 installs npm packages & runs vite build -> /app/ssa.client/dist
        CloudBuild->>Dockerfile: Stage 2 (build-server): dotnet:8.0 SDK restores ssa.server.csproj, publishes API, copies React dist to /app/publish/wwwroot
        CloudBuild->>Dockerfile: Stage 3 (final): mcr.microsoft.com/dotnet/aspnet:8.0 runtime image with PORT=8080 entrypoint
        CloudBuild-->>RedeployScript: Docker image pushed to australia-southeast2-docker.pkg.dev/ssa-gcp-515109/ssa-gcp-docker-repo/ssa-image:latest

        RedeployScript->>CloudRun: gcloud run deploy ssa-app (--set-env-vars: GCP__ProjectId, ConnectionStrings, etc.)
        CloudRun-->>RedeployScript: Revision deployed serving 100% traffic (https://ssa-app-*.run.app)

        RedeployScript->>FirebaseProxy: firebase deploy --only hosting (--config gcp/firebase.json)
        FirebaseProxy-->>RedeployScript: Hosting proxy live (https://ssa-gcp-515109.web.app rewrites ** -> ssa-app)
        RedeployScript-->>Admin: Redeploy complete!
    end