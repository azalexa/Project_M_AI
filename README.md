# MechMaster

### A cloud-based marketplace for everyday repairs and technical assistance

**MechMaster** is a full-stack web application prototype built to connect people who need help fixing something with people who can offer that help. It started as a small static website deployment experiment and evolved into a repair marketplace with customer accounts, public listings, responses, private conversations, a serverless API, and cloud data storage.

The project was built as a hands-on exercise in application development, identity management, Azure infrastructure, and continuous deployment. It demonstrates how several managed cloud services can be combined into a working web application without operating a traditional web server.

> **Project status: archived prototype (November 2026).** The original Azure environment was being decommissioned at the end of the project. The former website, API endpoints, identity tenant, and infrastructure identifiers should not be assumed to remain available. This repository documents the implementation and lessons learned; it is not a currently hosted production service.

## 1. The problem and the idea

Finding the right person for a small repair can be surprisingly difficult. Someone with a car that will not start, a leaking kitchen tap, or a faulty washing machine may not know who to contact. At the same time, skilled individuals and local service providers need a simple way to discover people who need help.

MechMaster was designed around two complementary types of listing:

1. **I need help:** A user describes a problem, chooses a category and location, and waits for responses. For example: *“My car will not start in the morning. I need help diagnosing the issue in Szczecin.”*
2. **I offer help:** A user advertises the type of assistance they can provide. For example: *“I can repair leaking taps and replace plumbing fixtures in Warsaw.”*

The goal was to make the first contact straightforward: discover a relevant listing, respond, and continue the conversation privately. The prototype focused on this communication flow rather than on payments, booking, or business verification.

## 2. What was implemented

| Capability | What it does | Prototype status |
| --- | --- | --- |
| Responsive marketplace interface | Presents listings, categories, forms, and account controls on desktop and mobile | Implemented |
| Two listing types | Supports requests for help and offers of assistance | Implemented |
| Search and filters | Filters by keywords, location, category, and listing type | Implemented |
| User registration and sign-in | Uses Microsoft Entra External ID rather than storing passwords in application tables | Integrated and manually tested |
| Shared listing storage | Publishes listings through an API into Azure Table Storage | Deployed and manually tested |
| Listing responses | Allows authenticated users to respond to listings created by others | Implemented in the API |
| Private conversations | Stores messages in a conversation linked to a listing and respondent | Implemented; not fully verified end to end with two real accounts |
| Listing management | Allows the creator to mark their own listing as closed | Implemented in the API |
| Automated frontend deployment | Publishes changes from the Git repository using Azure Pipelines | Working during development |
| Automated backend deployment | Publishes the API through a separate PowerShell script and Functions Core Tools | Working as a manual process, not integrated into the frontend pipeline |

**Important distinction:** Features described as implemented were present in the application code. A working health check, successful deployment, or passing mock test does not on its own prove that every user workflow was tested against live cloud services. The full marketplace was a proof of concept, not a production-validated release.

## 3. User experience

A typical workflow was designed to look like this:

1. A visitor opens the homepage and browses existing listings without signing in.
2. They search for a specific problem, category, or city.
3. To create a listing or contact another user, they sign in or register through Microsoft Entra External ID.
4. After authentication, the application obtains an access token for the MechMaster API.
5. The user posts a request for help or publishes an offer of assistance.
6. Another signed-in user responds to the listing.
7. The listing owner and respondent can exchange messages in a conversation associated with that response.
8. The listing owner can close the listing when the issue has been resolved.

The UI also included representative example listings for demonstration purposes. Those examples should not be confused with real user-generated content. In its initial demonstration mode, the frontend could save data in the browser; the later API-backed mode used shared storage on Azure.

## 4. System architecture

The solution separated the public website, customer identity, application logic, and stored data.

### Why these services?

| Layer | Service or technology | Responsibility |
| --- | --- | --- |
| Frontend | HTML, CSS, vanilla JavaScript | User interface and browser-side interaction |
| Static hosting | Azure Storage Static Website | Serves frontend assets over HTTPS |
| Customer identity | Microsoft Entra External ID | Customer registration, login, and identity tokens |
| Browser authentication | Microsoft Authentication Library (MSAL) | Redirect-based authentication and token acquisition |
| Backend | Azure Functions on Node.js | REST endpoints, input validation, permissions, and data operations |
| Persistent application data | Azure Table Storage | Stores listings, replies, and messages |
| Cloud credentials | Managed Identity and Azure RBAC | Gives the backend access to storage without exposing storage account keys |
| Source control | Git and GitHub | Stores application code and deployment configuration |
| Frontend CI/CD | Azure Pipelines | Publishes frontend updates after changes to the `main` branch |
| Provisioning and deployment | Azure CLI, PowerShell, Functions Core Tools | Creates resources, applies configuration, and publishes the API |

**PostgreSQL was not the application database.** An Azure Database for PostgreSQL Flexible Server and a database named `mechmaster` were also provisioned during the infrastructure work. The deployed marketplace API did not have PostgreSQL connection settings and used Azure Table Storage instead. The PostgreSQL instance was therefore not part of the verified application data path.

The original repository name, `Project_M_AI`, reflected an earlier direction. **No production AI diagnosis or recommendation feature was delivered in this prototype.**

## 5. How authentication and authorization worked

Authentication was intentionally delegated to **Microsoft Entra External ID**. This kept account registration and password management outside the marketplace's own database.

1. **Identity tenant:** A separate customer-facing Entra External ID directory handled sign-up and sign-in.
2. **Frontend application registration:** The browser application was registered as a single-page application with an allowed redirect URI.
3. **API application registration:** The protected API exposed a delegated permission named `access_as_user`.
4. **Permission assignment:** The frontend application was granted permission to request API access tokens.
5. **Token acquisition:** MSAL obtained tokens for signed-in users and attached them to protected API requests.
6. **Server-side validation:** The backend checked the token signature, issuer, audience, tenant, and required scope before allowing protected operations.
7. **Resource-level authorization:** Additional checks ensured, for example, that users could only close their own listings and that private conversations were accessible only to their participants.

The public listing endpoint did not require sign-in. Creating listings, submitting responses, reading private responses, and accessing conversations did require a validated user identity.

> **Security note:** The Azure Functions HTTP triggers used `authLevel: anonymous` because the application implemented bearer-token verification in its own request handlers. That setting must not be interpreted as an invitation to remove or bypass the authorization code.

User accounts lived in Entra External ID. Application data lived in Table Storage. Creating an account on MechMaster did **not** grant customers access to Azure Portal or Azure resource management.

## 6. Data model and API

Instead of a relational database, the backend used three Azure Storage tables:

| Table | Purpose |
| --- | --- |
| `MechMasterPosts` | Public listings and their ownership, category, city, type, status, and timestamps |
| `MechMasterResponses` | Replies associated with a listing and a responding user |
| `MechMasterMessages` | Messages within private conversations between a listing owner and respondent |

The backend was implemented with Azure Functions and the `@azure/data-tables` SDK. Azure Identity credentials were used to access the data service.

### REST endpoints

All routes use the `/api` prefix.

| Method | Endpoint | Function |
| --- | --- | --- |
| `GET` | `/health` | Reports whether the API process responds |
| `GET` | `/posts` | Returns public listings |
| `POST` | `/posts` | Creates a listing for the authenticated user |
| `PATCH` | `/posts/{id}` | Closes a listing owned by the authenticated user |
| `GET` | `/posts/{id}/responses` | Retrieves replies visible to the authenticated participant |
| `POST` | `/posts/{id}/responses` | Adds a response to another user's listing |
| `GET` | `/posts/{id}/responses/{respondentId}/messages` | Retrieves an authorized private conversation |
| `POST` | `/posts/{id}/responses/{respondentId}/messages` | Sends a message in an authorized conversation |

The implementation also validated input fields, returned appropriate HTTP errors, and restricted some repeated actions. For instance, a user could not respond twice to the same listing using the same account, and the listing owner could not respond to their own listing.

### Important data design limitations

Azure Table Storage is simple and cost-conscious for a small prototype, but it is not a direct replacement for a relational database. The implementation used basic entity queries rather than advanced full-text search, joins, transactional messaging, or rich reporting. These would need a more deliberate data design at larger scale.

## 7. Repository structure

```text
Project_M_AI/
├── frontend/
│   ├── index.html             # Marketplace interface
│   ├── styles.css             # Responsive design
│   ├── app.js                 # Search, forms, login and API integration
│   ├── config.js              # Public client-side configuration
│   └── favicon.svg
├── api/
│   ├── host.json              # Azure Functions host configuration
│   ├── package.json           # Node.js dependencies and test commands
│   ├── local.settings.example.json
│   ├── src/
│   │   ├── functions/index.js  # HTTP routes
│   │   └── lib/
│   │       ├── auth.js         # Entra token validation
│   │       ├── storage.js      # Azure Table Storage access
│   │       └── validate.js     # Input validation
│   └── test/                  # Validation and mocked integration tests
├── scripts/
│   ├── 01-Provision-Azure.ps1 # Resource and permission setup
│   └── 02-Deploy-API.ps1      # Tests, publish, health check, client config
├── azure-pipelines.yml       # Frontend deployment pipeline
└── README.md
```

This shows the main layout of the implemented prototype. The repository may also contain historical or supporting files from earlier iterations.

## 8. Development and deployment process

The application was built iteratively rather than deployed as one finished system.

### Phase 1: Static website and CI/CD

The first milestone was a minimal HTML/CSS site hosted in Azure Storage Static Website. Uploads initially failed because the developer's Azure account lacked data-plane permissions. After assigning the appropriate Storage Blob role, the site was uploaded successfully.

An existing Azure Pipelines configuration was then changed from a connection test into a real frontend deployment. The pipeline used an Azure service connection and uploaded files from `frontend/` to the `$web` container on commits to `main`. Its service principal needed its **own** Blob Data Contributor permission, separate from the developer's role.

### Phase 2: Identity and marketplace frontend

The static landing page became a responsive marketplace with listing categories, search, forms, account controls, and sample data. A customer-facing Entra External ID directory, sign-in flow, SPA registration, and API registration were configured. A misconfigured OpenID authority initially blocked login; fixing the tenant-specific authority enabled the identity integration.

### Phase 3: Backend and persistent storage

The backend was built in Node.js using Azure Functions and Azure Table Storage. Provisioning scripts created the necessary tables, Function App, access roles, and cross-origin settings. An API registration and `access_as_user` permission allowed the frontend to request protected access tokens.

The Function App used Managed Identity for storage access. Deployment exposed a separate issue: a legacy deployment connection-string setting conflicted with a storage account that disallowed shared-key authentication. Updating the Flex Consumption deployment storage to use system-assigned identity, granting Blob permissions, and removing the obsolete setting resolved the issue.

### Phase 4: End-to-end checks and retirement

The Function App was successfully published and its health endpoint responded. The frontend received the API URL and scope and was deployed through Azure Pipelines. A manual test confirmed that a real listing could be submitted. More extensive multi-user and production-readiness tests were not completed.

After the experiment, Azure resources were removed or scheduled for removal. The customer identity tenant later returned a `Tenant not found` response, and its original directory was no longer accessible. The final removal state and billing closure were not independently verified.

## 9. Running the code locally

The instructions below are for understanding and testing the repository. They do **not** recreate the original environment automatically.

### Requirements

1. A compatible Node.js and npm version for the checked-out code.
2. Azure Functions Core Tools v4 for running the API locally.
3. PowerShell and Azure CLI for the infrastructure scripts.
4. An Azure subscription and fresh identity/storage configuration for live cloud testing.

### Run backend tests

From the project root:

```powershell
cd api
npm install
npm test
```

The test suite includes field validation and a mocked API integration scenario covering creating listings, responding, accessing messages, and enforcing user ownership. Mocked tests do not establish that the live Azure configuration is correct.

### Start the API locally

```powershell
cd api
npm install
func start
```

A fresh `local.settings.json` and valid local Azure configuration are required for endpoints that depend on identity or Table Storage. Use `local.settings.example.json` as a starting point, and never commit actual secrets or credentials.

### Frontend configuration

The frontend reads public browser settings from `frontend/config.js`, including the SPA client ID, tenant-specific authority, redirect URI, API URL, and API permission scope. These settings **must be replaced** with values from newly created resources before deployment. Do not point a new installation at the retired tenant.

The page can be viewed as a static site, but the complete sign-in and shared-data flows require an active identity tenant and deployed API.

### Cloud deployment

The historical scripts are included for reference:

```powershell
.\scripts\01-Provision-Azure.ps1
.\scripts\02-Deploy-API.ps1 -ApiClientId "<NEW_API_CLIENT_ID>"
```

**Do not run these unchanged against a live subscription.** They contain environment-specific defaults from the original project, may create billable resources, and need review and updates before reuse. The backend deployment script assumes the supporting services and Entra application registrations have already been set up. The frontend pipeline only handles the static site; API deployment was separate.

## 10. Technical challenges and lessons learned

| Challenge | What it taught |
| --- | --- |
| Azure RBAC and identity separation | Owner access to a resource does not automatically equal blob data access, and a CI/CD service principal has its own permissions |
| Authentication authority configuration | OpenID discovery must use the correct customer tenant and authority address |
| Application-level API authorization | A valid sign-in session is not enough; API tokens need the correct audience, scope, and authorization checks |
| Cross-platform testing | A test mock that assumed Unix file paths failed on Windows and needed a platform-safe path comparison |
| Functions runtime detection | Local Azure Functions tooling required a valid Node.js worker runtime configuration |
| Flex Consumption package deployment | Deployment storage authentication and runtime storage settings are distinct concerns |
| Shared-key restrictions | Managed Identity and role-based access should be configured deliberately rather than weakening storage account security |
| Static versus dynamic architecture | A static website can still power a dynamic product when it calls an authenticated backend |
| Resource lifecycle and cost | Provisioned databases and other cloud services may cost money even if the application does not use them |

## 11. Limitations and future work

MechMaster was an MVP and learning project. Before it could be responsibly released as a public marketplace, additional work would be needed:

1. Complete end-to-end tests involving independent customer accounts, especially for private messaging and authorization boundaries.
2. Introduce monitoring, alerts, backups, recovery procedures, and a separate production environment.
3. Add spam prevention, abuse reporting, moderation, and limits on API requests.
4. Define privacy notices, account/data deletion workflows, data retention, and appropriate legal terms.
5. Add service-provider verification and user reviews if the platform were to facilitate real-world repairs.
6. Revisit search and data modeling for higher traffic, complex queries, and message volume.
7. Add automated backend deployment and a repeatable infrastructure-as-code approach.
8. Add broader performance, accessibility, and security testing.

The prototype did **not** implement integrated payments, booking, verified professional credentials, or a production AI assistant.

## 12. Project outcome

MechMaster demonstrated the complete technical path from an HTML/CSS deployment check to a cloud-hosted application with:

1. A real marketplace frontend and user flows.
2. External customer authentication through Microsoft Entra.
3. A serverless API with token and ownership checks.
4. Persistent listing data on Azure Table Storage.
5. Source-controlled frontend deployment using Azure Pipelines.
6. Practical experience diagnosing real cloud authentication, deployment, and configuration failures.

**The primary result of the project is both the working prototype that was demonstrated during development and the reusable understanding of how to build, connect, troubleshoot, and retire a multi-service application on Azure.**

---

**Status note:** This README describes the state reached during development in November 2026. It does not claim that the original cloud services are still deployed. No license is asserted here; check the repository for an explicit license before reuse or redistribution.
