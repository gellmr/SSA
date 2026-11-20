## Site Safety Assistant

This application is powered by Retrieval-Augmented Generation (RAG) and Google Cloud Vertex AI Search. It searches across 12 free public SafeWork Australia Codes of Practice PDFs (approx 662 total pages) to retrieve relevant passages and generate grounded answers, with cited source references.

You can ask it questions like `What legal Acts relate to employer liability if a worker is injured`?
The application will generate an answer grounded strictly by the PDF documents that are currently hosted in the RAG engine.
It gives a list of references including the page number, so you can click to view the original material.
This application might be used by a site engineer, or to help with worker induction.

**Live Demo:** \
[https://safety.mikegelldemo.tech](https://safety.mikegelldemo.tech)

### Architecture & Tech Stack

* **Frontend:** React
* **Backend:** .NET Core 8 Web API
* **RAG:** GCP Vertex AI Search (Discovery Engine)
* **Storage & Infrastructure:**
  - Google Cloud Storage (Document ingestion bucket)
  - GCP Cloud Run (Managed Docker container hosting)
  - Firebase Hosting (Frontend & SSL)
  - Cloudflare DNS

## Indexed Source Documents

The following 12 public PDFs from the **SafeWork Australia** _Model Codes of Practice_ were ingested into a Google Cloud Storage bucket and indexed by the Vertex AI Search data store:

* [Model Code of Practice: Confined Spaces](https://www.safeworkaustralia.gov.au/system/files/documents/1905/model-cop-confined-spaces.pdf)
* [Model Code of Practice: First Aid in the Workplace](https://www.safeworkaustralia.gov.au/system/files/documents/1705/mcop-first-aid-in-workplace-v1.pdf)
* [Model Code of Practice: How to Manage Work Health and Safety Risks](https://www.safeworkaustralia.gov.au/sites/default/files/2024-11/model_code_of_practice-how_to_manage_work_health_and_safety_risks-nov24.pdf)
* [Model Code of Practice: Construction Work](https://www.safeworkaustralia.gov.au/sites/default/files/2024-11/model_code_of_practice-construction_work-nov24.pdf)
* [Model Code of Practice: Managing the Work Environment and Facilities](https://www.safeworkaustralia.gov.au/system/files/documents/1901/code_of_practice_-_managing_the_work_environment_and_facilities.pdf)
* [Model Code of Practice: Managing Electrical Risks in the Workplace](https://www.safeworkaustralia.gov.au/system/files/documents/1810/model-cop-managing-electrical-risks-in-the-workplace.pdf)
* [Model Code of Practice: Managing the Risk of Falls at Workplaces](https://www.safeworkaustralia.gov.au/system/files/documents/1705/mcop-managing-the-risk-of-falls-at-workplaces-v1.pdf)
* [Model Code of Practice: Hazardous Manual Tasks](https://www.safeworkaustralia.gov.au/system/files/documents/1905/model-cop-hazardous-manual-tasks.pdf)
* [Model Code of Practice: Managing Noise and Preventing Hearing Loss at Work](https://www.safeworkaustralia.gov.au/system/files/documents/1810/model-cop-managing-noise-and-preventing-hearing-loss-at-work.pdf)
* [Model Code of Practice: Managing Psychosocial Hazards at Work](https://www.safeworkaustralia.gov.au/sites/default/files/2022-08/model_code_of_practice_-_managing_psychosocial_hazards_at_work_25082022_0.pdf)
* [Model Code of Practice: Managing Risks of Plant in the Workplace](https://www.safeworkaustralia.gov.au/system/files/documents/1705/mcop-managing-risks-of-plant-in-the-workplace-v1.pdf)
* [Model Code of Practice: Consultation, Cooperation and Coordination](https://www.safeworkaustralia.gov.au/system/files/documents/1901/code_of_practice_-_consultation_cooperation_coordination.pdf)
