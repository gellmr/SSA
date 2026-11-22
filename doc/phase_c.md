sequenceDiagram
    autonumber
    actor User as End-User / Browser
    participant FirebaseProxy as Firebase Hosting
    participant AppJsx as React Frontend (App.jsx)
    participant CloudRun as Cloud Run (ssa-app)
    participant SafetyController as API Controller (SafetyController.cs)
    participant SafetySearchService as RAG Service (SafetySearchService.cs)
    participant SafetyQueryModels as DTO Models (SafetyQueryModels.cs)
    participant DiscoveryEngine as Vertex AI Search (DataStore / Engine)
    participant GCSBucket as GCS Storage (gs://ssa-safety-docs)
    participant GeminiLLM as GCP Gemini LLM

    rect rgb(255, 245, 230)
        note over User, GeminiLLM: PHASE C: Live User RAG Query & PDF Citation Navigation

        User->>AppJsx: Open app in browser (https://ssa-gcp-515109.web.app or localhost:5173)
        User->>AppJsx: Type question ("What are the entry requirements for a confined space?") & click "Ask Assistant"
        AppJsx->>AppJsx: Set loading state, clear previous results
        AppJsx->>FirebaseProxy: POST /api/safety/ask { query: "..." }
        FirebaseProxy->>CloudRun: Proxy request to ssa-app container
        CloudRun->>SafetyController: Route to SafetyController.Ask([FromBody] SafetyQueryRequest)
        SafetyController->>SafetySearchService: Call AskSafetyQuestionAsync(query)

        SafetySearchService->>SafetySearchService: Get GCP Access Token via GoogleCredential.GetApplicationDefaultAsync()
        SafetySearchService->>DiscoveryEngine: GET /engines (Discover active ssa-eng-* sorted by createTime desc)
        DiscoveryEngine-->>SafetySearchService: Return active engine ID (ssa-eng-*)

        SafetySearchService->>DiscoveryEngine: POST /engines/{engineId}/servingConfigs/default_search:search
        note over SafetySearchService, DiscoveryEngine: Payload: query, pageSize=15, summarySpec (summaryResultCount=10, includeCitations=true, preamble=...), extractiveContentSpec (maxExtractiveAnswerCount=5)

        DiscoveryEngine->>GCSBucket: Retrieve matching PDF document chunks
        DiscoveryEngine->>GeminiLLM: Pass top PDF text segments + user query + prompt preamble
        GeminiLLM-->>DiscoveryEngine: Synthesize grounded response text + citation indices + pageNumbers
        DiscoveryEngine-->>SafetySearchService: Return search JSON (summaryText, results, derivedStructData, extractive_answers pageNumber)

        SafetySearchService->>SafetySearchService: Extract summary answer text
        SafetySearchService->>SafetySearchService: Extract doc title, URI, and pageNumber ("43")
        SafetySearchService->>SafetySearchService: Format docUrl (/api/safety/docs/model-cop-confined-spaces.pdf#page=43)
        SafetySearchService->>SafetySearchService: Call CleanHtml (decode HTML entities, strip tags, normalize spaces)
        SafetySearchService->>SafetyQueryModels: Construct SafetyQueryResponse DTO (Query, Answer, Citations, EngineId)
        SafetySearchService-->>SafetyController: Return SafetyQueryResponse
        SafetyController-->>CloudRun: Return 200 OK JSON
        CloudRun-->>FirebaseProxy: Return JSON response
        FirebaseProxy-->>AppJsx: Return SafetyQueryResponse JSON

        AppJsx->>AppJsx: Render grounded markdown answer + clickable citation links (📄 Model Code of Practice: Confined spaces (Page 43) ↗)

        User->>AppJsx: Click citation link (target="_blank")
        AppJsx->>FirebaseProxy: GET /api/safety/docs/model-cop-confined-spaces.pdf#page=43
        FirebaseProxy->>CloudRun: Route GET /api/safety/docs/model-cop-confined-spaces.pdf
        CloudRun->>SafetyController: Route to SafetyController.GetPdfDocument("model-cop-confined-spaces.pdf")

        alt Running on Localhost
            SafetyController->>SafetyController: Find file at gcp/ragdocs/model-cop-confined-spaces.pdf
            SafetyController-->>User: Return 200 OK application/pdf (inline)
        else Running in Cloud Run Container
            SafetyController->>SafetyController: File not in container -> Redirect to GCS Bucket
            SafetyController-->>User: Return 302 Redirect (https://storage.googleapis.com/ssa-safety-docs/model-cop-confined-spaces.pdf#page=43)
            User->>GCSBucket: GET /ssa-safety-docs/model-cop-confined-spaces.pdf#page=43
            GCSBucket-->>User: Return 200 OK application/pdf
        end
        note over User: Browser PDF Viewer opens new tab and natively scrolls directly to Page 43!
    end