// Publiczne dane konfiguracji. NIE umieszczaj tu client secret ani kluczy Storage.
window.MECHMASTER_CONFIG = Object.freeze({
  clientId: '0f111dad-b692-47fc-a60b-bb09f05e52d8',
  tenantId: '970b447f-8b34-437d-b665-1f05f66a1cd1',
  authority: 'https://mechmastercustomers.ciamlogin.com/970b447f-8b34-437d-b665-1f05f66a1cd1/',
  redirectUri: 'https://stmmtdevb80b98b57ede.z16.web.core.windows.net/',
  // Po wdrozeniu Azure Functions: np. https://func-mechmaster-api.azurewebsites.net/api
  apiBaseUrl: '',
  // Po rejestracji chronionego API: np. api://<API_APP_CLIENT_ID>/access_as_user
  apiScope: ''
});
